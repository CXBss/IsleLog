# 内链功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让日记和文章可以互相插入链接（按日期或关键字搜索目标），阅读时点击跳转。

**Architecture:** 正文里存标准 Markdown 链接，目标是自定义 scheme `islelog://memo/memos/123?lid=45`（远端名 + 本地 id 双标识）。新增 4 个纯函数模块（URI 构造解析、日期识别、搜索结果映射、跳转判定）+ 1 个选择器 Widget，各编辑器和渲染点只做很薄的接线。不动 Isar 模型，不动服务端。

**Tech Stack:** Flutter + Isar 3.x + flutter_markdown 0.7.x + url_launcher 6.x。包名 `isle_log`。

**Spec:** `docs/superpowers/specs/2026-09-06-inline-links-design.md`

## Global Constraints

- 分支 `server-feat`。API 文档以 `server-API.md` 为准（本功能不碰任何 API）
- **不新增、不修改任何 `@collection` 模型字段** → 全程不需要跑 `dart run build_runner build`
- **不改服务端**，不加数据库字段，不在同步流程里回写任何条目的正文
- **私密空间（vault）完全不接入**：不加插入入口、搜索结果里不出现 vault 条目、`vault_detail_page.dart` 不挂 `onTapLink`
- 自定义 scheme 固定为 `islelog`；host 只有 `memo` 和 `article` 两种
- 所有新文件的注释、日志、UI 文案用中文，与现有代码一致
- 每个任务结束都要 `flutter analyze` 无新增告警
- 已知无关问题：`test/widget_test.dart` 的 `tearDownAll` 超时是既有问题，不要试图"修复"它

---

## 文件结构

**新建**

| 文件 | 职责 |
|---|---|
| `lib/services/link/memo_link.dart` | 纯函数：链接 URI 的构造与解析、显示文字生成与清洗 |
| `lib/services/link/link_query.dart` | 纯函数：搜索框输入 → 日期区间 或 关键字 |
| `lib/services/link/link_target.dart` | 选择器行的数据结构 + 由实体列表构造它的纯函数 |
| `lib/services/link/link_search.dart` | 薄异步层：把 `LinkQuery` 翻译成 `DatabaseService` 调用 |
| `lib/services/link/link_resolver.dart` | 纯函数：由查库结果判定该打开谁 / 报哪种失效 |
| `lib/services/link/link_navigator.dart` | 薄导航层：解析 href → 查库 → push 页面或弹提示 |
| `lib/services/link/link_insertion.dart` | 纯函数：在光标处插入文本，返回新文本与新光标位置 |
| `lib/features/link_picker/link_picker_sheet.dart` | 选择器 BottomSheet |
| `lib/shared/widgets/highlighted_text.dart` | 由 `lib/features/vault/widgets/` 移入（供选择器复用） |

**修改**

| 文件 | 改动 |
|---|---|
| `lib/data/database/database_service.dart` | 新增 `getMemosBetween` / `getRecentMemos` / `getArticlesBetween` / `getRecentArticles` |
| `lib/features/memo_editor/memo_editor_page.dart` | 工具栏加内链按钮 + `_insertLink()` |
| `lib/features/articles/article_editor_page.dart` | 工具栏加内链按钮 + `_insertLink()`；新增 `openInPreview` 参数；预览 `Markdown` 挂 `onTapLink` |
| `lib/features/memo_detail/memo_detail_page.dart` | `MarkdownBody`（约 :480）挂 `onTapLink` |
| `lib/features/vault/widgets/vault_memo_card.dart` | 只改一行 import 路径 |

**明确不改**：`lib/features/home/widgets/memo_timeline_card.dart`（卡片里的链接不响应点击）、`lib/features/vault/vault_detail_page.dart`、`lib/services/sync/**`。

---

### Task 1: MemoLink — 链接格式与显示文字

**Files:**
- Create: `lib/services/link/memo_link.dart`
- Test: `test/services/link/memo_link_test.dart`

**Interfaces:**
- Consumes: 无（零依赖纯函数模块）
- Produces:
  - `enum LinkKind { memo, article }`
  - `class MemoLinkRef { final LinkKind kind; final String? remoteName; final int? localId; }`
  - `String MemoLink.build({required LinkKind kind, String? remoteName, int? localId})`
  - `MemoLinkRef? MemoLink.parse(String href)`
  - `String MemoLink.sanitizeLabel(String raw)`
  - `String MemoLink.labelForMemo({required String content, required DateTime createdAt, DateTime? now})`
  - `String MemoLink.labelForArticle(String title)`
  - `String MemoLink.markdown({required String label, required LinkKind kind, String? remoteName, int? localId})`
  - `String MemoLink.firstLineSummary(String content)`

- [ ] **Step 1: 写失败的测试**

创建 `test/services/link/memo_link_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/link/memo_link.dart';

void main() {
  group('build', () {
    test('已同步日记带远端名和本地 id', () {
      expect(
        MemoLink.build(kind: LinkKind.memo, remoteName: 'memos/123', localId: 45),
        'islelog://memo/memos/123?lid=45',
      );
    });

    test('未同步日记只带本地 id', () {
      expect(
        MemoLink.build(kind: LinkKind.memo, localId: 45),
        'islelog://memo?lid=45',
      );
    });

    test('文章用 article 作为 host', () {
      expect(
        MemoLink.build(kind: LinkKind.article, remoteName: 'articles/7', localId: 12),
        'islelog://article/articles/7?lid=12',
      );
    });
  });

  group('parse', () {
    test('解析出类型、远端名和本地 id', () {
      final ref = MemoLink.parse('islelog://memo/memos/123?lid=45')!;
      expect(ref.kind, LinkKind.memo);
      expect(ref.remoteName, 'memos/123');
      expect(ref.localId, 45);
    });

    test('未同步链接的远端名为 null', () {
      final ref = MemoLink.parse('islelog://memo?lid=45')!;
      expect(ref.remoteName, isNull);
      expect(ref.localId, 45);
    });

    test('文章链接', () {
      final ref = MemoLink.parse('islelog://article/articles/7?lid=12')!;
      expect(ref.kind, LinkKind.article);
      expect(ref.remoteName, 'articles/7');
    });

    test('build 与 parse 往返一致', () {
      const cases = [
        (LinkKind.memo, 'memos/1', 2),
        (LinkKind.article, 'articles/9', 8),
      ];
      for (final (kind, name, lid) in cases) {
        final href = MemoLink.build(kind: kind, remoteName: name, localId: lid);
        final ref = MemoLink.parse(href)!;
        expect(ref.kind, kind);
        expect(ref.remoteName, name);
        expect(ref.localId, lid);
      }
    });

    test('非 islelog scheme 返回 null', () {
      expect(MemoLink.parse('https://example.com/a'), isNull);
    });

    test('未知 host 返回 null', () {
      expect(MemoLink.parse('islelog://folder/folders/1?lid=3'), isNull);
    });

    test('既无远端名也无本地 id 返回 null', () {
      expect(MemoLink.parse('islelog://memo'), isNull);
    });

    test('lid 不是数字时按未同步处理但保留远端名', () {
      final ref = MemoLink.parse('islelog://memo/memos/123?lid=abc')!;
      expect(ref.remoteName, 'memos/123');
      expect(ref.localId, isNull);
    });

    test('非法字符串返回 null 而不抛异常', () {
      expect(MemoLink.parse('::::'), isNull);
      expect(MemoLink.parse(''), isNull);
    });
  });

  group('sanitizeLabel', () {
    test('去掉方括号，避免撑破 Markdown 链接语法', () {
      expect(MemoLink.sanitizeLabel('这是[重点]内容'), '这是重点内容');
    });

    test('换行和制表符压成单个空格', () {
      expect(MemoLink.sanitizeLabel('第一行\n第二行\t尾巴'), '第一行 第二行 尾巴');
    });

    test('连续空白折叠并去掉首尾空白', () {
      expect(MemoLink.sanitizeLabel('  a    b  '), 'a b');
    });
  });

  group('firstLineSummary', () {
    test('去掉标题标记', () {
      expect(MemoLink.firstLineSummary('## 今天的记录\n正文'), '今天的记录');
    });

    test('去掉待办标记', () {
      expect(MemoLink.firstLineSummary('- [ ] 买菜'), '买菜');
    });

    test('去掉引用和列表标记', () {
      expect(MemoLink.firstLineSummary('> 引用一句'), '引用一句');
      expect(MemoLink.firstLineSummary('- 列表项'), '列表项');
      expect(MemoLink.firstLineSummary('1. 第一条'), '第一条');
    });

    test('去掉行内粗体斜体和代码标记', () {
      expect(MemoLink.firstLineSummary('**加粗**和`代码`'), '加粗和代码');
    });

    test('已有的 Markdown 链接只保留文字', () {
      expect(
        MemoLink.firstLineSummary('见[03-12 暴雨](islelog://memo?lid=1)那天'),
        '见03-12 暴雨那天',
      );
    });

    test('跳过开头的空行取第一行有内容的', () {
      expect(MemoLink.firstLineSummary('\n\n真正的首行'), '真正的首行');
    });

    test('全空内容返回空串', () {
      expect(MemoLink.firstLineSummary('   \n\n '), '');
    });
  });

  group('labelForMemo', () {
    final now = DateTime(2026, 9, 6);

    test('同年只写月日，摘要截到 12 字', () {
      final label = MemoLink.labelForMemo(
        content: '深圳暴雨地铁停运了整整一个下午',
        createdAt: DateTime(2026, 3, 12),
        now: now,
      );
      // 摘要按码点截到 12 个字：深圳暴雨地铁停运了整整一
      expect(label, '03-12 深圳暴雨地铁停运了整整一…');
    });

    test('短摘要不加省略号', () {
      final label = MemoLink.labelForMemo(
        content: '晴',
        createdAt: DateTime(2026, 3, 12),
        now: now,
      );
      expect(label, '03-12 晴');
    });

    test('跨年写完整年月日', () {
      final label = MemoLink.labelForMemo(
        content: '旧事',
        createdAt: DateTime(2025, 3, 12),
        now: now,
      );
      expect(label, '2025-03-12 旧事');
    });

    test('正文为空时只有日期', () {
      final label = MemoLink.labelForMemo(
        content: '',
        createdAt: DateTime(2026, 3, 12),
        now: now,
      );
      expect(label, '03-12');
    });

    test('正文里的方括号被清洗掉', () {
      final label = MemoLink.labelForMemo(
        content: '看[这里]',
        createdAt: DateTime(2026, 3, 12),
        now: now,
      );
      expect(label, isNot(contains('[')));
      expect(label, isNot(contains(']')));
    });
  });

  group('markdown', () {
    test('拼出完整的 Markdown 链接', () {
      expect(
        MemoLink.markdown(
          label: '03-12 深圳暴雨',
          kind: LinkKind.memo,
          remoteName: 'memos/123',
          localId: 45,
        ),
        '[03-12 深圳暴雨](islelog://memo/memos/123?lid=45)',
      );
    });

    test('标签里的方括号会被清洗，链接不会被撑破', () {
      final md = MemoLink.markdown(
        label: 'a[b]c',
        kind: LinkKind.memo,
        localId: 1,
      );
      expect(md, '[abc](islelog://memo?lid=1)');
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/services/link/memo_link_test.dart`
Expected: FAIL，报 `Target of URI doesn't exist: 'package:isle_log/services/link/memo_link.dart'`

