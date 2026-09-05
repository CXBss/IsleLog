# 事件串（Thread）Phase 2 实现计划 —— AI 辅助

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 AI 每晚自动为事件串写一句话简介、并发现漏归类的日记，产出高置信度建议供用户一键确认；手动始终是主路径。

**Architecture:** 服务端每天凌晨 4 点跑一次批处理（ticker + 追赶判断，非 cron），先重算简介再做归属匹配，进度全部落在数据库列上（`summary_dirty` / `thread_scan_ts`），因此中止后能从断点续跑。AI 只写 `thread_suggestions` 和 `threads.summary`，永不触碰 `thread_members`。前台 AI 请求可抢占后台任务，抢占后批次退避 15 分钟。

**Tech Stack:** Go 1.25 + Echo v4 + SQLite（modernc.org/sqlite） | Flutter + Isar 3.x + Dio 5.x

**Spec:** `docs/superpowers/specs/2026-08-14-thread-linking-design.md`（Phase 2 = §6，另见 §8 分期与 §9 验收）

## Global Constraints

- 两个仓库：客户端 `/Users/cxb/Code/flutter/memos_local`（分支 `server-feat`）、服务端 `/Users/cxb/Code/go/islelog-back/islelog-server`（分支 `main`）
- 客户端 API 字段一律以 `server-API.md` 为准；本计划新增的接口需同步写入该文档
- 修改任何 Isar `@collection` 模型后必须运行 `dart run build_runner build --delete-conflicting-outputs`
- 服务端错误响应统一为 `{"code": 状态码, "message": "中文信息"}`
- **后台批次硬编码 `provider = LOCAL`**，绝不接 DeepSeek 分支
- **AI 永不写 `thread_members`**：AI 只写 `thread_suggestions` 与 `threads.summary`
- **建议置信度 `< 0.7` 直接丢弃、不入库**
- **候选事件串上限 150 条**（按最近活跃排序）
- **单次批次匹配上限 200 篇日记**
- 简介生成默认全量不截断；仅当正文总量超过 `ProviderConfig.ContextLength` 的 70% 时退回取样（最早 3 篇 + 最新 5 篇，每篇截断 800 字）
- 夜间批次时间：每日 04:00（服务器本地时区）；调度 ticker 间隔 10 分钟；抢占后退避 15 分钟
- ID 生成用 `util.NewID()`（snowflake）；时间字段 API 输出 RFC3339 UTC，库内 Unix 秒
- 提交信息用中文，格式 `feat:` / `fix:` / `docs:`

## 测试策略

沿用 Phase 1 已建立的两套模式：

- **服务端**：`handler/testutil_test.go` 已提供 `newTestDB` / `newTestUser` / `newTestMemo` / `newTestContext` / `decodeJSON` 夹具，直接复用，走真实 TDD。AI 调用用假 Provider 打桩（`service/ai/service_test.go` 已有先例），不依赖真实模型。
- **客户端**：同步与判定逻辑抽成纯函数放 `lib/data/database/thread_membership_policy.dart` 并单测；UI 拆出无状态展示组件做 widget test。Isar 读写与真实网络由服务端 curl 检查点和手动验收覆盖。

**已知问题（不在本计划范围）**：`flutter test` 全量运行时 `test/widget_test.dart` 的 `tearDownAll` 会卡住 12 分钟（`isar.close(deleteFromDisk: true)` 阻塞）。该问题在 Phase 1 已存在且不影响打包出的程序——`lib/` 中没有任何关闭数据库的调用。**验证客户端时请跑 `flutter test test/data test/features`，不要跑全量。**

## File Structure

**服务端（islelog-server）**

| 文件 | 责任 |
|------|------|
| `db/migrate.go` | 修改：`thread_suggestions` 建表；新增 `addColumnIfMissing` 与加列/回填逻辑 |
| `model/thread_suggestion.go` | 新建：`ThreadSuggestion` 与 `ToJSON` |
| `service/ai/types.go` | 修改：`ThreadSummaryRequest/Result`、`ThreadMatchRequest/Result`、`ThreadCandidate` |
| `service/ai/prompts.go` | 修改：两个 `buildXCompletion` 与 schema 常量 |
| `service/ai/thread.go` | 新建：`ThreadSummary` / `ThreadMatch` 两个 Service 方法与输出校验 |
| `service/ai/thread_test.go` | 新建：校验逻辑测试（假 Provider） |
| `service/thread_batch.go` | 新建：批处理与调度器（`ThreadBatchService`） |
| `handler/thread_suggestion.go` | 新建：建议列表/改状态接口 |
| `handler/thread_ai.go` | 新建：status / settings / batch:run / thread-summary 接口 |
| `handler/ai.go` | 修改：`preemptBackground` 与后台 cancel 槽 |
| `handler/thread.go` | 修改：`summarySource` / `summaryLocked` 显式声明；成员变更置 `summary_dirty` |
| `handler/memo.go` | 修改：创建/更新 memo 时重置 `thread_scan_ts` |
| `main.go` | 修改：注册新路由、启动调度器 |
| `server-API.md`（客户端仓库） | 修改：补 Phase 2 章节 |

**客户端（memos_local）**

| 文件 | 责任 |
|------|------|
| `lib/data/models/thread_entry.dart` | 修改：新增 `summaryLocked` |
| `lib/data/models/thread_suggestion_entry.dart` | 新建：`ThreadSuggestionEntry` 与 `SuggestionStatus` |
| `lib/data/database/database_service.dart` | 修改：注册 schema + 建议 CRUD |
| `lib/data/database/thread_membership_policy.dart` | 修改：建议合并的纯函数 |
| `lib/services/api/memos_api_service.dart` | 修改：Phase 2 接口 |
| `lib/services/sync/sync_service.dart` | 修改：拉取建议、推送 `summaryLocked` |
| `lib/features/threads/widgets/suggestion_banner.dart` | 新建：建议横幅（无状态，可测） |
| `lib/features/threads/widgets/thread_ai_status_line.dart` | 新建：状态行（无状态，可测） |
| `lib/features/threads/thread_detail_page.dart` | 修改：简介锁定按钮 |
| `lib/features/threads/threads_view.dart` | 修改：接入横幅与状态行 |
| `lib/features/home/widgets/memo_timeline_card.dart` | 修改：虚线建议 chip |
| `lib/features/settings/ai_settings_page.dart` | 修改：自动分析开关 + 立即分析按钮 |

---

# Part A — 服务端

### Task 1: 幂等加列机制与四列迁移

**Files:**
- Modify: `db/migrate.go`
- Create: `db/migrate_test.go`

**Interfaces:**
- Produces:
  - `func addColumnIfMissing(database *sql.DB, table, column, ddl string) (bool, error)` —— 返回是否真的加了列，用于只在首次加列时回填
  - `func BackfillThreadScanTs(database *sql.DB) error`
  - `func BackfillSummaryLocked(database *sql.DB) error`
  - 新列：`memos.thread_scan_ts`、`threads.summary_dirty`、`threads.summary_locked`、`users.thread_ai_enabled`
  - 新表：`app_settings(key TEXT PRIMARY KEY, value TEXT)`，存 `thread_ai_last_run_ts` / `thread_ai_paused_until_ts`

- [ ] **Step 1: 写失败的测试**

创建 `db/migrate_test.go`：

```go
package db

import (
	"database/sql"
	"path/filepath"
	"testing"
)

func openTestDB(t *testing.T) *sql.DB {
	t.Helper()
	database, err := Open(filepath.Join(t.TempDir(), "test.db"), "")
	if err != nil {
		t.Fatalf("打开测试数据库失败：%v", err)
	}
	t.Cleanup(func() { _ = database.Close() })
	return database
}

func hasColumn(t *testing.T, database *sql.DB, table, column string) bool {
	t.Helper()
	rows, err := database.Query(`SELECT name FROM pragma_table_info(?)`, table)
	if err != nil {
		t.Fatalf("查询列失败：%v", err)
	}
	defer rows.Close()
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatalf("扫描失败：%v", err)
		}
		if name == column {
			return true
		}
	}
	return false
}

func TestMigrateAddsPhase2Columns(t *testing.T) {
	database := openTestDB(t)

	for _, item := range []struct{ table, column string }{
		{"memos", "thread_scan_ts"},
		{"threads", "summary_dirty"},
		{"threads", "summary_locked"},
		{"users", "thread_ai_enabled"},
	} {
		if !hasColumn(t, database, item.table, item.column) {
			t.Fatalf("%s.%s 未创建", item.table, item.column)
		}
	}
}

func TestMigrateIsIdempotent(t *testing.T) {
	database := openTestDB(t)

	// Open 已执行过一次，再执行两次不应报错
	for i := 0; i < 2; i++ {
		if err := Migrate(database); err != nil {
			t.Fatalf("第 %d 次重复迁移失败：%v", i+2, err)
		}
	}
}

// 加列后全库历史日记都会变成「待分析」，第一晚会跑几小时且几乎全无意义，
// 因此加列的同一步必须把存量日记回填为已扫描。
func TestMigrateBackfillsExistingMemosAsScanned(t *testing.T) {
	database := openTestDB(t)
	if _, err := database.Exec(
		`INSERT INTO users (id, name, display_name, email, password_hash, role, created_ts, updated_ts, extra)
		 VALUES (1, 'alice', 'alice', '', 'x', 'USER', 100, 100, '{}')`); err != nil {
		t.Fatalf("插入用户失败：%v", err)
	}
	// 模拟「加列前就存在的日记」：直接把 thread_scan_ts 置 0
	if _, err := database.Exec(
		`INSERT INTO memos (id, user_id, content, visibility, row_status, pinned, tags, type, title,
		                    display_ts, created_ts, updated_ts, extra, thread_scan_ts)
		 VALUES (1, 1, '历史日记', 'PRIVATE', 'NORMAL', 0, '[]', 'MEMO', '', 100, 100, 555, '{}', 0)`); err != nil {
		t.Fatalf("插入日记失败：%v", err)
	}

	if err := BackfillThreadScanTs(database); err != nil {
		t.Fatalf("回填失败：%v", err)
	}

	var scanTs int64
	if err := database.QueryRow(`SELECT thread_scan_ts FROM memos WHERE id=1`).Scan(&scanTs); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if scanTs != 555 {
		t.Fatalf("thread_scan_ts = %d，期望回填为 updated_ts 555", scanTs)
	}
}

// Phase 1 中用户手写简介体现为 summary_source='MANUAL'，
// 加 summary_locked 时必须回填，否则这些简介会突然被 AI 接管。
func TestMigrateBackfillsSummaryLockedFromManualSource(t *testing.T) {
	database := openTestDB(t)
	if _, err := database.Exec(
		`INSERT INTO users (id, name, display_name, email, password_hash, role, created_ts, updated_ts, extra)
		 VALUES (1, 'alice', 'alice', '', 'x', 'USER', 100, 100, '{}')`); err != nil {
		t.Fatalf("插入用户失败：%v", err)
	}
	if _, err := database.Exec(
		`INSERT INTO threads (id, user_id, title, summary, summary_source, status, created_ts, updated_ts, row_status, summary_locked)
		 VALUES (1, 1, '手写', '我写的', 'MANUAL', 'ACTIVE', 100, 100, 'NORMAL', 0),
		        (2, 1, 'AI 写', 'AI 写的', 'AI', 'ACTIVE', 100, 100, 'NORMAL', 0)`); err != nil {
		t.Fatalf("插入事件串失败：%v", err)
	}

	if err := BackfillSummaryLocked(database); err != nil {
		t.Fatalf("回填失败：%v", err)
	}

	var manualLocked, aiLocked int
	if err := database.QueryRow(`SELECT summary_locked FROM threads WHERE id=1`).Scan(&manualLocked); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if err := database.QueryRow(`SELECT summary_locked FROM threads WHERE id=2`).Scan(&aiLocked); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if manualLocked != 1 {
		t.Fatal("summary_source='MANUAL' 的事件串应回填为已锁定")
	}
	if aiLocked != 0 {
		t.Fatal("summary_source='AI' 的事件串不应被锁定")
	}
}

func TestMigrateCreatesSuggestionTableWithUniquePairIndex(t *testing.T) {
	database := openTestDB(t)
	if _, err := database.Exec(
		`INSERT INTO users (id, name, display_name, email, password_hash, role, created_ts, updated_ts, extra)
		 VALUES (1, 'alice', 'alice', '', 'x', 'USER', 100, 100, '{}')`); err != nil {
		t.Fatalf("插入用户失败：%v", err)
	}
	insert := `INSERT INTO thread_suggestions (id, user_id, memo_id, thread_id, confidence, reason, status, created_ts)
	           VALUES (?, 1, 10, 20, 0.9, '', 'DISMISSED', 100)`
	if _, err := database.Exec(insert, 1); err != nil {
		t.Fatalf("首次插入失败：%v", err)
	}

	// 同一 (memo_id, thread_id) 再插入必须被唯一索引挡住 ——
	// 这正是「用户否掉后不再重复建议」的实现方式
	if _, err := database.Exec(insert, 2); err == nil {
		t.Fatal("同一 (memo_id, thread_id) 应被唯一索引拒绝")
	}
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./db/ -run TestMigrate -v
```

Expected: 编译失败，`undefined: BackfillThreadScanTs`

- [ ] **Step 3: 实现加列机制与建表**

在 `db/migrate.go` 的 `schema` 常量末尾（`idx_thread_members_memo` 之后、结尾反引号之前）追加：

```sql

CREATE TABLE IF NOT EXISTS thread_suggestions (
    id         INTEGER PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
    memo_id    INTEGER NOT NULL REFERENCES memos(id)   ON DELETE CASCADE,
    thread_id  INTEGER NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    confidence REAL    NOT NULL DEFAULT 0,
    reason     TEXT    NOT NULL DEFAULT '',
    status     TEXT    NOT NULL DEFAULT 'PENDING',
    created_ts INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_thread_suggestions_user_status
    ON thread_suggestions(user_id, status);

-- 同一 (memo, thread) 一辈子只存在一行：用户否掉之后，
-- 再怎么编辑正文也不会重新冒出同一条建议
CREATE UNIQUE INDEX IF NOT EXISTS idx_thread_suggestions_pair
    ON thread_suggestions(memo_id, thread_id);

CREATE TABLE IF NOT EXISTS app_settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT ''
);
```

在 `schema` 常量上方的表说明注释追加：

```
//	thread_suggestions  — AI 产出的归属建议，待用户确认
//	app_settings        — 单行键值配置（夜间批次调度状态等）
```

将 `Migrate` 替换为：

```go
// Migrate 将 schema 应用到 db，由 Open 自动调用，可多次调用。
func Migrate(database *sql.DB) error {
	if _, err := database.Exec(schema); err != nil {
		return err
	}
	return migratePhase2(database)
}

// migratePhase2 幂等地补齐 Phase 2 新增的列并回填历史数据。
//
// 加列必须先探测：CREATE TABLE IF NOT EXISTS 对已存在的表不会补列，
// 而 ALTER TABLE ADD COLUMN 重复执行会报 "duplicate column name"。
func migratePhase2(database *sql.DB) error {
	columns := []struct{ table, column, ddl string }{
		{"memos", "thread_scan_ts", "INTEGER NOT NULL DEFAULT 0"},
		{"threads", "summary_dirty", "INTEGER NOT NULL DEFAULT 0"},
		{"threads", "summary_locked", "INTEGER NOT NULL DEFAULT 0"},
		{"users", "thread_ai_enabled", "INTEGER NOT NULL DEFAULT 1"},
	}
	for _, item := range columns {
		added, err := addColumnIfMissing(database, item.table, item.column, item.ddl)
		if err != nil {
			return err
		}
		if !added {
			continue
		}
		// 只在「首次加上这一列」时回填，避免每次启动都重跑
		switch {
		case item.table == "memos" && item.column == "thread_scan_ts":
			if err := BackfillThreadScanTs(database); err != nil {
				return err
			}
		case item.table == "threads" && item.column == "summary_locked":
			if err := BackfillSummaryLocked(database); err != nil {
				return err
			}
		}
	}
	return nil
}

// addColumnIfMissing 在列不存在时添加，返回是否真的添加了。
func addColumnIfMissing(database *sql.DB, table, column, ddl string) (bool, error) {
	var count int
	err := database.QueryRow(
		`SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = ?`, table, column).Scan(&count)
	if err != nil {
		return false, err
	}
	if count > 0 {
		return false, nil
	}
	_, err = database.Exec("ALTER TABLE " + table + " ADD COLUMN " + column + " " + ddl)
	if err != nil {
		return false, err
	}
	return true, nil
}

// BackfillThreadScanTs 把存量日记标记为已扫描。
//
// 不回填的话，加完列后全库历史日记都会变成「待分析」——几年的日记乘以
// 每次十几秒，第一晚要跑几小时，而且此时事件串总共才几个，绝大多数分析
// 毫无意义。功能因此从「今天起写的和改的」开始生效；历史回扫是 Phase 3
// 的显式动作。
func BackfillThreadScanTs(database *sql.DB) error {
	_, err := database.Exec(`UPDATE memos SET thread_scan_ts = updated_ts WHERE thread_scan_ts = 0`)
	return err
}

// BackfillSummaryLocked 把 Phase 1 中用户手写的简介标记为已锁定，
// 保持既有行为——否则升级后这些简介会突然被 AI 接管改写。
func BackfillSummaryLocked(database *sql.DB) error {
	_, err := database.Exec(`UPDATE threads SET summary_locked = 1 WHERE summary_source = 'MANUAL'`)
	return err
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./db/ -v
```

Expected: 全部 PASS

- [ ] **Step 5: 全量测试与提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go build ./... && go test ./...
git add db/migrate.go db/migrate_test.go
git commit -m "feat: 事件串 Phase 2 数据库迁移与存量回填"
```

---

### Task 2: 建议模型与查询

**Files:**
- Create: `model/thread_suggestion.go`
- Create: `model/thread_suggestion_test.go`

**Interfaces:**
- Consumes: `model.FormatID(int64) string`
- Produces:
  - `model.ThreadSuggestion{ID, UserID, MemoID, ThreadID int64; Confidence float64; Reason, Status string; CreatedTs int64}`
  - `func (s *ThreadSuggestion) ResourceName() string` → `"threadSuggestions/{id}"`
  - `func (s *ThreadSuggestion) ToJSON(memoSnippet, threadTitle string) map[string]interface{}`
  - 常量 `SuggestionPending` / `SuggestionAccepted` / `SuggestionDismissed`
  - `const MinSuggestionConfidence = 0.7`

- [ ] **Step 1: 写失败的测试**

创建 `model/thread_suggestion_test.go`：

```go
package model

import "testing"

