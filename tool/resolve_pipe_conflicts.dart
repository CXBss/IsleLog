// 一次性修复：clean_ediary.dart 第二遍（\|\| → ||）把 560 条 eDiary 设成 pending 时
// 没有写 originalContent（编辑基线），同步时 decidePendingMemo 无法证明远端没变，
// 保守判成 conflict。这些是假冲突——远端就是第一遍 \|\| 的版本，本地是 || 版本，
// 没有第三方改动。
//
// 修法：确认每条的"本地内容 == 远端内容去掉反斜杠"，然后把 originalContent 设成
// 远端那份 \|\| 版本、清 conflictRemoteContent、状态改回 pending。下次同步 →
// decidePendingMemo 命中 pushLocal，干净推送。
//
// 不匹配纯竖线差异的条目会被列出但不动，留给人工看。
//
// 用法（先完全退出 IsleLog）：
//   dart run tool/resolve_pipe_conflicts.dart            # 预演
//   dart run tool/resolve_pipe_conflicts.dart --apply    # 备份后写入

import 'dart:io';

import 'package:isar/isar.dart';
import 'package:isle_log/data/models/article_entry.dart';
import 'package:isle_log/data/models/comment_entry.dart';
import 'package:isle_log/data/models/folder_entry.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/data/models/tag_stat.dart';
import 'package:isle_log/data/models/thread_entry.dart';
import 'package:isle_log/data/models/thread_suggestion_entry.dart';

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');
  final home = Platform.environment['HOME'];
  final dir = '$home/Library/Containers/dyc.dev.isleLog/Data/Documents';
  final dbFile = File('$dir/isle_v2.isar');
  if (!dbFile.existsSync()) {
    stderr.writeln('找不到 ${dbFile.path}');
    exit(1);
  }

  await Isar.initializeIsarCore(download: true);
  final Isar isar;
  try {
    isar = await Isar.open([
      MemoEntrySchema, TagStatSchema, CommentEntrySchema, ArticleEntrySchema,
      FolderEntrySchema, ThreadEntrySchema, ThreadSuggestionEntrySchema,
    ], directory: dir, name: 'isle_v2');
  } catch (e) {
    stderr.writeln('打开数据库失败（IsleLog 还开着？请先退出）：\n$e');
    exit(1);
  }

  final conflicts = await isar.memoEntrys
      .filter()
      .tagsElementEqualTo('eDiary日记')
      .syncStatusEqualTo(SyncStatus.conflict)
      .findAll();

  stdout.writeln('#eDiary日记 conflict 条目: ${conflicts.length}');
  stdout.writeln('模式: ${apply ? "APPLY" : "DRY-RUN"}\n');

  final safe = <MemoEntry>[];
  final unsure = <MemoEntry>[];
  for (final m in conflicts) {
    final remote = m.conflictRemoteContent;
    if (remote != null && remote.replaceAll(r'\|', '|') == m.content) {
      safe.add(m);
    } else {
      unsure.add(m);
    }
  }

  stdout.writeln('可自动解决（本地 == 远端去反斜杠）: ${safe.length}');
  stdout.writeln('需人工确认（差异不止竖线）      : ${unsure.length}');
  for (final m in unsure.take(20)) {
    stdout.writeln('  ── #${m.id} ${m.createdAt.toIso8601String()}');
    stdout.writeln('     远端: ${_clip(m.conflictRemoteContent ?? "(null)", 180)}');
    stdout.writeln('     本地: ${_clip(m.content, 180)}');
  }
  stdout.writeln('');

  if (!apply) {
    stdout.writeln('预演结束。加 --apply 执行（只处理"可自动解决"那批）。');
    await isar.close();
    return;
  }

  final backup = '${dbFile.path}.bak-${DateTime.now().millisecondsSinceEpoch}';
  await dbFile.copy(backup);
  stdout.writeln('已备份: $backup');

  await isar.writeTxn(() async {
    for (final m in safe) {
      m
        ..originalContent = m.conflictRemoteContent
        ..conflictRemoteContent = null
        ..syncStatus = SyncStatus.pending;
      await isar.memoEntrys.put(m);
    }
  });
  stdout.writeln('已把 ${safe.length} 条改回 pending 并写入编辑基线。');
  stdout.writeln('打开 IsleLog 手动同步一次，应当干净推送、不再冲突。');
  if (unsure.isNotEmpty) {
    stdout.writeln('另有 ${unsure.length} 条未处理，请在冲突界面人工查看。');
  }
  await isar.close();
}

String _clip(String s, int max) {
  final one = s.replaceAll('\n', '⏎');
  return one.length <= max ? one : '${one.substring(0, max)}…';
}
