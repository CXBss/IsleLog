import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/link_picker/link_picker_sheet.dart';
import 'package:isle_log/services/link/link_query.dart';
import 'package:isle_log/services/link/link_target.dart';
import 'package:isle_log/services/link/memo_link.dart';

LinkTarget _target({
  required int id,
  required String label,
  LinkKind kind = LinkKind.memo,
  String? remoteName,
  DateTime? createdAt,
  // 生产中日记的 preview（首行摘要）与 label（日期+摘要）本就不同；
  // 默认值故意不等于 label，避免标题和副标题渲染出同一段文字，
  // 让 find.text(label) 在已有用例里仍然只命中标题一处。
  String? preview,
}) => LinkTarget(
  kind: kind,
  localId: id,
  remoteName: remoteName,
  label: label,
  preview: preview ?? '$label 预览',
  createdAt: createdAt ?? DateTime(2026, 3, 12),
  updatedAt: createdAt ?? DateTime(2026, 3, 12),
);

/// 假搜索：记录收到的查询，按预设结果返回。
class _FakeSearch {
  final List<LinkTarget> all;
  LinkQuery? lastQuery;
  LinkKind? lastKind;

  _FakeSearch(this.all);

  Future<List<LinkTarget>> call(LinkQuery query, LinkKind? kind) async {
    lastQuery = query;
    lastKind = kind;
    if (kind == null) return all;
    return all.where((t) => t.kind == kind).toList();
  }
}

/// 打开选择器并把结果记到 [result] 里。
Future<void> _openSheet(
  WidgetTester tester,
  _FakeSearch search,
  List<LinkTarget?> result,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result.add(
                  await showLinkPickerSheet(context, search: search.call),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('打开时不输入也列出最近条目', (tester) async {
    final search = _FakeSearch([
      _target(id: 1, label: '03-12 深圳暴雨'),
      _target(id: 2, label: '03-11 阴天'),
    ]);

    await _openSheet(tester, search, []);

    expect(find.text('03-12 深圳暴雨'), findsOneWidget);
    expect(find.text('03-11 阴天'), findsOneWidget);
    expect(search.lastQuery!.isEmpty, isTrue);
  });

  testWidgets('输入日期后按日期查询', (tester) async {
    final search = _FakeSearch([_target(id: 1, label: '03-12 深圳暴雨')]);

    await _openSheet(tester, search, []);
    await tester.enterText(find.byType(TextField), '3-12');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(search.lastQuery!.isDate, isTrue);
    expect(search.lastQuery!.start, DateTime(DateTime.now().year, 3, 12));
  });

  testWidgets('输入关键字后按关键字查询', (tester) async {
    final search = _FakeSearch([_target(id: 1, label: '03-12 深圳暴雨')]);

    await _openSheet(tester, search, []);
    await tester.enterText(find.byType(TextField), '暴雨');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(search.lastQuery!.isKeyword, isTrue);
    expect(search.lastQuery!.keyword, '暴雨');
  });

  testWidgets('切到"文章"筛选后只查文章', (tester) async {
    final search = _FakeSearch([
      _target(id: 1, label: '03-12 深圳暴雨'),
      _target(id: 7, label: '海岛日志设计稿', kind: LinkKind.article),
    ]);

    await _openSheet(tester, search, []);
    await tester.tap(find.text('文章'));
    await tester.pumpAndSettle();

    expect(search.lastKind, LinkKind.article);
    expect(find.text('海岛日志设计稿'), findsOneWidget);
    expect(find.text('03-12 深圳暴雨'), findsNothing);
  });

  testWidgets('点选条目后关闭并返回该目标', (tester) async {
    final search = _FakeSearch([
      _target(id: 1, label: '03-12 深圳暴雨', remoteName: 'memos/123'),
    ]);
    final result = <LinkTarget?>[];

    await _openSheet(tester, search, result);
    await tester.tap(find.text('03-12 深圳暴雨'));
    await tester.pumpAndSettle();

    expect(result.single!.localId, 1);
    expect(result.single!.remoteName, 'memos/123');
  });

  testWidgets('未同步条目带"未同步"标记', (tester) async {
    final search = _FakeSearch([_target(id: 1, label: '草稿')]);

    await _openSheet(tester, search, []);

    expect(find.text('未同步'), findsOneWidget);
  });

  testWidgets('已同步条目不带标记', (tester) async {
    final search = _FakeSearch([
      _target(id: 1, label: '已同步的', remoteName: 'memos/1'),
    ]);

    await _openSheet(tester, search, []);

    expect(find.text('未同步'), findsNothing);
  });

  testWidgets('无结果时给空状态提示', (tester) async {
    final search = _FakeSearch([]);

    await _openSheet(tester, search, []);

    expect(find.text('没有匹配的日记或文章'), findsOneWidget);
  });
}