func TestThreadSuggestionToJSON(t *testing.T) {
	suggestion := &ThreadSuggestion{
		ID: 77, UserID: 1, MemoID: 1001, ThreadID: 20,
		Confidence: 0.86, Reason: "同样在讲工位的蛐蛐",
		Status: SuggestionPending, CreatedTs: 1755000000,
	}

	result := suggestion.ToJSON("今晚又听到蛐蛐了", "工位蛐蛐")

	if result["name"] != "threadSuggestions/77" {
		t.Fatalf("name = %v", result["name"])
	}
	if result["memo"] != "memos/1001" {
		t.Fatalf("memo = %v", result["memo"])
	}
	if result["thread"] != "threads/20" {
		t.Fatalf("thread = %v", result["thread"])
	}
	if result["memoSnippet"] != "今晚又听到蛐蛐了" {
		t.Fatalf("memoSnippet = %v", result["memoSnippet"])
	}
	if result["threadTitle"] != "工位蛐蛐" {
		t.Fatalf("threadTitle = %v", result["threadTitle"])
	}
	if result["confidence"] != 0.86 {
		t.Fatalf("confidence = %v", result["confidence"])
	}
	if result["status"] != "PENDING" {
		t.Fatalf("status = %v", result["status"])
	}
	if result["createTime"] != "2025-08-12T12:00:00Z" {
		t.Fatalf("createTime = %v", result["createTime"])
	}
}

