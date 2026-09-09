# 内链回写实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 推送一条日记/文章时，顺手把它正文里"只有本地 id、缺远端名"的内链补全，让内链在电脑和手机之间都能点开。

**Architecture:** 两个零依赖纯函数（改写正文、推送排序）+ 三处很薄的接线（日记推送、文章推送、解析器）。回写挂在附件上传改写正文 URL 的同一位置，复用既有的落盘机制，不新增任何机制、不动写入策略、不碰 Isar 模型。

**Tech Stack:** Flutter + Isar 3.x。包名 `isle_log`。

**Spec:** `docs/superpowers/specs/2026-09-08-inline-link-backfill-design.md`

## Global Constraints

- 分支从 `server-feat` 分出。本功能**不改服务端**，不加数据库字段
- **不新增、不修改任何 `@collection` 模型字段** → 不要跑 `dart run build_runner build`
- **只做机会主义回写**：只有本来就要推送的条目才回写。**绝不**主动把已 `synced` 的条目标脏重推——那会在服务端版本历史里制造"只改了一串 URL"的噪声版本
- 回写只改链接的 URI 部分，**不碰链接的显示文字**
- 回写必须挂在既有推送准备路径上（日记：`_pushMemoUpdate` 内、`_uploadPendingAttachments` 之后；文章：`_pushPendingArticles` 的 API 调用之前）。**不得**另开一条写正文的通道
- 私密空间（vault）完全不参与
- 注释与 UI 文案用中文，与现有代码一致
- 每个任务结束 `flutter analyze` 无新增告警
- 已知无关问题：`test/widget_test.dart` 的 `(tearDownAll)` 超时是既有问题，不要碰它，也不要算作失败
- **全量测试约 12 分钟**：只跑覆盖你改动的测试文件，全量由控制端单独跑

---

## 文件结构

**新建**

| 文件 | 职责 |
|---|---|
| `lib/services/link/link_backfill.dart` | 纯函数：`bareLinkTargets`（找出正文里的光杆链接目标）、`backfillLinks`（补全正文）、`sortForLinkBackfill`（推送排序） |
| `test/services/link/link_backfill_test.dart` | 上述三个函数的单测 |

**修改**

| 文件 | 改动 |
|---|---|
| `lib/services/link/link_resolver.dart` | 重写 `decideLinkAction`：收紧撞车守卫 + 两种失效按证据判断 |
| `test/services/link/link_resolver_test.dart` | 2 个用例改期望值，新增 1 个用例 |
| `lib/services/sync/sync_service.dart` | 日记推送排序 + 回写；文章推送排序 + 回写 |

**明确不改**：`lib/data/models/**`、`lib/data/database/memo_write_policy.dart`、`lib/features/**`、`lib/services/link/memo_link.dart`。

---

### Task 1: 正文回写纯函数

**Files:**
- Create: `lib/services/link/link_backfill.dart`
- Test: `test/services/link/link_backfill_test.dart`

**Interfaces:**
- Consumes（均已存在于 `lib/services/link/memo_link.dart`）：
  - `enum LinkKind { memo, article }`
  - `class MemoLinkRef { final LinkKind kind; final String? remoteName; final int? localId; }`
  - `MemoLinkRef? MemoLink.parse(String href)` — 非 `islelog://` 或两个标识都缺时返回 null
  - `String MemoLink.build({required LinkKind kind, String? remoteName, int? localId})`
- Produces:
  - `typedef RemoteNameLookup = String? Function(LinkKind kind, int localId);`
  - `Set<int> bareLinkTargets(String content, LinkKind kind)`
  - `String backfillLinks(String content, RemoteNameLookup lookup)`

- [ ] **Step 1: 写失败的测试**

