# 事件串（Thread）—— 日记关联性设计

日期：2026-08-14
分支：`server-feat`（客户端） / `main`（服务端 islelog-server）
涉及仓库：`/Users/cxb/Code/flutter/memos_local`（Flutter 客户端）、`/Users/cxb/Code/go/islelog-back/islelog-server`（Go 服务端）

---

## 1. 问题

一件事往往跨多篇日记。例如「工位附近有蛐蛐叫 → 晚上去找没找到 → 第二天没声了以为死了 → 第三天晚上又听到了」，这四篇分散在时间线上，单独看任何一篇都丢失了上下文。

现有的标签解决不了：标签是**无序分类**，只能告诉你哪几篇有关；需要的是**有序事件流**，能告诉你这件事发展到哪一步了。

## 2. 方案概述

引入「事件串」（Thread）作为一等实体：

- 一个事件串有标题、一句话简介、进行中/已完结状态
- 一篇日记可属于多个事件串（多对多）
- **事件串只能手动创建**，AI 不建议新建
- 创建后 AI 后台生成简介，用户可手动改写
- 每篇新日记保存后，后台拿**各事件串的简介**判断它可能属于哪个，产出建议供确认
- 用户主动触发的 AI 任务立刻抢占并中止后台任务

核心洞察：匹配的输入是**事件串简介**（压缩表示）而非候选日记全文。这让上下文占用与事件串数量线性相关且系数极小，同时不需要时间窗口启发式 —— 隔几个月复发的事件也能匹配上。

## 3. 数据模型

### 3.1 服务端新表

```sql
CREATE TABLE IF NOT EXISTS threads (
  id             INTEGER PRIMARY KEY,   -- snowflake，复用 util/snowflake.go
  user_id        INTEGER NOT NULL,
  title          TEXT NOT NULL,
  summary        TEXT DEFAULT '',       -- 一句话进展简介
  summary_source TEXT DEFAULT 'AI',     -- AI / MANUAL，MANUAL 后 AI 不再覆盖
  status         TEXT DEFAULT 'ACTIVE', -- ACTIVE / RESOLVED
  created_ts     INTEGER NOT NULL,
  updated_ts     INTEGER NOT NULL,
  row_status     TEXT DEFAULT 'NORMAL'  -- NORMAL / DELETED（软删，供同步删除检测）
);
CREATE INDEX IF NOT EXISTS idx_threads_user ON threads(user_id);

CREATE TABLE IF NOT EXISTS thread_members (
  thread_id  INTEGER NOT NULL,
  memo_id    INTEGER NOT NULL,
  created_ts INTEGER NOT NULL,
  PRIMARY KEY (thread_id, memo_id)
);
CREATE INDEX IF NOT EXISTS idx_thread_members_memo ON thread_members(memo_id);

CREATE TABLE IF NOT EXISTS thread_suggestions (
  id         INTEGER PRIMARY KEY,
  user_id    INTEGER NOT NULL,
  memo_id    INTEGER NOT NULL,
  thread_id  INTEGER NOT NULL,       -- 只建议加入已有事件串，不为 NULL
  confidence REAL    DEFAULT 0,
  reason     TEXT    DEFAULT '',
  status     TEXT    DEFAULT 'PENDING', -- PENDING / ACCEPTED / DISMISSED
  created_ts INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_thread_suggestions_user_status
  ON thread_suggestions(user_id, status);
```

`memos` 表加一列，标记「是否已被后台分析过」：

```sql
ALTER TABLE memos ADD COLUMN thread_scan_ts INTEGER DEFAULT 0;
```

### 3.2 设计取舍

**成员用 `thread_members` 中间表，而非 `threads` 上的 JSON 列。** 就当前功能而言，JSON 列足够（服务端唯一的反查场景是删 memo 时的级联清理，几十行 threads 用 `json_each()` 扫一遍即可），且能与客户端的 `memberLocalIds` 形态 1:1 对应。选中间表是为**未来的可扩展性**买选择权：

- 中间表可以给每条成员关系挂属性 —— 这一篇在事件中的作用、是手动加入还是从 AI 建议接受、加入时间等。JSON 数组做不到，届时要做数据迁移
- 反查「这篇属于哪些事件串」是索引查询而非全表扫描，若将来需要服务端反查接口可直接支持

只建最小列 `(thread_id, memo_id, created_ts)`，不预置投机性字段 —— 往中间表补列本就廉价，这正是中间表提供的价值。