// 阈值是产品决策：宁可漏报，也不要用平庸猜测磨损信任。
func TestMinSuggestionConfidenceIsSevenTenths(t *testing.T) {
	if MinSuggestionConfidence != 0.7 {
		t.Fatalf("MinSuggestionConfidence = %v，期望 0.7", MinSuggestionConfidence)
	}
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./model/ -run TestThreadSuggestion -v
```

Expected: 编译失败，`undefined: ThreadSuggestion`

- [ ] **Step 3: 实现模型**

创建 `model/thread_suggestion.go`：

```go
package model

import "time"

// 建议状态取值。
const (
	SuggestionPending   = "PENDING"
	SuggestionAccepted  = "ACCEPTED"
	SuggestionDismissed = "DISMISSED"
)

// MinSuggestionConfidence 是建议入库的最低置信度。
//
// 低于此值的模型输出直接丢弃、不入库：宁可漏报，也不要用平庸猜测磨损
// 用户对提示的信任。因为低置信度结果根本不存在，客户端也就不需要分档 UI。
const MinSuggestionConfidence = 0.7

// ThreadSuggestion 对应 thread_suggestions 表，是 AI 产出的归属建议。
//
// AI 只写这张表和 threads.summary，永不触碰 thread_members ——
// 成员写入一律由用户确认后走普通接口。
type ThreadSuggestion struct {
	ID         int64
	UserID     int64
	MemoID     int64
	ThreadID   int64
	Confidence float64
	Reason     string
	Status     string
	CreatedTs  int64
}

// ResourceName 返回 API 资源名称，格式为 "threadSuggestions/{id}"。
func (s *ThreadSuggestion) ResourceName() string {
	return "threadSuggestions/" + FormatID(s.ID)
}

// ToJSON 构建建议的 API 响应。
// memoSnippet 与 threadTitle 由调用方 JOIN 查出后传入，供客户端直接展示。
func (s *ThreadSuggestion) ToJSON(memoSnippet, threadTitle string) map[string]interface{} {
	return map[string]interface{}{
		"name":        s.ResourceName(),
		"memo":        "memos/" + FormatID(s.MemoID),
		"thread":      "threads/" + FormatID(s.ThreadID),
		"memoSnippet": memoSnippet,
		"threadTitle": threadTitle,
		"confidence":  s.Confidence,
		"reason":      s.Reason,
		"status":      s.Status,
		"createTime":  time.Unix(s.CreatedTs, 0).UTC().Format(time.RFC3339),
	}
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./model/ -v
```

Expected: 全部 PASS

- [ ] **Step 5: 提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server
git add model/thread_suggestion.go model/thread_suggestion_test.go
git commit -m "feat: 新增事件串建议模型"
```

---

### Task 3: 简介锁定与扫描标记的写入点

修掉 Phase 1 的 `summary_source` 推断缺陷，并让数据变更正确置脏。

**Files:**
- Modify: `handler/thread.go`（`UpdateThread`、`SetThreadMembers`、`CreateThread`）
- Modify: `handler/memo.go`（`CreateMemo` 第 168 行附近、`UpdateMemo` 第 392-397 行附近）
- Modify: `model/thread.go`（`Thread` 结构体与 `ToJSON`）
- Modify: `handler/thread_test.go`（追加测试）

**Interfaces:**
- Consumes: Task 1 的 `threads.summary_dirty` / `threads.summary_locked` / `memos.thread_scan_ts`
- Produces:
  - `model.Thread` 新增字段 `SummaryDirty bool`、`SummaryLocked bool`
  - `ToJSON` 输出新增 `summaryLocked`
  - `PATCH /threads/:id` 接受 `summarySource` 与 `summaryLocked`
  - `func markThreadSummaryDirty(database *sql.DB, threadID int64) error`
  - `func markMemoUnscanned(database *sql.DB, memoID int64) error`

- [ ] **Step 1: 写失败的测试**

在 `handler/thread_test.go` 末尾追加：

```go
// 创建时带手写简介必须同时锁定，否则当晚就被批次覆盖——与详情页手动
// 编辑简介的锁定语义（Task 13）保持一致。
func TestCreateThreadWithSummaryLocksIt(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)

	threadID := createThread(t, h, u, `{"title":"工位蛐蛐","summary":"用户自己写的"}`)

	result, _ := getThread(t, h, u, threadID)
	if result["summaryLocked"] != true {
		t.Fatalf("summaryLocked = %v，期望 true（创建时带手写简介应自动锁定）", result["summaryLocked"])
	}
}

// Phase 1 的缺陷：服务端从「请求里有没有 summary」推断用户是否手写，
// 而客户端每次 updateThread 都会带上 summary，导致用户只要改过一次标题，
// 该事件串的 AI 简介就永久失效。改为客户端显式声明。
func TestUpdateThreadDoesNotInferManualFromSummaryPresence(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)
	threadID := createThread(t, h, u, `{"title":"工位蛐蛐"}`)

	// 模拟客户端推送：带 summary 但显式声明来源仍是 AI
	c, rec := newTestContext(t, http.MethodPatch, "/api/v1/threads/"+threadID,
		`{"title":"工位蛐蛐（改名）","summary":"AI 写的","summarySource":"AI","summaryLocked":false}`, u)
	c.SetParamNames("thread")
	c.SetParamValues(threadID)
	if err := h.UpdateThread(c); err != nil {
		t.Fatalf("更新失败：%v", err)
	}

	result := decodeJSON(t, rec.Body.Bytes())
	if result["summarySource"] != "AI" {
		t.Fatalf("summarySource = %v，期望保持 AI（不得从 summary 存在推断为 MANUAL）", result["summarySource"])
	}
	if result["summaryLocked"] != false {
		t.Fatalf("summaryLocked = %v，期望 false", result["summaryLocked"])
	}
}

func TestUpdateThreadAcceptsExplicitLock(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)
	threadID := createThread(t, h, u, `{"title":"工位蛐蛐"}`)

	c, rec := newTestContext(t, http.MethodPatch, "/api/v1/threads/"+threadID,
		`{"summaryLocked":true}`, u)
	c.SetParamNames("thread")
	c.SetParamValues(threadID)
	if err := h.UpdateThread(c); err != nil {
		t.Fatalf("更新失败：%v", err)
	}

	if decodeJSON(t, rec.Body.Bytes())["summaryLocked"] != true {
		t.Fatal("锁定按钮应能单独把 summaryLocked 置为 true")
	}
	var locked int
	if err := database.QueryRow(`SELECT summary_locked FROM threads WHERE id=?`, threadID).Scan(&locked); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if locked != 1 {
		t.Fatalf("summary_locked = %d，期望 1", locked)
	}
}

// 成员变化必须置脏，否则夜间批次不知道该重算哪些简介。
func TestSetThreadMembersMarksSummaryDirty(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)
	memoID := newTestMemo(t, database, u, "第一篇", 1755000000)
	threadID := createThread(t, h, u, `{"title":"工位蛐蛐"}`)

	if _, err := database.Exec(`UPDATE threads SET summary_dirty=0 WHERE id=?`, threadID); err != nil {
		t.Fatalf("重置失败：%v", err)
	}
	setMembers(t, h, u, threadID, `{"memos":["memos/`+idOf(memoID)+`"]}`)

	var dirty int
	if err := database.QueryRow(`SELECT summary_dirty FROM threads WHERE id=?`, threadID).Scan(&dirty); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if dirty != 1 {
		t.Fatal("成员变更后 summary_dirty 应为 1")
	}
}

func TestCreateThreadWithMembersMarksSummaryDirty(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)
	memoID := newTestMemo(t, database, u, "第一篇", 1755000000)

	threadID := createThread(t, h, u, `{"title":"工位蛐蛐","memos":["memos/`+idOf(memoID)+`"]}`)

	var dirty int
	if err := database.QueryRow(`SELECT summary_dirty FROM threads WHERE id=?`, threadID).Scan(&dirty); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if dirty != 1 {
		t.Fatal("带初始成员创建后 summary_dirty 应为 1")
	}
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./handler/ -run "TestUpdateThreadDoesNotInfer|TestUpdateThreadAcceptsExplicitLock|MarksSummaryDirty" -v
```

Expected: FAIL —— `summaryLocked` 键不存在

- [ ] **Step 3: 模型加字段**

`model/thread.go`：在 `Thread` 结构体的 `Status` 之后加入两个字段：

```go
	SummaryDirty  bool // 1 = 简介待重算
	SummaryLocked bool // 1 = AI 不得改写
```

在 `ToJSON` 的 `result` map 中，`"summarySource"` 那一行之后加入：

```go
		"summaryLocked": t.SummaryLocked,
```

- [ ] **Step 4: 改造 handler/thread.go**

`CreateThread` 中已有的 `if req.Summary != "" { t.SummarySource = "MANUAL" }`（约第 145 行）补上锁定：

```go
	if req.Summary != "" {
		t.SummarySource = "MANUAL"
		// 手动写的简介必须同时锁定，否则当晚就被批次覆盖，是个坏惊喜——
		// 与详情页手动编辑简介时的锁定语义保持一致（见 §6.3）
		t.SummaryLocked = true
	}
```

把 `loadThread` 与 `ListThreads` 中的 SELECT 列表从
`id,user_id,title,summary,summary_source,status,created_ts,updated_ts,row_status`
改为
`id,user_id,title,summary,summary_source,status,created_ts,updated_ts,row_status,summary_dirty,summary_locked`，
并在对应的 `Scan(...)` 末尾追加 `&t.SummaryDirty, &t.SummaryLocked`（共 3 处：`loadThread` 一处、`ListThreads` 一处）。

`UpdateThread` 的请求体结构体改为：

```go
	var req struct {
		Title         *string `json:"title"`
		Summary       *string `json:"summary"`
		SummarySource *string `json:"summarySource"`
		SummaryLocked *bool   `json:"summaryLocked"`
		Status        *string `json:"status"`
	}
```

把原先「收到 summary 就置 MANUAL」的推断替换为显式声明：

```go
	if req.Summary != nil {
		t.Summary = *req.Summary
	}
	// 不再从「有没有 summary」推断意图：客户端每次推送都会带上 summary，
	// 推断会让改过一次标题的事件串永久失去 AI 简介（Phase 1 缺陷）
	if req.SummarySource != nil {
		if *req.SummarySource != "AI" && *req.SummarySource != "MANUAL" {
			return threadError(c, http.StatusBadRequest, "summarySource 只能为 AI 或 MANUAL")
		}
		t.SummarySource = *req.SummarySource
	}
	if req.SummaryLocked != nil {
		t.SummaryLocked = *req.SummaryLocked
	}
```

UPDATE 语句加上新列：

```go
	if _, err := h.db.Exec(
		`UPDATE threads SET title=?,summary=?,summary_source=?,summary_locked=?,status=?,updated_ts=? WHERE id=?`,
		t.Title, t.Summary, t.SummarySource, t.SummaryLocked, t.Status, t.UpdatedTs, t.ID); err != nil {
		return threadError(c, http.StatusInternalServerError, "更新失败")
	}
```

在文件末尾追加置脏辅助函数：

```go
// markThreadSummaryDirty 标记事件串的简介待重算，供夜间批次挑选。
func markThreadSummaryDirty(database *sql.DB, threadID int64) error {
	_, err := database.Exec(`UPDATE threads SET summary_dirty = 1 WHERE id = ?`, threadID)
	return err
}
```

在 `SetThreadMembers` 的 `writeChangeLog(...)` 之前、以及 `CreateThread` 的 `writeChangeLog(...)` 之前各插入：

```go
	if err := markThreadSummaryDirty(h.db, t.ID); err != nil {
		log.Printf("mark thread summary dirty error: %v", err)
	}
```

`handler/thread.go` 需新增 import `"log"`。

同样在 `cascadeRemoveMemoFromThreads` 的循环里，`writeChangeLog(database, userID, id, "thread", "UPDATE")` 之前插入：

```go
		if err := markThreadSummaryDirty(database, id); err != nil {
			log.Printf("mark thread summary dirty error: %v", err)
		}
```

- [ ] **Step 5: memo 写入点重置扫描标记**

在 `handler/thread.go` 末尾追加：

```go
// markMemoUnscanned 把日记标记为待分析。
//
// 仅在正文实际变化时调用：改 pin/archive/mood/weather 不应触发重新分析，
// 成员增删同样不触发（这正是用「扫过没有」而非「归属了没有」的收益）。
func markMemoUnscanned(database *sql.DB, memoID int64) error {
	_, err := database.Exec(`UPDATE memos SET thread_scan_ts = 0 WHERE id = ?`, memoID)
	return err
}
```

在 `handler/memo.go` 的 `UpdateMemo` 中，`writeChangeLog(h.db, u.ID, id, "memo", "UPDATE")`（约第 397 行）**之前**插入：

```go
	// 正文变化才重新分析归属；改 pin/mood/weather 等不重置
	if fields.Content != nil {
		if err := markMemoUnscanned(h.db, id); err != nil {
			log.Printf("mark memo unscanned error: %v", err)
		}
	}
```

`CreateMemo` 中新建的 memo，`thread_scan_ts` 由列默认值 0 自动满足「待分析」，**无需额外代码**。

- [ ] **Step 6: 运行测试确认通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go build ./... && go test ./...
```

Expected: 全部 PASS

- [ ] **Step 7: 提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server
git add handler/thread.go handler/thread_test.go handler/memo.go model/thread.go
git commit -m "feat: 简介锁定与扫描标记，修复 summary_source 推断缺陷"
```

---

### Task 4: AI 两个新操作与输出校验

**Files:**
- Modify: `service/ai/types.go`
- Modify: `service/ai/prompts.go`
- Create: `service/ai/thread.go`
- Create: `service/ai/thread_test.go`

**Interfaces:**
- Consumes: 既有 `completeWithOneJSONRepair`、`providerForRequest`、`ErrInvalidModelOutput`、`ProviderConfig.ContextLength`；Task 2 的 `model.MinSuggestionConfidence`（`service/ai` 与 `model` 互不依赖，import 不成环，因此阈值不重复定义）
- Produces:
  - `ai.ThreadEntryText{Content string}`
  - `ai.ThreadSummaryRequest{Title string; Entries []ThreadEntryText; ContextLength int; Provider ProviderName; CloudConsent bool}`
  - `ai.ThreadSummaryResult{Summary string; Usage Usage}`
  - `ai.ThreadCandidate{Name, Title, Summary, Status, LatestSnippet string}`
  - `ai.ThreadMatchRequest{Content string; Candidates []ThreadCandidate; Provider ProviderName; CloudConsent bool}`
  - `ai.ThreadMatchResult{ThreadName string; Confidence float64; Reason string; Usage Usage}`（`ThreadName` 为空表示无匹配）
  - `func (s *Service) ThreadSummary(ctx, ThreadSummaryRequest) (ThreadSummaryResult, error)`
  - `func (s *Service) ThreadMatch(ctx, ThreadMatchRequest) (ThreadMatchResult, error)`
  - `func SampleThreadEntries(entries []ThreadEntryText, contextLength int) []ThreadEntryText`

- [ ] **Step 1: 写失败的测试**

创建 `service/ai/thread_test.go`：

```go
package ai

import (
	"context"
	"strings"
	"testing"
)

// stubProvider 返回预设的模型输出，避免测试依赖真实模型。
type stubProvider struct {
	content string
}

func (p *stubProvider) CompleteJSON(ctx context.Context, request CompletionRequest) (CompletionResult, error) {
	return CompletionResult{Content: []byte(p.content)}, nil
}

func (p *stubProvider) Status(ctx context.Context) ProviderStatus {
	return ProviderStatus{Available: true}
}

func serviceWith(content string) *Service {
	return NewService(map[ProviderName]Provider{ProviderLocal: &stubProvider{content: content}})
}

func TestThreadSummaryTrimsAndReturnsSummary(t *testing.T) {
	service := serviceWith(`{"summary":"  找了两晚没找到，第三晚又听到了  "}`)

	result, err := service.ThreadSummary(context.Background(), ThreadSummaryRequest{
		Title:    "工位蛐蛐",
		Entries:  []ThreadEntryText{{Content: "工位附近有蛐蛐在叫"}},
		Provider: ProviderLocal,
	})
	if err != nil {
		t.Fatalf("生成失败：%v", err)
	}
	if result.Summary != "找了两晚没找到，第三晚又听到了" {
		t.Fatalf("Summary = %q", result.Summary)
	}
}

func TestThreadSummaryRejectsEmptyOutput(t *testing.T) {
	service := serviceWith(`{"summary":"   "}`)

	if _, err := service.ThreadSummary(context.Background(), ThreadSummaryRequest{
		Title: "工位蛐蛐", Entries: []ThreadEntryText{{Content: "正文"}}, Provider: ProviderLocal,
	}); err == nil {
		t.Fatal("空简介应视为无效输出")
	}
}

// 模型可能编造一个候选集中不存在的 id，必须整条丢弃。
func TestThreadMatchRejectsUnknownThreadName(t *testing.T) {
	service := serviceWith(`{"threadId":"threads/999","confidence":0.95,"reason":"编的"}`)

	result, err := service.ThreadMatch(context.Background(), ThreadMatchRequest{
		Content:    "今晚又听到蛐蛐了",
		Candidates: []ThreadCandidate{{Name: "threads/20", Title: "工位蛐蛐"}},
		Provider:   ProviderLocal,
	})
	if err != nil {
		t.Fatalf("匹配失败：%v", err)
	}
	if result.ThreadName != "" {
		t.Fatalf("候选集外的 id 应丢弃，实际 = %q", result.ThreadName)
	}
}

func TestThreadMatchDropsLowConfidence(t *testing.T) {
	service := serviceWith(`{"threadId":"threads/20","confidence":0.69,"reason":"不太确定"}`)

	result, err := service.ThreadMatch(context.Background(), ThreadMatchRequest{
		Content:    "今晚又听到蛐蛐了",
		Candidates: []ThreadCandidate{{Name: "threads/20", Title: "工位蛐蛐"}},
		Provider:   ProviderLocal,
	})
	if err != nil {
		t.Fatalf("匹配失败：%v", err)
	}
	if result.ThreadName != "" {
		t.Fatalf("置信度 0.69 低于 0.7 阈值，应丢弃，实际 = %q", result.ThreadName)
	}
}

func TestThreadMatchAcceptsConfidentHit(t *testing.T) {
	service := serviceWith(`{"threadId":"threads/20","confidence":0.86,"reason":"同样在讲工位的蛐蛐"}`)

	result, err := service.ThreadMatch(context.Background(), ThreadMatchRequest{
		Content:    "今晚又听到蛐蛐了",
		Candidates: []ThreadCandidate{{Name: "threads/20", Title: "工位蛐蛐"}},
		Provider:   ProviderLocal,
	})
	if err != nil {
		t.Fatalf("匹配失败：%v", err)
	}
	if result.ThreadName != "threads/20" {
		t.Fatalf("ThreadName = %q", result.ThreadName)
	}
	if result.Confidence != 0.86 {
		t.Fatalf("Confidence = %v", result.Confidence)
	}
	if result.Reason != "同样在讲工位的蛐蛐" {
		t.Fatalf("Reason = %q", result.Reason)
	}
}

func TestThreadMatchTreatsEmptyThreadIdAsNoMatch(t *testing.T) {
	service := serviceWith(`{"threadId":"","confidence":0,"reason":"无匹配"}`)

	result, err := service.ThreadMatch(context.Background(), ThreadMatchRequest{
		Content:    "随便写点什么",
		Candidates: []ThreadCandidate{{Name: "threads/20", Title: "工位蛐蛐"}},
		Provider:   ProviderLocal,
	})
	if err != nil {
		t.Fatalf("匹配失败：%v", err)
	}
	if result.ThreadName != "" {
		t.Fatalf("ThreadName = %q，期望空", result.ThreadName)
	}
}

func TestThreadMatchRejectsOutOfRangeConfidence(t *testing.T) {
	service := serviceWith(`{"threadId":"threads/20","confidence":1.7,"reason":"过度自信"}`)

	result, err := service.ThreadMatch(context.Background(), ThreadMatchRequest{
		Content:    "今晚又听到蛐蛐了",
		Candidates: []ThreadCandidate{{Name: "threads/20", Title: "工位蛐蛐"}},
		Provider:   ProviderLocal,
	})
	if err != nil {
		t.Fatalf("匹配失败：%v", err)
	}
	if result.ThreadName != "" {
		t.Fatalf("越界置信度应丢弃，实际 = %q", result.ThreadName)
	}
}

// 默认全量不截断；仅在超出上下文预算时才退回取样。
func TestSampleThreadEntriesKeepsAllWhenWithinBudget(t *testing.T) {
	entries := make([]ThreadEntryText, 20)
	for i := range entries {
		entries[i] = ThreadEntryText{Content: strings.Repeat("字", 100)}
	}

	sampled := SampleThreadEntries(entries, 200000)

	if len(sampled) != 20 {
		t.Fatalf("预算充足时应全量保留，实际 %d 篇", len(sampled))
	}
}

func TestSampleThreadEntriesFallsBackWhenOverBudget(t *testing.T) {
	entries := make([]ThreadEntryText, 40)
	for i := range entries {
		entries[i] = ThreadEntryText{Content: strings.Repeat("字", 2000)}
	}

	sampled := SampleThreadEntries(entries, 4096)

	if len(sampled) != 8 {
		t.Fatalf("超预算应退回最早 3 篇 + 最新 5 篇，实际 %d 篇", len(sampled))
	}
	for _, entry := range sampled {
		if len([]rune(entry.Content)) > 800 {
			t.Fatalf("取样后单篇应截断到 800 字，实际 %d", len([]rune(entry.Content)))
		}
	}
}

func TestSampleThreadEntriesHandlesFewerThanSampleSize(t *testing.T) {
	entries := []ThreadEntryText{{Content: "a"}, {Content: "b"}}

	if sampled := SampleThreadEntries(entries, 1); len(sampled) != 2 {
		t.Fatalf("成员数少于取样量时应原样返回，实际 %d 篇", len(sampled))
	}
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./service/ai/ -run "TestThread|TestSample" -v
```

Expected: 编译失败，`undefined: ThreadSummaryRequest`

- [ ] **Step 3: 加类型**

在 `service/ai/types.go` 末尾（`Provider` 接口定义之前）追加：

```go
// ThreadEntryText 是事件串中一篇日记的正文。
type ThreadEntryText struct {
	Content string `json:"content"`
}

// ThreadSummaryRequest 请求为事件串生成一句话简介。
type ThreadSummaryRequest struct {
	Title         string
	Entries       []ThreadEntryText
	ContextLength int // provider 配置的上下文长度，用于判断是否需要取样
	Provider      ProviderName
	CloudConsent  bool
}

// ThreadSummaryResult 是简介生成结果。
type ThreadSummaryResult struct {
	Summary string
	Usage   Usage
}

// ThreadCandidate 是归属匹配的候选事件串。
type ThreadCandidate struct {
	Name          string `json:"threadId"`
	Title         string `json:"title"`
	Summary       string `json:"summary"`
	Status        string `json:"status"`
	LatestSnippet string `json:"latestSnippet"`
}

// ThreadMatchRequest 请求判断一篇日记属于哪个事件串。
type ThreadMatchRequest struct {
	Content      string
	Candidates   []ThreadCandidate
	Provider     ProviderName
	CloudConsent bool
}

// ThreadMatchResult 是归属匹配结果，ThreadName 为空表示无匹配。
type ThreadMatchResult struct {
	ThreadName string
	Confidence float64
	Reason     string
	Usage      Usage
}
```

- [ ] **Step 4: 加 prompt**

在 `service/ai/prompts.go` 末尾追加：

```go
const threadSummarySchema = `{"summary":"一句话进展"}`

const threadMatchSchema = `{"threadId":"threads/123","confidence":0.0,"reason":"简短理由"}`

func buildThreadSummaryCompletion(request ThreadSummaryRequest) CompletionRequest {
	input, _ := json.Marshal(struct {
		Title   string            `json:"title"`
		Entries []ThreadEntryText `json:"entries"`
	}{Title: request.Title, Entries: request.Entries})

	return CompletionRequest{
		SystemPrompt: fmt.Sprintf(`你是 IsleLog 的事件串简介助手。提示词版本：%s。
只输出严格 JSON，不要输出 Markdown 围栏、思考过程或额外文字。输出结构必须是：%s。
把这些按时间排列的日记概括成一句话，说明这件事目前进展到哪一步，不超过 60 个汉字。
只陈述日记中确实写到的内容，不评论、不推测、不编造。使用简体中文。`, editingPromptVersion, threadSummarySchema),
		UserPrompt:  "请为以下事件串生成简介：\n" + string(input),
		Temperature: 0.2,
	}
}

func buildThreadMatchCompletion(request ThreadMatchRequest) CompletionRequest {
	input, _ := json.Marshal(struct {
		Content    string            `json:"content"`
		Candidates []ThreadCandidate `json:"candidates"`
	}{Content: request.Content, Candidates: request.Candidates})

	return CompletionRequest{
		SystemPrompt: fmt.Sprintf(`你是 IsleLog 的事件归属判断助手。提示词版本：%s。
只输出严格 JSON，不要输出 Markdown 围栏、思考过程或额外文字。输出结构必须是：%s。
判断给定日记是否是某个候选事件串的后续进展。
threadId 只能从候选列表的 threadId 中原样选取，绝对不可以编造或改写。
把握不足时必须返回 threadId 为空字符串、confidence 为 0，宁可不给结论也不要勉强匹配。
confidence 取 0 到 1，必须如实反映把握程度。reason 用一句简短中文说明依据。
status 为 RESOLVED 的事件串已被标记完结，除非日记明确是它的延续，否则不要选它。`, editingPromptVersion, threadMatchSchema),
		UserPrompt:  "请判断以下日记的归属：\n" + string(input),
		Temperature: 0.1,
	}
}
```

- [ ] **Step 5: 实现两个 Service 方法**

创建 `service/ai/thread.go`：

```go
package ai

import (
	"context"
	"encoding/json"
	"errors"
	"strings"

	"islelog-server/model"
)

// 取样参数：仅在正文总量超出上下文预算时启用。
const (
	sampleEarliestCount = 3
	sampleLatestCount   = 5
	sampleRuneLimit     = 800

	// 预算取 provider 上下文的 70%，留给 prompt 模板和输出
	contextBudgetRatio = 0.7
	// ContextLength 未配置时的保守回退值
	fallbackContextLength = 8192
)

// SampleThreadEntries 在正文总量超出上下文预算时退回取样。
//
// 默认全量不截断：本地模型上下文已达 20 万 token，全量是常态。取样只防一种
// 情况——某个事件串塞进几十篇超长正文导致上下文溢出，那条串会每晚失败且永远失败。
func SampleThreadEntries(entries []ThreadEntryText, contextLength int) []ThreadEntryText {
	if contextLength <= 0 {
		contextLength = fallbackContextLength
	}
	budget := int(float64(contextLength) * contextBudgetRatio)

	total := 0
	for _, entry := range entries {
		total += len([]rune(entry.Content))
	}
	if total <= budget {
		return entries
	}
	if len(entries) <= sampleEarliestCount+sampleLatestCount {
		return truncateEntries(entries)
	}

	sampled := make([]ThreadEntryText, 0, sampleEarliestCount+sampleLatestCount)
	sampled = append(sampled, entries[:sampleEarliestCount]...)
	sampled = append(sampled, entries[len(entries)-sampleLatestCount:]...)
	return truncateEntries(sampled)
}

func truncateEntries(entries []ThreadEntryText) []ThreadEntryText {
	result := make([]ThreadEntryText, 0, len(entries))
	for _, entry := range entries {
		runes := []rune(entry.Content)
		if len(runes) > sampleRuneLimit {
			entry.Content = string(runes[:sampleRuneLimit])
		}
		result = append(result, entry)
	}
	return result
}

// ThreadSummary 为事件串生成一句话简介。
func (s *Service) ThreadSummary(ctx context.Context, request ThreadSummaryRequest) (ThreadSummaryResult, error) {
	provider, err := s.providerForRequest(request.Provider, request.CloudConsent)
	if err != nil {
		return ThreadSummaryResult{}, err
	}
	request.Entries = SampleThreadEntries(request.Entries, request.ContextLength)

	var summary string
	usage, err := completeWithOneJSONRepair(
		ctx, provider, buildThreadSummaryCompletion(request), threadSummarySchema,
		func(content []byte) error {
			var candidate struct {
				Summary string `json:"summary"`
			}
			if err := json.Unmarshal(content, &candidate); err != nil {
				return err
			}
			trimmed := strings.TrimSpace(candidate.Summary)
			if trimmed == "" {
				return errors.New("简介为空")
			}
			summary = trimmed
			return nil
		},
	)
	if err != nil {
		return ThreadSummaryResult{}, err
	}
	return ThreadSummaryResult{Summary: summary, Usage: usage}, nil
}

// ThreadMatch 判断日记属于哪个候选事件串。
//
// 不信任模型返回值：编造的 id、越界的置信度、以及低于阈值的结果一律丢弃，
// 丢弃后等价于「无匹配」而非报错——模型没把握是正常情况，不该让批次失败。
func (s *Service) ThreadMatch(ctx context.Context, request ThreadMatchRequest) (ThreadMatchResult, error) {
	provider, err := s.providerForRequest(request.Provider, request.CloudConsent)
	if err != nil {
		return ThreadMatchResult{}, err
	}

	var decoded struct {
		ThreadID   string  `json:"threadId"`
		Confidence float64 `json:"confidence"`
		Reason     string  `json:"reason"`
	}
	usage, err := completeWithOneJSONRepair(
		ctx, provider, buildThreadMatchCompletion(request), threadMatchSchema,
		func(content []byte) error {
			return json.Unmarshal(content, &decoded)
		},
	)
	if err != nil {
		return ThreadMatchResult{}, err
	}

	name := strings.TrimSpace(decoded.ThreadID)
	if name == "" {
		return ThreadMatchResult{Usage: usage}, nil
	}
	if decoded.Confidence < 0 || decoded.Confidence > 1 {
		return ThreadMatchResult{Usage: usage}, nil
	}
	if decoded.Confidence < model.MinSuggestionConfidence {
		return ThreadMatchResult{Usage: usage}, nil
	}
	known := false
	for _, candidate := range request.Candidates {
		if candidate.Name == name {
			known = true
			break
		}
	}
	if !known {
		return ThreadMatchResult{Usage: usage}, nil
	}

	return ThreadMatchResult{
		ThreadName: name,
		Confidence: decoded.Confidence,
		Reason:     strings.TrimSpace(decoded.Reason),
		Usage:      usage,
	}, nil
}
```

- [ ] **Step 6: 运行测试确认通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./service/ai/ -v 2>&1 | tail -20
```

Expected: 全部 PASS

- [ ] **Step 7: 提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server
git add service/ai/
git commit -m "feat: 新增事件串简介生成与归属匹配的 AI 操作"
```

---

### Task 5: 夜间批处理与调度器

**Files:**
- Create: `service/thread_batch.go`
- Create: `service/thread_batch_test.go`

**Interfaces:**
- Consumes: Task 1 的列与 `app_settings` 表；Task 2 的 `model.ThreadSuggestion`、`model.MinSuggestionConfidence`；Task 4 的 `ai.ThreadSummary` / `ai.ThreadMatch` / `ai.ThreadCandidate` / `ai.ThreadEntryText`
- Produces:
  - `type ThreadAIRunner interface { ThreadSummary(...); ThreadMatch(...) }`
  - `func NewThreadBatchService(db *sql.DB, runner ThreadAIRunner, contextLength int) *ThreadBatchService`
  - `func (s *ThreadBatchService) RunOnce(ctx context.Context) error` —— 跑一遍完整批次
  - `func (s *ThreadBatchService) Start(ctx context.Context)` —— 启动 10 分钟 ticker
  - `func (s *ThreadBatchService) Status(userID int64) (BatchStatus, error)`
  - `func (s *ThreadBatchService) Pause(d time.Duration) error` —— 被抢占时退避
  - `BatchStatus{PendingMemos, DirtyThreads int; LastRunTs, PausedUntilTs int64; LastError string}`
  - `func (s *ThreadBatchService) ShouldRun(now time.Time) (bool, error)`

- [ ] **Step 1: 写失败的测试**

创建 `service/thread_batch_test.go`：

```go
package service

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"

	"islelog-server/db"
	"islelog-server/service/ai"
)

// fakeRunner 记录调用并返回预设结果，避免依赖真实模型。
type fakeRunner struct {
	summary      string
	matchName    string
	matchConf    float64
	summaryCalls int
	matchCalls   int
	err          error
}

func (r *fakeRunner) ThreadSummary(ctx context.Context, req ai.ThreadSummaryRequest) (ai.ThreadSummaryResult, error) {
	r.summaryCalls++
	if r.err != nil {
		return ai.ThreadSummaryResult{}, r.err
	}
	return ai.ThreadSummaryResult{Summary: r.summary}, nil
}

func (r *fakeRunner) ThreadMatch(ctx context.Context, req ai.ThreadMatchRequest) (ai.ThreadMatchResult, error) {
	r.matchCalls++
	if r.err != nil {
		return ai.ThreadMatchResult{}, r.err
	}
	return ai.ThreadMatchResult{ThreadName: r.matchName, Confidence: r.matchConf, Reason: "测试"}, nil
}

func newBatchTestDB(t *testing.T) *sql.DB {
	t.Helper()
	database, err := db.Open(filepath.Join(t.TempDir(), "test.db"), "")
	if err != nil {
		t.Fatalf("打开数据库失败：%v", err)
	}
	t.Cleanup(func() { _ = database.Close() })
	if _, err := database.Exec(
		`INSERT INTO users (id, name, display_name, email, password_hash, role, created_ts, updated_ts, extra, thread_ai_enabled)
		 VALUES (1, 'alice', 'alice', '', 'x', 'USER', 100, 100, '{}', 1)`); err != nil {
		t.Fatalf("插入用户失败：%v", err)
	}
	return database
}

func insertMemo(t *testing.T, database *sql.DB, id int64, content string, scanTs int64) {
	t.Helper()
	if _, err := database.Exec(
		`INSERT INTO memos (id, user_id, content, visibility, row_status, pinned, tags, type, title,
		                    display_ts, created_ts, updated_ts, extra, thread_scan_ts)
		 VALUES (?, 1, ?, 'PRIVATE', 'NORMAL', 0, '[]', 'MEMO', '', 100, 100, 100, '{}', ?)`,
		id, content, scanTs); err != nil {
		t.Fatalf("插入日记失败：%v", err)
	}
}

func insertThread(t *testing.T, database *sql.DB, id int64, title string, dirty, locked int) {
	t.Helper()
	if _, err := database.Exec(
		`INSERT INTO threads (id, user_id, title, summary, summary_source, status, created_ts, updated_ts,
		                      row_status, summary_dirty, summary_locked)
		 VALUES (?, 1, ?, '', 'AI', 'ACTIVE', 100, 100, 'NORMAL', ?, ?)`,
		id, title, dirty, locked); err != nil {
		t.Fatalf("插入事件串失败：%v", err)
	}
}

func TestRunOnceRegeneratesDirtySummary(t *testing.T) {
	database := newBatchTestDB(t)
	insertMemo(t, database, 10, "工位附近有蛐蛐在叫", 100)
	insertThread(t, database, 20, "工位蛐蛐", 1, 0)
	if _, err := database.Exec(
		`INSERT INTO thread_members (thread_id, memo_id, created_ts) VALUES (20, 10, 100)`); err != nil {
		t.Fatalf("插入成员失败：%v", err)
	}
	runner := &fakeRunner{summary: "找了两晚没找到"}
	svc := NewThreadBatchService(database, runner, 200000)

	if err := svc.RunOnce(context.Background()); err != nil {
		t.Fatalf("批次失败：%v", err)
	}

	var summary string
	var dirty int
	if err := database.QueryRow(
		`SELECT summary, summary_dirty FROM threads WHERE id=20`).Scan(&summary, &dirty); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if summary != "找了两晚没找到" {
		t.Fatalf("summary = %q", summary)
	}
	if dirty != 0 {
		t.Fatal("处理后应清除 summary_dirty")
	}
}

// 锁定的简介是用户的意志，AI 不得改写。
func TestRunOnceSkipsLockedSummary(t *testing.T) {
	database := newBatchTestDB(t)
	insertThread(t, database, 20, "工位蛐蛐", 1, 1)
	runner := &fakeRunner{summary: "AI 想写的"}
	svc := NewThreadBatchService(database, runner, 200000)

	if err := svc.RunOnce(context.Background()); err != nil {
		t.Fatalf("批次失败：%v", err)
	}

	if runner.summaryCalls != 0 {
		t.Fatalf("锁定的事件串不应调用模型，实际调用 %d 次", runner.summaryCalls)
	}
}

func TestRunOnceWritesSuggestionAndMarksScanned(t *testing.T) {
	database := newBatchTestDB(t)
	insertMemo(t, database, 10, "今晚又听到蛐蛐了", 0)
	insertThread(t, database, 20, "工位蛐蛐", 0, 0)
	runner := &fakeRunner{matchName: "threads/20", matchConf: 0.9}
	svc := NewThreadBatchService(database, runner, 200000)

	if err := svc.RunOnce(context.Background()); err != nil {
		t.Fatalf("批次失败：%v", err)
	}

	var count int
	if err := database.QueryRow(
		`SELECT COUNT(*) FROM thread_suggestions WHERE memo_id=10 AND thread_id=20 AND status='PENDING'`).
		Scan(&count); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if count != 1 {
		t.Fatalf("应写入 1 条待确认建议，实际 %d 条", count)
	}
	var scanTs int64
	if err := database.QueryRow(`SELECT thread_scan_ts FROM memos WHERE id=10`).Scan(&scanTs); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if scanTs == 0 {
		t.Fatal("分析成功后应写 thread_scan_ts")
	}
}

func TestRunOnceNoMatchStillMarksScanned(t *testing.T) {
	database := newBatchTestDB(t)
	insertMemo(t, database, 10, "随便写点什么", 0)
	insertThread(t, database, 20, "工位蛐蛐", 0, 0)
	runner := &fakeRunner{matchName: ""}
	svc := NewThreadBatchService(database, runner, 200000)

	if err := svc.RunOnce(context.Background()); err != nil {
		t.Fatalf("批次失败：%v", err)
	}

	var count int
	if err := database.QueryRow(`SELECT COUNT(*) FROM thread_suggestions`).Scan(&count); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if count != 0 {
		t.Fatalf("无匹配不应写建议，实际 %d 条", count)
	}
	var scanTs int64
	if err := database.QueryRow(`SELECT thread_scan_ts FROM memos WHERE id=10`).Scan(&scanTs); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if scanTs == 0 {
		t.Fatal("无匹配也算分析完成，应写 thread_scan_ts，否则每晚重跑")
	}
}

// 用户否掉过的建议不能重新冒出来——靠 (memo_id, thread_id) 唯一索引拦截。
func TestRunOnceDoesNotResurrectDismissedSuggestion(t *testing.T) {
	database := newBatchTestDB(t)
	insertMemo(t, database, 10, "今晚又听到蛐蛐了", 0)
	insertThread(t, database, 20, "工位蛐蛐", 0, 0)
	if _, err := database.Exec(
		`INSERT INTO thread_suggestions (id, user_id, memo_id, thread_id, confidence, reason, status, created_ts)
		 VALUES (1, 1, 10, 20, 0.9, '', 'DISMISSED', 100)`); err != nil {
		t.Fatalf("插入失败：%v", err)
	}
	runner := &fakeRunner{matchName: "threads/20", matchConf: 0.9}
	svc := NewThreadBatchService(database, runner, 200000)

	if err := svc.RunOnce(context.Background()); err != nil {
		t.Fatalf("批次失败：%v", err)
	}

	var status string
	if err := database.QueryRow(
		`SELECT status FROM thread_suggestions WHERE memo_id=10 AND thread_id=20`).Scan(&status); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if status != "DISMISSED" {
		t.Fatalf("已忽略的建议不应被复活，status = %s", status)
	}
}

func TestRunOnceSkipsDisabledUser(t *testing.T) {
	database := newBatchTestDB(t)
	if _, err := database.Exec(`UPDATE users SET thread_ai_enabled = 0 WHERE id = 1`); err != nil {
		t.Fatalf("关闭开关失败：%v", err)
	}
	insertMemo(t, database, 10, "今晚又听到蛐蛐了", 0)
	insertThread(t, database, 20, "工位蛐蛐", 1, 0)
	runner := &fakeRunner{matchName: "threads/20", matchConf: 0.9, summary: "x"}
	svc := NewThreadBatchService(database, runner, 200000)

	if err := svc.RunOnce(context.Background()); err != nil {
		t.Fatalf("批次失败：%v", err)
	}

	if runner.matchCalls != 0 || runner.summaryCalls != 0 {
		t.Fatalf("关闭开关的用户不应消耗模型，match=%d summary=%d", runner.matchCalls, runner.summaryCalls)
	}
}

// 软删的日记不参与分析。
func TestRunOnceSkipsDeletedMemo(t *testing.T) {
	database := newBatchTestDB(t)
	insertMemo(t, database, 10, "已删除", 0)
	if _, err := database.Exec(`UPDATE memos SET row_status='DELETED' WHERE id=10`); err != nil {
		t.Fatalf("软删失败：%v", err)
	}
	insertThread(t, database, 20, "工位蛐蛐", 0, 0)
	runner := &fakeRunner{}
	svc := NewThreadBatchService(database, runner, 200000)

	if err := svc.RunOnce(context.Background()); err != nil {
		t.Fatalf("批次失败：%v", err)
	}

	if runner.matchCalls != 0 {
		t.Fatalf("软删日记不应分析，实际调用 %d 次", runner.matchCalls)
	}
}

func TestShouldRunOnlyAfterFourAMAndOncePerDay(t *testing.T) {
	database := newBatchTestDB(t)
	svc := NewThreadBatchService(database, &fakeRunner{}, 200000)

	beforeFour := time.Date(2026, 8, 24, 3, 30, 0, 0, time.Local)
	afterFour := time.Date(2026, 8, 24, 4, 30, 0, 0, time.Local)

	if run, err := svc.ShouldRun(beforeFour); err != nil || run {
		t.Fatalf("4 点前不应运行，run=%v err=%v", run, err)
	}
	if run, err := svc.ShouldRun(afterFour); err != nil || !run {
		t.Fatalf("4 点后且今天未跑过应运行，run=%v err=%v", run, err)
	}

	if err := svc.markRun(afterFour); err != nil {
		t.Fatalf("记录运行失败：%v", err)
	}
	if run, err := svc.ShouldRun(afterFour.Add(time.Hour)); err != nil || run {
		t.Fatalf("同一天不应重复运行，run=%v err=%v", run, err)
	}

	// 次日 4 点后应再次运行
	if run, err := svc.ShouldRun(afterFour.Add(24 * time.Hour)); err != nil || !run {
		t.Fatalf("次日应重新运行，run=%v err=%v", run, err)
	}
}

// 被抢占后退避，否则用户夜间使用时批次会陷入「被 cancel → 立刻重试」的循环。
func TestShouldRunRespectsPause(t *testing.T) {
	database := newBatchTestDB(t)
	svc := NewThreadBatchService(database, &fakeRunner{}, 200000)
	now := time.Date(2026, 8, 24, 4, 30, 0, 0, time.Local)

	if err := svc.Pause(15 * time.Minute); err != nil {
		t.Fatalf("设置退避失败：%v", err)
	}

	if run, _ := svc.ShouldRun(now); run {
		t.Fatal("退避期内不应运行")
	}
	if run, _ := svc.ShouldRun(time.Now().Add(20 * time.Minute)); !run {
		t.Fatal("退避期结束后应恢复运行")
	}
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./service/ -run "TestRunOnce|TestShouldRun" -v
```

Expected: 编译失败，`undefined: NewThreadBatchService`

- [ ] **Step 3: 实现批处理服务**

创建 `service/thread_batch.go`：

```go
package service

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	"islelog-server/model"
	"islelog-server/service/ai"
	"islelog-server/util"
)

const (
	// 夜间批次时刻（服务器本地时区）
	batchHour = 4
	// 调度检查间隔。用 ticker + 追赶判断而非 cron：服务在 4 点恰好重启、
	// 或宕了两小时，醒来后照样补上当天批次；cron 会直接错过。
	batchTickInterval = 10 * time.Minute
	// 单次批次的匹配上限，纯保险丝
	maxMemosPerBatch = 200
	// 候选事件串上限，防止事件串极多时撑爆输入
	maxThreadCandidates = 150

	settingLastRunTs     = "thread_ai_last_run_ts"
	settingPausedUntilTs = "thread_ai_paused_until_ts"
	settingLastError     = "thread_ai_last_error"
)

// ThreadAIRunner 是批处理依赖的 AI 能力，便于测试打桩。
type ThreadAIRunner interface {
	ThreadSummary(context.Context, ai.ThreadSummaryRequest) (ai.ThreadSummaryResult, error)
	ThreadMatch(context.Context, ai.ThreadMatchRequest) (ai.ThreadMatchResult, error)
}

// BatchStatus 是暴露给客户端的调度状态。
type BatchStatus struct {
	PendingMemos  int
	DirtyThreads  int
	LastRunTs     int64
	PausedUntilTs int64
	LastError     string
}

// ThreadBatchService 每晚一次地重算事件串简介并产出归属建议。
type ThreadBatchService struct {
	db            *sql.DB
	runner        ThreadAIRunner
	contextLength int
}

func NewThreadBatchService(database *sql.DB, runner ThreadAIRunner, contextLength int) *ThreadBatchService {
	return &ThreadBatchService{db: database, runner: runner, contextLength: contextLength}
}

// Start 启动调度循环，随传入 context 结束而退出。
func (s *ThreadBatchService) Start(ctx context.Context) {
	ticker := time.NewTicker(batchTickInterval)
	go func() {
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				run, err := s.ShouldRun(time.Now())
				if err != nil {
					log.Printf("thread batch schedule check error: %v", err)
					continue
				}
				if !run {
					continue
				}
				if err := s.RunOnce(ctx); err != nil {
					log.Printf("thread batch run error: %v", err)
					_ = s.putSetting(settingLastError, err.Error())
					continue
				}
				_ = s.putSetting(settingLastError, "")
				if err := s.markRun(time.Now()); err != nil {
					log.Printf("thread batch mark run error: %v", err)
				}
			}
		}
	}()
}

// ShouldRun 判断此刻是否该跑批次：已过今天 4 点、今天还没跑过、且不在退避期内。
func (s *ThreadBatchService) ShouldRun(now time.Time) (bool, error) {
	pausedUntil, err := s.getSettingInt(settingPausedUntilTs)
	if err != nil {
		return false, err
	}
	if now.Unix() < pausedUntil {
		return false, nil
	}
	todayAtFour := time.Date(now.Year(), now.Month(), now.Day(), batchHour, 0, 0, 0, now.Location())
	if now.Before(todayAtFour) {
		return false, nil
	}
	lastRun, err := s.getSettingInt(settingLastRunTs)
	if err != nil {
		return false, err
	}
	return lastRun < todayAtFour.Unix(), nil
}

// Pause 设置退避截止时间，供前台抢占后调用。
func (s *ThreadBatchService) Pause(d time.Duration) error {
	return s.putSetting(settingPausedUntilTs, strconv.FormatInt(time.Now().Add(d).Unix(), 10))
}

func (s *ThreadBatchService) markRun(now time.Time) error {
	return s.putSetting(settingLastRunTs, strconv.FormatInt(now.Unix(), 10))
}

// RunOnce 跑一遍完整批次：先重算简介，后归属匹配。
//
// 顺序不能反——匹配的输入正是各事件串的简介，简介没更新就是拿旧的去匹配。
func (s *ThreadBatchService) RunOnce(ctx context.Context) error {
	userIDs, err := s.enabledUserIDs()
	if err != nil {
		return err
	}
	for _, userID := range userIDs {
		if err := s.refreshSummaries(ctx, userID); err != nil {
			return err
		}
		if err := s.matchMemos(ctx, userID); err != nil {
			return err
		}
	}
	return nil
}

func (s *ThreadBatchService) enabledUserIDs() ([]int64, error) {
	rows, err := s.db.Query(`SELECT id FROM users WHERE thread_ai_enabled = 1`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (s *ThreadBatchService) refreshSummaries(ctx context.Context, userID int64) error {
	rows, err := s.db.Query(
		`SELECT id, title FROM threads
		 WHERE user_id=? AND row_status='NORMAL' AND summary_dirty=1 AND summary_locked=0`, userID)
	if err != nil {
		return err
	}
	type target struct {
		id    int64
		title string
	}
	var targets []target
	for rows.Next() {
		var item target
		if err := rows.Scan(&item.id, &item.title); err != nil {
			rows.Close()
			return err
		}
		targets = append(targets, item)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	for _, item := range targets {
		entries, err := s.threadEntries(item.id)
		if err != nil {
			return err
		}
		if len(entries) == 0 {
			// 空事件串没什么可总结的，清除脏标记即可
			if _, err := s.db.Exec(`UPDATE threads SET summary_dirty=0 WHERE id=?`, item.id); err != nil {
				return err
			}
			continue
		}
		result, err := s.runner.ThreadSummary(ctx, ai.ThreadSummaryRequest{
			Title:         item.title,
			Entries:       entries,
			ContextLength: s.contextLength,
			Provider:      ai.ProviderLocal, // 后台任务硬编码 LOCAL，绝不上云
		})
		if err != nil {
			return err
		}
		now := time.Now().Unix()
		// bump updated_ts，否则客户端永远拉不到新简介
		if _, err := s.db.Exec(
			`UPDATE threads SET summary=?, summary_source='AI', summary_dirty=0, updated_ts=? WHERE id=?`,
			result.Summary, now, item.id); err != nil {
			return err
		}
		if err := s.writeChangeLog(userID, item.id, "thread", "UPDATE"); err != nil {
			return err
		}
	}
	return nil
}

func (s *ThreadBatchService) threadEntries(threadID int64) ([]ai.ThreadEntryText, error) {
	rows, err := s.db.Query(
		`SELECT m.content FROM thread_members tm
		 JOIN memos m ON m.id = tm.memo_id AND m.row_status='NORMAL'
		 WHERE tm.thread_id = ? ORDER BY m.display_ts ASC`, threadID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var entries []ai.ThreadEntryText
	for rows.Next() {
		var content string
		if err := rows.Scan(&content); err != nil {
			return nil, err
		}
		entries = append(entries, ai.ThreadEntryText{Content: content})
	}
	return entries, rows.Err()
}

func (s *ThreadBatchService) matchMemos(ctx context.Context, userID int64) error {
	candidates, err := s.threadCandidates(userID)
	if err != nil {
		return err
	}
	if len(candidates) == 0 {
		return nil // 没有事件串就无从匹配，也不必标记已扫描
	}

	rows, err := s.db.Query(
		`SELECT id, content FROM memos
		 WHERE user_id=? AND row_status='NORMAL' AND type='MEMO' AND thread_scan_ts=0
		 ORDER BY updated_ts ASC LIMIT ?`, userID, maxMemosPerBatch)
	if err != nil {
		return err
	}
	type target struct {
		id      int64
		content string
	}
	var targets []target
	for rows.Next() {
		var item target
		if err := rows.Scan(&item.id, &item.content); err != nil {
			rows.Close()
			return err
		}
		targets = append(targets, item)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	for _, item := range targets {
		result, err := s.runner.ThreadMatch(ctx, ai.ThreadMatchRequest{
			Content:    item.content,
			Candidates: candidates,
			Provider:   ai.ProviderLocal,
		})
		if err != nil {
			return err
		}
		if result.ThreadName != "" && result.Confidence >= model.MinSuggestionConfidence {
			threadID, parseErr := strconv.ParseInt(strings.TrimPrefix(result.ThreadName, "threads/"), 10, 64)
			if parseErr == nil {
				// INSERT OR IGNORE：唯一索引挡住已被否掉的同一 (memo, thread) 对
				if _, err := s.db.Exec(
					`INSERT OR IGNORE INTO thread_suggestions
					 (id, user_id, memo_id, thread_id, confidence, reason, status, created_ts)
					 VALUES (?, ?, ?, ?, ?, ?, 'PENDING', ?)`,
					newSuggestionID(), userID, item.id, threadID,
					result.Confidence, result.Reason, time.Now().Unix()); err != nil {
					return err
				}
			}
		}
		// 无匹配也算分析完成，否则每晚都会重跑同一篇
		if _, err := s.db.Exec(
			`UPDATE memos SET thread_scan_ts=? WHERE id=?`, time.Now().Unix(), item.id); err != nil {
			return err
		}
	}
	return nil
}

func (s *ThreadBatchService) threadCandidates(userID int64) ([]ai.ThreadCandidate, error) {
	rows, err := s.db.Query(
		`SELECT id, title, summary, status FROM threads
		 WHERE user_id=? AND row_status='NORMAL'
		 ORDER BY updated_ts DESC LIMIT ?`, userID, maxThreadCandidates)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var candidates []ai.ThreadCandidate
	for rows.Next() {
		var id int64
		var candidate ai.ThreadCandidate
		if err := rows.Scan(&id, &candidate.Title, &candidate.Summary, &candidate.Status); err != nil {
			return nil, err
		}
		candidate.Name = "threads/" + model.FormatID(id)
		snippet, err := s.latestSnippet(id)
		if err != nil {
			return nil, err
		}
		candidate.LatestSnippet = snippet
		candidates = append(candidates, candidate)
	}
	return candidates, rows.Err()
}

// latestSnippet 取事件串最新一篇日记的首句。
//
// 只给简介时，模型面对「还是没找到」这类没有关键词的短日记容易在多个事件串
// 之间摇摆；看到最新进展就能判定。
func (s *ThreadBatchService) latestSnippet(threadID int64) (string, error) {
	var content string
	err := s.db.QueryRow(
		`SELECT m.content FROM thread_members tm
		 JOIN memos m ON m.id = tm.memo_id AND m.row_status='NORMAL'
		 WHERE tm.thread_id = ? ORDER BY m.display_ts DESC LIMIT 1`, threadID).Scan(&content)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return model.Snippet(content), nil
}

// Status 返回队列与调度状态。
func (s *ThreadBatchService) Status(userID int64) (BatchStatus, error) {
	var status BatchStatus
	if err := s.db.QueryRow(
		`SELECT COUNT(*) FROM memos
		 WHERE user_id=? AND row_status='NORMAL' AND type='MEMO' AND thread_scan_ts=0`,
		userID).Scan(&status.PendingMemos); err != nil {
		return status, err
	}
	if err := s.db.QueryRow(
		`SELECT COUNT(*) FROM threads
		 WHERE user_id=? AND row_status='NORMAL' AND summary_dirty=1 AND summary_locked=0`,
		userID).Scan(&status.DirtyThreads); err != nil {
		return status, err
	}
	var err error
	if status.LastRunTs, err = s.getSettingInt(settingLastRunTs); err != nil {
		return status, err
	}
	if status.PausedUntilTs, err = s.getSettingInt(settingPausedUntilTs); err != nil {
		return status, err
	}
	if status.LastError, err = s.getSetting(settingLastError); err != nil {
		return status, err
	}
	return status, nil
}

func (s *ThreadBatchService) getSetting(key string) (string, error) {
	var value string
	err := s.db.QueryRow(`SELECT value FROM app_settings WHERE key=?`, key).Scan(&value)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return value, err
}

func (s *ThreadBatchService) getSettingInt(key string) (int64, error) {
	value, err := s.getSetting(key)
	if err != nil || value == "" {
		return 0, err
	}
	parsed, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		return 0, nil // 脏数据当作 0，不阻断调度
	}
	return parsed, nil
}

func (s *ThreadBatchService) putSetting(key, value string) error {
	_, err := s.db.Exec(
		`INSERT INTO app_settings (key, value) VALUES (?, ?)
		 ON CONFLICT(key) DO UPDATE SET value = excluded.value`, key, value)
	return err
}

func (s *ThreadBatchService) writeChangeLog(userID, entityID int64, entity, action string) error {
	_, err := s.db.Exec(
		`INSERT INTO change_log (user_id, entity, entity_id, action, created_ts) VALUES (?, ?, ?, ?, ?)`,
		userID, entity, entityID, action, time.Now().Unix())
	if err != nil {
		return fmt.Errorf("write change log: %w", err)
	}
	return nil
}
```

在同文件末尾加入 ID 生成辅助：

```go
func newSuggestionID() int64 { return util.NewID() }
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./service/ -v 2>&1 | tail -25
```

Expected: 全部 PASS

- [ ] **Step 5: 提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server
git add service/thread_batch.go service/thread_batch_test.go
git commit -m "feat: 事件串夜间批处理与调度器"
```

---

### Task 6: 建议接口

**Files:**
- Create: `handler/thread_suggestion.go`
- Create: `handler/thread_suggestion_test.go`

**Interfaces:**
- Consumes: Task 2 的 `model.ThreadSuggestion`；`handler/testutil_test.go` 夹具；`handler/thread.go` 中的 `threadError`
- Produces:
  - `func NewThreadSuggestionHandler(db *sql.DB) *ThreadSuggestionHandler`
  - `func (h *ThreadSuggestionHandler) ListSuggestions(c echo.Context) error`
  - `func (h *ThreadSuggestionHandler) UpdateSuggestion(c echo.Context) error`

- [ ] **Step 1: 写失败的测试**

创建 `handler/thread_suggestion_test.go`：

```go
package handler

import (
	"net/http"
	"testing"
)

func seedSuggestion(t *testing.T, h *ThreadSuggestionHandler, userID, id, memoID, threadID int64, status string) {
	t.Helper()
	if _, err := h.db.Exec(
		`INSERT INTO thread_suggestions (id, user_id, memo_id, thread_id, confidence, reason, status, created_ts)
		 VALUES (?, ?, ?, ?, 0.9, '同样在讲蛐蛐', ?, 100)`,
		id, userID, memoID, threadID, status); err != nil {
		t.Fatalf("插入建议失败：%v", err)
	}
}

func seedThreadRow(t *testing.T, h *ThreadSuggestionHandler, userID, id int64, title, rowStatus string) {
	t.Helper()
	if _, err := h.db.Exec(
		`INSERT INTO threads (id, user_id, title, summary, summary_source, status, created_ts, updated_ts,
		                      row_status, summary_dirty, summary_locked)
		 VALUES (?, ?, ?, '', 'AI', 'ACTIVE', 100, 100, ?, 0, 0)`,
		id, userID, title, rowStatus); err != nil {
		t.Fatalf("插入事件串失败：%v", err)
	}
}

func TestListSuggestionsReturnsPendingWithContext(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadSuggestionHandler(database)
	memoID := newTestMemo(t, database, u, "今晚又听到蛐蛐了", 1755000000)
	seedThreadRow(t, h, u.ID, 20, "工位蛐蛐", "NORMAL")
	seedSuggestion(t, h, u.ID, 1, memoID, 20, "PENDING")

	c, rec := newTestContext(t, http.MethodGet, "/api/v1/thread-suggestions", "", u)
	if err := h.ListSuggestions(c); err != nil {
		t.Fatalf("查询失败：%v", err)
	}

	list := decodeJSON(t, rec.Body.Bytes())["suggestions"].([]interface{})
	if len(list) != 1 {
		t.Fatalf("应返回 1 条，实际 %d 条", len(list))
	}
	item := list[0].(map[string]interface{})
	if item["threadTitle"] != "工位蛐蛐" {
		t.Fatalf("threadTitle = %v，应 JOIN 出事件串标题供客户端直接展示", item["threadTitle"])
	}
	if item["memoSnippet"] != "今晚又听到蛐蛐了" {
		t.Fatalf("memoSnippet = %v", item["memoSnippet"])
	}
}

func TestListSuggestionsExcludesOtherStatuses(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadSuggestionHandler(database)
	memoID := newTestMemo(t, database, u, "日记", 1755000000)
	seedThreadRow(t, h, u.ID, 20, "工位蛐蛐", "NORMAL")
	seedSuggestion(t, h, u.ID, 1, memoID, 20, "DISMISSED")

	c, rec := newTestContext(t, http.MethodGet, "/api/v1/thread-suggestions", "", u)
	if err := h.ListSuggestions(c); err != nil {
		t.Fatalf("查询失败：%v", err)
	}

	if list := decodeJSON(t, rec.Body.Bytes())["suggestions"].([]interface{}); len(list) != 0 {
		t.Fatalf("默认只返回 PENDING，实际 %d 条", len(list))
	}
}

// memo 与 thread 都是软删除，ON DELETE CASCADE 不会触发，必须显式过滤。
func TestListSuggestionsFiltersSoftDeletedMemoAndThread(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadSuggestionHandler(database)
	deletedMemo := newTestMemo(t, database, u, "将被删除", 1755000000)
	aliveMemo := newTestMemo(t, database, u, "还在", 1755100000)
	seedThreadRow(t, h, u.ID, 20, "正常事件串", "NORMAL")
	seedThreadRow(t, h, u.ID, 21, "已删事件串", "DELETED")
	seedSuggestion(t, h, u.ID, 1, deletedMemo, 20, "PENDING")
	seedSuggestion(t, h, u.ID, 2, aliveMemo, 21, "PENDING")
	if _, err := database.Exec(`UPDATE memos SET row_status='DELETED' WHERE id=?`, deletedMemo); err != nil {
		t.Fatalf("软删失败：%v", err)
	}

	c, rec := newTestContext(t, http.MethodGet, "/api/v1/thread-suggestions", "", u)
	if err := h.ListSuggestions(c); err != nil {
		t.Fatalf("查询失败：%v", err)
	}

	if list := decodeJSON(t, rec.Body.Bytes())["suggestions"].([]interface{}); len(list) != 0 {
		t.Fatalf("软删的 memo/thread 对应的建议不应返回，实际 %d 条", len(list))
	}
}

func TestListSuggestionsRejectsOtherUsersData(t *testing.T) {
	database := newTestDB(t)
	owner := newTestUser(t, database, "alice")
	intruder := newTestUser(t, database, "bob")
	h := NewThreadSuggestionHandler(database)
	memoID := newTestMemo(t, database, owner, "日记", 1755000000)
	seedThreadRow(t, h, owner.ID, 20, "工位蛐蛐", "NORMAL")
	seedSuggestion(t, h, owner.ID, 1, memoID, 20, "PENDING")

	c, rec := newTestContext(t, http.MethodGet, "/api/v1/thread-suggestions", "", intruder)
	if err := h.ListSuggestions(c); err != nil {
		t.Fatalf("查询失败：%v", err)
	}

	if list := decodeJSON(t, rec.Body.Bytes())["suggestions"].([]interface{}); len(list) != 0 {
		t.Fatalf("不应返回他人的建议，实际 %d 条", len(list))
	}
}

func TestUpdateSuggestionChangesStatus(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadSuggestionHandler(database)
	memoID := newTestMemo(t, database, u, "日记", 1755000000)
	seedThreadRow(t, h, u.ID, 20, "工位蛐蛐", "NORMAL")
	seedSuggestion(t, h, u.ID, 1, memoID, 20, "PENDING")

	c, rec := newTestContext(t, http.MethodPatch, "/api/v1/thread-suggestions/1",
		`{"status":"ACCEPTED"}`, u)
	c.SetParamNames("suggestion")
	c.SetParamValues("1")
	if err := h.UpdateSuggestion(c); err != nil {
		t.Fatalf("更新失败：%v", err)
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("状态码 = %d；响应：%s", rec.Code, rec.Body.String())
	}

	var status string
	if err := database.QueryRow(`SELECT status FROM thread_suggestions WHERE id=1`).Scan(&status); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if status != "ACCEPTED" {
		t.Fatalf("status = %s", status)
	}
}

// AI 永不写 thread_members：接受建议只记录状态，成员写入走客户端推送链路，
// 否则服务端与客户端两个写入方会互相覆盖。
func TestAcceptSuggestionDoesNotWriteThreadMembers(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadSuggestionHandler(database)
	memoID := newTestMemo(t, database, u, "日记", 1755000000)
	seedThreadRow(t, h, u.ID, 20, "工位蛐蛐", "NORMAL")
	seedSuggestion(t, h, u.ID, 1, memoID, 20, "PENDING")

	c, _ := newTestContext(t, http.MethodPatch, "/api/v1/thread-suggestions/1", `{"status":"ACCEPTED"}`, u)
	c.SetParamNames("suggestion")
	c.SetParamValues("1")
	if err := h.UpdateSuggestion(c); err != nil {
		t.Fatalf("更新失败：%v", err)
	}

	var count int
	if err := database.QueryRow(`SELECT COUNT(*) FROM thread_members`).Scan(&count); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if count != 0 {
		t.Fatal("服务端不得代写 thread_members")
	}
}

func TestUpdateSuggestionRejectsInvalidStatus(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadSuggestionHandler(database)
	memoID := newTestMemo(t, database, u, "日记", 1755000000)
	seedThreadRow(t, h, u.ID, 20, "工位蛐蛐", "NORMAL")
	seedSuggestion(t, h, u.ID, 1, memoID, 20, "PENDING")

	c, rec := newTestContext(t, http.MethodPatch, "/api/v1/thread-suggestions/1", `{"status":"MAYBE"}`, u)
	c.SetParamNames("suggestion")
	c.SetParamValues("1")
	if err := h.UpdateSuggestion(c); err != nil {
		t.Fatalf("处理失败：%v", err)
	}
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("状态码 = %d，期望 400", rec.Code)
	}
}

func TestUpdateSuggestionRejectsOtherUsersSuggestion(t *testing.T) {
	database := newTestDB(t)
	owner := newTestUser(t, database, "alice")
	intruder := newTestUser(t, database, "bob")
	h := NewThreadSuggestionHandler(database)
	memoID := newTestMemo(t, database, owner, "日记", 1755000000)
	seedThreadRow(t, h, owner.ID, 20, "工位蛐蛐", "NORMAL")
	seedSuggestion(t, h, owner.ID, 1, memoID, 20, "PENDING")

	c, rec := newTestContext(t, http.MethodPatch, "/api/v1/thread-suggestions/1", `{"status":"ACCEPTED"}`, intruder)
	c.SetParamNames("suggestion")
	c.SetParamValues("1")
	if err := h.UpdateSuggestion(c); err != nil {
		t.Fatalf("处理失败：%v", err)
	}
	if rec.Code != http.StatusForbidden {
		t.Fatalf("状态码 = %d，期望 403", rec.Code)
	}
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./handler/ -run "TestListSuggestions|TestUpdateSuggestion|TestAcceptSuggestion" -v
```

Expected: 编译失败，`undefined: NewThreadSuggestionHandler`

- [ ] **Step 3: 实现**

创建 `handler/thread_suggestion.go`：

```go
package handler

import (
	"database/sql"
	"net/http"
	"strconv"

	"islelog-server/middleware"
	"islelog-server/model"

	"github.com/labstack/echo/v4"
)

// ThreadSuggestionHandler 提供 AI 归属建议的读取与状态变更。
type ThreadSuggestionHandler struct{ db *sql.DB }

func NewThreadSuggestionHandler(database *sql.DB) *ThreadSuggestionHandler {
	return &ThreadSuggestionHandler{db: database}
}

// ListSuggestions 返回当前用户的建议，默认只返回待确认的。
//
// memo 与 thread 都是软删除，ON DELETE CASCADE 不会触发，因此必须显式过滤
// row_status，否则删掉一篇日记后它的建议还会挂在横幅里。
func (h *ThreadSuggestionHandler) ListSuggestions(c echo.Context) error {
	u := middleware.GetCurrentUser(c)
	status := c.QueryParam("status")
	if status == "" {
		status = model.SuggestionPending
	}

	rows, err := h.db.Query(
		`SELECT s.id, s.user_id, s.memo_id, s.thread_id, s.confidence, s.reason, s.status, s.created_ts,
		        m.content, t.title
		 FROM thread_suggestions s
		 JOIN memos   m ON m.id = s.memo_id   AND m.row_status = 'NORMAL'
		 JOIN threads t ON t.id = s.thread_id AND t.row_status = 'NORMAL'
		 WHERE s.user_id = ? AND s.status = ?
		 ORDER BY s.confidence DESC, s.created_ts DESC`, u.ID, status)
	if err != nil {
		return threadError(c, http.StatusInternalServerError, "查询失败")
	}
	defer rows.Close()

	suggestions := []map[string]interface{}{}
	for rows.Next() {
		s := &model.ThreadSuggestion{}
		var content, title string
		if err := rows.Scan(&s.ID, &s.UserID, &s.MemoID, &s.ThreadID, &s.Confidence,
			&s.Reason, &s.Status, &s.CreatedTs, &content, &title); err != nil {
			return threadError(c, http.StatusInternalServerError, "查询失败")
		}
		suggestions = append(suggestions, s.ToJSON(model.Snippet(content), title))
	}
	if err := rows.Err(); err != nil {
		return threadError(c, http.StatusInternalServerError, "查询失败")
	}

	return c.JSON(http.StatusOK, map[string]interface{}{"suggestions": suggestions})
}

// UpdateSuggestion 修改建议状态。
//
// 收到 ACCEPTED 时**只记录状态**，不写 thread_members —— 成员写入完全走
// 客户端既有的事件串推送链路，避免服务端与客户端两个写入方互相覆盖。
func (h *ThreadSuggestionHandler) UpdateSuggestion(c echo.Context) error {
	u := middleware.GetCurrentUser(c)
	id, err := strconv.ParseInt(c.Param("suggestion"), 10, 64)
	if err != nil {
		return threadError(c, http.StatusBadRequest, "无效ID")
	}

	var ownerID int64
	err = h.db.QueryRow(`SELECT user_id FROM thread_suggestions WHERE id=?`, id).Scan(&ownerID)
	if err == sql.ErrNoRows {
		return threadError(c, http.StatusNotFound, "未找到")
	}
	if err != nil {
		return threadError(c, http.StatusInternalServerError, "查询失败")
	}
	if ownerID != u.ID {
		return threadError(c, http.StatusForbidden, "无权修改")
	}

	var req struct {
		Status string `json:"status"`
	}
	if err := c.Bind(&req); err != nil {
		return threadError(c, http.StatusBadRequest, "请求格式错误")
	}
	if req.Status != model.SuggestionAccepted && req.Status != model.SuggestionDismissed {
		return threadError(c, http.StatusBadRequest, "status 只能为 ACCEPTED 或 DISMISSED")
	}

	if _, err := h.db.Exec(
		`UPDATE thread_suggestions SET status=? WHERE id=?`, req.Status, id); err != nil {
		return threadError(c, http.StatusInternalServerError, "更新失败")
	}

	return c.JSON(http.StatusOK, map[string]interface{}{})
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./handler/ -v 2>&1 | tail -15
```

Expected: 全部 PASS

- [ ] **Step 5: 提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server
git add handler/thread_suggestion.go handler/thread_suggestion_test.go
git commit -m "feat: 事件串建议读取与状态变更接口"
```

---

### Task 7: 前台抢占与退避

**Files:**
- Modify: `handler/ai.go`
- Modify: `handler/ai_test.go`（追加测试）

**Interfaces:**
- Consumes: 既有 `localGate` / `tryAcquireProvider`
- Produces:
  - `func (h *AIHandler) RegisterBackground(cancel context.CancelFunc) func()` —— 后台任务开始时登记，返回注销函数
  - `func (h *AIHandler) preemptBackground()` —— 前台请求调用，cancel 后台并等待闸门释放
  - `func (h *AIHandler) SetPauser(p BatchPauser)`，`type BatchPauser interface { Pause(time.Duration) error }`

- [ ] **Step 1: 写失败的测试**

在 `handler/ai_test.go` 末尾追加：

```go
func TestPreemptBackgroundCancelsRegisteredTask(t *testing.T) {
	handler := NewAIHandler(nil)
	ctx, cancel := context.WithCancel(context.Background())
	unregister := handler.RegisterBackground(cancel)
	defer unregister()

	handler.preemptBackground()

	select {
	case <-ctx.Done():
	case <-time.After(time.Second):
		t.Fatal("后台任务的 context 应被取消")
	}
}

// 被抢占后必须退避，否则用户夜间使用时批次会陷入
// 「被 cancel → 立刻重试 → 又被 cancel」的循环。
func TestPreemptBackgroundPausesBatch(t *testing.T) {
	handler := NewAIHandler(nil)
	pauser := &fakePauser{}
	handler.SetPauser(pauser)
	_, cancel := context.WithCancel(context.Background())
	unregister := handler.RegisterBackground(cancel)
	defer unregister()

	handler.preemptBackground()

	if pauser.paused != preemptBackoff {
		t.Fatalf("退避时长 = %v，期望 %v", pauser.paused, preemptBackoff)
	}
}

func TestPreemptBackgroundIsNoopWhenIdle(t *testing.T) {
	handler := NewAIHandler(nil)
	pauser := &fakePauser{}
	handler.SetPauser(pauser)

	handler.preemptBackground() // 后台空闲

	if pauser.paused != 0 {
		t.Fatal("后台空闲时不应触发退避")
	}
}

type fakePauser struct{ paused time.Duration }

func (p *fakePauser) Pause(d time.Duration) error {
	p.paused = d
	return nil
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./handler/ -run TestPreemptBackground -v
```

Expected: 编译失败，`handler.RegisterBackground undefined`

- [ ] **Step 3: 实现**

在 `handler/ai.go` 的常量区追加：

```go
	// 被前台抢占后批次退避的时长
	preemptBackoff = 15 * time.Minute
	// 抢占后等待后台释放闸门的上限
	preemptWait = 3 * time.Second
)
```

在 `AIHandler` 结构体中追加字段：

```go
	// 夜间批次严格串行、localGate 容量为 1，因此同一时刻只有一个后台调用，
	// 「注册表」退化成单个 cancel 槽即可
	bgMu     sync.Mutex
	bgCancel context.CancelFunc
	pauser   BatchPauser
```

在文件中追加：

```go
// BatchPauser 让抢占方通知批处理退避。
type BatchPauser interface {
	Pause(time.Duration) error
}

// SetPauser 注入批处理服务，供抢占后设置退避。
func (h *AIHandler) SetPauser(p BatchPauser) {
	h.bgMu.Lock()
	defer h.bgMu.Unlock()
	h.pauser = p
}

// RegisterBackground 登记正在运行的后台任务，返回注销函数。
func (h *AIHandler) RegisterBackground(cancel context.CancelFunc) func() {
	h.bgMu.Lock()
	h.bgCancel = cancel
	h.bgMu.Unlock()
	return func() {
		h.bgMu.Lock()
		h.bgCancel = nil
		h.bgMu.Unlock()
	}
}

// preemptBackground 中止后台任务并让批次退避，供前台请求在抢闸门前调用。
//
// 后台进度全在 thread_scan_ts / summary_dirty 上，被中止的项不写回，
// 退避结束后从断点续跑，因此中止是安全的。
func (h *AIHandler) preemptBackground() {
	h.bgMu.Lock()
	cancel := h.bgCancel
	pauser := h.pauser
	h.bgMu.Unlock()
	if cancel == nil {
		return
	}
	cancel()
	if pauser != nil {
		if err := pauser.Pause(preemptBackoff); err != nil {
			log.Printf("pause thread batch error: %v", err)
		}
	}
	// 等待后台释放闸门；超时则照旧走 429 分支
	deadline := time.Now().Add(preemptWait)
	for time.Now().Before(deadline) {
		if len(h.localGate) == 0 {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
}
```

在 `tryAcquireProvider` 的开头插入：

```go
	if provider == ai.ProviderLocal {
		h.preemptBackground()
	}
```

`handler/ai.go` 需新增 import `"log"`。

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./handler/ -v 2>&1 | tail -10
```

Expected: 全部 PASS（既有的 429 与取消相关测试也应继续通过）

- [ ] **Step 5: 提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server
git add handler/ai.go handler/ai_test.go
git commit -m "feat: 前台 AI 请求抢占后台批次并触发退避"
```

---

### Task 8: 状态 / 开关 / 立即执行接口与接线

**Files:**
- Create: `handler/thread_ai.go`
- Create: `handler/thread_ai_test.go`
- Modify: `main.go`

**Interfaces:**
- Consumes: Task 5 的 `service.ThreadBatchService`（`Status` / `RunOnce` / `Pause`）；Task 7 的 `AIHandler.RegisterBackground`
- Produces:
  - `func NewThreadAIHandler(db *sql.DB, batch *service.ThreadBatchService, aiH *AIHandler, providerReady func() bool) *ThreadAIHandler`
  - `GetStatus` / `UpdateSettings` / `RunBatch` 三个 handler
  - 路由注册与调度器启动

- [ ] **Step 1: 写失败的测试**

创建 `handler/thread_ai_test.go`：

```go
package handler

import (
	"net/http"
	"testing"

	"islelog-server/service"
)

func newThreadAIHandler(t *testing.T, ready bool) (*ThreadAIHandler, *fakeBatchRunner) {
	t.Helper()
	database := newTestDB(t)
	runner := &fakeBatchRunner{}
	batch := service.NewThreadBatchService(database, runner, 200000)
	return NewThreadAIHandler(database, batch, NewAIHandler(nil), func() bool { return ready }), runner
}

func TestGetStatusReportsQueueAndProvider(t *testing.T) {
	h, _ := newThreadAIHandler(t, true)
	u := newTestUser(t, h.db, "alice")
	newTestMemo(t, h.db, u, "待分析", 1755000000) // thread_scan_ts 默认 0

	c, rec := newTestContext(t, http.MethodGet, "/api/v1/ai/thread-status", "", u)
	if err := h.GetStatus(c); err != nil {
		t.Fatalf("查询失败：%v", err)
	}

	result := decodeJSON(t, rec.Body.Bytes())
	if result["enabled"] != true {
		t.Fatalf("enabled = %v，默认应开启", result["enabled"])
	}
	if result["providerAvailable"] != true {
		t.Fatalf("providerAvailable = %v", result["providerAvailable"])
	}
	if result["pendingMemos"] != float64(1) {
		t.Fatalf("pendingMemos = %v，期望 1", result["pendingMemos"])
	}
}

func TestUpdateSettingsTogglesEnabled(t *testing.T) {
	h, _ := newThreadAIHandler(t, true)
	u := newTestUser(t, h.db, "alice")

	c, _ := newTestContext(t, http.MethodPatch, "/api/v1/ai/thread-settings", `{"enabled":false}`, u)
	if err := h.UpdateSettings(c); err != nil {
		t.Fatalf("更新失败：%v", err)
	}

	var enabled int
	if err := h.db.QueryRow(`SELECT thread_ai_enabled FROM users WHERE id=?`, u.ID).Scan(&enabled); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if enabled != 0 {
		t.Fatalf("thread_ai_enabled = %d，期望 0", enabled)
	}
}

func TestRunBatchExecutesImmediately(t *testing.T) {
	h, runner := newThreadAIHandler(t, true)
	u := newTestUser(t, h.db, "alice")
	newTestMemo(t, h.db, u, "今晚又听到蛐蛐了", 1755000000)
	if _, err := h.db.Exec(
		`INSERT INTO threads (id, user_id, title, summary, summary_source, status, created_ts, updated_ts,
		                      row_status, summary_dirty, summary_locked)
		 VALUES (20, ?, '工位蛐蛐', '', 'AI', 'ACTIVE', 100, 100, 'NORMAL', 0, 0)`, u.ID); err != nil {
		t.Fatalf("插入事件串失败：%v", err)
	}

	c, rec := newTestContext(t, http.MethodPost, "/api/v1/ai/thread-batch:run", "", u)
	if err := h.RunBatch(c); err != nil {
		t.Fatalf("执行失败：%v", err)
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("状态码 = %d；响应：%s", rec.Code, rec.Body.String())
	}
	if runner.matchCalls == 0 {
		t.Fatal("立即执行应真的跑一遍匹配")
	}
}

func TestRunBatchRejectedWhenProviderUnavailable(t *testing.T) {
	h, _ := newThreadAIHandler(t, false)
	u := newTestUser(t, h.db, "alice")

	c, rec := newTestContext(t, http.MethodPost, "/api/v1/ai/thread-batch:run", "", u)
	if err := h.RunBatch(c); err != nil {
		t.Fatalf("处理失败：%v", err)
	}
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("状态码 = %d，期望 503", rec.Code)
	}
}
```

在 `service/thread_batch_test.go` 中把 `fakeRunner` 改名导出给 handler 包用不可行（跨包），因此在 `handler/thread_ai_test.go` 中另建一个：

```go
type fakeBatchRunner struct {
	matchCalls   int
	summaryCalls int
}

func (r *fakeBatchRunner) ThreadSummary(ctx context.Context, req ai.ThreadSummaryRequest) (ai.ThreadSummaryResult, error) {
	r.summaryCalls++
	return ai.ThreadSummaryResult{Summary: "测试简介"}, nil
}

func (r *fakeBatchRunner) ThreadMatch(ctx context.Context, req ai.ThreadMatchRequest) (ai.ThreadMatchResult, error) {
	r.matchCalls++
	return ai.ThreadMatchResult{}, nil
}
```

并在该测试文件 import 中加入 `"context"` 与 `"islelog-server/service/ai"`。

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./handler/ -run "TestGetStatus|TestUpdateSettings|TestRunBatch" -v
```

Expected: 编译失败，`undefined: NewThreadAIHandler`

- [ ] **Step 3: 实现**

创建 `handler/thread_ai.go`：

```go
package handler

import (
	"context"
	"database/sql"
	"net/http"
	"time"

	"islelog-server/middleware"
	"islelog-server/service"

	"github.com/labstack/echo/v4"
)

// ThreadAIHandler 暴露夜间批次的状态、开关与立即执行。
type ThreadAIHandler struct {
	db            *sql.DB
	batch         *service.ThreadBatchService
	ai            *AIHandler
	providerReady func() bool
}

func NewThreadAIHandler(
	database *sql.DB,
	batch *service.ThreadBatchService,
	aiHandler *AIHandler,
	providerReady func() bool,
) *ThreadAIHandler {
	return &ThreadAIHandler{db: database, batch: batch, ai: aiHandler, providerReady: providerReady}
}

// GetStatus 返回队列深度与调度状态，供客户端显示「N 篇待分析 · 今晚 4:00 处理」。
func (h *ThreadAIHandler) GetStatus(c echo.Context) error {
	u := middleware.GetCurrentUser(c)

	var enabled int
	if err := h.db.QueryRow(
		`SELECT thread_ai_enabled FROM users WHERE id=?`, u.ID).Scan(&enabled); err != nil {
		return threadError(c, http.StatusInternalServerError, "查询失败")
	}
	status, err := h.batch.Status(u.ID)
	if err != nil {
		return threadError(c, http.StatusInternalServerError, "查询失败")
	}

	result := map[string]interface{}{
		"enabled":           enabled == 1,
		"providerAvailable": h.providerReady(),
		"pendingMemos":      status.PendingMemos,
		"dirtyThreads":      status.DirtyThreads,
		"lastRunError":      status.LastError,
	}
	if status.LastRunTs > 0 {
		result["lastRunTime"] = time.Unix(status.LastRunTs, 0).UTC().Format(time.RFC3339)
	}
	return c.JSON(http.StatusOK, result)
}

// UpdateSettings 切换该用户的自动分析开关。
func (h *ThreadAIHandler) UpdateSettings(c echo.Context) error {
	u := middleware.GetCurrentUser(c)
	var req struct {
		Enabled *bool `json:"enabled"`
	}
	if err := c.Bind(&req); err != nil {
		return threadError(c, http.StatusBadRequest, "请求格式错误")
	}
	if req.Enabled == nil {
		return threadError(c, http.StatusBadRequest, "enabled 不能为空")
	}
	value := 0
	if *req.Enabled {
		value = 1
	}
	if _, err := h.db.Exec(
		`UPDATE users SET thread_ai_enabled=? WHERE id=?`, value, u.ID); err != nil {
		return threadError(c, http.StatusInternalServerError, "更新失败")
	}
	return c.JSON(http.StatusOK, map[string]interface{}{"enabled": *req.Enabled})
}

// RunBatch 立即跑一遍批次，供不想等到凌晨的场景使用。
func (h *ThreadAIHandler) RunBatch(c echo.Context) error {
	if !h.providerReady() {
		return threadError(c, http.StatusServiceUnavailable, "本地模型不可用")
	}

	ctx, cancel := context.WithCancel(c.Request().Context())
	defer cancel()
	unregister := h.ai.RegisterBackground(cancel)
	defer unregister()

	if err := h.batch.RunOnce(ctx); err != nil {
		return threadError(c, http.StatusBadGateway, "分析失败，请稍后再试")
	}
	return c.JSON(http.StatusOK, map[string]interface{}{})
}
```

- [ ] **Step 4: 接线 main.go**

在 `aiSvc := aiservice.NewService(aiProviders)` 之后追加：

```go
	threadBatchSvc := service.NewThreadBatchService(database, aiSvc, cfg.AI.Local.ContextLength)
```

在 `aiH := handler.NewAIHandler(aiSvc)` 所在的 handler 初始化区之后追加：

```go
	threadSuggestionH := handler.NewThreadSuggestionHandler(database)
	threadAIH := handler.NewThreadAIHandler(database, threadBatchSvc, aiH, func() bool {
		for _, status := range aiSvc.ProviderStatuses(context.Background()) {
			if status.Name == aiservice.ProviderLocal {
				return status.Enabled && status.Available
			}
		}
		return false
	})
	// 让前台抢占后台时能通知批次退避
	aiH.SetPauser(threadBatchSvc)
```

在 AI 路由区追加：

```go
	api.GET("/ai/thread-status", threadAIH.GetStatus)
	api.PATCH("/ai/thread-settings", threadAIH.UpdateSettings)
	api.POST("/ai/thread-batch:run", threadAIH.RunBatch)

	api.GET("/thread-suggestions", threadSuggestionH.ListSuggestions)
	api.PATCH("/thread-suggestions/:suggestion", threadSuggestionH.UpdateSuggestion)
```

在 `addr := fmt.Sprintf(...)` 之前启动调度器：

```go
	// 夜间批次调度器：随进程生命周期运行
	batchCtx, stopBatch := context.WithCancel(context.Background())
	defer stopBatch()
	threadBatchSvc.Start(batchCtx)
```

`main.go` 需新增 import `"context"`。

- [ ] **Step 5: 运行测试确认通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go build ./... && go test ./...
```

Expected: 编译成功，全部 PASS

- [ ] **Step 6: 提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server
git add handler/thread_ai.go handler/thread_ai_test.go main.go
git commit -m "feat: 事件串 AI 状态、开关与立即执行接口"
```

---

### Task 9: API 文档与服务端端到端验证

**服务端检查点** —— 完成后服务端可脱离客户端独立验证。

**Files:**
- Modify: `server-API.md`（客户端仓库 `/Users/cxb/Code/flutter/memos_local/server-API.md`）

- [ ] **Step 1: 补文档**

在 `server-API.md` 的「## 变更日志（增量同步）」之前插入：

````markdown
## 事件串 AI 辅助

> 仅适用于 IsleLog 自建服务。每天凌晨 4 点跑一次批处理：先重算「脏」事件串的简介，
> 再为待分析的日记产出归属建议。后台任务**硬编码使用 LOCAL 模型**，绝不上云。
> AI 只写 `thread_suggestions` 与 `threads.summary`，永不修改事件串成员。

### 状态

`GET /api/v1/ai/thread-status` **[IsleLog 扩展]**

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

`lastRunTime` 在从未运行过时不输出。

### 开关

`PATCH /api/v1/ai/thread-settings` **[IsleLog 扩展]**

请求体 `{"enabled": false}`。关闭后夜间批次对该用户完全不运行，`pendingMemos` 会持续累积但不消耗模型。

### 立即执行

`POST /api/v1/ai/thread-batch:run` **[IsleLog 扩展]**

立即跑一遍批次，效果与夜间批次一致。本地模型不可用时返回 503。

### 建议列表

`GET /api/v1/thread-suggestions?status=PENDING` **[IsleLog 扩展]**

```json
{
  "suggestions": [
    {
      "name": "threadSuggestions/77",
      "memo": "memos/1001",
      "thread": "threads/20",
      "memoSnippet": "今晚又听到蛐蛐了",
      "threadTitle": "工位蛐蛐",
      "confidence": 0.86,
      "reason": "同样在讲工位的蛐蛐",
      "status": "PENDING",
      "createTime": "2026-08-24T04:00:12Z"
    }
  ]
}
```

按置信度倒序。**置信度低于 0.7 的匹配结果直接丢弃、不入库**，因此列表中不会出现低置信度项。
`memo` 或 `thread` 已被软删除的建议不会返回。

### 修改建议状态

`PATCH /api/v1/thread-suggestions/:id` **[IsleLog 扩展]**

请求体 `{"status": "ACCEPTED"}` 或 `{"status": "DISMISSED"}`。

> **接受建议不会写入事件串成员。** 服务端只记录状态，成员写入由客户端走
> `PUT /threads/:id/members` 完成，避免两个写入方互相覆盖。
>
> 同一 `(memo, thread)` 组合在库中只存在一行：用户忽略之后，再怎么编辑正文
> 也不会重新收到同一条建议。

### 事件串字段变化

`PATCH /api/v1/threads/:id` 新增两个字段：

| 字段 | 说明 |
|------|------|
| `summarySource` | `AI` / `MANUAL`，简介来源，仅供展示 |
| `summaryLocked` | bool，为 true 时 AI 不再改写该简介 |

服务端**不再从「请求里是否带 summary」推断来源**，两者都必须由客户端显式声明。
Thread 响应结构相应新增 `summaryLocked`。

---
````

- [ ] **Step 2: 启动服务端**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go run . &
curl -s http://localhost:8080/healthz
```

Expected: `{"status":"ok"}`

- [ ] **Step 3: 端到端验证**

把 `$TOKEN` 换成实际 token 后逐条执行并核对：

```bash
# 1. 状态：升级后 pendingMemos 应为 0（存量已回填为已扫描）
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/ai/thread-status

# 2. 新建一篇日记 → pendingMemos 变为 1
curl -s -X POST http://localhost:8080/api/v1/memos \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"content":"今晚又听到蛐蛐了"}'
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/ai/thread-status

# 3. 立即执行批次
curl -s -X POST -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/ai/thread-batch:run

# 4. 查看产出的建议
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/thread-suggestions

# 5. 忽略某条建议，再跑一次批次，确认不会复活
curl -s -X PATCH http://localhost:8080/api/v1/thread-suggestions/$SID \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"status":"DISMISSED"}'

# 6. 关闭开关后再跑，确认不消耗模型
curl -s -X PATCH http://localhost:8080/api/v1/ai/thread-settings \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"enabled":false}'
```

逐条核对：

- [ ] 首次 `thread-status` 的 `pendingMemos` 为 **0** —— 存量日记已回填，不会触发全库分析
- [ ] 新建日记后 `pendingMemos` 变为 1
- [ ] 批次执行后事件串的 `summary` 被填上，且 `summaryLocked` 为 false
- [ ] 建议列表返回的 `confidence` 均 ≥ 0.7
- [ ] 忽略某条建议后重跑批次，该建议仍为 `DISMISSED`，不会变回 `PENDING`
- [ ] 给某事件串 `PATCH {"summaryLocked": true}` 后重跑批次，其 `summary` 不再变化
- [ ] 关闭开关后重跑批次，`pendingMemos` 不减少
- [ ] 批次运行期间调用 `/api/v1/ai/tag-suggestions`，标签建议正常返回而非 429

- [ ] **Step 4: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add server-API.md
git commit -m "docs: 补充事件串 AI 辅助接口文档"
```

**Phase 2 服务端到此完成。**

---

# Part B — 客户端

### Task 10: 建议模型、锁定字段与数据库操作

**Files:**
- Create: `lib/data/models/thread_suggestion_entry.dart`
- Modify: `lib/data/models/thread_entry.dart`
- Modify: `lib/data/database/database_service.dart`

**Interfaces:**
- Consumes: `SyncStatus`（`lib/data/models/memo_entry.dart`）
- Produces:
  - `enum SuggestionStatus { pending, accepted, dismissed }`
  - `class ThreadSuggestionEntry`（字段见下）
  - `ThreadEntry.summaryLocked`
  - `DatabaseService.saveSuggestion(ThreadSuggestionEntry, {bool skipTimestamp}) → Future<int>`
  - `DatabaseService.getPendingSuggestions() → Future<List<ThreadSuggestionEntry>>`
  - `DatabaseService.getSuggestionsForMemo(int memoLocalId) → Future<List<ThreadSuggestionEntry>>`
  - `DatabaseService.getSyncedSuggestions() → Future<List<ThreadSuggestionEntry>>`
  - `DatabaseService.getPendingSyncSuggestions() → Future<List<ThreadSuggestionEntry>>`
  - `DatabaseService.hardDeleteSuggestion(int) → Future<bool>`

- [ ] **Step 1: 创建模型**

创建 `lib/data/models/thread_suggestion_entry.dart`：

```dart
import 'package:isar/isar.dart';

import 'memo_entry.dart';

part 'thread_suggestion_entry.g.dart';

/// 建议状态
enum SuggestionStatus { pending, accepted, dismissed }

/// AI 产出的事件串归属建议
///
/// 服务端只对置信度 ≥ 0.7 的匹配入库，因此本地不需要按置信度分档展示。
@collection
class ThreadSuggestionEntry {
  Id id = Isar.autoIncrement;

  /// 远端资源名 "threadSuggestions/{id}"，不设 unique（同 memosName 的理由）
  @Index()
  String? suggestionName;

  /// 建议关联的日记本地 id；value 索引供时间线卡片反查
  @Index()
  int memoLocalId = 0;

  /// 建议归入的事件串本地 id
  int threadLocalId = 0;

  double confidence = 0;
  String reason = '';

  @enumerated
  SuggestionStatus status = SuggestionStatus.pending;

  DateTime createdAt = DateTime.now();

  /// 本地已操作但尚未推送时为 pending，拉取时不会被服务端旧状态覆盖
  @enumerated
  SyncStatus syncStatus = SyncStatus.synced;
}
```

在 `lib/data/models/thread_entry.dart` 的 `summaryIsManual` 之后追加：

```dart
  /// 锁定后 AI 不再改写简介
  ///
  /// 与 [summaryIsManual] 是两件事：后者记录「谁写的」仅供展示，前者决定
  /// 「AI 能不能改」。分开是因为用户可能想冻结一条 AI 写得不错的简介，
  /// 而不必把它原样重打一遍。
  bool summaryLocked = false;
```

- [ ] **Step 2: 注册 schema 并生成代码**

`lib/data/database/database_service.dart` 的 import 区加入：

```dart
import '../models/thread_suggestion_entry.dart';
```

`Isar.open` 的 schema 列表中，`ThreadEntrySchema` 之后加入 `ThreadSuggestionEntrySchema,`。

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: 生成 `lib/data/models/thread_suggestion_entry.g.dart`，无错误

- [ ] **Step 3: 加入 watchDbChanges**

在 `watchDbChanges` 中，`threadStream` 之后加入：

```dart
    // 建议增删同样要触发列表刷新（横幅与卡片 chip 都依赖它）
    final suggestionStream = isar.threadSuggestionEntrys.watchLazy(
      fireImmediately: false,
    );
```

并把 `mergeWith` 的列表改为 `[commentStream, articleStream, folderStream, threadStream, suggestionStream]`。

- [ ] **Step 4: 实现 CRUD**

在 `database_service.dart` 末尾（类闭合大括号之前）追加：

```dart
  // ────────────────────────────────────────────────────────────────
  // 事件串建议（ThreadSuggestionEntry）
  // ────────────────────────────────────────────────────────────────

  static Future<int> saveSuggestion(ThreadSuggestionEntry suggestion) async {
    final isar = await db;
    final id = await isar.writeTxn(
      () => isar.threadSuggestionEntrys.put(suggestion),
    );
    return id;
  }

  /// 待用户确认的建议，按置信度倒序。
  static Future<List<ThreadSuggestionEntry>> getPendingSuggestions() async {
    final isar = await db;
    final result = await isar.threadSuggestionEntrys
        .filter()
        .statusEqualTo(SuggestionStatus.pending)
        .sortByConfidenceDesc()
        .findAll();
    debugPrint('[DB] getPendingSuggestions → ${result.length} 条');
    return result;
  }

  /// 某篇日记的待确认建议（时间线卡片的虚线 chip 用）。
  static Future<List<ThreadSuggestionEntry>> getSuggestionsForMemo(
    int memoLocalId,
  ) async {
    final isar = await db;
    return isar.threadSuggestionEntrys
        .filter()
        .memoLocalIdEqualTo(memoLocalId)
        .statusEqualTo(SuggestionStatus.pending)
        .findAll();
  }

  static Future<List<ThreadSuggestionEntry>> getSyncedSuggestions() async {
    final isar = await db;
    return isar.threadSuggestionEntrys
        .filter()
        .syncStatusEqualTo(SyncStatus.synced)
        .findAll();
  }

  static Future<List<ThreadSuggestionEntry>> getPendingSyncSuggestions() async {
    final isar = await db;
    return isar.threadSuggestionEntrys
        .filter()
        .syncStatusEqualTo(SyncStatus.pending)
        .findAll();
  }

  static Future<bool> hardDeleteSuggestion(int id) async {
    final isar = await db;
    return isar.writeTxn(() => isar.threadSuggestionEntrys.delete(id));
  }
```

- [ ] **Step 5: 确认编译**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter analyze 2>&1 | grep -cE "error •|warning •"
```

Expected: `0`

- [ ] **Step 6: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/data/models/thread_suggestion_entry.dart lib/data/models/thread_suggestion_entry.g.dart lib/data/models/thread_entry.dart lib/data/models/thread_entry.g.dart lib/data/database/database_service.dart
git commit -m "feat: 新增事件串建议模型与简介锁定字段"
```

---

### Task 11: 建议合并的纯函数

拉取时不能让服务端的旧状态覆盖本地已操作但未推送的建议。把这条判定抽成纯函数单测。

**Files:**
- Modify: `lib/data/database/thread_membership_policy.dart`
- Modify: `test/data/database/thread_membership_policy_test.dart`

**Interfaces:**
- Produces: `bool shouldOverwriteSuggestion(ThreadSuggestionEntry? local)`

- [ ] **Step 1: 写失败的测试**

在 `test/data/database/thread_membership_policy_test.dart` 的最后一个 `group` 之后、闭合大括号之前追加：

```dart
  group('shouldOverwriteSuggestion', () {
    test('本地不存在时写入', () {
      expect(shouldOverwriteSuggestion(null), isTrue);
    });

    test('本地已同步时可被服务端覆盖', () {
      final local = ThreadSuggestionEntry()..syncStatus = SyncStatus.synced;

      expect(shouldOverwriteSuggestion(local), isTrue);
    });

    // 离线点了「加入」或「忽略」后，服务端仍是 PENDING；
    // 若被覆盖，用户的操作会凭空复活成待确认。
    test('本地已操作未推送时不被覆盖', () {
      final local = ThreadSuggestionEntry()
        ..syncStatus = SyncStatus.pending
        ..status = SuggestionStatus.dismissed;

      expect(shouldOverwriteSuggestion(local), isFalse);
    });
  });
```

并在该文件 import 区加入：

```dart
import 'package:isle_log/data/models/thread_suggestion_entry.dart';
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter test test/data/database/thread_membership_policy_test.dart
```

Expected: 编译失败，`shouldOverwriteSuggestion` 未定义

- [ ] **Step 3: 实现**

在 `lib/data/database/thread_membership_policy.dart` 末尾追加：

```dart
/// 判断拉取到的远端建议是否可以覆盖本地记录。
///
/// 本地已操作但尚未推送（`syncStatus == pending`）时必须保留：服务端此刻
/// 仍是 `PENDING`，覆盖会让用户离线点过的「加入」或「忽略」凭空复活。
bool shouldOverwriteSuggestion(ThreadSuggestionEntry? local) {
  if (local == null) return true;
  return local.syncStatus == SyncStatus.synced;
}
```

并在该文件 import 区加入：

```dart
import '../models/thread_suggestion_entry.dart';
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter test test/data/database/thread_membership_policy_test.dart
```

Expected: All tests passed

- [ ] **Step 5: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/data/database/thread_membership_policy.dart test/data/database/thread_membership_policy_test.dart
git commit -m "feat: 新增建议合并判定纯函数"
```

---

### Task 12: API 客户端接口与同步

**Files:**
- Modify: `lib/services/api/memos_api_service.dart`
- Modify: `lib/services/sync/sync_service.dart`

**Interfaces:**
- Consumes: Task 10 的模型与 CRUD；Task 11 的 `shouldOverwriteSuggestion`
- Produces:
  - `Future<Map<String, dynamic>> getThreadAiStatus()`
  - `Future<void> setThreadAiEnabled(bool enabled)`
  - `Future<void> runThreadBatch()`
  - `Future<List<Map<String, dynamic>>> listThreadSuggestions({String status})`
  - `Future<void> updateThreadSuggestion({required String name, required String status})`
  - `updateThread` 新增可选参数 `String? summarySource, bool? summaryLocked`
  - `SyncService._pullSuggestions(MemosApiService)` / `_pushPendingSuggestions(MemosApiService)`

- [ ] **Step 1: 加 API 方法**

在 `memos_api_service.dart` 的 `setThreadMembers` 之后追加：

```dart
  /// 夜间批次的队列与调度状态
  Future<Map<String, dynamic>> getThreadAiStatus() async {
    try {
      final res = await _dio.get('/api/v1/ai/thread-status');
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 切换自动分析总开关
  Future<void> setThreadAiEnabled(bool enabled) async {
    try {
      await _dio.patch('/api/v1/ai/thread-settings', data: {'enabled': enabled});
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 立即跑一遍夜间批次
  Future<void> runThreadBatch() async {
    try {
      await _dio.post('/api/v1/ai/thread-batch:run');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 拉取建议列表（默认待确认）
  Future<List<Map<String, dynamic>>> listThreadSuggestions({
    String status = 'PENDING',
  }) async {
    try {
      final res = await _dio.get(
        '/api/v1/thread-suggestions',
        queryParameters: {'status': status},
      );
      final list = (res.data['suggestions'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      debugPrint('[API] listThreadSuggestions → ${list.length} 条');
      return list;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 修改建议状态（ACCEPTED / DISMISSED）
  Future<void> updateThreadSuggestion({
    required String name,
    required String status,
  }) async {
    try {
      await _dio.patch('/api/v1/$name', data: {'status': status});
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }
```

修改既有的 `updateThread`，加上两个参数并写入请求体：

```dart
  Future<Map<String, dynamic>> updateThread({
    required String name,
    String? title,
    String? summary,
    String? summarySource,
    bool? summaryLocked,
    String? status,
  }) async {
```

请求体 map 中追加：

```dart
        // 服务端不再从「有没有 summary」推断来源，必须显式声明，
        // 否则每次推送都会把简介判定为手写，AI 永远无法接管
        if (summarySource != null) 'summarySource': summarySource,
        if (summaryLocked != null) 'summaryLocked': summaryLocked,
```

- [ ] **Step 2: 推送时带上来源与锁定**

在 `sync_service.dart` 的 `_pushPendingThreads` 中，把 `api.updateThread(...)` 调用改为：

```dart
          await api.updateThread(
            name: thread.threadName!,
            title: thread.title,
            summary: thread.summary,
            summarySource: thread.summaryIsManual ? 'MANUAL' : 'AI',
            summaryLocked: thread.summaryLocked,
            status: thread.status == ThreadStatus.resolved
                ? 'RESOLVED'
                : 'ACTIVE',
          );
```

在 `_applyRemoteThread` 中追加一行，让锁定状态能从远端同步下来：

```dart
      ..summaryLocked = data['summaryLocked'] == true
```

- [ ] **Step 3: 实现建议的拉取与推送**

在 `sync_service.dart` 末尾（类闭合大括号之前）追加：

```dart
  // ────────────────────────────────────────────────────────────────
  // 事件串建议同步
  // ────────────────────────────────────────────────────────────────

  /// 拉取待确认建议。
  ///
  /// 不走 changelog：建议是短命数据且高阈值过滤后列表很短，每次全量拉取
  /// 比维护 entity 分支和冲突判定简单得多。
  static Future<int> _pullSuggestions(MemosApiService api) async {
    debugPrint('[Sync] _pullSuggestions 开始');
    var pulled = 0;
    try {
      final remoteList = await api.listThreadSuggestions();
      final remoteNames = remoteList
          .map((data) => data['name'] as String?)
          .whereType<String>()
          .toSet();

      for (final data in remoteList) {
        final name = data['name'] as String?;
        if (name == null) continue;

        final local = await DatabaseService.getSuggestionByName(name);
        if (!shouldOverwriteSuggestion(local)) continue;

        final memo = await DatabaseService.getMemoByMemosName(
          data['memo'] as String? ?? '',
        );
        final thread = await DatabaseService.getThreadByThreadName(
          data['thread'] as String? ?? '',
        );
        // 本地还没有对应的日记或事件串就跳过，下轮同步补齐
        if (memo == null || thread == null) continue;

        final entry = local ?? ThreadSuggestionEntry();
        entry
          ..suggestionName = name
          ..memoLocalId = memo.id
          ..threadLocalId = thread.id
          ..confidence = (data['confidence'] as num?)?.toDouble() ?? 0
          ..reason = data['reason'] as String? ?? ''
          ..status = SuggestionStatus.pending
          ..syncStatus = SyncStatus.synced
          ..createdAt =
              DateTime.tryParse(data['createTime'] as String? ?? '')?.toLocal() ??
              DateTime.now();
        await DatabaseService.saveSuggestion(entry);
        pulled++;
      }

      // 远端已不在待确认列表中的（被其他设备处理掉了）本地物理删除
      for (final local in await DatabaseService.getSyncedSuggestions()) {
        if (local.suggestionName != null &&
            !remoteNames.contains(local.suggestionName)) {
          await DatabaseService.hardDeleteSuggestion(local.id);
        }
      }
    } catch (e) {
      debugPrint('[Sync] _pullSuggestions 失败: $e');
    }
    debugPrint('[Sync] _pullSuggestions 完成，拉取 $pulled 条');
    return pulled;
  }

  /// 推送本地对建议的处理结果。
  static Future<int> _pushPendingSuggestions(MemosApiService api) async {
    final pending = await DatabaseService.getPendingSyncSuggestions();
    var pushed = 0;
    for (final suggestion in pending) {
      if (suggestion.suggestionName == null) continue;
      try {
        await api.updateThreadSuggestion(
          name: suggestion.suggestionName!,
          status: suggestion.status == SuggestionStatus.accepted
              ? 'ACCEPTED'
              : 'DISMISSED',
        );
        // 处理完的建议不再需要留在本地
        await DatabaseService.hardDeleteSuggestion(suggestion.id);
        pushed++;
      } catch (e) {
        debugPrint('[Sync] 推送建议失败 id=${suggestion.id}: $e');
      }
    }
    return pushed;
  }
```

在 `database_service.dart` 的建议 CRUD 区追加按名查询：

```dart
  static Future<ThreadSuggestionEntry?> getSuggestionByName(String name) async {
    final isar = await db;
    return isar.threadSuggestionEntrys
        .filter()
        .suggestionNameEqualTo(name)
        .findFirst();
  }
```

- [ ] **Step 4: 接入同步主流程**

在 `_sync` 中 `await _pullThreads(api);` 之后追加：

```dart
      // 建议在事件串之后拉取，保证 threadLocalId 能映射到本地
      await _pullSuggestions(api);
```

在 `_pushPending` 的 `count += await _pushPendingThreads(api);` 之后追加：

```dart
    // 建议最后推送：接受建议引发的成员变更已在上一步推完
    count += await _pushPendingSuggestions(api);
```

在 `sync_service.dart` import 区加入：

```dart
import '../../data/models/thread_suggestion_entry.dart';
```

- [ ] **Step 5: 确认编译与测试**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter analyze 2>&1 | grep -cE "error •|warning •" && flutter test test/data test/features 2>&1 | tail -c 120
```

Expected: `0` 且 All tests passed

- [ ] **Step 6: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/services/api/memos_api_service.dart lib/services/sync/sync_service.dart lib/data/database/database_service.dart
git commit -m "feat: 事件串建议同步与简介锁定推送"
```

---

### Task 13: 简介锁定按钮

**Files:**
- Modify: `lib/features/threads/thread_detail_page.dart`

**Interfaces:**
- Consumes: Task 10 的 `ThreadEntry.summaryLocked`
- Produces: 详情页简介行右侧的锁定切换

**本任务没有自动化测试**：锁定按钮嵌在依赖 Isar 的有状态页面里，widget test 中无法构造。以 `flutter analyze` 通过 + 手动确认为准。

- [ ] **Step 1: 加锁定切换**

在 `thread_detail_page.dart` 的 `_save()` 之后追加：

```dart
  Future<void> _toggleSummaryLock() async {
    final thread = _thread;
    if (thread == null) return;
    thread.summaryLocked = !thread.summaryLocked;
    await _save();
  }
```

把简介那一段（`Padding` 包着 `InkWell` 的整块）替换为：

```dart
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _edit(
                      label: '简介',
                      initial: thread.summary,
                      allowEmpty: true,
                      onSave: (value) {
                        thread.summary = value;
                        thread.summaryIsManual = true;
                        // 手动改写后自动锁定，否则当晚就被批次覆盖
                        thread.summaryLocked = true;
                        _save();
                      },
                    ),
                    child: Text(
                      thread.summary.isEmpty ? '点击添加一句话简介' : thread.summary,
                      style: TextStyle(
                        color: thread.summary.isEmpty
                            ? Colors.grey
                            : AppColors.textBody(context),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    thread.summaryLocked ? Icons.lock : Icons.lock_open_outlined,
                    size: 18,
                    color: thread.summaryLocked
                        ? AppColors.primary
                        : AppColors.textSecondary(context),
                  ),
                  tooltip: thread.summaryLocked ? '已锁定，点击解锁' : '锁定简介，AI 不再改写',
                  onPressed: _toggleSummaryLock,
                ),
              ],
            ),
          ),
```

- [ ] **Step 2: 确认编译**

```bash
flutter analyze 2>&1 | grep -cE "error •|warning •"
```

Expected: `0`

- [ ] **Step 3: 手动验证**

- [ ] 打开某事件串详情页，简介右侧显示空心锁
- [ ] 点击后变为实心锁并带主题色，再次点击恢复
- [ ] 手动改写简介后，锁自动变为实心（无需再点）

- [ ] **Step 4: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/features/threads/thread_detail_page.dart
git commit -m "feat: 事件串简介锁定按钮"
```

---

### Task 14: 建议横幅与状态行

**Files:**
- Create: `lib/features/threads/widgets/suggestion_banner.dart`
- Create: `lib/features/threads/widgets/thread_ai_status_line.dart`
- Create: `test/features/threads/suggestion_banner_test.dart`
- Create: `test/features/threads/thread_ai_status_line_test.dart`
- Modify: `lib/features/threads/threads_view.dart`

**Interfaces:**
- Produces:
  - `class SuggestionItem { final String suggestionLocalKey; final String memoSnippet; final String threadTitle; final String reason; }`
  - `class SuggestionBanner extends StatelessWidget { final List<SuggestionItem> items; final void Function(int index) onAccept; final void Function(int index) onDismiss; }`
  - `class ThreadAiStatusData { final bool enabled; final bool providerAvailable; final int pendingMemos; final int dirtyThreads; }`
  - `class ThreadAiStatusLine extends StatelessWidget { final ThreadAiStatusData data; }`

- [ ] **Step 1: 写失败的 widget 测试**

创建 `test/features/threads/thread_ai_status_line_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/threads/widgets/thread_ai_status_line.dart';

Future<void> _pump(WidgetTester tester, ThreadAiStatusData data) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: ThreadAiStatusLine(data: data))),
  );
}

