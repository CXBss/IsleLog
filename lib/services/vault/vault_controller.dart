import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database/database_service.dart';
import '../../data/models/vault_entry.dart';
import 'vault_storage.dart';
import 'vault_sync.dart';

/// 隐私空间会话状态：解锁/锁定、后台超时自动锁定。
///
/// [isUnlockedListenable] 是锁定事件的唯一广播渠道——UI 必须监听它，
/// 在收到 false 时清空输入并退出页面。否则会出现"计时器已锁定、
/// 编辑器还开着并持有明文、此时点保存直接崩溃"。
class VaultController with WidgetsBindingObserver {
  VaultController._(this._storage);

  @visibleForTesting
  VaultController.forTesting(VaultStorage storage) : _storage = storage {
    // 同时登记为单例：被测代码（如 VaultMigration）走的是 [instance]，
    // 不这样做就没法把测试用的 storage 注入进去。
    _instance = this;
  }

  static VaultController? _instance;

  static VaultController get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('VaultController 尚未初始化，请先 await VaultController.init()');
    }
    return i;
  }

  static Future<void> init() async {
    if (_instance != null) return;
    final supportDir = await getApplicationSupportDirectory();
    // 中性目录名；不用系统 Caches（会被系统清空，日记数据不可接受）
    final dir = Directory(p.join(supportDir.path, 'blob'));
    _instance = VaultController._(VaultStorage(dir: dir));
  }

  final VaultStorage _storage;
  final ValueNotifier<bool> _isUnlocked = ValueNotifier(false);
  DateTime? _backgroundedAt;

  static const _backgroundLockTimeout = Duration(seconds: 60);

  ValueListenable<bool> get isUnlockedListenable => _isUnlocked;
  bool get isUnlocked => _storage.isUnlocked;
  int get revision => _storage.revision;
  List<VaultEntry> get entries => _storage.entries;
  VaultStorage get storage => _storage;

  Future<bool> vaultExists() => _storage.exists();

  Future<String> createVault(String passphrase) async {
    final code = await _storage.createVault(passphrase);
    _isUnlocked.value = true;
    return code;
  }

  Future<bool> tryUnlock(String candidate) async {
    final ok = await _storage.unlock(candidate);
    if (ok) _isUnlocked.value = true;
    return ok;
  }

  Future<bool> adoptRemotePair(
    Uint8List idxBytes,
    Uint8List? atcBytes,
    String passphrase,
  ) async {
    final ok = await _storage.adoptRemotePair(idxBytes, atcBytes, passphrase);
    if (ok) _isUnlocked.value = true;
    return ok;
  }

  void lock() {
    if (!_storage.isUnlocked) return;
    // 3 分钟防抖窗口里的改动必须在这里推掉，否则锁定后就再没机会了。
    // flushPush 不需要主密钥（只读磁盘密文），所以清 key 之后它照样能跑完。
    unawaited(VaultSync.flushPush());
    _storage.lock();
    _isUnlocked.value = false;
  }

  Future<void> saveEntry(VaultEntry entry) async {
    entry.tags = DatabaseService.extractTags(entry.content);
    entry.updatedAt = DateTime.now();
    await _storage.saveEntry(entry);
    VaultSync.schedulePush(_storage.revision);
  }

  Future<void> deleteEntry(String id) async {
    await _storage.deleteEntry(id);
    VaultSync.schedulePush(_storage.revision);
  }

  Future<void> addAttachment(VaultAttachment attachment) async {
    await _storage.addAttachment(attachment);
    VaultSync.schedulePush(_storage.revision);
  }

  Uint8List? attachmentBytes(String id) => _storage.attachmentBytes(id);
  String? attachmentMimeType(String id) => _storage.attachmentMimeType(id);

  void attachLifecycleObserver() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// 只处理 paused。
  ///
  /// 不纳入 inactive / hidden：下拉通知栏、来电横幅、权限弹窗都会触发那两个状态，
  /// 把它们算进锁定计时会让正常操作频繁掉锁，而且对任务切换器截图问题毫无帮助
  /// ——那个由 Task 15 的截屏防护解决。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isUnlocked) return;
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
      unawaited(VaultSync.flushPush()); // 用户已经离开，没必要再等满 3 分钟
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null &&
          DateTime.now().difference(since) > _backgroundLockTimeout) {
        lock();
      }
    }
  }
}
