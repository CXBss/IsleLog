# 内链回写：让内链在多设备之间可点

日期：2026-09-08
分支：`server-feat`（API 参考 `server-API.md`）
前置：`docs/superpowers/specs/2026-09-06-inline-links-design.md`（内链本体，已实现并合入 `6283895`）
涉及仓库：仅本仓库（Flutter 客户端），服务端无需任何改动

---

## 1. 问题

内链现在存双标识：远端资源名 + 本地 Isar id（`islelog://memo/memos/123?lid=45`）。目标在插入链接时若还没同步，链接里就只有 `lid`。

原设计明确不回写引用方正文，理由是"污染版本历史、可能触发冲突"，并声称「此时 `lid` 兜底仍然在本机有效」。这句话是对的——**但只在本机有效**。

使用者是电脑 + 手机两台设备，因此多设备是主场景而非边角。实际后果：

```
电脑上离线：写日记 A
电脑上离线：写日记 B，插入指向 A 的链接 → islelog://memo?lid=45
电脑联网：A、B 都是 pending，一起推送
          A 拿到 memos/500 ✅   B 拿到 memos/501 ✅
          但 B 的正文里仍然是 islelog://memo?lid=45  ← 没有任何环节改过它
手机拉取：B 的链接里 lid=45 在手机上毫无意义 → 链接是死的
```

关键点：**光是"一起同步"并不能修好链接**。推送把两条日记都送上去了，但引用方的正文内容原样保留着那个只在电脑上有意义的本地 id。要让链接跨设备可用，必须有一个显式的回写步骤。

## 2. 范围

**做**

- 推送一条日记/文章时，顺手把它正文里"只有 `lid`、缺远端名"的内链补全
- 调整推送顺序，让被引用者先拿到远端名
- 收紧解析时的撞车守卫，并把两种失效提示改成按证据判断

**不做**

- **不主动修已经 `synced` 的条目**。只有本来就要推送的条目才做回写，零额外请求、零额外版本记录。代价是"写完就再没碰过"的日记里链接可能长期只有 `lid`——但它在本机始终可用，下次编辑该日记时自动补齐。（此项目刚修过一个同类问题：未设置心情天气的日记每次编辑都在服务端版本历史留 `null→0` 噪声，见 `72d5e18`。不重蹈覆辙。）
- 不做拉取时回写。拉到的正文里若有别台设备的 `lid`，本机无从解析，留着即可——解析器会如实报「还没同步到本设备」。
- 不为"两条互相引用且都未同步"（环）做特殊处理，见 §7。
- 不改服务端、不加数据库字段、不动 Isar 模型。

## 3. 回写机制

### 挂载点

`SyncService._pushMemoUpdate`（`sync_service.dart:599`）开头，紧挨着 `_uploadPendingAttachments` 之后。

**这个位置是安全的，而且有现成先例。** 附件上传在推送前就会改写正文：

```dart
// sync_service.dart:1179
memo.content = memo.content.replaceAll(localUri, newAtt.remoteUrl!);
```

把 `file://` 本地路径换成远端 URL——和内链回写是同一个动作。推送成功后的落盘由 `reconcileMemoPushSuccess` → `mergePreparedMemoForPush` 负责，而后者比对的是 **`updatedAt` 而不是内容**：

```dart
// memo_write_policy.dart
bool mergePreparedMemoForPush(MemoEntry latest, MemoEntry prepared) {
  if (latest.updatedAt != prepared.updatedAt) return false;
  latest..content = prepared.content..attachmentsJson = ...;
  return true;
}
```

其注释已明写「附件上传会更新正文 URL 和附件资源名，需要将实际提交的数据落盘」。

由此得到三条保证，**都不需要新增任何机制**：