代价：`PUT members` 的实现从一条 `UPDATE` 变成事务内的 `DELETE` + 批量 `INSERT`；服务端与客户端 `memberLocalIds` 之间需要一次形态转换。均可接受。

**不存冗余的 `member_count` / `started_ts` / `last_ts`。** 这些冗余不只是维护成本，是**会算错**：`started_ts` / `last_ts` 冗余的是成员 memo 的 `display_ts`，而用户随时能改某篇日记的日期。改完之后冗余列就悄悄过期，且没有任何地方会触发重算 —— 除非在 memo 的 PATCH 里反查所有包含它的事件串。为一个列表页排序字段付这个代价不划算。列表接口现查聚合（`COUNT` / `MIN` / `MAX`），事件串是几十个量级，开销可忽略。

**不存 `seq` 排序字段。** 成员一律按 memo 的 `display_ts` 排序。日记本身就是时间事件，而 `display_ts` 已可由客户端修改；再存一个手工顺序会与之打架，还需额外处理顺序冲突。

**不复用 Memos 的 `relations` 字段。** `relations` 是 Memos v0.25 兼容层（COMMENT 语义），当前由 `service/memo.go:GetRelationsJSON` 根据评论数临时合成，并无实体表。事件串有标题、状态、简介等一等属性，`relations` 表达不了。走 IsleLog 扩展路线，与 `folders` 一致。

**扫描条件用「扫过没有」而非「归属了没有」。** 用 `thread_scan_ts` 判断：
- 支持多归属 —— 已手动归入「工位蛐蛐」的日记，仍可被识别为同时属于「加班周」
- 避免抖动 —— 用户把日记移出事件串时不会触发重新分析

**成员整体 last-write-wins，不做成员级 tombstone。** 成员级墓碑需要一套操作队列，而「两台设备同时修改同一事件串成员」概率极低，复杂度不划算。

### 3.3 客户端 Isar 模型

```dart
enum ThreadStatus { active, resolved }
enum SuggestionStatus { pending, accepted, dismissed }

@collection
class ThreadEntry {
  Id id = Isar.autoIncrement;

  /// 远端资源名 "threads/{id}"，未同步为 null；不设 unique（同 memosName 的理由）
  @Index() String? threadName;

  String title = '';
  String summary = '';
  bool summaryIsManual = false;      // true 时 AI 不再覆盖 summary

  @enumerated ThreadStatus status = ThreadStatus.active;

  /// 成员的本地 memo id；value 索引支持「这篇属于哪些事件串」的反查
  @Index(type: IndexType.value)
  List<int> memberLocalIds = [];

  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();

  @enumerated SyncStatus syncStatus = SyncStatus.pending;
  DateTime? lastSyncAt;
  bool isDeleted = false;
}

@collection
class ThreadSuggestionEntry {
  Id id = Isar.autoIncrement;
  @Index() String? suggestionName;   // "threadSuggestions/{id}"
  @Index() int memoLocalId = 0;
  int threadLocalId = 0;
  double confidence = 0;
  String reason = '';
  @enumerated SuggestionStatus status = SuggestionStatus.pending;
  DateTime createdAt = DateTime.now();
}
```

成员关系**不建独立 collection**，直接用 `ThreadEntry.memberLocalIds` 的 value 索引。事件串总量是几十个量级，正查反查都是一次索引查询。

修改模型后必须运行：

```bash
dart run build_runner build --delete-conflicting-outputs
```

## 4. 服务端 API

