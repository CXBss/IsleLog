// 一次性脚本：把带 #eDiary日记 标签、用 || 连接的多段日记拆成多条 memo。
//
// 规则（详见 tool/ediary_split_core.dart）：
//   - 首段留在原 memo：content 换成首段（去 ||，末尾补 #eDiary日记），
//     写入编辑基线 originalContent = 拆分前全文（= 当前服务端内容），状态转 pending。
//   - 其余每段新建 memo：pending、无 memosName，content = 该段原文 + 末尾 #eDiary日记。
//   - 新段 createdAt：日期永远取原日记的日期；时间 = 段首 HH:MM:SS / HH:MM /
//     (YYYY-MM-DD HH:MM:SS 取时间部分)，无时间戳则上一段 +1 分钟，跨天则不加。
//   - 有附件 / 属事件串的条目跳过不拆。
//
// 用法（先确认 IsleLog 已退出）：
//   dart run tool/split_ediary.dart            # 预演：出报告，不写库
//   dart run tool/split_ediary.dart --apply    # 备份后写入（仍只在本地，全 pending）

import 'dart:io';

import 'package:isar/isar.dart';
import 'package:isle_log/data/models/article_entry.dart';
import 'package:isle_log/data/models/comment_entry.dart';
import 'package:isle_log/data/models/folder_entry.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/data/models/tag_stat.dart';
import 'package:isle_log/data/models/thread_entry.dart';
import 'package:isle_log/data/models/thread_suggestion_entry.dart';

import 'ediary_clean_core.dart' show extractTagsLike;
import 'ediary_split_core.dart';

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

  // 事件串成员的本地 memo id
  final threads = await isar.threadEntrys.where().findAll();
  final threadMemberIds = <int>{for (final t in threads) ...t.memberLocalIds};

  final ed = await isar.memoEntrys
      .filter()
      .tagsElementEqualTo(kEdiaryTag)
      .isDeletedEqualTo(false)
      .findAll();
  final withPipe = ed.where((m) => m.content.contains('||')).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  final plans = <_Plan>[];
  final skipped = <MemoEntry>[];
  final degenerate = <MemoEntry>[];
  for (final m in withPipe) {
    if (m.attachmentsJson.isNotEmpty || threadMemberIds.contains(m.id)) {
      skipped.add(m);
      continue;
    }
    final segs = splitSegments(m.content);
    if (segs.isEmpty) {
      degenerate.add(m);
      continue;
    }
    final times = computeSegmentTimes(m.createdAt, segs);
    plans.add(_Plan(m, [
      for (var i = 0; i < segs.length; i++)
        _Seg(buildSegmentContent(segs[i]), times[i]),
    ]));
  }

  final multi = plans.where((p) => p.segs.length >= 2).toList();
  final single = plans.where((p) => p.segs.length == 1).toList();
  final newMemoCount = multi.fold<int>(0, (s, p) => s + p.segs.length - 1);

  stdout.writeln('带 #$kEdiaryTag 且含 || 的条目: ${withPipe.length}');
  stdout.writeln('  跳过（有附件/属事件串）: ${skipped.length}');
  stdout.writeln('  异常（切完无有效内容）  : ${degenerate.length}');
  stdout.writeln('  真正拆分（≥2 段）      : ${multi.length}  → 新建 memo $newMemoCount 条');
  stdout.writeln('  仅去尾部孤立 ||（1 段） : ${single.length}');
  stdout.writeln('  模式: ${apply ? "APPLY" : "DRY-RUN"}\n');

  final report = await _writeReport(multi, single, skipped, degenerate);
  stdout.writeln('完整报告: $report\n');
  _printSamples(multi);

  if (!apply) {
    stdout.writeln('这是预演。确认报告后加 --apply。');
    await isar.close();
    return;
  }

  final backup = '${dbFile.path}.bak-${DateTime.now().millisecondsSinceEpoch}';
  await dbFile.copy(backup);
  stdout.writeln('已备份: $backup');

  var updated = 0, created = 0;
  await isar.writeTxn(() async {
    for (final p in plans) {
      final original = p.original;
      final baseline = original.content; // 拆分前全文 = 当前服务端内容
      // 首段写回原 memo（memosName 等远端身份本就在对象上，直接 put 即保留）
      original
        ..content = p.segs.first.content
        ..originalContent = baseline
        ..syncStatus = SyncStatus.pending
        ..updatedAt = DateTime.now();
      _applyDerived(original);
      await isar.memoEntrys.put(original);
      updated++;
      // 其余段新建
      for (var i = 1; i < p.segs.length; i++) {
        final seg = p.segs[i];
        final n = MemoEntry()
          ..content = seg.content
          ..createdAt = seg.time
          ..updatedAt = seg.time
          ..syncStatus = SyncStatus.pending;
        _applyDerived(n);
        await isar.memoEntrys.put(n);
        created++;
      }
    }
  });

  stdout.writeln('完成：改写首段 $updated 条，新建段落 $created 条，全部 pending。');
  stdout.writeln('回滚：退出 App → 还原 $backup');
  stdout.writeln('确认无误后再打开 IsleLog 同步一次（首段走 pushLocal 更新，其余走新建）。');
  await isar.close();
}