1. 回写后的正文既发给服务端、也存回本地，两边一致
2. `updatedAt` 不动，因此不会被判成"用户编辑"，也不会污染时间线排序
3. 推送期间用户真的编辑了 → `updatedAt` 变化 → 既有逻辑保持 `pending`、下轮重推，回写在下轮重新执行（幂等，见 §7）

**不得**在这条路径之外另开一条写正文的通道。

### 纯函数

```dart
// lib/services/link/link_backfill.dart
typedef RemoteNameLookup = String? Function(LinkKind kind, int localId);

String backfillLinks(String content, RemoteNameLookup lookup);
```

只改写"缺远端名且带 `lid`"的内链：用 `lookup` 查该 `lid` 对应实体的远端名，查到就用 `MemoLink.build` 重新拼出完整 URI，查不到就原样保留。`lid` 始终保留（补全后的链接同时带两个标识，与既有格式一致）。

零依赖纯函数，与 `memo_link.dart` / `link_query.dart` 同类。

### 调用方

`_pushMemoUpdate` 内：以 `memo.content` 为输入，`lookup` 实现为查 `DatabaseService.getMemoById` / `getArticleById` 并取其 `memosName` / `articleName`，把结果写回 `memo.content`，然后照常推送。

文章走 `_pushPendingArticles` 的对应位置，逻辑相同。

## 4. 推送顺序

`_pushPending` 现有顺序为「日记 → 评论 → 文件夹 → 文章 → 事件串 → 建议」，注释已写明两处刻意排序：「文件夹（先于文章，确保 folderName 有值）」「事件串最后推送：离线日记先取得 memosName 后才能成为成员」。

内链要做的是在**日记内部**再排一次序：正文里带光杆链接的日记，排在它引用的日记之后。

```dart
// lib/services/link/link_backfill.dart
List<T> sortForLinkBackfill<T>(
  List<T> pending, {
  required int Function(T) localIdOf,
  required String Function(T) contentOf,
});
```

Kahn 拓扑排序 + 环兜底：每轮取出"其光杆链接指向的目标都不在待排集合里、或已被取出"的条目；某轮一个都取不出（成环）则把剩余条目按原序全部输出，不死循环。

同一函数用泛型服务日记与文章两处调用。

**跨类型引用有一处已知盲区，本设计接受它。** 文章在日记之后推送，因此：

- 文章引用日记 → 日记已有名字，正常补全 ✅
- **日记引用尚未同步的文章 → 本轮补不上，而且不会有"下轮"**（这条日记推完就是 `synced`，机会主义回写不会再碰它），要等下次编辑该日记时才补

调换顺序（文章先于日记）只会把盲区翻转到另一侧，不解决问题；线性顺序无法同时满足两个方向。真要根治得跨类型做一次拓扑排序，为一个自愈的边角情况引入这种复杂度不划算。日记引用日记（最常见的情形）不受影响。

## 5. 解析规则收紧

### 撞车守卫

现有判据在链接有远端名、而 `lid` 命中的条目"自己没有远端名"时放行，会打开一条无关的本地草稿。回写做上去之后带远端名的链接变多，落进这个窗口的机会随之增加。

新判据：**链接有远端名时，`lid` 命中者的远端名必须相等**；链接没有远端名时，`lid` 是唯一权威标识，命中即放行。

```dart
bool _sameEntity(MemoLinkRef ref, LinkedEntitySnapshot snap) =>
    ref.remoteName == null || snap.remoteName == ref.remoteName;
```

### 两种失效按证据判断

现有规则把"我找不到"说成"它被删了"，方向恰好是吓人的那个：手机上 A 只是还没拉下来，却提示「已不存在或已被删除」。

新规则：**`missing` 只在拿到实物且它是软删除状态时才成立**，其余一切找不到的情况一律 `notSynced`。

### 完整判定（替换 `decideLinkAction` 现有实现）