- [ ] **Step 3: 写实现**

创建 `lib/services/link/memo_link.dart`：

```dart
/// 内链（日记 ↔ 文章互相引用）的链接格式。
///
/// 正文里存的是标准 Markdown 链接，目标用自定义 scheme：
///
/// ```
/// [03-12 深圳暴雨地铁停…](islelog://memo/memos/123?lid=45)
/// [草稿：年终总结](islelog://memo?lid=45)
/// [《海岛日志设计稿》](islelog://article/articles/7?lid=12)
/// ```
///
/// 双标识的理由见 docs/superpowers/specs/2026-09-06-inline-links-design.md：
/// 远端名跨设备有效但未同步条目没有，本地 id 一定有但只在本机有意义。
///
/// 本文件是零依赖纯函数模块，不要在这里引入 Flutter 或 Isar。
library;

/// 链接目标的类型。
enum LinkKind { memo, article }

/// 一条内链解析后的结果。
class MemoLinkRef {
  final LinkKind kind;

  /// 远端资源名，如 "memos/123" / "articles/7"；目标未同步时为 null。
  final String? remoteName;

  /// 目标在本机 Isar 的自增主键；缺失时为 null。
  final int? localId;

  const MemoLinkRef({required this.kind, this.remoteName, this.localId});
}

class MemoLink {
  MemoLink._();

  static const String scheme = 'islelog';

  static const int _summaryMaxChars = 12;

  /// 构造链接 URI。远端名整段进 path，不做字符替换。
  static String build({
    required LinkKind kind,
    String? remoteName,
    int? localId,
  }) {
    final host = kind == LinkKind.memo ? 'memo' : 'article';
    final path = (remoteName == null || remoteName.isEmpty)
        ? ''
        : '/$remoteName';
    final query = localId == null ? '' : '?lid=$localId';
    return '$scheme://$host$path$query';
  }

  /// 解析链接 URI；不是内链、或两个标识都缺失时返回 null。
  static MemoLinkRef? parse(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null || uri.scheme != scheme) return null;

    final LinkKind kind;
    switch (uri.host) {
      case 'memo':
        kind = LinkKind.memo;
      case 'article':
        kind = LinkKind.article;
      default:
        return null;
    }

    final rawPath = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    final remoteName = rawPath.isEmpty ? null : rawPath;
    final localId = int.tryParse(uri.queryParameters['lid'] ?? '');

    // 两个标识都没有的链接无法定位任何条目，视为非法。
    if (remoteName == null && localId == null) return null;

