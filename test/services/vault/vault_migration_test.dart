import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/services/vault/vault_controller.dart';
import 'package:isle_log/services/vault/vault_migration.dart';
import 'package:isle_log/services/vault/vault_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 移入隐私空间的失败路径。
///
/// 回归的是这个缺口：`_moveIntoVaultLocked` 先写 vault、再硬删远端。远端删除
/// 失败时若直接 `return failed`，vault 里就留下一份副本、而服务端明文还在——
/// "移入隐私空间"变成"两边都留一份"。
///
/// 同时验证反向约束：**不能无条件撤销副本**。若远端其实已经删成功（客户端
/// 因超时误判），撤销 vault 副本会导致本地日记在下一次同步时被 changelog 的
/// DELETE 记录连带物理删除，vault 与本地同时为空 = 永久丢日记。
void main() {
  late Directory tempDir;
  late VaultController controller;
  HttpServer? server;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vault_migration_test_');
    controller = VaultController.forTesting(VaultStorage(dir: tempDir));
    await controller.createVault('CorrectHorse1');
    server = null;
  });

  tearDown(() async {
    await server?.close(force: true);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 起一个本地 HTTP 服务，固定按 [status] 回应。
  /// 用真实回环请求而不是 mock：被测代码自己 new 了 MemosApiService，
  /// 没有注入点；而"拿到 HTTP 错误响应"与"没有任何响应"正是本 bug 的分界。
  Future<String> startServer(int status) async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server = s;
    s.listen((req) async {
      req.response.statusCode = status;
      req.response.write('{"code":$status,"message":"测试"}');
      await req.response.close();
    });
    return 'http://127.0.0.1:${s.port}';
  }

  MemoEntry syncedMemo() => MemoEntry()
    ..memosName = 'memos/42'
    ..content = '这条要移进隐私空间'
    ..createdAt = DateTime.utc(2026, 3, 1)
    ..syncStatus = SyncStatus.synced;

  test('远端删除被拒绝（500）时回滚 vault 副本', () async {
    final base = await startServer(500);
    SharedPreferences.setMockInitialValues({
      'memos_server_url': base,
      'memos_access_token': 'test-token',
    });

    final result = await VaultMigration.moveIntoVault(syncedMemo());

    expect(result, VaultMigrationResult.failed);
    // 核心断言：vault 里不能留下副本，否则等于"本地藏起来、云端明文照旧"。
    expect(controller.entries, isEmpty);
  });

  test('远端无响应（连不上）时保留 vault 副本，不冒丢日记的风险', () async {
    // 端口 1 上没有任何服务：连接被拒 ⇒ 没有 HTTP 响应 ⇒ 结论未知。
    SharedPreferences.setMockInitialValues({
      'memos_server_url': 'http://127.0.0.1:1',
      'memos_access_token': 'test-token',
    });

    final result = await VaultMigration.moveIntoVault(syncedMemo());

    expect(result, VaultMigrationResult.failed);
    // 结论未知时必须保住副本：远端可能已经删了，撤掉副本就是永久丢日记。
    expect(controller.entries, hasLength(1));
    expect(controller.entries.single.movedFromMemosName, 'memos/42');
    expect(controller.entries.single.content, '这条要移进隐私空间');
  });
}