```dart
if (byRemoteName != null) {
  return byRemoteName.isDeleted ? LinkAction.missing : LinkAction.openByRemoteName;
}
if (byLocalId != null && _sameEntity(ref, byLocalId)) {
  return byLocalId.isDeleted ? LinkAction.missing : LinkAction.openByLocalId;
}
return LinkAction.notSynced;
```

三个分支，比现有实现更少。注意 `isDeleted` 的判断必须在 `_sameEntity` **之后**——撞上一条无关的已删除日记应报 `notSynced`，不是 `missing`。

### 对既有测试的影响（有意的行为变更）

| 用例 | 旧结果 | 新结果 |
|---|---|---|
| 链接有远端名，两边都查不到 | `missing` | `notSynced` |
| `lid` 撞到远端名不一致的条目 | `missing` | `notSynced` |
| 链接有远端名，`lid` 命中者无远端名 | `openByLocalId`（打开无关条目） | `notSynced` |

其余用例结果不变。文案上 `notSynced` 沿用「这条日记还没同步到本设备」/「这篇文章还没同步到本设备」。

## 6. 覆盖率

做完之后，链接在什么情况下跨设备可用：

| 情形 | 结果 |
|---|---|
| 插入时目标已同步 | 链接一出生就完整 ✅ |
| 离线写一批、之后一起同步 | 排序保证被引用者先拿到名字，引用方推送时补全 ✅ |
| 目标同步了、引用方此后再未编辑过 | 保持光杆，本机可用、他机报「还没同步到本设备」⚠️ |
| 两条互相引用且都未同步 | 其中一条保持光杆，下次编辑时补全 ⚠️ |
| 日记引用尚未同步的文章 | 保持光杆，下次编辑该日记时补全 ⚠️（§4 的跨类型盲区） |

三种 ⚠️ 都是"本机始终可用、他机提示明确、下次编辑该条目时自愈"，没有静默错误——不会打开错误的条目，也不会谎称条目已删除。

## 7. 边界

- **幂等**：回写只匹配"缺远端名"的链接，补完即不再匹配。跑两遍等于跑一遍——这条必须有测试，因为推送重试会真的跑第二遍。
- **目标推送失败**：远端名是推送引用方的那一刻现查的，查不到就不替换，正文原样不动，下轮重试。
- **冲突条目**：`_pushPending` 本来就跳过 `conflict` 状态的条目，不受影响。
- **环**：拓扑排序的兜底分支按原序输出，不死循环；受影响的那条链接下次编辑时补全。
- **私密空间**：vault 不参与内链，也不经过 `DatabaseService`，与本设计无交集。
- **标签清洗**：回写只改 URI 部分，不碰链接的显示文字，因此不涉及 `#` 清洗问题（见 `extractTags` 那条已知陷阱）。

## 8. 测试

全部落在纯函数上，不需要新的 widget 测试。

| 测试文件 | 覆盖 |
|---|---|
| `test/services/link/link_backfill_test.dart` | 无链接的正文原样返回；光杆 `lid` 且目标可解析 → 补全；目标不可解析 → 原样；已完整的链接不被重写；一条正文里多个链接；日记链接与文章链接；正文里的畸形 `islelog://` 不被碰；**同一正文跑两遍结果相同** |
| 同上（排序部分） | 引用方排到被引用者之后；无引用关系保持原序；目标不在待排集合时不影响原序；**成环时按原序输出且不死循环** |
| `test/services/link/link_resolver_test.dart` | 按 §5 的表调整三个既有用例的期望值；新增「撞上无关的已删除条目 → `notSynced`」 |

验证：`flutter test test/services/link/` + `flutter analyze`。全量套件约 12 分钟，由控制端单独跑。

## 9. 不做的事

- 不主动修已同步条目的链接（§2）
- 不做拉取时回写
- 不为环做特殊处理
- 不改 `MemoLink` 的链接格式——格式不变，只是缺失的那一半被填上
- 不改服务端、不加字段、不动 Isar 模型（因此不需要 `build_runner`）