void main() {
  testWidgets('待分析时显示数量与处理时间', (tester) async {
    await _pump(
      tester,
      const ThreadAiStatusData(
        enabled: true,
        providerAvailable: true,
        pendingMemos: 3,
        dirtyThreads: 1,
      ),
    );

    expect(find.text('3 篇待分析 · 今晚 4:00 处理'), findsOneWidget);
  });

  testWidgets('模型离线时明确提示', (tester) async {
    await _pump(
      tester,
      const ThreadAiStatusData(
        enabled: true,
        providerAvailable: false,
        pendingMemos: 3,
        dirtyThreads: 0,
      ),
    );

    expect(find.text('模型离线，暂停分析'), findsOneWidget);
  });

  testWidgets('关闭自动分析时提示已关闭', (tester) async {
    await _pump(
      tester,
      const ThreadAiStatusData(
        enabled: false,
        providerAvailable: true,
        pendingMemos: 5,
        dirtyThreads: 0,
      ),
    );

    expect(find.text('自动分析已关闭'), findsOneWidget);
  });

  // 空闲时整行不占位，避免常驻噪音
  testWidgets('无待处理项时不渲染任何内容', (tester) async {
    await _pump(
      tester,
      const ThreadAiStatusData(
        enabled: true,
        providerAvailable: true,
        pendingMemos: 0,
        dirtyThreads: 0,
      ),
    );

    expect(find.byType(Text), findsNothing);
  });
}
```

创建 `test/features/threads/suggestion_banner_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/threads/widgets/suggestion_banner.dart';