创建 `test/services/link/link_backfill_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/link/link_backfill.dart';
import 'package:isle_log/services/link/memo_link.dart';

/// 固定的假查询：45 → memos/500，12 → articles/7，其余查不到。
String? _lookup(LinkKind kind, int localId) {
  if (kind == LinkKind.memo && localId == 45) return 'memos/500';
  if (kind == LinkKind.article && localId == 12) return 'articles/7';
  return null;
}

void main() {
  group('bareLinkTargets', () {
    test('找出光杆日记链接的目标 id', () {
      const content = '见[03-12 暴雨](islelog://memo?lid=45)那天';

      expect(bareLinkTargets(content, LinkKind.memo), {45});
    });

    test('已完整的链接不算光杆', () {
      const content = '见[03-12 暴雨](islelog://memo/memos/500?lid=45)那天';

      expect(bareLinkTargets(content, LinkKind.memo), isEmpty);
    });

    test('只返回指定类型的目标', () {
      const content =
          '[a](islelog://memo?lid=45) 和 [b](islelog://article?lid=12)';

      expect(bareLinkTargets(content, LinkKind.memo), {45});
      expect(bareLinkTargets(content, LinkKind.article), {12});
    });

    test('没有链接时返回空集', () {
      expect(bareLinkTargets('普通正文', LinkKind.memo), isEmpty);
    });

    test('同一目标出现多次只算一个', () {
      const content =
          '[a](islelog://memo?lid=45) 又 [b](islelog://memo?lid=45)';

      expect(bareLinkTargets(content, LinkKind.memo), {45});
    });
  });

  group('backfillLinks', () {
    test('光杆链接且目标可解析时补上远端名', () {
      const content = '见[03-12 暴雨](islelog://memo?lid=45)那天';

      expect(
        backfillLinks(content, _lookup),
        '见[03-12 暴雨](islelog://memo/memos/500?lid=45)那天',
      );
    });

    test('补全后仍保留 lid', () {
      final result = backfillLinks('[a](islelog://memo?lid=45)', _lookup);

      expect(result, contains('lid=45'));
    });

    test('目标查不到时原样保留', () {
      const content = '[a](islelog://memo?lid=999)';

      expect(backfillLinks(content, _lookup), content);
    });

    test('已完整的链接不被重写', () {
      const content = '[a](islelog://memo/memos/123?lid=45)';

      expect(backfillLinks(content, _lookup), content);
    });

    test('文章链接同样补全', () {
      expect(
        backfillLinks('[a](islelog://article?lid=12)', _lookup),
        '[a](islelog://article/articles/7?lid=12)',
      );
    });

    test('一条正文里多个链接分别处理', () {
      const content =
          '[a](islelog://memo?lid=45)、[b](islelog://memo?lid=999)、'
          '[c](islelog://article?lid=12)';

      expect(
        backfillLinks(content, _lookup),
        '[a](islelog://memo/memos/500?lid=45)、[b](islelog://memo?lid=999)、'
        '[c](islelog://article/articles/7?lid=12)',
      );
    });

    test('没有内链的正文原样返回', () {
      const content = '普通正文，还有个外链 https://example.com';

      expect(backfillLinks(content, _lookup), content);
    });

    test('畸形的 islelog 串不被改动', () {
      const content = '[a](islelog://folder?lid=45) [b](islelog://memo)';

      expect(backfillLinks(content, _lookup), content);
    });

    test('跑两遍结果相同（幂等）', () {
      const content =
          '[a](islelog://memo?lid=45)、[b](islelog://article?lid=12)';

      final once = backfillLinks(content, _lookup);
      final twice = backfillLinks(once, _lookup);

      expect(twice, once);
    });

    test('查询返回空串视为查不到', () {
      String? emptyLookup(LinkKind kind, int localId) => '';
      const content = '[a](islelog://memo?lid=45)';

      expect(backfillLinks(content, emptyLookup), content);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/services/link/link_backfill_test.dart`
Expected: FAIL，报 `Target of URI doesn't exist: 'package:isle_log/services/link/link_backfill.dart'`

- [ ] **Step 3: 写实现**

创建 `lib/services/link/link_backfill.dart`：