/// 复刻 DatabaseService.saveMemo 写入前的派生逻辑：重算 tags 与待办状态。
void _applyDerived(MemoEntry m) {
  m.tags = extractTagsLike(m.content);
  final pending = RegExp(r'- \[ \]').allMatches(m.content).length;
  final done = RegExp(r'- \[[xX]\]').allMatches(m.content).length;
  m.pendingTodoCount = pending;
  m.todoStatus = (pending == 0 && done == 0)
      ? TodoStatus.none
      : (pending > 0 ? TodoStatus.hasPending : TodoStatus.allDone);
}

class _Plan {
  _Plan(this.original, this.segs);
  final MemoEntry original;
  final List<_Seg> segs;
}

class _Seg {
  _Seg(this.content, this.time);
  final String content;
  final DateTime time;
}

void _printSamples(List<_Plan> multi) {
  final n = multi.length < 4 ? multi.length : 4;
  if (n == 0) return;
  stdout.writeln('前 $n 条拆分示例：');
  for (var i = 0; i < n; i++) {
    final p = multi[i];
    stdout.writeln('──── 源 #${p.original.id}  ${p.original.createdAt.toIso8601String()}'
        '  → ${p.segs.length} 段');
    for (var j = 0; j < p.segs.length; j++) {
      final s = p.segs[j];
      final head = s.content.replaceAll('\n', '⏎');
      stdout.writeln('   [$j] ${s.time.toIso8601String()}  '
          '${head.length > 90 ? '${head.substring(0, 90)}…' : head}');
    }
  }
  stdout.writeln('');
}

Future<String> _writeReport(
  List<_Plan> multi,
  List<_Plan> single,
  List<MemoEntry> skipped,
  List<MemoEntry> degenerate,
) async {
  final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
  final path = '${Directory.systemTemp.path}/ediary-split-$ts.txt';
  final b = StringBuffer()
    ..writeln('IsleLog #$kEdiaryTag || 拆分报告')
    ..writeln('生成: ${DateTime.now()}')
    ..writeln('真正拆分 ${multi.length} 条，仅清尾部 || ${single.length} 条，'
        '跳过 ${skipped.length} 条，异常 ${degenerate.length} 条')
    ..writeln('=' * 78);

  for (final p in multi) {
    b
      ..writeln('')
      ..writeln('源 #${p.original.id}  原 createdAt=${p.original.createdAt.toIso8601String()}'
          '  memosName=${p.original.memosName ?? "(未同步)"}  → ${p.segs.length} 段')
      ..writeln('-' * 78);
    for (var j = 0; j < p.segs.length; j++) {
      b
        ..writeln('【段 $j】 createdAt = ${p.segs[j].time.toIso8601String()}'
            '${j == 0 ? "  (首段=原 memo，时间不变)" : ""}')
        ..writeln(p.segs[j].content)
        ..writeln('-' * 40);
    }
    b.writeln('=' * 78);
  }

  if (single.isNotEmpty) {
    b.writeln('\n\n########## 仅去尾部孤立 || （内容轻微变化）##########');
    for (final p in single) {
      b
        ..writeln('\n源 #${p.original.id}  ${p.original.createdAt.toIso8601String()}')
        ..writeln('新内容: ${p.segs.first.content}')
        ..writeln('-' * 78);
    }
  }

  if (skipped.isNotEmpty) {
    b.writeln('\n\n########## 跳过（有附件/属事件串，未处理）##########');
    for (final m in skipped) {
      b.writeln('  #${m.id}  ${m.createdAt.toIso8601String()}  附件${m.attachmentsJson.length}  '
          '"${m.content.replaceAll('\n', ' ').substring(0, m.content.length < 50 ? m.content.length : 50)}"');
    }
  }

  await File(path).writeAsString(b.toString());
  return path;
}
