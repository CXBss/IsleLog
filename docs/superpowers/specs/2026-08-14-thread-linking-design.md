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
- 创建后 AI 生成简介，用户可手动改写
- **每晚一次批处理**：拿各事件串的简介判断当天新增/修改的日记可能属于哪个，产出建议供确认
- 用户主动触发的 AI 任务抢占并中止后台任务（详见 §6）

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
```

> `thread_suggestions` 表与 `thread_scan_ts` 等列属于 Phase 2，定义见 §6.8（含幂等加列机制与 unique index 去重）。

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
  bool summaryIsManual = false;      // 来源：true = 用户写的（仅供 UI 显示）
  bool summaryLocked = false;        // true 时 AI 不得改写（Phase 2 新增）

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
  @enumerated SyncStatus syncStatus = SyncStatus.synced;
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

> 建议与 AI 相关接口属于 Phase 2，见 §6.9。

**只做成员的全量替换**，不做单成员 POST/DELETE。理由是**离线客户端的重试语义**：客户端离线期间可能对同一事件串加了 3 篇、删了 1 篇；若只有单条接口，push 需先 diff 再发 4 个请求，第 3 个失败时事件串停在中间状态 —— 而 `syncStatus` 只有一个标记位，表达不了「还差一篇和一个删除」，重试也得记住发到哪了。`PUT` 整个列表则是一个请求、一次原子写、一条 changelog、天然幂等，失败原样重发即可。服务端实现见下方事务说明。

服务端实现为一个事务：`DELETE FROM thread_members WHERE thread_id = ?` 后批量 `INSERT`，随后 bump `threads.updated_ts` 并写一条 changelog。

代价是并发覆盖：两台设备同时改同一事件串时后写覆盖先写，先写方新增的成员会丢。这正是 §5.3 接受的 LWW 取舍，对单人单设备为主的场景成本远低于成员级墓碑机制。

接口风格对齐现有「设置 Memo 的附件」（`PATCH /memos/:memo/attachments`）。

**不做反查接口** `GET /memos/:memo/threads`：客户端本地有全量数据，本地索引查询即可。

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

建议（`thread_suggestions`）**不进 changelog**，每次同步全量拉取待确认列表即可，理由见 §6.9。

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

## 6. Phase 2：AI 辅助

Phase 1 交付的是纯手动的事件串。Phase 2 让 AI 承担两件事：**给事件串写一句话简介**，以及**发现漏归类的日记**。手动始终是主路径，AI 只是兜底。

### 6.1 调度：每晚一次批处理

不做实时分析。所有 AI 工作集中在**每天凌晨 4 点**跑一个批次。

这带来三个免费的好处，都不需要额外代码：
- 一天之内对同一篇日记的反复编辑，天然合并成一次分析
- 批量增删成员天然合并成一次简介重算
- 用户睡着时跑，与前台请求基本不冲突

**不引入 cron 库**，用 10 分钟间隔的 ticker 加追赶判断：

```go
// 今天的 4 点已过，且今天还没跑过，且不在退避期内
if now.After(todayAt4) && lastRunTs < todayAt4.Unix() && now.After(pausedUntil) {
    runNightlyBatch()
}
```

比真 cron 更健壮：服务在 4 点恰好重启、或宕了两小时，醒来后照样补上当天批次；真 cron 会直接错过。

`last_run_ts` **只在批次完整跑完时才写**。中途被中止（抢占、超时、进程退出）都不写，下次自然续跑。

### 6.2 批次内容与顺序

```
1. 重算简介：所有 summary_dirty = 1 且 summary_locked = 0 的事件串
2. 归属匹配：所有 thread_scan_ts = 0 的日记（单次上限 200 篇）
```

**顺序不能反**：匹配的输入正是各事件串的简介，简介没更新就是拿旧的去匹配。两步不并发，`localGate` 本来也只有 1。

### 6.3 简介生成

- 输入：事件串标题 + **全部成员的完整正文**，不截断
- 输出：一句话进展简介（≤ 60 字）
- `summary_locked = 1` 时跳过，不覆盖已锁定的简介
- 每次都**全量重算**，不做增量

**锁定与来源是两件事。** `summary_source`（AI / MANUAL）记录**谁写的**，供 UI 显示；`summary_locked` 决定 **AI 能不能改**。二者分开的原因：若只有 `summary_source`，用户想冻结一条 AI 写得不错的简介，唯一办法是把它原样重打一遍好让它变成 MANUAL —— 显然不合理。

- 用户点锁定按钮 → `summary_locked = 1`，来源不变
- 用户手动改写简介 → 同时置 `summary_source = MANUAL` 且 `summary_locked = 1`（否则当晚就被覆盖，是个坏惊喜）
- 用户解锁 → AI 在下次 `summary_dirty` 时恢复接管

不做增量的理由：增量（旧简介 + 新成员正文）当初是为了防止上下文溢出，但本地模型上下文已达 20 万 token，全量不再是问题。而增量要额外维护「哪些成员是新的」「成员被移除时回退全量」两套逻辑和两套 prompt，并且拿简介再总结简介会像传话游戏一样逐轮漂移。夜间批次里「脏」的事件串通常只有 1–3 个，省那几次调用不值得。

**唯一的兜底**：整串正文超过该 provider 配置上下文（`ProviderConfig.ContextLength`）的 70% 时，退回取样（最早 3 篇 + 最新 5 篇，每篇截断 800 字）。阈值从配置推导而非写死数字，换硬件后改配置即可。这条防的是「某个事件串塞进几十篇超长正文 → 上下文溢出 → 该串每晚失败且永远失败」。

### 6.4 归属匹配

- 触发：memo 创建时，以及 memo 更新且 **content 实际变化**时 —— 后者把 `thread_scan_ts` 重置为 0。仅改 pin/archive/mood/weather 等不重置；成员增删也不重置
- 输入：
  - 当前日记正文
  - 候选事件串列表，每条含 `title + summary + status + 最新一篇日记首句`
  - 候选上限 150 条（按最近活跃排序），保险丝
- 输出：命中的事件串 + `confidence` + `reason`，或无匹配
- 成功后写 `thread_scan_ts = now`

附加「最新一篇首句」是为了救「还是没找到」这类短到没有关键词的日记 —— 只看简介模型容易在多个事件串间摇摆，看到最新进展即可判定。

`RESOLVED` 的事件串**照样参与匹配**，prompt 中注明已完结、除非明确延续否则不选。蛐蛐正是「以为死了 → 又叫了」，过早标完结就永远匹配不上。

**不做时间窗口过滤**：简介匹配与时间无关，隔几个月复发的事件也能命中。

#### 服务端必须校验模型输出

照搬润色那套「不信任模型返回值」的思路：

- `threadId` 不在本次候选集中 → 整条丢弃（防编造）
- `confidence` 不在 0–1 → 丢弃
- **`confidence < 0.7` → 丢弃，不入库**

高阈值是刻意的取舍：宁可漏报，也不要用平庸猜测磨损信任。代价是「还是没找到」这类短日记可能需要手动归类。

因为低置信度结果根本不入库，**不需要「低置信度收进列表」的分档 UI**，也不需要 LOCAL 不可用时的关键词粗排兜底——那条路径产出的 confidence 永远够不到 0.7，写了也不会有可见结果。模型不可用就什么都不做，等下次。

### 6.5 隐私边界

- **后台批次硬编码 `provider = LOCAL`**，不接 DeepSeek 分支 —— 后台任务无法代用户同意上云（`cloudConsent` 仅对当次请求有效且不持久化）
- 只有用户手动触发的两个接口才可选 DeepSeek 并带 `cloudConsent`
- **AI 永不写 `thread_members`**。AI 只写 `thread_suggestions` 和 `threads.summary`

### 6.6 前台抢占与退避

夜间批次严格串行、`localGate` 容量为 1，因此**同一时刻只有一个后台调用**。spec 早期设想的 `CancelFunc` 注册表退化成一个字段：

```go
type AIHandler struct {
    bgMu     sync.Mutex
    bgCancel context.CancelFunc // nil = 后台空闲
}
```

前台请求（标签建议 / 润色 / 手动触发）在 `tryAcquireProvider` **之前**先调 `preemptBackground()`：取锁、cancel、等闸门释放，上限 3 秒，超时则照旧返回 429。

底层已具备该能力：`handler/ai_test.go` 中的 `TestAIForwardsCanceledRequestContext` 与 `TestAIConcurrencyGateReleasesAfterContextCancellation` 证明 provider 会透传 context 取消、闸门会正确释放。

**被抢占后必须退避**，否则用户夜间使用的那段时间里，批次会陷入「被 cancel → 立刻重试 → 又被 cancel」的循环：

```
被抢占 → paused_until = now + 15min，且不写 last_run_ts
```

进度全在 `thread_scan_ts` / `summary_dirty` 上，15 分钟后从断点续跑，跑完才写 `last_run_ts`。

### 6.7 首次上线的存量回填

`thread_scan_ts` 默认 0 意味着**加完列后全库历史日记都变成「待分析」**。几年的日记 × 每次十几秒，第一晚要跑几小时，且绝大多数毫无意义（此时事件串总共才几个）。

因此加列迁移的同一步里执行一次：

```sql
UPDATE memos SET thread_scan_ts = updated_ts WHERE thread_scan_ts = 0;
```

功能从「今天起写的和改的」开始生效。历史回扫是 Phase 3 的显式动作（用户在设置页主动触发、明确知道要跑多久），不是升级后的意外惊喜。

### 6.8 数据模型增补

服务端 `Migrate` 目前只执行 `CREATE TABLE IF NOT EXISTS`，没有加列机制。需引入幂等 helper（`PRAGMA table_info` 查后再 `ALTER`）：

```go
func addColumnIfMissing(db *sql.DB, table, column, ddl string) error
```

用它加三列：

```sql
memos.thread_scan_ts     INTEGER NOT NULL DEFAULT 0  -- 0 = 待分析
threads.summary_dirty    INTEGER NOT NULL DEFAULT 0  -- 1 = 简介待重算
threads.summary_locked   INTEGER NOT NULL DEFAULT 0  -- 1 = AI 不得改写
users.thread_ai_enabled  INTEGER NOT NULL DEFAULT 1  -- 自动分析总开关
```

加 `summary_locked` 时回填，保持 Phase 1 的既有行为：

```sql
UPDATE threads SET summary_locked = 1 WHERE summary_source = 'MANUAL';
```

开关用**独立列而非 `users.extra` 的 JSON**：worker 每轮要用它过滤，`json_extract` 写在轮询 SQL 里既慢又脆。

建议表：

```sql
CREATE TABLE IF NOT EXISTS thread_suggestions (
  id         INTEGER PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  memo_id    INTEGER NOT NULL REFERENCES memos(id)   ON DELETE CASCADE,
  thread_id  INTEGER NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
  confidence REAL    NOT NULL DEFAULT 0,
  reason     TEXT    NOT NULL DEFAULT '',
  status     TEXT    NOT NULL DEFAULT 'PENDING',  -- PENDING / ACCEPTED / DISMISSED
  created_ts INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_thread_suggestions_user_status
  ON thread_suggestions(user_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_thread_suggestions_pair
  ON thread_suggestions(memo_id, thread_id);
```

**unique index 取代了显式去重逻辑**：同一对 `(memo, thread)` 一辈子只存在一行，插入用 `INSERT OR IGNORE`。用户否掉之后再怎么改正文都不会重新冒出来，且省掉一次「先查有没有 DISMISSED」的查询。

代价：接受建议后又把日记移出事件串，系统不会再建议第二次。这是刻意的——第二次提示只会烦人。

**软删除不触发级联**：memo 和 thread 都是软删除，`ON DELETE CASCADE` 不会触发。列表接口必须显式过滤，只返回 memo 与 thread 均为 `NORMAL` 的建议。

调度状态存单行配置：`thread_ai_last_run_ts`、`thread_ai_paused_until_ts`。

### 6.9 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/ai/thread-status` | 队列与调度状态 |
| PATCH | `/api/v1/ai/thread-settings` | `{enabled}` 开关 |
| POST | `/api/v1/ai/thread-batch:run` | 立即跑一次批次 |
| POST | `/api/v1/ai/thread-summary` | 单个事件串重新生成简介，可选 DeepSeek |
| GET | `/api/v1/thread-suggestions` | 参数 `status`，默认 `PENDING` |
| PATCH | `/api/v1/thread-suggestions/:id` | 改 `status` 为 `ACCEPTED` / `DISMISSED` |

`thread-status` 响应：

```json
{
  "enabled": true,
  "providerAvailable": true,
  "pendingMemos": 3,
  "dirtyThreads": 1,
  "lastRunTime": "2026-08-24T04:00:12Z",
  "lastRunError": ""
}
```

**不做「单篇日记重新分析归属」接口**：有了「立即跑批次」，它没有独立价值。

**建议不走 changelog。** 每次同步直接 `GET /thread-suggestions?status=PENDING` 全量拉取——高阈值之后这个列表本来就很短，增量同步的复杂度（entity 分支、冲突判定）换不来任何东西。

#### 修复 Phase 1 的 `summary_source` 缺陷

Phase 1 中，服务端从「请求里有没有 `summary`」**推断**用户是否手写。而客户端 `_pushPendingThreads` 每次 `updateThread` 都会带上 `summary`，导致**用户只要改过一次标题或标记过一次完结，该事件串的 AI 简介就永久失效**。Phase 1 未暴露此问题，因为当时还没有 AI 写简介。

改为客户端**显式声明**：

```
PATCH /threads/:id  {
  "summary": "...",
  "summarySource": "AI" | "MANUAL",
  "summaryLocked": true
}
```

服务端不再推断意图，三个字段都由客户端显式声明。`summaryLocked` 同时也是锁定按钮的写入通道。

配套：**AI 生成简介后必须 bump `threads.updated_ts` 并写 changelog**，否则客户端永远拉不到新简介。

### 6.10 客户端

**建议的接受流程：服务端不代写成员。**

服务端收到 `ACCEPTED` 只记录状态，成员写入完全走客户端既有的事件串推送链路：客户端本地把 memo 加进 `memberLocalIds`（thread 转 pending）+ 把建议标为 accepted，两者各自按既有规则同步。

这样避免两个写入方（服务端 accept 分支 + 客户端 `PUT members`）互相覆盖，且让「AI 永不写 `thread_members`」在代码上真的没有那条路径。离线点「加入」也照常工作。

**新增本地集合** `ThreadSuggestionEntry`：`suggestionName` / `memoLocalId` / `threadLocalId` / `confidence` / `reason` / `status` / `syncStatus`，形状照 `ThreadEntry`。拉取时只覆盖本地 `synced` 的行，本地已操作但未推送的保持不动，避免离线操作被服务端旧状态复活。

**建议的两个入口**（高阈值筛过之后剩下的都有把握，两个都值得做）：

- 事件串 Tab 顶部横幅：「发现 N 条可能的关联」→ 展开显示 `日记首行 + 理由`，两个按钮：加入 / 忽略
- 时间线卡片虚线 chip：`? 工位蛐蛐`，就地确认或忽略，不弹窗不跳页

后者正是 Phase 1 推迟的 spec §7.5 —— 当时推迟的理由就是「与建议 chip 共用同一块卡片区域，一起做只改一遍布局」。

**简介锁定按钮：**

事件串详情页简介行右侧一个锁图标。未锁定为空心锁 + 次级色，提示「锁定简介，AI 不再改写」；锁定后为实心锁 + 主题色，提示「已锁定，点击解锁」。点击即切换 `summaryLocked` 并置 `syncStatus = pending`。

手动改写简介时自动锁定，无需再点按钮。

**状态与开关：**

事件串 Tab 顶部一行状态，仅在非空闲时显示：

```
3 篇待分析 · 今晚 4:00 处理      ← 正常
模型离线，暂停分析                ← providerAvailable = false
```

设置页：`自动分析事件关联` 开关 + `立即分析` 按钮。

## 7. 客户端 UI

### 7.1 导航调整

底部导航由 `待办 | 主页 | FAB | 日历 | 文章` 改为：

```
事件串 | 主页 | (FAB) | 日历 | 待办
```

文章入口移入侧边抽屉。改动位于 `lib/shared/widgets/main_scaffold.dart`，`AppStrings` 增加 `navThreads`。

### 7.2 事件串 Tab

- 顶部：有 `PENDING` 建议时显示横幅「发现 N 条可能的关联」，点击进入确认列表（Phase 2，另见 §6.10 的状态行）
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

> 整节属于 Phase 2：两种 chip 共用同一块卡片区域，一起做只需改一遍布局。

### 7.6 编辑器

AppBar 增加「事件串」按钮，手动选择已有事件串或新建。**手动是主路径，AI 只是兜底** —— 因此 Phase 1 不含 AI 也完全可用。

> 实现修正：原设计放在底部工具栏，但该行已有录音/拍照/附件/位置/天气/心情，多一个 36px 按钮会在窄屏上把保存按钮挤出可视区。改放 AppBar（与「AI 助手」同列），语义上也更贴切——两者都是针对整篇日记的操作，而非插入内容的工具。

### 7.7 创建页的批量加入

创建事件串时必须能**搜索日记并批量加入**（复用现有全文搜索）。纯手动创建路线下这是必需配套：否则「工位蛐蛐」那四篇要退出去一篇篇挂，不可用。

## 8. 分期

**Phase 1 — 纯手动，无 AI。做完即可解决蛐蛐问题。已完成。**

- 服务端：`threads` + `thread_members` 两表 + CRUD API + changelog entity `thread`
- 客户端：`ThreadEntry` 模型 + 同步（含离线推送顺序、冲突）+ 底部 Tab 改版 + 详情页事件串 chip 与上下篇导航 + 编辑器手动挂载 + 创建页批量加入
- 文档：`server-API.md` 补 threads 章节

**Phase 2 — AI 辅助**（设计见 §6）

服务端：
- 幂等加列 helper + `memos.thread_scan_ts` / `threads.summary_dirty` / `users.thread_ai_enabled` 三列，加列时回填存量日记为已扫描
- `thread_suggestions` 表（含 `(memo_id, thread_id)` unique index）
- 夜间调度器（ticker + 追赶 + 退避）与批处理：先重算简介、后归属匹配
- AI 操作 `buildThreadSummaryCompletion` / `buildThreadMatchCompletion` + 输出校验（候选集校验、0.7 阈值）
- 前台抢占（单槽 cancel + 3 秒等待）
- 接口：`thread-status` / `thread-settings` / `thread-batch:run` / `thread-summary` / `thread-suggestions` 增删改
- 修复 Phase 1 的 `summary_source` 推断缺陷，改为客户端显式声明
- 文档：`server-API.md` 补 AI 与建议章节

客户端：
- `ThreadSuggestionEntry` 集合 + 全量拉取待确认列表（不走 changelog）
- 事件串 Tab 建议横幅 + 状态行；时间线卡片虚线 chip 就地确认
- 设置页开关与「立即分析」
- 推送 thread 时显式带 `summarySource`

**Phase 3 — 可选**

- 用已有事件串简介**回扫历史日记**（是回扫，不是从历史中发现新事件串）。Phase 2 已把存量日记标记为已扫描，因此这必须是用户显式触发的动作
- 长期无更新的事件串自动建议标记完结

## 9. 验收标准

Phase 1（已验证）：

- 手动创建「工位蛐蛐」，搜索并一次加入 4 篇历史日记
- 任一篇的详情页显示事件串 chip 与 `← 上一篇 · 3/4 · 下一篇 →`，可前后跳转
- 离线新建一篇日记并加入该事件串，恢复网络后 memo 与 thread 成员均正确同步
- 另一设备通过 changelog 增量同步拉到该事件串及其全部成员

Phase 2：

- 升级到含 Phase 2 的服务端后，`thread_status` 的 `pendingMemos` 为 0（存量日记已回填为已扫描），不会触发全库分析
- 新写一篇「今晚又听到蛐蛐了」，次日 4 点后同步，时间线卡片出现虚线 chip `? 工位蛐蛐`，点击即加入且成员正确推送
- 同一篇日记的建议被忽略后，再次编辑其正文也不会重新出现（unique index 生效）
- 手动点「立即分析」可跳过等待，效果与夜间批次一致
- 批次运行中触发标签建议：标签建议正常返回（不 429），批次被中止且 15 分钟后从断点续跑
- 关闭「自动分析事件关联」后，夜间批次不再运行，`pendingMemos` 持续累积但不消耗模型
- 用户手动改写某事件串的简介后，改标题或标记完结，简介不再被 AI 覆盖（`summary_source` 缺陷已修）
- 对一条 AI 生成的简介点锁定按钮，此后夜间批次不再改写它；解锁后下次 `summary_dirty` 时恢复生成
- 删除一篇有待确认建议的日记，该建议不再出现在横幅中（软删过滤生效）
