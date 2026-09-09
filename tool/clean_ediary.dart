// 一次性维护脚本：把带 #ediary日记 标签、从旧日记 App 导入的日记正文里
// 夹带的 HTML 实体（&#50; &nbsp; &amp; …）和残留标签（<br> <div> …）统一清掉。
//
// 用法（务必先完全退出 IsleLog App，否则数据库被占用打不开）：
//
//   dart run tool/clean_ediary.dart                # 预演：只统计 + 出报告，不写库
//   dart run tool/clean_ediary.dart --apply        # 备份数据库后真正写入
//
// 可选参数：
//   --dir=<路径>     指定数据库所在目录（默认 macOS 沙箱容器 Documents 目录）
//   --tag=<标签>     指定要清洗的标签（默认 ediary日记）
//   --limit=<N>      只处理前 N 条（调试用）
//
// 写入规则：
//   - 正文被清洗的条目：content 换成清洗结果，tags 按同规则重算；
//   - syncStatus 不是 conflict 的：置为 pending 且 updatedAt 刷新，
//     下次 App 同步会把干净版本推到服务端（旧版本仍在服务端版本历史里）；
//   - syncStatus 是 conflict 的：只改本地 content/tags，不动 syncStatus，
//     避免绕过冲突保留机制——这些条目需你之后在冲突界面里自行处理。

import 'dart:io';

import 'package:isar/isar.dart';
import 'package:isle_log/data/models/article_entry.dart';
import 'package:isle_log/data/models/comment_entry.dart';
import 'package:isle_log/data/models/folder_entry.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/data/models/tag_stat.dart';
import 'package:isle_log/data/models/thread_entry.dart';
import 'package:isle_log/data/models/thread_suggestion_entry.dart';

import 'ediary_clean_core.dart';

const _defaultTag = 'eDiary日记';
const _dbName = 'isle_v2';

String _defaultDbDir() {
  final home = Platform.environment['HOME'] ?? '';
  return '$home/Library/Containers/dyc.dev.isleLog/Data/Documents';
}

String _arg(List<String> args, String key, String fallback) {
  final hit = args.firstWhere(
    (a) => a.startsWith('--$key='),
    orElse: () => '',
  );
  return hit.isEmpty ? fallback : hit.substring('--$key='.length);
}

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');
  final dbDir = _arg(args, 'dir', _defaultDbDir());
  final tag = _arg(args, 'tag', _defaultTag);
  final limit = int.tryParse(_arg(args, 'limit', ''));

  final dbFile = File('$dbDir/$_dbName.isar');
  if (!dbFile.existsSync()) {
    stderr.writeln('找不到数据库文件：${dbFile.path}');
    stderr.writeln('用 --dir=<目录> 指定 isle_v2.isar 所在目录。');
    exit(1);
  }

  stdout.writeln('数据库：${dbFile.path}');
  stdout.writeln('标签  ：#$tag');
  stdout.writeln('模式  ：${apply ? "APPLY（会写库）" : "DRY-RUN（只读）"}');
  stdout.writeln('');

  await Isar.initializeIsarCore(download: true);
  final Isar isar;
  try {
    isar = await Isar.open(
      [
        MemoEntrySchema,
        TagStatSchema,
        CommentEntrySchema,
        ArticleEntrySchema,
        FolderEntrySchema,
        ThreadEntrySchema,
        ThreadSuggestionEntrySchema,
      ],
      directory: dbDir,
      name: _dbName,
    );
  } catch (e) {
    stderr.writeln('打开数据库失败（IsleLog App 是否还开着？请先完全退出）：\n$e');
    exit(1);
  }

  var candidates = await isar.memoEntrys
      .filter()
      .tagsElementEqualTo(tag)
      .isDeletedEqualTo(false)
      .findAll();
  candidates.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  if (limit != null && limit < candidates.length) {
    candidates = candidates.sublist(0, limit);
  }

  final changed = <_Change>[];
  for (final m in candidates) {
    final cleaned = cleanEdiaryContent(m.content);
    if (cleaned != m.content) {
      changed.add(_Change(m, cleaned));
    }
  }

  final conflicts = changed.where((c) => c.memo.syncStatus == SyncStatus.conflict).toList();
  final withOriginal = changed.where((c) => c.memo.originalContent != null).length;

  stdout.writeln('带 #$tag 且未删除：${candidates.length} 条');
  stdout.writeln('正文需要清洗    ：${changed.length} 条');
  stdout.writeln('其中处于 conflict：${conflicts.length} 条（只改本地，不推送）');
  stdout.writeln('其中有编辑前快照：$withOriginal 条（originalContent 保持不动）');
  stdout.writeln('');

  final report = await _writeReport(changed, tag: tag, apply: apply);
  stdout.writeln('完整前后对照已写到：\n$report\n');

  _printSamples(changed);

  if (!apply) {
    stdout.writeln('这是预演。确认报告无误后，加 --apply 重新运行。');
    await isar.close();
    return;
  }

  final backup = '${dbFile.path}.bak-${DateTime.now().millisecondsSinceEpoch}';
  await dbFile.copy(backup);
  stdout.writeln('已备份数据库到：$backup');

  final now = DateTime.now();
  var pushCount = 0;
  var localOnlyCount = 0;
  await isar.writeTxn(() async {
    for (final c in changed) {
      final m = c.memo;
      m.content = c.cleaned;
      m.tags = extractTagsLike(c.cleaned);
      if (m.syncStatus == SyncStatus.conflict) {
        localOnlyCount++;
      } else {
        m.syncStatus = SyncStatus.pending;
        m.updatedAt = now;
        pushCount++;
      }
      await isar.memoEntrys.put(m);
    }
  });

  stdout.writeln('写入完成：$pushCount 条置为 pending 待推送，$localOnlyCount 条仅改本地。');
  stdout.writeln('现在可以打开 IsleLog，手动同步一次把干净版本推到服务端。');
  await isar.close();
}