```dart
import 'memo_link.dart';

/// 查询某个本地 id 对应实体的远端资源名；查不到返回 null。
typedef RemoteNameLookup = String? Function(LinkKind kind, int localId);

/// 匹配正文里的内链 URI。
///
/// Markdown 链接的目标以 `)` 收尾，正文里裸写时以空白收尾，两者都排除即可。
final RegExp _linkUri = RegExp(r'islelog://[^\s)]+');

/// 找出正文里所有「只有本地 id、缺远端名」的 [kind] 类目标的本地 id。
///
/// 供推送排序判断依赖关系用。
Set<int> bareLinkTargets(String content, LinkKind kind) {
  final ids = <int>{};
  for (final match in _linkUri.allMatches(content)) {
    final ref = MemoLink.parse(match.group(0)!);
    if (ref == null) continue;
    if (ref.kind != kind) continue;
    if (ref.remoteName != null) continue;
    final lid = ref.localId;
    if (lid != null) ids.add(lid);
  }
  return ids;
}

/// 把正文里缺远端名的内链补全。
///
/// 只改 URI，不碰链接的显示文字。只补「缺远端名且有 lid」的链接，因此天然幂等——
/// 补完的链接下次不再匹配。查不到远端名就原样保留，等目标同步后的下一次推送再补。
String backfillLinks(String content, RemoteNameLookup lookup) {
  if (!content.contains('${MemoLink.scheme}://')) return content;

  return content.replaceAllMapped(_linkUri, (match) {
    final href = match.group(0)!;
    final ref = MemoLink.parse(href);
    // 不是合法内链（未知 host、两个标识都缺）→ 原样
    if (ref == null) return href;
    // 已经有远端名 → 原样
    if (ref.remoteName != null) return href;

    final lid = ref.localId;
    if (lid == null) return href;

    final remoteName = lookup(ref.kind, lid);
    if (remoteName == null || remoteName.isEmpty) return href;

    return MemoLink.build(
      kind: ref.kind,
      remoteName: remoteName,
      localId: lid,
    );
  });
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/services/link/link_backfill_test.dart`
Expected: PASS，16 个用例全过

- [ ] **Step 5: analyze**

