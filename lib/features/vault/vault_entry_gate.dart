import 'package:flutter/material.dart';

import '../../services/settings/settings_service.dart';
import '../../services/vault/vault_controller.dart';
import '../../services/vault/vault_crypto.dart';
import '../../services/vault/vault_sync.dart';
import 'vault_page.dart';

enum VaultInputKind { none, create, unlock, recover }

/// 搜索框输入的口令识别与分派。
///
/// 单独成文件（而不是塞进已有 1400 行的 home_view.dart）：分类逻辑是纯函数，
/// 拿出来才能单测；home_view 那边只留一行调用。
class VaultEntryGate {
  VaultEntryGate._();

  /// 上一个已尝试且失败的候选串。同一个词重复提交时直接跳过，不重复跑 Argon2id。
  static String? _lastFailedCandidate;

  /// 纯函数分类。不碰磁盘、不碰网络，供单测直接调用。
  static VaultInputKind classify(
    String raw, {
    required bool vaultExists,
    required bool serverConfigured,
  }) {
    if (raw.startsWith('+')) {
      final passphrase = raw.substring(1);
      if (vaultExists) return VaultInputKind.none;
      return _isStrong(passphrase) ? VaultInputKind.create : VaultInputKind.none;
    }
    if (raw.startsWith('?')) {
      final passphrase = raw.substring(1);
      if (vaultExists || !serverConfigured) return VaultInputKind.none;
      return _isPlausible(passphrase)
          ? VaultInputKind.recover
          : VaultInputKind.none;
    }
    if (!vaultExists) return VaultInputKind.none;
    return _isPlausible(raw) ? VaultInputKind.unlock : VaultInputKind.none;
  }

  /// 解锁/恢复的门槛：够长、无空格、ASCII 可打印。不要求字符类组合——
  /// 失败的代价只是一次静默的空搜索结果；但创建阶段已强制 ASCII，
  /// 加 ASCII 判断可以避免用户搜索 8 字以上的中文词时白跑 Argon2id。
  static bool _isPlausible(String s) =>
      s.length >= 8 && !s.contains(' ') && VaultCrypto.isAsciiPrintable(s);

  /// 创建的门槛：ASCII 可打印 + 大小写字母 + 数字。
  ///
  /// 防止日常搜索里凑巧输入一个 8 位以上、以 '+' 开头的词（如 "+项目截止0824"）
  /// 被误判成创建请求；顺带保证真口令有基本强度。
  ///
  /// ASCII 限制是为了消掉 Unicode 归一化问题（见 VaultCrypto.isAsciiPrintable）——
  /// 非 ASCII 口令在新设备上可能派生出不同密钥，换机时解不开数据。
  static bool _isStrong(String s) =>
      _isPlausible(s) &&
      s.contains(RegExp(r'[a-z]')) &&
      s.contains(RegExp(r'[A-Z]')) &&
      s.contains(RegExp(r'[0-9]'));

  /// 返回 true 表示已接管（已跳转到隐私空间），调用方不应再展示搜索结果。
  ///
  /// ⚠️ 只能从 SearchDelegate.buildResults 路径调用，绝不能从 buildSuggestions
  /// 调用——那会让每次按键都跑一次 32MB Argon2id。
  static Future<bool> handle(BuildContext context, String raw) async {
    if (raw == _lastFailedCandidate) return false;

    final vaultExists = await VaultController.instance.vaultExists();
    final serverConfigured = await SettingsService.isConfigured;
    final kind = classify(
      raw,
      vaultExists: vaultExists,
      serverConfigured: serverConfigured,
    );
    if (kind == VaultInputKind.none) return false;

    switch (kind) {
      case VaultInputKind.create:
        if (!context.mounted) return true;
        return _handleCreate(context, raw.substring(1));
      case VaultInputKind.unlock:
        final ok = await VaultController.instance.tryUnlock(raw);
        if (!ok) {
          _lastFailedCandidate = raw;
          return false;
        }
        _lastFailedCandidate = null;
        // 进入页面之前同步完成拉取：unawaited 的 pull 会在页面打开后整体替换
        // 内存 entries，用户可能基于旧条目保存，覆盖远端新内容。
        await VaultSync.pullIfNewer();
        if (!context.mounted) return true;
        _enterVault(context);
        return true;
      case VaultInputKind.recover:
        final ok = await VaultSync.recoverFromRemote(raw.substring(1));
        if (!ok) {
          _lastFailedCandidate = raw;
          return false;
        }
        _lastFailedCandidate = null;
        if (!context.mounted) return true;
        _enterVault(context);
        return true;
      case VaultInputKind.none:
        return false;
    }
  }

  static Future<bool> _handleCreate(
    BuildContext context,
    String passphrase,
  ) async {
    // 换机用户误用 +口令 会把云端旧备份整体覆盖成空 vault（新 MK）。
    // 创建前先查云端：已有备份则阻止创建并引导用 ?口令 恢复。
    if (await SettingsService.isConfigured) {
      final hasRemote = await VaultSync.hasRemoteBackup();
      if (hasRemote) {
        if (!context.mounted) return true;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('检测到已有备份'),
            content: const Text(
              '云端已存在加密备份，本机无法直接新建。\n请在搜索框输入 ?你的口令 从云端恢复。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return true;
      }
    }
    if (!context.mounted) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建隐私空间？'),
        content: Text('口令：$passphrase\n\n忘记口令将无法恢复数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认创建'),
          ),
        ],
      ),
    );
    if (confirmed != true) return true; // 用户取消：已接管，但不展示搜索结果

    final code = await VaultController.instance.createVault(passphrase);
    if (!context.mounted) return true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复码'),
        content: Text(
          '忘记口令时可用此码解锁：\n\n$code\n\n'
          '请抄下并妥善保管，此码只显示这一次。\n\n'
          '换新设备时，在搜索框输入 ?你的口令 即可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我已记录'),
          ),
        ],
      ),
    );
    if (!context.mounted) return true;
    _enterVault(context);
    return true;
  }

  static void _enterVault(BuildContext context) {
    Navigator.of(context).pop(); // 关闭搜索页
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VaultPage()),
    );
  }
}