const _items = [
  SuggestionItem(
    suggestionLocalKey: '1',
    memoSnippet: '今晚又听到蛐蛐了',
    threadTitle: '工位蛐蛐',
    reason: '同样在讲工位的蛐蛐',
  ),
  SuggestionItem(
    suggestionLocalKey: '2',
    memoSnippet: '装了新灯',
    threadTitle: '装修',
    reason: '同一轮装修',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  List<SuggestionItem> items = _items,
  void Function(int)? onAccept,
  void Function(int)? onDismiss,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SuggestionBanner(
          items: items,
          onAccept: onAccept ?? (_) {},
          onDismiss: onDismiss ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('显示条数与每条的日记摘要和事件串', (tester) async {
    await _pump(tester);

    expect(find.text('发现 2 条可能的关联'), findsOneWidget);
    expect(find.text('今晚又听到蛐蛐了'), findsOneWidget);
    expect(find.textContaining('工位蛐蛐'), findsWidgets);
    expect(find.text('同样在讲工位的蛐蛐'), findsOneWidget);
  });

  testWidgets('无建议时不渲染', (tester) async {
    await _pump(tester, items: const []);

    expect(find.textContaining('发现'), findsNothing);
  });

  testWidgets('加入与忽略各自回调对应的索引', (tester) async {
    int? accepted;
    int? dismissed;
    await _pump(
      tester,
      onAccept: (index) => accepted = index,
      onDismiss: (index) => dismissed = index,
    );

    await tester.tap(find.byKey(const Key('suggestion_accept_1')));
    await tester.tap(find.byKey(const Key('suggestion_dismiss_0')));
    await tester.pump();

    expect(accepted, 1);
    expect(dismissed, 0);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter test test/features/threads/
```

Expected: 编译失败，找不到两个新文件

- [ ] **Step 3: 实现状态行**

创建 `lib/features/threads/widgets/thread_ai_status_line.dart`：

```dart
import 'package:flutter/material.dart';

import '../../../shared/constants/app_constants.dart';

/// 夜间批次的可见状态
class ThreadAiStatusData {
  final bool enabled;
  final bool providerAvailable;
  final int pendingMemos;
  final int dirtyThreads;

  const ThreadAiStatusData({
    required this.enabled,
    required this.providerAvailable,
    required this.pendingMemos,
    required this.dirtyThreads,
  });

  bool get hasWork => pendingMemos > 0 || dirtyThreads > 0;
}

/// 事件串页顶部的一行分析状态。
///
/// 只在有待处理项时出现——空闲时整行不占位，避免常驻噪音。
/// 文案给确定的时间点而不是「分析中」，因为批次每晚固定 4 点跑。
class ThreadAiStatusLine extends StatelessWidget {
  final ThreadAiStatusData data;

  const ThreadAiStatusLine({super.key, required this.data});

  String? _label() {
    if (!data.hasWork) return null;
    if (!data.enabled) return '自动分析已关闭';
    if (!data.providerAvailable) return '模型离线，暂停分析';
    return '${data.pendingMemos} 篇待分析 · 今晚 4:00 处理';
  }

  @override
  Widget build(BuildContext context) {
    final label = _label();
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
      ),
    );
  }
}
```

- [ ] **Step 4: 实现横幅**

创建 `lib/features/threads/widgets/suggestion_banner.dart`：

```dart
import 'package:flutter/material.dart';

import '../../../shared/constants/app_constants.dart';

/// 横幅中一条待确认建议的展示数据
class SuggestionItem {
  final String suggestionLocalKey;
  final String memoSnippet;
  final String threadTitle;
  final String reason;

  const SuggestionItem({
    required this.suggestionLocalKey,
    required this.memoSnippet,
    required this.threadTitle,
    required this.reason,
  });
}

/// 事件串页顶部的待确认建议横幅。
///
/// 服务端只保留置信度 ≥ 0.7 的匹配，因此这里不做置信度分档展示——
/// 出现在这里的每一条都值得看一眼。
class SuggestionBanner extends StatelessWidget {
  final List<SuggestionItem> items;
  final void Function(int index) onAccept;
  final void Function(int index) onDismiss;

  const SuggestionBanner({
    super.key,
    required this.items,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.primarySofter(context),
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '发现 ${items.length} 条可能的关联',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.onPrimarySoft(context),
            ),
          ),
          const SizedBox(height: 4),
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[index].memoSnippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        Text(
                          '→「${items[index].threadTitle}」· ${items[index].reason}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: Key('suggestion_accept_$index'),
                    icon: const Icon(Icons.check, size: 18),
                    color: AppColors.primary,
                    tooltip: '加入',
                    onPressed: () => onAccept(index),
                  ),
                  IconButton(
                    key: Key('suggestion_dismiss_$index'),
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textSecondary(context),
                    tooltip: '忽略',
                    onPressed: () => onDismiss(index),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter test test/features/threads/
```

Expected: All tests passed

- [ ] **Step 6: 接入事件串页**

在 `threads_view.dart` 的 `_ThreadsViewState` 中新增状态与加载：

```dart
  List<ThreadSuggestionEntry> _suggestions = [];
  List<SuggestionItem> _suggestionItems = [];
  ThreadAiStatusData? _aiStatus;

  Future<void> _loadSuggestions() async {
    final suggestions = await DatabaseService.getPendingSuggestions();
    final items = <SuggestionItem>[];
    for (final suggestion in suggestions) {
      final memo = await DatabaseService.getMemoById(suggestion.memoLocalId);
      final thread = await DatabaseService.getThreadById(suggestion.threadLocalId);
      if (memo == null || thread == null || memo.isDeleted || thread.isDeleted) {
        continue;
      }
      items.add(SuggestionItem(
        suggestionLocalKey: '${suggestion.id}',
        memoSnippet: memo.content.replaceAll('\n', ' '),
        threadTitle: thread.title,
        reason: suggestion.reason,
      ));
    }
    if (mounted) {
      setState(() {
        _suggestions = suggestions;
        _suggestionItems = items;
      });
    }
  }

  /// 接受建议：本地把日记加进事件串，并把建议标为已接受。
  ///
  /// 成员写入走客户端既有的推送链路，服务端不代写，避免两个写入方互相覆盖。
  Future<void> _acceptSuggestion(int index) async {
    final suggestion = _suggestions[index];
    final thread = await DatabaseService.getThreadById(suggestion.threadLocalId);
    if (thread != null) {
      thread
        ..memberLocalIds = toggleThreadMember(
          thread.memberLocalIds,
          suggestion.memoLocalId,
          selected: true,
        )
        ..syncStatus = SyncStatus.pending;
      await DatabaseService.saveThread(thread);
    }
    suggestion
      ..status = SuggestionStatus.accepted
      ..syncStatus = SyncStatus.pending;
    await DatabaseService.saveSuggestion(suggestion);
    await _loadSuggestions();
    await _load();
  }

  Future<void> _dismissSuggestion(int index) async {
    final suggestion = _suggestions[index]
      ..status = SuggestionStatus.dismissed
      ..syncStatus = SyncStatus.pending;
    await DatabaseService.saveSuggestion(suggestion);
    await _loadSuggestions();
  }
```

在 `initState` 中调用 `_loadSuggestions();`，在 `_watch()` 的监听回调里也加上 `_loadSuggestions()`。

`build` 的 `ListView` children 最前面插入：

```dart
              if (_aiStatus != null) ThreadAiStatusLine(data: _aiStatus!),
              SuggestionBanner(
                items: _suggestionItems,
                onAccept: _acceptSuggestion,
                onDismiss: _dismissSuggestion,
              ),
```

`_aiStatus` 在同步后由 `MemosApiService.getThreadAiStatus()` 填充；离线或请求失败时保持 null，状态行自然不显示。加载方法：

```dart
  Future<void> _loadAiStatus() async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) return;
    try {
      final data = await MemosApiService(baseUrl: url, token: token)
          .getThreadAiStatus();
      if (!mounted) return;
      setState(() {
        _aiStatus = ThreadAiStatusData(
          enabled: data['enabled'] == true,
          providerAvailable: data['providerAvailable'] == true,
          pendingMemos: (data['pendingMemos'] as num?)?.toInt() ?? 0,
          dirtyThreads: (data['dirtyThreads'] as num?)?.toInt() ?? 0,
        );
      });
    } catch (_) {
      // 离线或服务端不支持时静默跳过，状态行不显示
    }
  }
```

在 `initState` 中一并调用 `_loadAiStatus();`。文件顶部按需补齐 import：`thread_suggestion_entry.dart`、`thread_membership_policy.dart`、`memos_api_service.dart`、`settings_service.dart`、两个新 widget。

- [ ] **Step 7: 确认编译与测试**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter analyze 2>&1 | grep -cE "error •|warning •" && flutter test test/data test/features 2>&1 | tail -c 120
```

Expected: `0` 且 All tests passed

- [ ] **Step 8: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/features/threads/ test/features/threads/
git commit -m "feat: 事件串页建议横幅与分析状态行"
```

---

### Task 15: 时间线卡片虚线建议 chip

**Files:**
- Modify: `lib/features/home/widgets/memo_timeline_card.dart`

**Interfaces:**
- Consumes: `DatabaseService.getSuggestionsForMemo`、`getThreadById`、`saveSuggestion`、`saveThread`；`toggleThreadMember`

**本任务没有自动化测试**：chip 嵌在依赖 Isar 的卡片状态里。以 `flutter analyze` + 手动确认为准。

- [ ] **Step 1: 加载建议**

在 `_MemoCardState` 中新增：

```dart
  ThreadSuggestionEntry? _suggestion;
  String _suggestionThreadTitle = '';

  Future<void> _loadSuggestion() async {
    final list = await DatabaseService.getSuggestionsForMemo(memo.id);
    if (list.isEmpty) {
      if (mounted && _suggestion != null) {
        setState(() {
          _suggestion = null;
          _suggestionThreadTitle = '';
        });
      }
      return;
    }
    final thread = await DatabaseService.getThreadById(list.first.threadLocalId);
    if (!mounted || thread == null || thread.isDeleted) return;
    setState(() {
      _suggestion = list.first;
      _suggestionThreadTitle = thread.title;
    });
  }

  Future<void> _acceptSuggestion() async {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    final thread = await DatabaseService.getThreadById(suggestion.threadLocalId);
    if (thread != null) {
      thread
        ..memberLocalIds = toggleThreadMember(
          thread.memberLocalIds,
          suggestion.memoLocalId,
          selected: true,
        )
        ..syncStatus = SyncStatus.pending;
      await DatabaseService.saveThread(thread);
    }
    suggestion
      ..status = SuggestionStatus.accepted
      ..syncStatus = SyncStatus.pending;
    await DatabaseService.saveSuggestion(suggestion);
    await _loadSuggestion();
  }

  Future<void> _dismissSuggestion() async {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    suggestion
      ..status = SuggestionStatus.dismissed
      ..syncStatus = SyncStatus.pending;
    await DatabaseService.saveSuggestion(suggestion);
    await _loadSuggestion();
  }
```

在 `initState` 中调用 `_loadSuggestion();`，在 `didUpdateWidget` 里换 memo 时也调用一次。

- [ ] **Step 2: 渲染虚线 chip**

在卡片底部那一行（`_SyncBadge` 所在的 Row）之前插入：

```dart
              if (_suggestion != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          '? $_suggestionThreadTitle',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.onPrimarySoft(context),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check, size: 16),
                        color: AppColors.primary,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                        tooltip: '加入事件串',
                        onPressed: _acceptSuggestion,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        color: Colors.grey[500],
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                        tooltip: '忽略',
                        onPressed: _dismissSuggestion,
                      ),
                    ],
                  ),
                ),