Run: `flutter analyze lib/services/link test/services/link`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/services/link/link_backfill.dart test/services/link/link_backfill_test.dart
git commit -m "feat: 内链正文回写纯函数"
```

---

### Task 2: 推送排序纯函数

**Files:**
- Modify: `lib/services/link/link_backfill.dart`（追加 `sortForLinkBackfill`）
- Test: `test/services/link/link_backfill_test.dart`（追加一个 group）

**Interfaces:**
- Consumes: `bareLinkTargets`、`LinkKind`（Task 1）
- Produces:
  - `List<T> sortForLinkBackfill<T>(List<T> pending, {required LinkKind kind, required int Function(T) localIdOf, required String Function(T) contentOf})`

- [ ] **Step 1: 写失败的测试**

追加到 `test/services/link/link_backfill_test.dart` 的 `main()` 里（不要改动 Task 1 的用例）：

```dart
  group('sortForLinkBackfill', () {
    /// 测试用的最小条目：只有 id 和正文。
    ({int id, String content}) item(int id, [String content = '']) =>
        (id: id, content: content);

    List<({int id, String content})> sortItems(
      List<({int id, String content})> items,
    ) => sortForLinkBackfill(
      items,
      kind: LinkKind.memo,
      localIdOf: (i) => i.id,
      contentOf: (i) => i.content,
    );

    test('引用方排到被引用者之后', () {
      final sorted = sortItems([
        item(1, '见[x](islelog://memo?lid=2)'),
        item(2),
      ]);

      expect(sorted.map((i) => i.id), [2, 1]);
    });

    test('无引用关系时保持原序', () {
      final sorted = sortItems([item(1), item(2), item(3)]);

      expect(sorted.map((i) => i.id), [1, 2, 3]);
    });

    test('目标不在本批次时不影响原序', () {
      final sorted = sortItems([
        item(1, '见[x](islelog://memo?lid=99)'),
        item(2),
      ]);

      expect(sorted.map((i) => i.id), [1, 2]);
    });

    test('已完整的链接不产生依赖', () {
      final sorted = sortItems([
        item(1, '见[x](islelog://memo/memos/500?lid=2)'),
        item(2),
      ]);

      expect(sorted.map((i) => i.id), [1, 2]);
    });

    test('链式依赖按拓扑序排开', () {
      // 1 → 2 → 3，期望 3、2、1
      final sorted = sortItems([
        item(1, '[x](islelog://memo?lid=2)'),
        item(2, '[x](islelog://memo?lid=3)'),
        item(3),
      ]);

      expect(sorted.map((i) => i.id), [3, 2, 1]);
    });

    test('成环时按原序输出且不死循环', () {
      final sorted = sortItems([
        item(1, '[x](islelog://memo?lid=2)'),
        item(2, '[x](islelog://memo?lid=1)'),
      ]);

      expect(sorted.map((i) => i.id), [1, 2]);
    });

    test('环之外的条目仍然被正确排序', () {
      // 3 无依赖应先出；1 和 2 互相引用，按原序补在后面
      final sorted = sortItems([
        item(1, '[x](islelog://memo?lid=2)'),
        item(2, '[x](islelog://memo?lid=1)'),
        item(3),
      ]);

      expect(sorted.first.id, 3);
      expect(sorted.map((i) => i.id).skip(1), [1, 2]);
    });

    test('自引用不会把自己卡死', () {
      final sorted = sortItems([
        item(1, '[x](islelog://memo?lid=1)'),
        item(2),
      ]);

      expect(sorted.map((i) => i.id).toSet(), {1, 2});
      expect(sorted.length, 2);
    });

    test('空列表与单元素原样返回', () {
      expect(sortItems([]), isEmpty);
      expect(sortItems([item(7)]).single.id, 7);
    });

    test('不修改传入的列表', () {
      final input = [item(1, '[x](islelog://memo?lid=2)'), item(2)];

      sortItems(input);

      expect(input.map((i) => i.id), [1, 2]);
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/services/link/link_backfill_test.dart`
Expected: FAIL，报 `The function 'sortForLinkBackfill' isn't defined`（Task 1 的用例仍应通过）

- [ ] **Step 3: 写实现**

追加到 `lib/services/link/link_backfill.dart` 末尾：

```dart
/// 把待推送列表排序，使「正文里带光杆链接的条目」排在它引用的条目之后。
///
/// 这样被引用者先拿到远端名，引用方推送时才补得上。与既有的
/// 「文件夹先于文章」「事件串最后推送」是同一个套路。
///
/// 只考虑同批次内、同类型的依赖：目标不在本批次（已同步或不存在）不构成依赖。
/// 成环时把剩余条目按原序输出，不死循环——受影响的链接下次编辑该条目时再补。
List<T> sortForLinkBackfill<T>(
  List<T> pending, {
  required LinkKind kind,
  required int Function(T) localIdOf,
  required String Function(T) contentOf,
}) {
  if (pending.length < 2) return List<T>.of(pending);

  final idsInBatch = pending.map(localIdOf).toSet();
  final deps = <int, Set<int>>{};
  for (final item in pending) {
    final self = localIdOf(item);
    deps[self] = bareLinkTargets(contentOf(item), kind)
        // 自引用不构成依赖，否则它永远等不到自己
        .where((id) => id != self && idsInBatch.contains(id))
        .toSet();
  }

  final sorted = <T>[];
  final emitted = <int>{};
  final remaining = List<T>.of(pending);

  while (remaining.isNotEmpty) {
    final ready = remaining
        .where((item) => deps[localIdOf(item)]!.every(emitted.contains))
        .toList();
    if (ready.isEmpty) {
      // 成环：剩下的按原序输出，保证函数一定终止
      sorted.addAll(remaining);
      break;
    }
    for (final item in ready) {
      sorted.add(item);
      emitted.add(localIdOf(item));
    }
    remaining.removeWhere((item) => emitted.contains(localIdOf(item)));
  }

  return sorted;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/services/link/link_backfill_test.dart`
Expected: PASS，26 个用例全过（Task 1 的 16 个 + 本任务的 10 个）

- [ ] **Step 5: analyze**

Run: `flutter analyze lib/services/link test/services/link`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/services/link/link_backfill.dart test/services/link/link_backfill_test.dart
git commit -m "feat: 内链回写的推送排序（拓扑序，成环时按原序兜底）"
```

---

### Task 3: 解析规则收紧

**Files:**
- Modify: `lib/services/link/link_resolver.dart`（重写 `decideLinkAction`）
- Test: `test/services/link/link_resolver_test.dart`（改 2 个用例的期望值，新增 1 个）

**Interfaces:**
- Consumes: `MemoLinkRef`、`LinkKind`（`memo_link.dart`）
- Produces: `decideLinkAction` 签名不变，`LinkedEntitySnapshot` / `LinkAction` 定义不变，仅判定逻辑改变

- [ ] **Step 1: 改测试（先改期望，再改实现）**

在 `test/services/link/link_resolver_test.dart` 中做三处改动，**其余 9 个用例一字不动**：

其一，把这个用例的名字和期望值改掉：

```dart
  test('本地 id 撞到了远端名不一致的条目，判定为未同步', () {
    // 换设备后本地 id 会撞车。既然对不上，就不能猜着开；
    // 而"找不到"不等于"被删了"，所以是 notSynced 而不是 missing。
    expect(
      decideLinkAction(
        ref: _synced,
        byRemoteName: null,
        byLocalId: const LinkedEntitySnapshot(remoteName: 'memos/999'),
      ),
      LinkAction.notSynced,
    );
  });
```

其二，把这个用例的名字和期望值改掉：

```dart
  test('链接有远端名但两边都查不到，说明还没同步到本设备', () {
    // 手里没有实物，就不能断言它被删了——多设备下更可能只是还没拉下来
    expect(
      decideLinkAction(ref: _synced, byRemoteName: null, byLocalId: null),
      LinkAction.notSynced,
    );
  });
```

其三，在文件末尾 `}` 之前新增一个用例：

```dart
  test('撞上一条无关的已删除条目，仍报未同步而不是已删除', () {
    // 那具"尸体"不是链接指向的东西，不能拿它当"目标已删除"的证据
    expect(
      decideLinkAction(
        ref: _synced,
        byRemoteName: null,
        byLocalId: const LinkedEntitySnapshot(
          remoteName: 'memos/999',
          isDeleted: true,
        ),
      ),
      LinkAction.notSynced,
    );
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/services/link/link_resolver_test.dart`
Expected: FAIL，3 个用例失败（两个改了期望的 + 新增的），其余 9 个通过

- [ ] **Step 3: 重写 decideLinkAction**

把 `lib/services/link/link_resolver.dart` 里 `decideLinkAction` 的**函数体**整个替换为下面这段，并在其上方新增私有辅助函数 `_sameEntity`。签名、`LinkedEntitySnapshot`、`LinkAction` 全都保持不变：

```dart
/// 判断 [snap] 是否就是 [ref] 指向的那一条。
///
/// 撞车守卫只在两边都有远端名时才成立：只有那时"对不上"才有意义。
/// 链接没有远端名说明它是在目标同步前创建的，此时 lid 是唯一权威标识。
bool _sameEntity(MemoLinkRef ref, LinkedEntitySnapshot snap) =>
    ref.remoteName == null || snap.remoteName == ref.remoteName;

/// 由两次查库的结果判定该打开谁、或报哪种失效。
///
/// 两段式：先找一个还活着的目标；都没有活的，再看有没有"目标确实被删了"的
/// 证据来决定说哪句话。
///
/// 归档条目照常打开——是用户主动点的，读得到才合理。
/// `missing` 只在**拿到实物且它是软删除**时才成立；其余一切找不到的情况
/// （没拉下来、撞车判否、链接只有 lid 而本机没有）一律 `notSynced`。
/// 把"我找不到"说成"它被删了"会吓到用户，而且多设备下前者常见得多。
LinkAction decideLinkAction({
  required MemoLinkRef ref,
  required LinkedEntitySnapshot? byRemoteName,
  required LinkedEntitySnapshot? byLocalId,
}) {
  // 第一段：任何一个活着的目标都可以打开，远端名优先
  if (byRemoteName != null && !byRemoteName.isDeleted) {
    return LinkAction.openByRemoteName;
  }
  final localIsSame = byLocalId != null && _sameEntity(ref, byLocalId);
  if (localIsSame && !byLocalId.isDeleted) {
    return LinkAction.openByLocalId;
  }

  // 第二段：没有活的，看是否见到了目标本身的"尸体"
  final sawDeletedTarget =
      (byRemoteName?.isDeleted ?? false) || (localIsSame && byLocalId.isDeleted);
  return sawDeletedTarget ? LinkAction.missing : LinkAction.notSynced;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/services/link/link_resolver_test.dart`
Expected: PASS，12 个用例全过

- [ ] **Step 5: analyze**

Run: `flutter analyze lib/services/link test/services/link`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/services/link/link_resolver.dart test/services/link/link_resolver_test.dart
git commit -m "fix: 内链撞车守卫收紧，两种失效提示改为按证据判断"
```

---

### Task 4: 接进日记推送

**Files:**
- Modify: `lib/services/sync/sync_service.dart`（`_pushPending` 的日记循环、`_pushMemoUpdate` 开头）

**Interfaces:**
- Consumes: `backfillLinks`、`sortForLinkBackfill`、`RemoteNameLookup`（Task 1、2）
- Produces: 无（内部接线）

**为什么这样接是安全的**（实现者必读，不要另想办法）：

`_pushMemoUpdate` 里紧邻的 `_uploadPendingAttachments` **已经在推送前改写正文**——`sync_service.dart:1179` 把 `file://` 本地路径替换成远端 URL。推送成功后的落盘由 `reconcileMemoPushSuccess` → `mergePreparedMemoForPush` 负责，而后者比对的是 **`updatedAt` 而不是内容**，其注释明写「附件上传会更新正文 URL 和附件资源名，需要将实际提交的数据落盘」。

所以：改写后的正文既发给服务端也存回本地；`updatedAt` 不动；推送期间用户真的编辑了会被既有机制识别并保持 `pending`，下轮重推时回写重新执行（幂等）。**不要**在这条路径之外另开写正文的通道，也**不要**改 `memo_write_policy.dart`。

- [ ] **Step 1: 加 import**

该文件目前**没有** import 任何 `link/` 下的东西。它的 `../` 段是按字母序排的（`../api/`、`../attachment/`、`../settings/`、`../vault/`），所以这两行插在 `../attachment/attachment_service.dart` 与 `../settings/settings_service.dart` 之间：

```dart
import '../link/link_backfill.dart';
import '../link/memo_link.dart';
```

`memo_link.dart` 是为了 `LinkKind`。

- [ ] **Step 2: 日记推送前排序**

在 `_pushPending` 中，把

```dart
    final pendingList = await DatabaseService.getPendingSyncMemos();
    debugPrint('[Sync] _pushPending: 待推送 ${pendingList.length} 条');
```

改成

```dart
    final rawPending = await DatabaseService.getPendingSyncMemos();
    // 被引用的日记先推，引用方才补得上远端名（同「文件夹先于文章」的套路）
    final pendingList = sortForLinkBackfill(
      rawPending,
      kind: LinkKind.memo,
      localIdOf: (m) => m.id,
      contentOf: (m) => m.content,
    );
    debugPrint('[Sync] _pushPending: 待推送 ${pendingList.length} 条');
```

循环体本身不动。

- [ ] **Step 3: 在 _pushMemoUpdate 里回写**

在 `_pushMemoUpdate` 中，把

```dart
    // ── 补传离线附件 ──
    await _uploadPendingAttachments(api, memo, url, token);
```

改成

```dart
    // ── 补传离线附件 ──
    await _uploadPendingAttachments(api, memo, url, token);

    // ── 补全正文里缺远端名的内链 ──
    // 与上面的附件 URL 替换同理：改写后的正文既发给服务端也随本次推送落盘。
    memo.content = await _backfillMemoLinks(memo.content);
```

然后在 `_pushMemoUpdate` 之后新增这个私有方法：

```dart
  /// 把正文里缺远端名的内链补全（查不到的原样保留）。
  ///
  /// 查询是异步的，而 [backfillLinks] 是同步纯函数，因此先把用到的
  /// 本地 id 一次性查成映射表，再交给纯函数替换。
  static Future<String> _backfillMemoLinks(String content) async {
    final memoIds = bareLinkTargets(content, LinkKind.memo);
    final articleIds = bareLinkTargets(content, LinkKind.article);
    if (memoIds.isEmpty && articleIds.isEmpty) return content;

    final names = <(LinkKind, int), String>{};
    for (final id in memoIds) {
      final name = (await DatabaseService.getMemoById(id))?.memosName;
      if (name != null) names[(LinkKind.memo, id)] = name;
    }
    for (final id in articleIds) {
      final name = (await DatabaseService.getArticleById(id))?.articleName;
      if (name != null) names[(LinkKind.article, id)] = name;
    }

    return backfillLinks(content, (kind, id) => names[(kind, id)]);
  }
```

- [ ] **Step 4: 跑覆盖改动的测试 + analyze**

Run: `flutter test test/services/link/`
Expected: PASS（38 个用例：backfill 26 + resolver 12）

Run: `flutter analyze lib/services/sync lib/services/link`
Expected: 无新增告警（该文件既有若干 info 级 lint，只要不新增即可）

- [ ] **Step 5: 提交**

```bash
git add lib/services/sync/sync_service.dart
git commit -m "feat: 日记推送时补全正文内链并按引用关系排序"
```

---

### Task 5: 接进文章推送

**Files:**
- Modify: `lib/services/sync/sync_service.dart`（`_pushPendingArticles`）

**Interfaces:**
- Consumes: `backfillLinks`、`sortForLinkBackfill`、`_backfillMemoLinks`（Task 4 新增的私有方法，文章复用它——它同时处理日记链接与文章链接）
- Produces: 无

**注意**：文章的两个分支（新建 / 更新）都以 `await DatabaseService.saveArticle(article, skipTimestamp: true)` 收尾，所以改写 `article.content` 天然会落盘，不需要额外处理。

- [ ] **Step 1: 文章推送前排序**

在 `_pushPendingArticles` 中，把

```dart
    final pending = await DatabaseService.getPendingSyncArticles();
    debugPrint('[Sync] _pushPendingArticles: ${pending.length} 篇待推送');
```

改成

```dart
    final rawPending = await DatabaseService.getPendingSyncArticles();
    // 被引用的文章先推，引用方才补得上远端名
    final pending = sortForLinkBackfill(
      rawPending,
      kind: LinkKind.article,
      localIdOf: (a) => a.id,
      contentOf: (a) => a.content,
    );
    debugPrint('[Sync] _pushPendingArticles: ${pending.length} 篇待推送');
```

- [ ] **Step 2: 在推送前回写文章正文**

在 `_pushPendingArticles` 的 `try {` 之后、文件夹解析那段 `if (article.folderName == null && ...)` 之**前**，插入：

```dart
        // ── 补全正文里缺远端名的内链 ──
        // 文章的两个分支都以 saveArticle(skipTimestamp: true) 收尾，
        // 因此这里改写 content 会随本次推送一并落盘。
        article.content = await _backfillMemoLinks(article.content);
```

- [ ] **Step 3: 跑覆盖改动的测试 + analyze**

Run: `flutter test test/services/link/`
Expected: PASS，38 个用例

Run: `flutter analyze lib/services/sync lib/services/link`
Expected: 无新增告警

- [ ] **Step 4: 提交**

```bash
git add lib/services/sync/sync_service.dart
git commit -m "feat: 文章推送时补全正文内链并按引用关系排序"
```

---

### Task 6: 端到端验证

**Files:** 无新增，只跑验证

- [ ] **Step 1: 全量静态检查**

Run: `flutter analyze`
Expected: 与本分支开工前的告警数一致（全是既有 info 级 lint），**本功能新增/修改的文件零告警**。逐条核对：`flutter analyze | grep -E "link_backfill|link_resolver"` 应无输出。

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: 通过数 = 开工前 + 39（backfill 26 + resolver 新增 1 + 已有 11 保持）。唯一失败仍是 `test/widget_test.dart` 的 `(tearDownAll)` 超时——既有问题，不要动它，但要确认**除它以外**没有新失败。

- [ ] **Step 3: 确认没有触碰禁区**

Run: `git diff --stat <本功能第一个提交的父提交>..HEAD -- lib/data/models lib/data/database/memo_write_policy.dart lib/features`
Expected: 无输出（模型、写入策略、UI 全都没动，因此也不需要 build_runner）

- [ ] **Step 4: 真机/模拟器冒烟（两台设备）**

这一步需要电脑和手机各跑一次，控制端无法代劳：

1. **断网**，在设备 A 上新建日记甲（写点内容，先不同步）
2. 断网状态下再新建日记乙，插入一条指向甲的内链 → 保存
3. 打开乙的详情页，点那条链接 → 应能跳到甲（此时链接里只有 lid，走本机兜底）
4. **联网**，触发同步
5. 在设备 A 上打开乙 → 右上角菜单「复制 Markdown」→ 粘贴出来看，链接应已变成 `islelog://memo/memos/<数字>?lid=<数字>`（**这是回写成功的直接证据**）
6. 在设备 B 上同步、打开乙、点那条链接 → 应能跳到甲（**这是本功能的目的**）
7. 在设备 B 上点一条指向「B 还没拉下来的条目」的链接 → 提示应是「这条日记还没同步到本设备」，**不应**是「已不存在或已被删除」
8. 在设备 A 上删除甲并同步，再到设备 B 同步后点链接 → 这时才应提示「已不存在或已被删除」
9. 检查设备 A 上日记乙的版本历史 → **不应**因为这次回写多出一条"只改了 URL"的版本（回写是搭在本来就要发生的推送上的）

- [ ] **Step 5: 收尾提交**

若冒烟发现问题，修完后：

```bash
git add -A
git commit -m "fix: 内链回写冒烟测试修正"
```

若没有问题则无需提交。

---

## 自查记录

**spec 覆盖**：spec §3（回写机制）→ Task 1 + Task 4；§4（推送顺序）→ Task 2 + Task 4/5；§5（解析收紧）→ Task 3；§6（覆盖率）→ Task 6 冒烟第 5-8 步；§7（边界：幂等、目标失败、环）→ Task 1/2 的测试；§8（测试）→ 各任务的测试步骤。

**与 spec 的一处偏差**：spec §5 给的判定是三分支写法，会让「远端名命中的那条已删除、而 lid 命中的那条存活」返回 `missing`，与既有测试「以存活的为准」冲突。计划改用两段式（先找活的，再看死亡证据），既满足 spec「`missing` 只在拿到实物且软删除时成立」的要求，又保住那个既有用例——11 个既有用例里只有 2 个需要改期望值，而不是 3 个。

**类型一致性**：`RemoteNameLookup`（Task 1）→ `backfillLinks` 的第二参数（Task 1）→ `_backfillMemoLinks` 里以 `(kind, id) => names[(kind, id)]` 提供（Task 4），签名一致；`sortForLinkBackfill` 的三个具名参数在 Task 4（日记）与 Task 5（文章）两处调用处拼写一致。