路由注册在 `main.go` 的 `api` 分组（已带 `authMW`）。

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/threads` | 列表，参数 `status` / `pageSize` / `pageToken`；不含成员详情，`memberCount`/`startedTime`/`lastTime` 由 JOIN `memos` 现算 |
| POST | `/api/v1/threads` | 创建，`{title, summary?, memos: ["memos/1", ...]}` |
| GET | `/api/v1/threads/:thread` | 详情，含 `members: [{memo, snippet, displayTime}]` |
| PATCH | `/api/v1/threads/:thread` | 改 `title` / `summary` / `status`，支持 `?updateMask=` |
| DELETE | `/api/v1/threads/:thread` | 软删（`row_status = DELETED`） |
| PUT | `/api/v1/threads/:thread/members` | **全量替换**成员列表 `{memos: [...]}` |
| GET | `/api/v1/thread-suggestions` | 参数 `status`（默认 `PENDING`） |
| PATCH | `/api/v1/thread-suggestions/:suggestion` | 改 `status` 为 `ACCEPTED` / `DISMISSED` |
| POST | `/api/v1/ai/thread-summary` | 手动重新生成简介 `{thread, provider, cloudConsent}` |
| POST | `/api/v1/ai/thread-match` | 手动重新分析归属 `{memo, provider, cloudConsent}` |

**只做成员的全量替换**，不做单成员 POST/DELETE。理由是**离线客户端的重试语义**：客户端离线期间可能对同一事件串加了 3 篇、删了 1 篇；若只有单条接口，push 需先 diff 再发 4 个请求，第 3 个失败时事件串停在中间状态 —— 而 `syncStatus` 只有一个标记位，表达不了「还差一篇和一个删除」，重试也得记住发到哪了。`PUT` 整个列表则是一个请求、一次原子写、一条 changelog、天然幂等，失败原样重发即可。配合 JSON 列，服务端实现就是一条 `UPDATE threads SET members = ?`。

服务端实现为一个事务：`DELETE FROM thread_members WHERE thread_id = ?` 后批量 `INSERT`，随后 bump `threads.updated_ts` 并写一条 changelog。

代价是并发覆盖：两台设备同时改同一事件串时后写覆盖先写，先写方新增的成员会丢。这正是 §5.3 接受的 LWW 取舍，对单人单设备为主的场景成本远低于成员级墓碑机制。

接口风格对齐现有「设置 Memo 的附件」（`PATCH /memos/:memo/attachments`）。

**不做反查接口** `GET /memos/:memo/threads`：客户端本地有全量数据，本地索引查询即可。

`PATCH /thread-suggestions/:suggestion` 收到 `ACCEPTED` 时，服务端代为执行成员写入（等价于一次 `PUT members` 的增量），并写 thread 的 changelog。

### Thread 响应结构

```json
{
  "name": "threads/123",
  "title": "工位蛐蛐",
  "summary": "工位附近有蛐蛐叫，找了两晚没找到，第三晚又听到了",
  "summarySource": "AI",
  "status": "ACTIVE",
  "memberCount": 4,
  "startedTime": "2026-08-11T09:00:00Z",
  "lastTime": "2026-08-13T22:00:00Z",
  "createTime": "2026-08-11T09:30:00Z",
  "updateTime": "2026-08-13T22:05:00Z",
  "members": [
    { "memo": "memos/1001", "snippet": "工位附近有蛐蛐在叫……", "displayTime": "2026-08-11T09:00:00Z" }
  ]
}
```

`members` 仅在详情接口输出。

## 5. 增量同步

`change_log` 表新增 entity 取值：

- `thread`，`entityId` 为 `threads/{id}`
- `thread_suggestion`，`entityId` 为 `threadSuggestions/{id}`

**成员增删只写 thread 的 UPDATE changelog**，不 bump 成员 memo 的 `updated_ts`。否则会把无关 memo 卷入增量同步，并可能污染版本历史（`memo_revision_logs`）。

客户端消费到 `thread` 变更时调 `GET /api/v1/threads/{id}`，一次取回含成员的完整数据 —— 单个事件串成员通常十几篇，全量返回比做成员级增量便宜得多。

已有的「变更条数 ≥ 300 则降级全量同步」规则不变。

### 5.1 离线创建与推送顺序

离线新建的 memo 没有 `memosName`，无法作为成员推送。Push 阶段：

1. 先推 memo（沿用现有 `_pushPending`）
2. 再推 thread：把 `memberLocalIds` 映射为 `memosName`，映射不到的成员**本次跳过**，thread 保持 `pending`，下一轮补齐

与现有 `localFolderId` 的处理是同一套路。

### 5.2 级联删除

- **删除 memo**：先经 `idx_thread_members_memo` 查出受影响的 `thread_id` 列表（供写 changelog 用），再 `DELETE FROM thread_members WHERE memo_id = ?`，然后 bump 这些事件串的 `updated_ts` 并各写一条 `thread` 的 UPDATE changelog；同时把该 memo 相关的 `PENDING` 建议置为 `DISMISSED`
- **软删 thread**（`row_status = DELETED`）：`thread_members` 行原样保留（便于恢复），仅写 `thread` 的 DELETE changelog；客户端据此本地删除
- 客户端侧对应：memo 本地删除时从所有 `ThreadEntry.memberLocalIds` 中移除该 id

### 5.3 冲突

`title` / `summary` / `status` / 成员列表**整体** last-write-wins（比较 `updatedAt`）。冲突时保留本地并标记 `syncStatus = conflict`，复用现有机制。

## 6. AI 行为

### 6.1 两类后台任务

**A. 简介生成（增量）**

- 触发：事件串创建后，以及每次成员发生变化后
- 首次（创建时，成员少）做全量总结
- 之后一律增量：输入为 `旧简介 + 新加入成员的正文` → 输出新简介，输入量恒定
- 兜底（需全量重算，如批量删成员）：取样 **最早 3 篇 + 最新 5 篇，每篇截断 800 字**
- `summary_source = MANUAL` 时跳过，不覆盖用户手写的简介

全量重算必须取样的原因：「装修」这类长事件串可能攒 30 篇 × 1500 字 ≈ 6 万 tokens，超出本地模型 5 万上下文。真正的 context 压力在这里，不在匹配环节。

**B. 归属匹配**

- 触发：memo 创建时，以及 memo 更新且 **content 实际变化**时 —— 后者需把 `thread_scan_ts` 重置为 `0` 再入队。仅改 pin/archive/mood/weather 等不重置。成员增删同样不重置（这正是用「扫过没有」而非「归属了没有」的收益：把日记移出事件串不会触发重新分析）
- 去重：同一 `(memo_id, thread_id)` 若已存在 `DISMISSED` 的建议，则不再重复建议 —— 否则每次编辑正文都会把用户否掉的建议重新推一遍
- 输入：
  - 当前日记正文
  - **全部**事件串的 `title + summary`（`RESOLVED` 的也参与，prompt 中注明已完结）
  - 每个事件串**最新一篇日记的首句**
- 输出：命中的 `thread_id` + `confidence` + `reason`，或「无匹配」
- 结果写入 `thread_suggestions`（`PENDING`）
- 成功后写 `thread_scan_ts = now`

上下文预算（本地模型 5 万）：

| 输入项 | 量级 |
|--------|------|
| 30 个事件串 title + summary（约 50 字/条） | ~2000 tokens |
| 30 条最新一篇首句（约 30 字/条） | ~1200 tokens |
| 新日记正文（长文按 2000 字算） | ~3000 tokens |
| prompt 模板 | ~500 tokens |
| **合计** | **< 7000 tokens** |

裕度充足。附加「最新一篇首句」是为了救「还是没找到」这类短到没有关键词的日记 —— 只看简介模型容易在多个事件串间摇摆，看到最新进展即可判定。

`RESOLVED` 事件串照样参与匹配：蛐蛐正是「以为死了 → 又叫了」，过早标完结就永远匹配不上。

**不做时间窗口过滤。** 简介匹配与时间无关，隔几个月复发的事件也能命中。

### 6.2 隐私边界

沿用服务端现有规则（`cloudConsent` 仅对当前请求有效、不持久化）：

- **后台任务硬编码 `provider = LOCAL`**，不接 DeepSeek 分支 —— 后台任务无法代用户同意上云
- `LOCAL` 不可用时：简介生成跳过（保持旧简介）；归属匹配退化为关键词粗排，`confidence` 封顶 0.5，`reason` 标注「关键词匹配」，且**不写 `thread_scan_ts`**，待 LOCAL 恢复后重跑
- 用户在客户端手动触发 `/ai/thread-summary` 或 `/ai/thread-match` 时，才可选 DeepSeek 并带 `cloudConsent`

**AI 永不直接写 `thread_members`。** AI 只写 `thread_suggestions` 和 `threads.summary`。成员写入一律由用户确认后走普通 API。这是服务端既有规则「AI 接口不会直接修改 memo 或 article，仅返回建议内容供客户端确认」的延续。

### 6.3 前台抢占

现有并发闸门在 `handler/ai.go`：`localGate` 容量 1、`deepSeekGate` 容量 2，`tryAcquireProvider` 为非阻塞获取，满则返回 429。

新增抢占逻辑：

- `AIHandler` 持有后台任务的 `context.CancelFunc` 注册表（mutex 保护）
- 前台请求（标签建议 / 润色 / 手动重新分析）在获取 `localGate` **之前**先调用 `preemptBackground()`：cancel 当前后台任务，并等待其释放闸门（超时 2s，超时则照常返回 429）
- cancel 会断开到本地模型的 HTTP 连接，llama.cpp 收到断连即停止生成，闸门随之释放
- 后台 worker 用**阻塞式**获取闸门（它可以等），前台仍用 `tryAcquireProvider`

**被中止的任务不丢**：`thread_scan_ts` 保持 `0`，稍后空闲时自然重跑；服务重启后启动扫描一遍即可补上。内存队列只做调度，持久化状态靠这一列。后台 worker 单并发，避免打爆 LOCAL。

## 7. 客户端 UI

### 7.1 导航调整

底部导航由 `待办 | 主页 | FAB | 日历 | 文章` 改为：

```
事件串 | 主页 | (FAB) | 日历 | 待办
```

文章入口移入侧边抽屉。改动位于 `lib/shared/widgets/main_scaffold.dart`，`AppStrings` 增加 `navThreads`。

### 7.2 事件串 Tab

- 顶部：有 `PENDING` 建议时显示横幅「发现 N 条可能的关联」，点击进入确认列表
- 分组：进行中 / 已完结
- 卡片：`标题 · 简介 · 4 篇 · 08月11日–08月13日`

### 7.3 事件串详情页

竖向时间线，每篇一张精简卡片（日期 + 正文前 3 行 + 天气/心情图标），点击进入原日记。顶部可编辑标题、改写简介、标记完结。

### 7.4 日记详情页（解决核心痛点）

- 正文上方一排事件串 chip；多个并排，超过 2 个折叠为 `+N`
- 底部导航条：`← 上一篇 · 事件串「工位蛐蛐」3/4 · 下一篇 →`

单看一篇不再丢上下文，因为前后文永远在手边。

### 7.5 时间线卡片

右上角小 chip 显示所属事件串（标题截断）。有待确认建议时显示**淡色虚线 chip**（`? 工位蛐蛐`），点击就地确认或忽略，不弹窗、不跳页。

### 7.6 编辑器

工具栏增加「事件串」按钮，手动选择已有事件串或新建。**手动是主路径，AI 只是兜底** —— 因此 Phase 1 不含 AI 也完全可用。

### 7.7 创建页的批量加入

创建事件串时必须能**搜索日记并批量加入**（复用现有全文搜索）。纯手动创建路线下这是必需配套：否则「工位蛐蛐」那四篇要退出去一篇篇挂，不可用。

## 8. 分期

**Phase 1 — 纯手动，无 AI。做完即可解决蛐蛐问题。**

- 服务端：`threads` + `thread_members` 两表 + CRUD API + changelog entity `thread`
- 客户端：`ThreadEntry` 模型 + 同步（含离线推送顺序、冲突）+ 底部 Tab 改版 + 详情页事件串 chip 与上下篇导航 + 编辑器手动挂载 + 创建页批量加入
- 文档：`server-API.md` 补 threads 章节

**Phase 2 — AI 兜底**

- 服务端：`thread_suggestions` 表 + `memos.thread_scan_ts` 列 + `/ai/thread-summary` + `/ai/thread-match` + 后台 worker + 前台抢占 + changelog entity `thread_suggestion`
- 客户端：`ThreadSuggestionEntry` + 建议横幅 + 时间线虚线 chip 就地确认
- 文档：`server-API.md` 补 AI 与建议章节

**Phase 3 — 可选**

- 用已有事件串简介**回扫历史日记**（注意：是回扫，不是从历史中发现新事件串）
- 长期无更新的事件串自动建议标记完结

## 9. 验收标准

Phase 1：

- 手动创建「工位蛐蛐」，搜索并一次加入 4 篇历史日记
- 任一篇的详情页显示事件串 chip 与 `← 上一篇 · 3/4 · 下一篇 →`，可前后跳转
- 离线新建一篇日记并加入该事件串，恢复网络后 memo 与 thread 成员均正确同步
- 另一设备通过 changelog 增量同步拉到该事件串及其全部成员

Phase 2：

- 新写一篇「今晚又听到蛐蛐了」，保存后不做任何操作，时间线卡片出现虚线 chip `? 工位蛐蛐`，点击即加入
- 后台分析进行中时手动触发标签建议，标签建议立即返回（不 429），且后台任务稍后自动重跑
- 关闭 LOCAL provider 后，后台匹配退化为关键词建议且 `thread_scan_ts` 保持 0