    return MemoLinkRef(kind: kind, remoteName: remoteName, localId: localId);
  }

  /// 清洗链接显示文字。
  ///
  /// 方括号会撑破 `[label](uri)` 语法，换行会让内联链接失效，
  /// 因此必须在拼 Markdown 之前处理掉。
  static String sanitizeLabel(String raw) => raw
      .replaceAll(RegExp(r'[\[\]]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// 取正文第一行有内容的文字，并去掉常见 Markdown 标记。
  static String firstLineSummary(String content) {
    for (final rawLine in content.split('\n')) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      // 行首块级标记：标题 / 引用 / 待办 / 列表
      line = line.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
      line = line.replaceFirst(RegExp(r'^>\s*'), '');
      line = line.replaceFirst(RegExp(r'^[-*+]\s+\[[ xX]\]\s*'), '');
      line = line.replaceFirst(RegExp(r'^[-*+]\s+'), '');
      line = line.replaceFirst(RegExp(r'^\d+\.\s+'), '');
      // 已有的 Markdown 链接与图片只保留文字部分
      line = line.replaceAllMapped(
        RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
        (m) => m.group(1) ?? '',
      );
      // 行内强调标记
      line = line.replaceAll(RegExp(r'(\*{1,3}|_{1,3}|~~|`)'), '');
      line = line.trim();
      if (line.isNotEmpty) return line;
    }
    return '';
  }

  /// 日记的链接显示文字：`MM-DD 首行摘要`，跨年时写全年份。
  static String labelForMemo({
    required String content,
    required DateTime createdAt,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final mm = createdAt.month.toString().padLeft(2, '0');
    final dd = createdAt.day.toString().padLeft(2, '0');
    final datePart = createdAt.year == today.year
        ? '$mm-$dd'
        : '${createdAt.year}-$mm-$dd';

    final summary = sanitizeLabel(_truncate(firstLineSummary(content)));
    return summary.isEmpty ? datePart : '$datePart $summary';
  }

  /// 文章的链接显示文字就是标题；标题为空时给一个占位。
  static String labelForArticle(String title) {
    final label = sanitizeLabel(title);
    return label.isEmpty ? '未命名文章' : label;
  }

  /// 拼出可直接插入正文的 Markdown 链接。
  static String markdown({
    required String label,
    required LinkKind kind,
    String? remoteName,
    int? localId,
  }) {
    final uri = build(kind: kind, remoteName: remoteName, localId: localId);
    return '[${sanitizeLabel(label)}]($uri)';
  }

  /// 按码点截断，避免把中文或 emoji 从中间劈开。
  static String _truncate(String text) {
    final runes = text.runes.toList();
    if (runes.length <= _summaryMaxChars) return text;
    return '${String.fromCharCodes(runes.take(_summaryMaxChars))}…';
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/services/link/memo_link_test.dart`
Expected: PASS，全部用例通过

- [ ] **Step 5: analyze**

Run: `flutter analyze lib/services/link test/services/link`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/services/link/memo_link.dart test/services/link/memo_link_test.dart
git commit -m "feat: 内链 URI 格式与显示文字生成"
```

---

### Task 2: 搜索框输入识别（日期 vs 关键字）

**Files:**
- Create: `lib/services/link/link_query.dart`
- Test: `test/services/link/link_query_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class LinkQuery { final DateTime? start; final DateTime? end; final String keyword; bool get isDate; bool get isKeyword; bool get isEmpty; }`
    - `start` 含端点，`end` **不含**端点（半开区间）
  - `LinkQuery parseLinkQuery(String raw, {DateTime? now})`

- [ ] **Step 1: 写失败的测试**

创建 `test/services/link/link_query_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/link/link_query.dart';

void main() {
  final now = DateTime(2026, 9, 6, 15, 30);

  group('日期识别', () {
    test('月-日 按今年解释', () {
      final q = parseLinkQuery('3-12', now: now);
      expect(q.isDate, isTrue);
      expect(q.start, DateTime(2026, 3, 12));
      expect(q.end, DateTime(2026, 3, 13));
    });

    test('月/日 与月-日 等价', () {
      expect(parseLinkQuery('3/12', now: now).start, DateTime(2026, 3, 12));
    });

    test('补零写法同样识别', () {
      expect(parseLinkQuery('03-12', now: now).start, DateTime(2026, 3, 12));
    });

    test('完整年月日', () {
      final q = parseLinkQuery('2025-03-12', now: now);
      expect(q.start, DateTime(2025, 3, 12));
      expect(q.end, DateTime(2025, 3, 13));
    });

    test('斜杠写法的年月日', () {
      expect(parseLinkQuery('2025/3/12', now: now).start, DateTime(2025, 3, 12));
    });

    test('中文年月日', () {
      expect(
        parseLinkQuery('2025年3月12日', now: now).start,
        DateTime(2025, 3, 12),
      );
    });

    test('年-月 覆盖整月', () {
      final q = parseLinkQuery('2025-03', now: now);
      expect(q.start, DateTime(2025, 3, 1));
      expect(q.end, DateTime(2025, 4, 1));
    });

    test('十二月的整月区间跨到次年一月', () {
      final q = parseLinkQuery('2025-12', now: now);
      expect(q.start, DateTime(2025, 12, 1));
      expect(q.end, DateTime(2026, 1, 1));
    });

    test('中文年月', () {
      expect(parseLinkQuery('2025年3月', now: now).start, DateTime(2025, 3, 1));
    });

    test('今天', () {
      final q = parseLinkQuery('今天', now: now);
      expect(q.start, DateTime(2026, 9, 6));
      expect(q.end, DateTime(2026, 9, 7));
    });

    test('昨天', () {
      expect(parseLinkQuery('昨天', now: now).start, DateTime(2026, 9, 5));
    });

    test('前天', () {
      expect(parseLinkQuery('前天', now: now).start, DateTime(2026, 9, 4));
    });

    test('首尾空格不影响识别', () {
      expect(parseLinkQuery('  3-12  ', now: now).start, DateTime(2026, 3, 12));
    });
  });

  group('关键字', () {
    test('单独四位数字当关键字，不当年份', () {
      final q = parseLinkQuery('2025', now: now);
      expect(q.isDate, isFalse);
      expect(q.keyword, '2025');
    });

    test('普通文字是关键字', () {
      final q = parseLinkQuery('深圳暴雨', now: now);
      expect(q.isKeyword, isTrue);
      expect(q.keyword, '深圳暴雨');
    });

    test('月份越界时退化为关键字', () {
      expect(parseLinkQuery('13-45', now: now).isKeyword, isTrue);
    });

    test('日期越界时退化为关键字', () {
      expect(parseLinkQuery('2025-02-30', now: now).isKeyword, isTrue);
    });

    test('关键字去掉首尾空格', () {
      expect(parseLinkQuery('  暴雨 ', now: now).keyword, '暴雨');
    });
  });

  group('空输入', () {
    test('空串既不是日期也不是关键字', () {
      final q = parseLinkQuery('', now: now);
      expect(q.isEmpty, isTrue);
      expect(q.isDate, isFalse);
      expect(q.isKeyword, isFalse);
    });

    test('纯空格等同空串', () {
      expect(parseLinkQuery('   ', now: now).isEmpty, isTrue);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/services/link/link_query_test.dart`
Expected: FAIL，报找不到 `link_query.dart`

- [ ] **Step 3: 写实现**

创建 `lib/services/link/link_query.dart`：

```dart
/// 内链选择器搜索框的输入解释。
///
/// 一个输入框同时承担"按日期找"和"按关键字找"：先按日期模式逐个匹配，
/// 全不命中才当关键字。零依赖纯函数模块。
library;

/// 搜索框输入的解释结果。
///
/// [start] 含端点、[end] 不含端点（半开区间）；两者要么都有要么都没有。
class LinkQuery {
  final DateTime? start;
  final DateTime? end;
  final String keyword;

  const LinkQuery._({this.start, this.end, this.keyword = ''});

  const LinkQuery.empty() : start = null, end = null, keyword = '';

  bool get isDate => start != null;
  bool get isKeyword => start == null && keyword.isNotEmpty;
  bool get isEmpty => start == null && keyword.isEmpty;
}

/// 把搜索框原始输入解释成日期区间或关键字。
LinkQuery parseLinkQuery(String raw, {DateTime? now}) {
  final text = raw.trim();
  if (text.isEmpty) return const LinkQuery.empty();

  final today = now ?? DateTime.now();

  // 相对日：今天 / 昨天 / 前天
  const relative = {'今天': 0, '昨天': -1, '前天': -2};
  final offset = relative[text];
  if (offset != null) {
    final day = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(Duration(days: offset));
    return _day(day);
  }

  // 年-月-日：2025-03-12 / 2025/3/12 / 2025年3月12日
  final ymd = RegExp(
    r'^(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})日?$',
  ).firstMatch(text);
  if (ymd != null) {
    final day = _validDate(
      int.parse(ymd.group(1)!),
      int.parse(ymd.group(2)!),
      int.parse(ymd.group(3)!),
    );
    if (day != null) return _day(day);
    return _keyword(text);
  }

  // 年-月：2025-03 / 2025年3月
  final ym = RegExp(r'^(\d{4})[-/年](\d{1,2})月?$').firstMatch(text);
  if (ym != null) {
    final year = int.parse(ym.group(1)!);
    final month = int.parse(ym.group(2)!);
    if (month >= 1 && month <= 12) {
      return LinkQuery._(
        start: DateTime(year, month, 1),
        end: DateTime(year, month + 1, 1),
      );
    }
    return _keyword(text);
  }

  // 月-日：3-12 / 03/12，按今年解释
  final md = RegExp(r'^(\d{1,2})[-/](\d{1,2})$').firstMatch(text);
  if (md != null) {
    final day = _validDate(
      today.year,
      int.parse(md.group(1)!),
      int.parse(md.group(2)!),
    );
    if (day != null) return _day(day);
    return _keyword(text);
  }

  // 单独的四位数字不当年份——它更可能是正文里的字。
  return _keyword(text);
}

LinkQuery _day(DateTime day) => LinkQuery._(
  start: DateTime(day.year, day.month, day.day),
  end: DateTime(day.year, day.month, day.day).add(const Duration(days: 1)),
);

LinkQuery _keyword(String text) => LinkQuery._(keyword: text);

/// 构造日期并验证没有被 DateTime 溢出修正（2 月 30 日会变成 3 月 2 日）。
DateTime? _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/services/link/link_query_test.dart`
Expected: PASS

- [ ] **Step 5: analyze**

Run: `flutter analyze lib/services/link test/services/link`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/services/link/link_query.dart test/services/link/link_query_test.dart
git commit -m "feat: 内链搜索框的日期/关键字识别"
```

---

### Task 3: 搜索结果的数据结构与查询层

**Files:**
- Create: `lib/services/link/link_target.dart`
- Create: `lib/services/link/link_search.dart`
- Modify: `lib/data/database/database_service.dart`（在 `getMemosByDate` 后、`getMemoById` 前插入 `getMemosBetween`；在 `searchArticles` 后插入 `getArticlesBetween` 和 `getRecentArticles`）
- Test: `test/services/link/link_target_test.dart`

**Interfaces:**
- Consumes: `LinkKind`、`MemoLink.labelForMemo`、`MemoLink.labelForArticle`、`MemoLink.firstLineSummary`（Task 1）；`LinkQuery`（Task 2）
- Produces:
  - `class LinkTarget { final LinkKind kind; final int localId; final String? remoteName; final String label; final String preview; final DateTime createdAt; final DateTime updatedAt; bool get isSynced; }`
  - `List<LinkTarget> buildLinkTargets({required List<MemoEntry> memos, required List<ArticleEntry> articles, int? excludeMemoId, int? excludeArticleId, DateTime? now, int limit = 50})`
  - `typedef LinkSearchFn = Future<List<LinkTarget>> Function(LinkQuery query, LinkKind? kind)`
  - `Future<List<LinkTarget>> searchLinkTargets(LinkQuery query, LinkKind? kind, {int? excludeMemoId, int? excludeArticleId})`
  - `DatabaseService.getMemosBetween(DateTime start, DateTime endExclusive)`
  - `DatabaseService.getRecentMemos({int limit = 20})`
  - `DatabaseService.getArticlesBetween(DateTime start, DateTime endExclusive)`
  - `DatabaseService.getRecentArticles({int limit = 20})`

- [ ] **Step 1: 写失败的测试**

创建 `test/services/link/link_target_test.dart`（只测纯函数 `buildLinkTargets`，不碰 Isar）：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/article_entry.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/services/link/link_target.dart';
import 'package:isle_log/services/link/memo_link.dart';

MemoEntry _memo({
  required int id,
  String content = '正文',
  String? memosName,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => MemoEntry()
  ..id = id
  ..content = content
  ..memosName = memosName
  ..createdAt = createdAt ?? DateTime(2026, 3, 12)
  ..updatedAt = updatedAt ?? DateTime(2026, 3, 12);

ArticleEntry _article({
  required int id,
  String title = '标题',
  String? articleName,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => ArticleEntry()
  ..id = id
  ..title = title
  ..articleName = articleName
  ..createdAt = createdAt ?? DateTime(2026, 3, 12)
  ..updatedAt = updatedAt ?? DateTime(2026, 3, 12);

void main() {
  final now = DateTime(2026, 9, 6);

  test('日记映射出日期加摘要的标签', () {
    final targets = buildLinkTargets(
      memos: [_memo(id: 1, content: '深圳暴雨', memosName: 'memos/123')],
      articles: [],
      now: now,
    );

    expect(targets.single.kind, LinkKind.memo);
    expect(targets.single.localId, 1);
    expect(targets.single.remoteName, 'memos/123');
    expect(targets.single.label, '03-12 深圳暴雨');
    expect(targets.single.isSynced, isTrue);
  });

  test('文章映射出标题作为标签', () {
    final targets = buildLinkTargets(
      memos: [],
      articles: [_article(id: 7, title: '海岛日志设计稿', articleName: 'articles/7')],
      now: now,
    );

    expect(targets.single.kind, LinkKind.article);
    expect(targets.single.label, '海岛日志设计稿');
    expect(targets.single.preview, '海岛日志设计稿');
  });

  test('没有远端名的条目标记为未同步', () {
    final targets = buildLinkTargets(
      memos: [_memo(id: 1)],
      articles: [],
      now: now,
    );

    expect(targets.single.isSynced, isFalse);
    expect(targets.single.remoteName, isNull);
  });

  test('排除正在编辑的日记自己', () {
    final targets = buildLinkTargets(
      memos: [_memo(id: 1), _memo(id: 2)],
      articles: [],
      excludeMemoId: 1,
      now: now,
    );

    expect(targets.map((t) => t.localId), [2]);
  });

  test('排除正在编辑的文章自己', () {
    final targets = buildLinkTargets(
      memos: [],
      articles: [_article(id: 7), _article(id: 8)],
      excludeArticleId: 7,
      now: now,
    );

    expect(targets.map((t) => t.localId), [8]);
  });

  test('日记与文章按更新时间倒序混排', () {
    final targets = buildLinkTargets(
      memos: [
        _memo(id: 1, content: '旧', updatedAt: DateTime(2026, 1, 1)),
        _memo(id: 2, content: '新', updatedAt: DateTime(2026, 5, 1)),
      ],
      articles: [
        _article(id: 7, title: '中', updatedAt: DateTime(2026, 3, 1)),
      ],
      now: now,
    );

    expect(targets.map((t) => t.localId), [2, 7, 1]);
  });

  test('超过上限时截断', () {
    final targets = buildLinkTargets(
      memos: List.generate(30, (i) => _memo(id: i + 1)),
      articles: [],
      limit: 20,
      now: now,
    );

    expect(targets.length, 20);
  });

  test('日记预览取首行且去掉 Markdown 标记', () {
    final targets = buildLinkTargets(
      memos: [_memo(id: 1, content: '## 今天的记录\n第二行')],
      articles: [],
      now: now,
    );

    expect(targets.single.preview, '今天的记录');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/services/link/link_target_test.dart`
Expected: FAIL，报找不到 `link_target.dart`

- [ ] **Step 3: 写 link_target.dart**

创建 `lib/services/link/link_target.dart`：

```dart
import '../../data/models/article_entry.dart';
import '../../data/models/memo_entry.dart';
import 'memo_link.dart';

/// 选择器列表里的一行：一个可被插入为链接的目标。
class LinkTarget {
  final LinkKind kind;

  /// 目标在本机 Isar 的自增主键。
  final int localId;

  /// 远端资源名，未同步时为 null。
  final String? remoteName;

  /// 插入正文时使用的显示文字。
  final String label;

  /// 列表里展示的摘要：日记取首行，文章取标题。
  final String preview;

  final DateTime createdAt;
  final DateTime updatedAt;

  const LinkTarget({
    required this.kind,
    required this.localId,
    required this.remoteName,
    required this.label,
    required this.preview,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isSynced => remoteName != null;

  /// 拼出可直接插入正文的 Markdown 链接。
  String toMarkdown() => MemoLink.markdown(
    label: label,
    kind: kind,
    remoteName: remoteName,
    localId: localId,
  );
}

/// 把查库结果映射成选择器行，按更新时间倒序混排并截断。
///
/// 纯函数，不碰数据库——查询条件由 [searchLinkTargets] 负责。
List<LinkTarget> buildLinkTargets({
  required List<MemoEntry> memos,
  required List<ArticleEntry> articles,
  int? excludeMemoId,
  int? excludeArticleId,
  DateTime? now,
  int limit = 50,
}) {
  final targets = <LinkTarget>[];

  for (final memo in memos) {
    if (memo.id == excludeMemoId) continue;
    targets.add(
      LinkTarget(
        kind: LinkKind.memo,
        localId: memo.id,
        remoteName: memo.memosName,
        label: MemoLink.labelForMemo(
          content: memo.content,
          createdAt: memo.createdAt,
          now: now,
        ),
        preview: MemoLink.firstLineSummary(memo.content),
        createdAt: memo.createdAt,
        updatedAt: memo.updatedAt,
      ),
    );
  }

  for (final article in articles) {
    if (article.id == excludeArticleId) continue;
    final label = MemoLink.labelForArticle(article.title);
    targets.add(
      LinkTarget(
        kind: LinkKind.article,
        localId: article.id,
        remoteName: article.articleName,
        label: label,
        preview: label,
        createdAt: article.createdAt,
        updatedAt: article.updatedAt,
      ),
    );
  }

  targets.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return targets.length <= limit ? targets : targets.sublist(0, limit);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/services/link/link_target_test.dart`
Expected: PASS

- [ ] **Step 5: 给 DatabaseService 加区间查询**

在 `lib/data/database/database_service.dart` 中 `getMemosByDate` 方法之后插入：

```dart
  /// 获取 [start]（含）到 [endExclusive]（不含）之间创建的未删除、未归档日记。
  ///
  /// 供内链选择器按月/按日筛选使用。Isar 的 createdAtBetween 两端都含，
  /// 因此上界减 1 毫秒来实现半开区间。
  static Future<List<MemoEntry>> getMemosBetween(
    DateTime start,
    DateTime endExclusive,
  ) async {
    final isar = await db;
    final result = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .createdAtBetween(
          start,
          endExclusive.subtract(const Duration(milliseconds: 1)),
        )
        .sortByCreatedAtDesc()
        .findAll();
    debugPrint('[DB] getMemosBetween($start, $endExclusive) → ${result.length} 条');
    return result;
  }

  /// 获取最近更新的未删除、未归档日记。
  ///
  /// 与 getMemosPaged 的区别：**不排除置顶条目**。置顶只影响时间线的排布，
  /// 不应该让一条日记在内链选择器里消失。
  static Future<List<MemoEntry>> getRecentMemos({int limit = 20}) async {
    final isar = await db;
    final result = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .sortByUpdatedAtDesc()
        .limit(limit)
        .findAll();
    debugPrint('[DB] getRecentMemos limit=$limit → ${result.length} 条');
    return result;
  }
```

在同一文件中 `searchArticles` 方法之后插入：

```dart
  /// 获取 [start]（含）到 [endExclusive]（不含）之间创建的未删除、未归档文章。
  static Future<List<ArticleEntry>> getArticlesBetween(
    DateTime start,
    DateTime endExclusive,
  ) async {
    final isar = await db;
    final result = await isar.articleEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .createdAtBetween(
          start,
          endExclusive.subtract(const Duration(milliseconds: 1)),
        )
        .sortByCreatedAtDesc()
        .findAll();
    debugPrint(
      '[DB] getArticlesBetween($start, $endExclusive) → ${result.length} 条',
    );
    return result;
  }

  /// 获取最近更新的未删除、未归档文章。
  static Future<List<ArticleEntry>> getRecentArticles({int limit = 20}) async {
    final isar = await db;
    final result = await isar.articleEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .sortByUpdatedAtDesc()
        .limit(limit)
        .findAll();
    debugPrint('[DB] getRecentArticles limit=$limit → ${result.length} 条');
    return result;
  }
```

- [ ] **Step 6: 写 link_search.dart**

创建 `lib/services/link/link_search.dart`：

```dart
import '../../data/database/database_service.dart';
import '../../data/models/article_entry.dart';
import '../../data/models/memo_entry.dart';
import 'link_query.dart';
import 'link_target.dart';
import 'memo_link.dart';

/// 选择器使用的搜索入口签名。
///
/// 抽成 typedef 是为了让 widget 测试注入假数据，不必拖起 Isar。
typedef LinkSearchFn =
    Future<List<LinkTarget>> Function(LinkQuery query, LinkKind? kind);

/// 按 [query] 查出可作为链接目标的日记与文章。
///
/// [kind] 为 null 表示两种都要。归档、已删除、私密空间条目均不在结果内
/// （vault 是独立的加密存储，本来就不经过 DatabaseService）。
Future<List<LinkTarget>> searchLinkTargets(
  LinkQuery query,
  LinkKind? kind, {
  int? excludeMemoId,
  int? excludeArticleId,
}) async {
  final wantMemo = kind == null || kind == LinkKind.memo;
  final wantArticle = kind == null || kind == LinkKind.article;

  var memos = <MemoEntry>[];
  var articles = <ArticleEntry>[];

  if (query.isDate) {
    if (wantMemo) {
      memos = await DatabaseService.getMemosBetween(query.start!, query.end!);
    }
    if (wantArticle) {
      articles = await DatabaseService.getArticlesBetween(
        query.start!,
        query.end!,
      );
    }
  } else if (query.isKeyword) {
    if (wantMemo) memos = await DatabaseService.searchMemos(query.keyword);
    if (wantArticle) {
      articles = await DatabaseService.searchArticles(query.keyword);
      // searchArticles 不过滤归档，这里补上。
      articles = articles.where((a) => !a.isArchived).toList();
    }
  } else {
    // 空输入：列最近更新的条目，不输入也能选。
    if (wantMemo) memos = await DatabaseService.getRecentMemos(limit: 20);
    if (wantArticle) {
      articles = await DatabaseService.getRecentArticles(limit: 20);
    }
  }

  return buildLinkTargets(
    memos: memos,
    articles: articles,
    excludeMemoId: excludeMemoId,
    excludeArticleId: excludeArticleId,
    limit: 50,
  );
}
```

- [ ] **Step 7: 跑测试与 analyze**

Run: `flutter test test/services/link/`
Expected: PASS

Run: `flutter analyze lib/services/link lib/data/database test/services/link`
Expected: `No issues found!`

- [ ] **Step 8: 提交**

```bash
git add lib/services/link/link_target.dart lib/services/link/link_search.dart \
        lib/data/database/database_service.dart test/services/link/link_target_test.dart
git commit -m "feat: 内链目标的查询与映射"
```

---

### Task 4: 选择器 BottomSheet

**Files:**
- Move: `lib/features/vault/widgets/highlighted_text.dart` → `lib/shared/widgets/highlighted_text.dart`
- Modify: `lib/features/vault/widgets/vault_memo_card.dart:5`（import 路径）
- Create: `lib/features/link_picker/link_picker_sheet.dart`
- Test: `test/features/link_picker/link_picker_sheet_test.dart`

**Interfaces:**
- Consumes: `LinkTarget`、`LinkSearchFn`、`searchLinkTargets`（Task 3）；`parseLinkQuery`（Task 2）；`LinkKind`（Task 1）
- Produces:
  - `Future<LinkTarget?> showLinkPickerSheet(BuildContext context, {LinkSearchFn? search, int? excludeMemoId, int? excludeArticleId})`

- [ ] **Step 1: 移动 HighlightedText 到 shared**

```bash
git mv lib/features/vault/widgets/highlighted_text.dart lib/shared/widgets/highlighted_text.dart
```

把 `lib/shared/widgets/highlighted_text.dart` 里的 import 由

```dart
import '../../../shared/constants/app_constants.dart';
```

改成

```dart
import '../constants/app_constants.dart';
```

把 `lib/features/vault/widgets/vault_memo_card.dart:5` 的

```dart
import 'highlighted_text.dart';
```

改成

```dart
import '../../../shared/widgets/highlighted_text.dart';
```

同时把 `highlighted_text.dart` 类注释里提到 `VaultBrowseModel.apply` 的那句改成「与调用方的搜索口径保持一致」——它现在是共享组件了，不该再指向 vault。

Run: `flutter analyze lib`
Expected: `No issues found!`

- [ ] **Step 2: 写失败的测试**

创建 `test/features/link_picker/link_picker_sheet_test.dart`：

```dart
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
}) => LinkTarget(
  kind: kind,
  localId: id,
  remoteName: remoteName,
  label: label,
  preview: label,
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
```

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/features/link_picker/link_picker_sheet_test.dart`
Expected: FAIL，报找不到 `link_picker_sheet.dart`

- [ ] **Step 4: 写实现**

创建 `lib/features/link_picker/link_picker_sheet.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/link/link_query.dart';
import '../../services/link/link_search.dart';
import '../../services/link/link_target.dart';
import '../../services/link/memo_link.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/widgets/highlighted_text.dart';

/// 弹出内链选择器，返回用户选中的目标；用户取消时返回 null。
///
/// [search] 仅供测试注入，生产代码不要传。
Future<LinkTarget?> showLinkPickerSheet(
  BuildContext context, {
  LinkSearchFn? search,
  int? excludeMemoId,
  int? excludeArticleId,
}) => showModalBottomSheet<LinkTarget>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _LinkPickerSheet(
    search:
        search ??
        (query, kind) => searchLinkTargets(
          query,
          kind,
          excludeMemoId: excludeMemoId,
          excludeArticleId: excludeArticleId,
        ),
  ),
);

class _LinkPickerSheet extends StatefulWidget {
  final LinkSearchFn search;
  const _LinkPickerSheet({required this.search});

  @override
  State<_LinkPickerSheet> createState() => _LinkPickerSheetState();
}

class _LinkPickerSheetState extends State<_LinkPickerSheet> {
  final TextEditingController _queryCtrl = TextEditingController();

  /// null 表示"全部"。
  LinkKind? _kindFilter;

  List<LinkTarget> _results = [];
  bool _loading = true;
  Timer? _debounce;

  /// 每次查询自增，用于丢弃过期的异步结果。
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _runSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  /// 输入变化时防抖，避免每敲一个字都全表扫描一遍。
  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  Future<void> _runSearch() async {
    final seq = ++_requestSeq;
    setState(() => _loading = true);
    final query = parseLinkQuery(_queryCtrl.text);
    final results = await widget.search(query, _kindFilter);
    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  void _setFilter(LinkKind? kind) {
    setState(() => _kindFilter = kind);
    _runSearch();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    final text =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}'
        '-${picked.day.toString().padLeft(2, '0')}';
    _queryCtrl.text = text;
    await _runSearch();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '插入链接',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            _buildSearchField(),
            _buildFilterChips(),
            const Divider(height: 1),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: TextField(
      controller: _queryCtrl,
      autofocus: false,
      textInputAction: TextInputAction.search,
      onChanged: _onQueryChanged,
      onSubmitted: (_) => _runSearch(),
      decoration: InputDecoration(
        isDense: true,
        hintText: '搜索日期或关键字，如 3-12 / 暴雨',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          tooltip: '选择日期',
          onPressed: _pickDate,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );

  Widget _buildFilterChips() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        _chip('全部', null),
        const SizedBox(width: 8),
        _chip('日记', LinkKind.memo),
        const SizedBox(width: 8),
        _chip('文章', LinkKind.article),
      ],
    ),
  );

  Widget _chip(String label, LinkKind? kind) => ChoiceChip(
    label: Text(label),
    selected: _kindFilter == kind,
    onSelected: (_) => _setFilter(kind),
  );

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的日记或文章',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      );
    }
    final keyword = parseLinkQuery(_queryCtrl.text).keyword;
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 48),
      itemBuilder: (_, index) => _buildRow(_results[index], keyword),
    );
  }

  Widget _buildRow(LinkTarget target, String keyword) {
    final isMemo = target.kind == LinkKind.memo;
    return ListTile(
      dense: true,
      leading: Icon(
        isMemo ? Icons.article_outlined : Icons.description_outlined,
        size: 20,
        color: AppColors.primary,
      ),
      title: HighlightedText(
        text: target.label,
        query: keyword,
        maxLines: 1,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        '${target.createdAt.year}-'
        '${target.createdAt.month.toString().padLeft(2, '0')}-'
        '${target.createdAt.day.toString().padLeft(2, '0')}',
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
      ),
      trailing: target.isSynced
          ? null
          : Text(
              '未同步',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
      onTap: () => Navigator.pop(context, target),
    );
  }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/features/link_picker/link_picker_sheet_test.dart`
Expected: PASS

如果 `AppColors.primary` 不是静态常量而是需要 context 的方法，按 `lib/shared/constants/app_constants.dart` 里的实际签名调整（其它页面怎么用就怎么用）。

- [ ] **Step 6: analyze + 全量测试**

Run: `flutter analyze lib test`
Expected: `No issues found!`

Run: `flutter test test/features test/services test/data`
Expected: PASS（`widget_test.dart` 不在这批里，它的既有超时问题与本次无关）

- [ ] **Step 7: 提交**

```bash
git add lib/shared/widgets/highlighted_text.dart lib/features/vault/widgets/vault_memo_card.dart \
        lib/features/link_picker/link_picker_sheet.dart \
        test/features/link_picker/link_picker_sheet_test.dart
git commit -m "feat: 内链选择器（按日期或关键字搜索日记与文章）"
```

---

### Task 5: 光标处插入 + 日记编辑器接入

**Files:**
- Create: `lib/services/link/link_insertion.dart`
- Modify: `lib/features/memo_editor/memo_editor_page.dart`（在 `_insertTodo` 后加 `_insertLink`；工具栏 Todo 按钮之后加内链按钮）
- Test: `test/services/link/link_insertion_test.dart`

**Interfaces:**
- Consumes: `LinkTarget.toMarkdown()`（Task 3）、`showLinkPickerSheet`（Task 4）
- Produces:
  - `class TextInsertion { final String text; final int cursor; }`
  - `TextInsertion insertAtCursor({required String text, required int cursor, required String insert})`

- [ ] **Step 1: 写失败的测试**

创建 `test/services/link/link_insertion_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/link/link_insertion.dart';

void main() {
  test('在光标处插入，光标落到插入内容之后', () {
    final result = insertAtCursor(text: '前后', cursor: 1, insert: '中');

    expect(result.text, '前中后');
    expect(result.cursor, 2);
  });

  test('光标在开头', () {
    final result = insertAtCursor(text: 'abc', cursor: 0, insert: 'X');

    expect(result.text, 'Xabc');
    expect(result.cursor, 1);
  });

  test('光标在末尾', () {
    final result = insertAtCursor(text: 'abc', cursor: 3, insert: 'X');

    expect(result.text, 'abcX');
    expect(result.cursor, 4);
  });

  test('光标无效（-1）时追加到末尾', () {
    final result = insertAtCursor(text: 'abc', cursor: -1, insert: 'X');

    expect(result.text, 'abcX');
    expect(result.cursor, 4);
  });

  test('光标越界时追加到末尾', () {
    final result = insertAtCursor(text: 'abc', cursor: 99, insert: 'X');

    expect(result.text, 'abcX');
    expect(result.cursor, 4);
  });

  test('空正文', () {
    final result = insertAtCursor(text: '', cursor: 0, insert: 'X');

    expect(result.text, 'X');
    expect(result.cursor, 1);
  });

  test('不额外补空格', () {
    final result = insertAtCursor(
      text: '跟那天一样',
      cursor: 1,
      insert: '[03-12 暴雨](islelog://memo?lid=1)',
    );

    expect(result.text, '跟[03-12 暴雨](islelog://memo?lid=1)那天一样');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/services/link/link_insertion_test.dart`
Expected: FAIL，报找不到 `link_insertion.dart`

- [ ] **Step 3: 写实现**

创建 `lib/services/link/link_insertion.dart`：

```dart
/// 在光标处插入文本的纯计算，供两个编辑器共用。
///
/// 抽出来是为了能单测：编辑器里的 TextEditingController 操作没法直接断言。
library;

/// 一次插入的结果：新正文与新光标位置。
class TextInsertion {
  final String text;
  final int cursor;

  const TextInsertion({required this.text, required this.cursor});
}

/// 在 [cursor] 处插入 [insert]，光标落到插入内容之后。
///
/// [cursor] 无效（负数或越界）时追加到末尾——这与编辑器里
/// `sel.isValid ? sel.baseOffset : text.length` 的既有约定一致。
/// 不做任何空格补齐，与 `_insertAtCursor` 的现有行为保持一致。
TextInsertion insertAtCursor({
  required String text,
  required int cursor,
  required String insert,
}) {
  final pos = (cursor < 0 || cursor > text.length) ? text.length : cursor;
  return TextInsertion(
    text: text.substring(0, pos) + insert + text.substring(pos),
    cursor: pos + insert.length,
  );
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/services/link/link_insertion_test.dart`
Expected: PASS

- [ ] **Step 5: 日记编辑器接入**

在 `lib/features/memo_editor/memo_editor_page.dart` 顶部 import 区加（与既有相对路径风格一致）：

```dart
import '../../services/link/link_insertion.dart';
import '../link_picker/link_picker_sheet.dart';
```

在 `_insertTodo()` 定义之后插入：

```dart
  /// 弹出内链选择器，把选中的日记/文章作为 Markdown 链接插到光标处。
  Future<void> _insertLink() async {
    final target = await showLinkPickerSheet(
      context,
      excludeMemoId: widget.editingMemo?.id,
    );
    if (target == null || !mounted) return;

    final ctrl = _contentCtrl;
    final sel = ctrl.selection;
    final result = insertAtCursor(
      text: ctrl.text,
      cursor: sel.isValid ? sel.baseOffset : ctrl.text.length,
      insert: target.toMarkdown(),
    );
    ctrl.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
    _contentFocus.requestFocus();
  }
```

在工具栏第一行、Todo 按钮（`_FmtButton(icon: Icons.check_box_outline_blank, tooltip: 'Todo', ...)`）之后插入：

```dart
                        _FmtButton(
                          icon: Icons.add_link,
                          tooltip: '插入内链',
                          onTap: _insertLink,
                        ),
```

- [ ] **Step 6: analyze + 全量测试**

Run: `flutter analyze lib test`
Expected: `No issues found!`

Run: `flutter test test/features test/services test/data`
Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add lib/services/link/link_insertion.dart test/services/link/link_insertion_test.dart \
        lib/features/memo_editor/memo_editor_page.dart
git commit -m "feat: 日记编辑器支持插入内链"
```

---

### Task 6: 文章编辑器接入 + 预览模式参数

**Files:**
- Modify: `lib/features/articles/article_editor_page.dart`
  - 构造函数加 `openInPreview`（约 :36-41）
  - `initState` 初始化 `_previewMode`（约 :79）
  - `_insertAtCursor` 之后加 `_insertLink`（约 :512）
  - `_buildToolbar()` 第一行按钮追加内链按钮（约 :691）

**Interfaces:**
- Consumes: `insertAtCursor`（Task 5）、`showLinkPickerSheet`（Task 4）
- Produces: `ArticleEditorPage({Key? key, ArticleEntry? editingArticle, FolderEntry? initialFolder, bool openInPreview})`——Task 8 的跳转要用它直接进预览模式

- [ ] **Step 1: 加 openInPreview 参数**

把 `lib/features/articles/article_editor_page.dart` 的类头改成：

```dart
class ArticleEditorPage extends StatefulWidget {
  final ArticleEntry? editingArticle;
  /// 新建时可预设文件夹
  final FolderEntry? initialFolder;

  /// 打开时直接进入预览（阅读）模式。
  ///
  /// 内链跳转到文章时用：点链接是"去读"，不是"去改"。
  final bool openInPreview;

  const ArticleEditorPage({
    super.key,
    this.editingArticle,
    this.initialFolder,
    this.openInPreview = false,
  });
```

在 `initState()` 里，`_contentCtrl` 初始化之后加一行：

```dart
    _previewMode = widget.openInPreview;
```

- [ ] **Step 2: 加 _insertLink**

顶部 import 区加：

```dart
import '../../services/link/link_insertion.dart';
import '../link_picker/link_picker_sheet.dart';
```

在 `_insertLinePrefix` 之后插入：

```dart
  /// 弹出内链选择器，把选中的日记/文章作为 Markdown 链接插到光标处。
  Future<void> _insertLink() async {
    final target = await showLinkPickerSheet(
      context,
      excludeArticleId: widget.editingArticle?.id,
    );
    if (target == null || !mounted) return;

    final ctrl = _contentCtrl;
    final sel = ctrl.selection;
    final result = insertAtCursor(
      text: ctrl.text,
      cursor: sel.isValid ? sel.baseOffset : ctrl.text.length,
      insert: target.toMarkdown(),
    );
    ctrl.value = ctrl.value.copyWith(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
    _contentFocus.requestFocus();
  }
```

- [ ] **Step 3: 加工具栏按钮**

在 `_buildToolbar()` 第一行按钮里，`Icons.format_quote`（引用）那个 `_ToolbarBtn` 之后追加：

```dart
                  _ToolbarBtn(icon: Icons.add_link, tooltip: '插入内链',
                      onTap: _insertLink),
```

注意：这一行紧邻已有的 `_ToolbarBtn(icon: Icons.link, tooltip: '链接', ...)`（插入普通外链 `[](url)`）。两者必须保持不同的图标和 tooltip，不要合并、不要替换。

- [ ] **Step 4: analyze + 全量测试**

Run: `flutter analyze lib test`
Expected: `No issues found!`

Run: `flutter test test/features test/services test/data`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/features/articles/article_editor_page.dart
git commit -m "feat: 文章编辑器支持插入内链，并可直接以预览模式打开"
```

---

### Task 7: 跳转判定（纯函数）

**Files:**
- Create: `lib/services/link/link_resolver.dart`
- Test: `test/services/link/link_resolver_test.dart`

**Interfaces:**
- Consumes: `MemoLinkRef`（Task 1）
- Produces:
  - `class LinkedEntitySnapshot { final String? remoteName; final bool isDeleted; }`
  - `enum LinkAction { openByRemoteName, openByLocalId, notSynced, missing }`
  - `LinkAction decideLinkAction({required MemoLinkRef ref, required LinkedEntitySnapshot? byRemoteName, required LinkedEntitySnapshot? byLocalId})`

- [ ] **Step 1: 写失败的测试**

创建 `test/services/link/link_resolver_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/link/link_resolver.dart';
import 'package:isle_log/services/link/memo_link.dart';

const _synced = MemoLinkRef(
  kind: LinkKind.memo,
  remoteName: 'memos/123',
  localId: 45,
);
const _unsynced = MemoLinkRef(kind: LinkKind.memo, localId: 45);

void main() {
  test('按远端名查到就打开它', () {
    expect(
      decideLinkAction(
        ref: _synced,
        byRemoteName: const LinkedEntitySnapshot(remoteName: 'memos/123'),
        byLocalId: null,
      ),
      LinkAction.openByRemoteName,
    );
  });

  test('远端名查不到时用本地 id 兜底', () {
    expect(
      decideLinkAction(
        ref: _synced,
        byRemoteName: null,
        byLocalId: const LinkedEntitySnapshot(remoteName: 'memos/123'),
      ),
      LinkAction.openByLocalId,
    );
  });

  test('本地 id 命中的条目还没同步过，视为同一条', () {
    expect(
      decideLinkAction(
        ref: _unsynced,
        byRemoteName: null,
        byLocalId: const LinkedEntitySnapshot(remoteName: null),
      ),
      LinkAction.openByLocalId,
    );
  });

  test('本地 id 撞到了远端名不一致的条目，判定为失效', () {
    // 换设备后 Isar 自增 id 会撞车，没有这一步会跳到完全无关的日记
    expect(
      decideLinkAction(
        ref: _synced,
        byRemoteName: null,
        byLocalId: const LinkedEntitySnapshot(remoteName: 'memos/999'),
      ),
      LinkAction.missing,
    );
  });

  test('远端名命中但条目已软删除，判定为失效', () {
    expect(
      decideLinkAction(
        ref: _synced,
        byRemoteName: const LinkedEntitySnapshot(
          remoteName: 'memos/123',
          isDeleted: true,
        ),
        byLocalId: null,
      ),
      LinkAction.missing,
    );
  });

  test('本地 id 命中但条目已软删除，判定为失效', () {
    expect(
      decideLinkAction(
        ref: _unsynced,
        byRemoteName: null,
        byLocalId: const LinkedEntitySnapshot(
          remoteName: null,
          isDeleted: true,
        ),
      ),
      LinkAction.missing,
    );
  });

  test('链接没有远端名且本地也查不到，说明目标没同步到本设备', () {
    expect(
      decideLinkAction(ref: _unsynced, byRemoteName: null, byLocalId: null),
      LinkAction.notSynced,
    );
  });

  test('链接有远端名但两边都查不到，说明条目已不存在', () {
    expect(
      decideLinkAction(ref: _synced, byRemoteName: null, byLocalId: null),
      LinkAction.missing,
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/services/link/link_resolver_test.dart`
Expected: FAIL，报找不到 `link_resolver.dart`

- [ ] **Step 3: 写实现**

创建 `lib/services/link/link_resolver.dart`：

```dart
import 'memo_link.dart';

/// 查库结果里跳转判定需要用到的那两个字段。
///
/// 用快照而不是直接吃 MemoEntry / ArticleEntry，是为了让判定逻辑保持纯粹、
/// 同时服务日记和文章两种实体。
class LinkedEntitySnapshot {
  final String? remoteName;
  final bool isDeleted;

  const LinkedEntitySnapshot({this.remoteName, this.isDeleted = false});
}

/// 点击一条内链之后该做什么。
enum LinkAction {
  /// 打开按远端名查到的那条
  openByRemoteName,

  /// 打开按本地 id 查到的那条
  openByLocalId,

  /// 目标从未同步到本设备
  notSynced,

  /// 目标已不存在或已被删除
  missing,
}

/// 由两次查库的结果判定该打开谁、或报哪种失效。
///
/// 归档条目照常打开——是用户主动点的，读得到才合理；软删除则按失效处理。
LinkAction decideLinkAction({
  required MemoLinkRef ref,
  required LinkedEntitySnapshot? byRemoteName,
  required LinkedEntitySnapshot? byLocalId,
}) {
  if (byRemoteName != null && !byRemoteName.isDeleted) {
    return LinkAction.openByRemoteName;
  }

  if (byLocalId != null && !byLocalId.isDeleted) {
    // 本地 id 在别的设备上指向完全不同的条目。若命中的条目自己有远端名、
    // 却和链接里的对不上，说明这不是同一条。
    final sameEntity =
        byLocalId.remoteName == null || byLocalId.remoteName == ref.remoteName;
    if (sameEntity) return LinkAction.openByLocalId;
  }

  // 链接本身就没有远端名，说明目标当初就没同步过，换设备自然找不到。
  if (ref.remoteName == null) return LinkAction.notSynced;

  return LinkAction.missing;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/services/link/link_resolver_test.dart`
Expected: PASS

- [ ] **Step 5: analyze**

Run: `flutter analyze lib/services/link test/services/link`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/services/link/link_resolver.dart test/services/link/link_resolver_test.dart
git commit -m "feat: 内链跳转判定（远端名优先，本地 id 兜底并校验）"
```

---

### Task 8: 点击跳转接线

**Files:**
- Create: `lib/services/link/link_navigator.dart`
- Modify: `lib/features/memo_detail/memo_detail_page.dart`（`MarkdownBody` 约 :480）
- Modify: `lib/features/articles/article_editor_page.dart`（预览 `Markdown` 约 :622）

**Interfaces:**
- Consumes: `MemoLink.parse`、`decideLinkAction`、`LinkedEntitySnapshot`、`LinkAction`（Task 1、7）；`ArticleEditorPage.openInPreview`（Task 6）
- Produces: `Future<void> LinkNavigator.openHref(BuildContext context, String? href)`

- [ ] **Step 1: 写 link_navigator.dart**

创建 `lib/services/link/link_navigator.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../data/database/database_service.dart';
import '../../features/articles/article_editor_page.dart';
import '../../features/memo_detail/memo_detail_page.dart';
import 'link_resolver.dart';
import 'memo_link.dart';

/// 点击正文里的链接之后的落地处理。
///
/// 内链走本地查库 + 页面跳转，其它 URL 交给系统浏览器。
class LinkNavigator {
  LinkNavigator._();

  static Future<void> openHref(BuildContext context, String? href) async {
    if (href == null || href.isEmpty) return;

    final ref = MemoLink.parse(href);
    if (ref == null) {
      // 普通外链。用 launchUrlString 而非 Uri，理由同 location_service：
      // 绕过 Uri 对汉字的自动 percent-encode。
      await launchUrlString(href, mode: LaunchMode.externalApplication);
      return;
    }

    // await 之前先取出，避免跨异步边界用 context。
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (ref.kind == LinkKind.memo) {
      await _openMemo(navigator, messenger, ref);
    } else {
      await _openArticle(navigator, messenger, ref);
    }
  }

  static Future<void> _openMemo(
    NavigatorState navigator,
    ScaffoldMessengerState messenger,
    MemoLinkRef ref,
  ) async {
    final byName = ref.remoteName == null
        ? null
        : await DatabaseService.getMemoByMemosName(ref.remoteName!);
    final byId = ref.localId == null
        ? null
        : await DatabaseService.getMemoById(ref.localId!);

    final action = decideLinkAction(
      ref: ref,
      byRemoteName: byName == null
          ? null
          : LinkedEntitySnapshot(
              remoteName: byName.memosName,
              isDeleted: byName.isDeleted,
            ),
      byLocalId: byId == null
          ? null
          : LinkedEntitySnapshot(
              remoteName: byId.memosName,
              isDeleted: byId.isDeleted,
            ),
    );

    switch (action) {
      case LinkAction.openByRemoteName:
        await navigator.push(
          MaterialPageRoute(builder: (_) => MemoDetailPage(memo: byName!)),
        );
      case LinkAction.openByLocalId:
        await navigator.push(
          MaterialPageRoute(builder: (_) => MemoDetailPage(memo: byId!)),
        );
      case LinkAction.notSynced:
        _toast(messenger, '这条日记还没同步到本设备');
      case LinkAction.missing:
        _toast(messenger, '链接的条目已不存在或已被删除');
    }
  }

  static Future<void> _openArticle(
    NavigatorState navigator,
    ScaffoldMessengerState messenger,
    MemoLinkRef ref,
  ) async {
    final byName = ref.remoteName == null
        ? null
        : await DatabaseService.getArticleByArticleName(ref.remoteName!);
    final byId = ref.localId == null
        ? null
        : await DatabaseService.getArticleById(ref.localId!);

    final action = decideLinkAction(
      ref: ref,
      byRemoteName: byName == null
          ? null
          : LinkedEntitySnapshot(
              remoteName: byName.articleName,
              isDeleted: byName.isDeleted,
            ),
      byLocalId: byId == null
          ? null
          : LinkedEntitySnapshot(
              remoteName: byId.articleName,
              isDeleted: byId.isDeleted,
            ),
    );

    switch (action) {
      case LinkAction.openByRemoteName:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) =>
                ArticleEditorPage(editingArticle: byName!, openInPreview: true),
          ),
        );
      case LinkAction.openByLocalId:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) =>
                ArticleEditorPage(editingArticle: byId!, openInPreview: true),
          ),
        );
      case LinkAction.notSynced:
        _toast(messenger, '这篇文章还没同步到本设备');
      case LinkAction.missing:
        _toast(messenger, '链接的条目已不存在或已被删除');
    }
  }

  static void _toast(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
```

`getArticleByArticleName` 的第二个参数如果不是可选的，按 `database_service.dart:1122` 的实际签名调用。

- [ ] **Step 2: 日记详情页挂 onTapLink**

在 `lib/features/memo_detail/memo_detail_page.dart` 顶部 import 区加：

```dart
import '../../services/link/link_navigator.dart';
```

在正文那个 `MarkdownBody`（约 :480，`data: _displayContent` 那个）的 `styleSheet:` 之后加一行：

```dart
                        onTapLink: (_, href, _) =>
                            LinkNavigator.openHref(context, href),
```

注意：**只改正文那一处**。同文件里评论区的 `MarkdownBody`（约 :953）和冲突远端版本的 `MarkdownBody`（约 :1330）都不加——评论没有插入入口，冲突区是只读对照。

- [ ] **Step 3: 文章预览挂 onTapLink**

在 `lib/features/articles/article_editor_page.dart` 顶部 import 区加：

```dart
import '../../services/link/link_navigator.dart';
```

把预览区的 `Markdown`（约 :622）改成：

```dart
                ? Markdown(
                    data: _contentCtrl.text.isEmpty ? '*（内容为空）*' : _contentCtrl.text,
                    padding: const EdgeInsets.all(16),
                    onTapLink: (_, href, _) =>
                        LinkNavigator.openHref(context, href),
                  )
```

- [ ] **Step 4: 确认时间线卡片没被改动**

Run: `git diff --stat lib/features/home/widgets/memo_timeline_card.dart`
Expected: 无输出（卡片里的链接不响应点击，是设计决定，不是遗漏）

- [ ] **Step 5: analyze + 全量测试**

Run: `flutter analyze lib test`
Expected: `No issues found!`

Run: `flutter test test/features test/services test/data`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add lib/services/link/link_navigator.dart \
        lib/features/memo_detail/memo_detail_page.dart \
        lib/features/articles/article_editor_page.dart
git commit -m "feat: 详情页与文章预览支持点击内链跳转"
```

---

### Task 9: 端到端验证

**Files:** 无新增，只跑验证

- [ ] **Step 1: 全量静态检查**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: 新增的 7 个测试文件全部 PASS。`test/widget_test.dart` 的 `tearDownAll` 超时是既有问题，不要动它——但要确认**除它以外**没有新的失败。

- [ ] **Step 3: 真机/模拟器冒烟**

跑起应用，按顺序验证：

1. 新建一条日记 → 工具栏点内链按钮 → 不输入任何内容，能看到最近条目列表
2. 输入 `3-12` → 只列出 3 月 12 日的条目；输入一个关键字 → 列出全文命中的条目
3. 点日历图标选一个日期 → 输入框填入 `yyyy-MM-dd`，列表随之刷新
4. 切到"文章"chip → 只剩文章
5. 选中一条 → 正文光标处出现 `[03-12 …](islelog://memo/…)`
6. 保存 → 进详情页 → 点那个链接 → 跳到目标日记详情；按返回能回来
7. 在首页时间线卡片上点那段链接文字 → 进的是**本条**详情，不是链接目标
8. 文章编辑器里插一条内链 → 切预览模式 → 点它能跳走
9. 编辑一条日记插入链接后**不同步**，链接形如 `islelog://memo?lid=N` 时仍可点开
10. 详情页里放一个普通 `https://` 链接，点击能唤起浏览器（这是本次顺带修的）
11. **键盘弹起时选择器仍然好用**：点开选择器 → 点搜索框让键盘弹出 → 确认拖动条、「插入链接」标题、搜索框都完整可见，且下方列表还能滚动、能选中条目。

    > **关于这一条的一段更正记录（值得一读，避免后人重走）**：
    >
    > 任务级评审曾判定「固定 0.75 屏高 + 键盘高度的 padding 会把搜索框顶出屏幕上沿」，据此改成了现在这段随键盘收缩的高度计算。随后两次尝试为它写回归测试都失败——写出来的断言在**未修复的代码上也是绿的**。
    >
    > 最后查 Flutter SDK 源码定论：`showModalBottomSheet(isScrollControlled: true)` 在 `bottom_sheet.dart:619-621` 把子节点的 `maxHeight` 约束为 `constraints.maxHeight`。也就是说**框架本来就会把 sheet 钳在可用高度内，内容不可能被顶出屏幕上沿**。原评审对成因的判断是错的；现在这段高度计算只是把框架已经在做的事写明，让代码自解释，并不修复任何用户可见的 bug。
    >
    > 因此这里不存在"缺少自动化保护的已知 bug"。任何断言"顶部不出界"的测试都是不可证伪的（框架保证它恒真），写了等于假信心，已删除。这一条冒烟保留的意义是主观体验——键盘占掉半屏后列表还剩多少、够不够用——那本来就该靠人眼。

- [ ] **Step 4: 确认没有触碰禁区**

Run: `git diff --stat 3d0b9b0..HEAD -- lib/services/sync lib/data/models`
Expected: 无输出（同步逻辑和 Isar 模型全都没动，因此也不需要跑 build_runner）

`3d0b9b0` 是本功能开工前的那次提交（写 spec 那次）。**不要**用 `main...HEAD` —— `server-feat` 和 `main` 本来就差着大量自建服务功能，那样比会全是无关差异。

Run: `git diff --stat 3d0b9b0..HEAD -- lib/features/vault`
Expected: 只有 `lib/features/vault/widgets/vault_memo_card.dart` 一行 import 改动（Task 4 移动 HighlightedText 带来的），没有别的

- [ ] **Step 5: 收尾提交**

若冒烟发现问题，修完后：

```bash
git add -A
git commit -m "fix: 内链功能冒烟测试修正"
```

若没有问题则无需提交。

---

## 自查记录

**spec 覆盖**：spec 第 3 节（链接格式）→ Task 1；第 4 节（模块划分）→ Task 1/3/4/7/8；第 5 节（选择器）→ Task 2/3/4；第 6 节（跳转与失效）→ Task 7/8；第 7 节（测试）→ 各任务的测试步骤 + Task 9；第 2 节的"私密空间不参与"→ Global Constraints + Task 8 Step 4 的禁区检查。

**与 spec 的两处偏差**（都是实现细节，不改变行为）：

1. spec 第 4 节写"`DatabaseService` 新增 `searchLinkTargets()`"。实际把它放在 `lib/services/link/link_search.dart`，`DatabaseService` 只加三个通用查询方法。理由：`LinkTarget` 属于 link 层，让 `DatabaseService` 反向依赖 `services/link` 会把分层弄反。
2. spec 第 5 节写"沿用 `memo_search_card` 现有做法"做高亮。实际复用 `HighlightedText`（原在 vault 下，Task 4 移到 `shared/widgets`）——它本来就是个通用组件，只是位置放错了。