```

文件顶部补 import：`thread_suggestion_entry.dart`、`thread_membership_policy.dart`。

- [ ] **Step 3: 确认编译**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter analyze 2>&1 | grep -cE "error •|warning •"
```

Expected: `0`

- [ ] **Step 4: 手动验证**

- [ ] 有待确认建议的日记，卡片上出现虚线 chip `? 事件串名`
- [ ] 点 ✓ 后 chip 消失，该日记出现在对应事件串中
- [ ] 点 ✕ 后 chip 消失，同步后不再出现

- [ ] **Step 5: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/features/home/widgets/memo_timeline_card.dart
git commit -m "feat: 时间线卡片就地确认事件串建议"
```

---

### Task 16: 设置页开关与立即分析

**Files:**
- Modify: `lib/features/settings/ai_settings_page.dart`

**Interfaces:**
- Consumes: Task 12 的 `getThreadAiStatus` / `setThreadAiEnabled` / `runThreadBatch`

**本任务没有自动化测试**：页面依赖真实网络与服务端状态。以 `flutter analyze` + 手动确认为准。

- [ ] **Step 1: 加入开关与按钮**

在 `_AiSettingsPageState` 中新增：

```dart
  bool? _threadAiEnabled;
  bool _running = false;

  Future<MemosApiService?> _api() async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) return null;
    return MemosApiService(baseUrl: url, token: token);
  }

  Future<void> _loadThreadAi() async {
    final api = await _api();
    if (api == null) return;
    try {
      final data = await api.getThreadAiStatus();
      if (mounted) setState(() => _threadAiEnabled = data['enabled'] == true);
    } catch (_) {
      // 服务端不支持或离线时不显示该项
    }
  }

  Future<void> _toggleThreadAi(bool value) async {
    final api = await _api();
    if (api == null) return;
    setState(() => _threadAiEnabled = value);
    try {
      await api.setThreadAiEnabled(value);
    } catch (e) {
      if (mounted) {
        setState(() => _threadAiEnabled = !value);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('设置失败：$e')));
      }
    }
  }

  Future<void> _runNow() async {
    final api = await _api();
    if (api == null) return;
    setState(() => _running = true);
    try {
      await api.runThreadBatch();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('分析完成')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('分析失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }
```

在 `initState` 中调用 `_loadThreadAi();`。

在页面主体（Provider 卡片列表之后、隐私说明之前）插入：

```dart
        if (_threadAiEnabled != null) ...[
          const Divider(height: 24),
          SwitchListTile(
            value: _threadAiEnabled!,
            activeColor: AppColors.primary,
            title: const Text('自动分析事件关联'),
            subtitle: const Text('每晚 4:00 生成事件串简介并发现可能的关联，仅使用本地模型'),
            onChanged: _toggleThreadAi,
          ),
          ListTile(
            leading: _running
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_circle_outline),
            title: const Text('立即分析'),
            subtitle: const Text('不想等到凌晨时手动跑一次'),
            onTap: _running ? null : _runNow,
          ),
        ],
```

文件顶部补 import：`memos_api_service.dart`、`settings_service.dart`、`app_constants.dart`。

- [ ] **Step 2: 确认编译与全部测试**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter analyze 2>&1 | grep -cE "error •|warning •" && flutter test test/data test/features 2>&1 | tail -c 120
```

Expected: `0` 且 All tests passed

- [ ] **Step 3: Phase 2 完整验收**

按 spec §9 的 Phase 2 标准逐条走：

- [ ] 升级服务端后 `thread-status` 的 `pendingMemos` 为 0，不触发全库分析
- [ ] 新写一篇「今晚又听到蛐蛐了」，点「立即分析」，同步后时间线卡片出现虚线 chip `? 工位蛐蛐`，点 ✓ 即加入且成员正确推送
- [ ] 该建议被忽略后，再次编辑其正文并重跑分析，建议不再出现
- [ ] 批次运行中触发编辑器的标签建议：标签建议正常返回（不 429）
- [ ] 关闭「自动分析事件关联」后重跑，`pendingMemos` 持续累积但不消耗模型
- [ ] 手动改写某事件串简介后，改标题或标记完结，简介不再被 AI 覆盖
- [ ] 对一条 AI 生成的简介点锁定，重跑分析后它不再变化；解锁后恢复生成
- [ ] 删除一篇有待确认建议的日记，该建议不再出现在横幅中

- [ ] **Step 4: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/features/settings/ai_settings_page.dart
git commit -m "feat: AI 设置页事件串分析开关与立即执行"
```

---

## Phase 2 完成标志

- 服务端：四列迁移与存量回填、`thread_suggestions` 表、两个 AI 操作与输出校验、夜间调度器与批处理、前台抢占与退避、六个接口、`server-API.md` 已更新
- 客户端：`ThreadSuggestionEntry` 集合与同步、简介锁定按钮、建议横幅与状态行、时间线虚线 chip、设置页开关与立即分析
- 全部自动化测试通过：`go test ./...` 与 `flutter test test/data test/features`

**不在 Phase 2 范围**：历史日记回扫（Phase 3，必须由用户显式触发，因为 Phase 2 已把存量标记为已扫描）、长期无更新的事件串自动建议完结。