class _Change {
  _Change(this.memo, this.cleaned);
  final MemoEntry memo;
  final String cleaned;
}

void _printSamples(List<_Change> changed) {
  final n = changed.length < 5 ? changed.length : 5;
  if (n == 0) return;
  stdout.writeln('前 $n 条示例（截断到 240 字）：');
  for (var i = 0; i < n; i++) {
    final c = changed[i];
    stdout.writeln('──────── #${c.memo.id}  ${c.memo.createdAt.toIso8601String()} '
        '[${c.memo.syncStatus.name}]');
    stdout.writeln('- 旧: ${_clip(c.memo.content, 240)}');
    stdout.writeln('+ 新: ${_clip(c.cleaned, 240)}');
  }
  stdout.writeln('');
}

String _clip(String s, int max) {
  final one = s.replaceAll('\n', '⏎');
  return one.length <= max ? one : '${one.substring(0, max)}…';
}

Future<String> _writeReport(
  List<_Change> changed, {
  required String tag,
  required bool apply,
}) async {
  final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
  final path = '${Directory.systemTemp.path}/ediary-clean-$ts.txt';
  final b = StringBuffer()
    ..writeln('IsleLog #$tag 正文清洗报告  ${apply ? "(APPLY)" : "(DRY-RUN)"}')
    ..writeln('生成时间：${DateTime.now()}')
    ..writeln('需要清洗：${changed.length} 条')
    ..writeln('=' * 72);
  for (final c in changed) {
    b
      ..writeln('')
      ..writeln('#${c.memo.id}  ${c.memo.createdAt.toIso8601String()}  '
          'syncStatus=${c.memo.syncStatus.name}  '
          'memosName=${c.memo.memosName ?? "(未同步)"}')
      ..writeln('-' * 72)
      ..writeln('【旧】')
      ..writeln(c.memo.content)
      ..writeln('-' * 72)
      ..writeln('【新】')
      ..writeln(c.cleaned)
      ..writeln('=' * 72);
  }
  final f = File(path);
  await f.writeAsString(b.toString());
  return path;
}
