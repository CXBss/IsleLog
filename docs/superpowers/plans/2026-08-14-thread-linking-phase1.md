# 事件串（Thread）Phase 1 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让多篇相关日记能被手动归入一条命名的「事件串」，并在日记详情页提供上/下一篇导航，使单看一篇不再丢失上下文。

**Architecture:** 服务端新增 `threads` + `thread_members` 两张表与一组 REST 接口，成员以整表全量替换（`PUT`）方式写入，变更通过既有 `change_log` 机制驱动客户端增量同步。客户端新增 `ThreadEntry` Isar 集合，成员以本地 memo id 列表存储，推送时映射为远端 `memosName`；底部导航将「文章」让位给「事件串」。Phase 1 不含任何 AI 能力。

**Tech Stack:** Go 1.25 + Echo v4 + SQLite（modernc.org/sqlite，测试用非加密构建） | Flutter + Isar 3.x + Dio 5.x

**Spec:** `docs/superpowers/specs/2026-08-14-thread-linking-design.md`

## Global Constraints

- 两个仓库：客户端 `/Users/cxb/Code/flutter/memos_local`（分支 `server-feat`）、服务端 `/Users/cxb/Code/go/islelog-back/islelog-server`
- 客户端 API 字段一律以 `server-API.md` 为准，不得凭记忆猜测；本计划新增的接口需同步写入该文档
- 修改任何 Isar `@collection` 模型后必须运行 `dart run build_runner build --delete-conflicting-outputs`
- 服务端所有错误响应统一为 `{"code": 状态码, "message": "中文信息"}`
- 服务端 SQL 建表语句一律 `IF NOT EXISTS`，保证对已有数据库反复执行幂等
- 资源名格式：事件串为 `threads/{id}`，日记为 `memos/{id}`
- 时间字段 API 输出一律 RFC3339 UTC；数据库内一律 Unix 秒
- ID 生成使用 `util.NewID()`（snowflake）
- Phase 1 不引入 `thread_suggestions` 表、不引入 `memos.thread_scan_ts` 列、不调用任何 AI 接口
- 提交信息使用中文，格式 `feat:` / `fix:` / `docs:`

## 测试策略

两个仓库的可测性不同，分别采用其既有模式：

- **服务端**：目前没有任何接触数据库的测试。Task 1 建立一个基于临时文件 SQLite 的测试夹具（`db.Open(tmpdir, "")` 走默认非加密驱动），此后所有 handler 走真实 TDD。
- **客户端**：既有测试（`test/data/database/memo_write_policy_test.dart`）的模式是**把同步决策抽成纯函数单独测试**，不测 Isar 本身。本计划沿用：新增 `thread_membership_policy.dart` 存放全部同步决策逻辑并单测；UI 拆出无状态展示组件做 widget test。Isar 读写与真实网络同步由 Task 5 的 curl 检查点和 Task 13 的手动验收覆盖。
- **导航改版（Task 9）没有自动化测试** —— `MainScaffold` 的子页面依赖已打开的 Isar 实例，widget test 中无法构造。该任务以 `flutter analyze` 通过 + 手动运行确认为准，计划中明确标注。

## File Structure

**服务端（islelog-server）**

| 文件 | 责任 |
|------|------|
| `db/migrate.go` | 修改：`schema` 常量追加两张表 |
| `model/thread.go` | 新建：`Thread` / `ThreadStats` / `ThreadMember` 结构体与 `ToJSON`、`Snippet` |
| `handler/thread.go` | 新建：`ThreadHandler`，CRUD + 成员全量替换 |
| `handler/testutil_test.go` | 新建：测试用 DB / user / echo context 夹具 |
| `handler/thread_test.go` | 新建：`ThreadHandler` 的测试 |
| `model/thread_test.go` | 新建：`ToJSON` / `Snippet` 的纯函数测试 |
| `handler/memo.go` | 修改：`DeleteMemo` 增加 `thread_members` 级联清理 |
| `main.go` | 修改：注册 threads 路由 |
| `server-API.md` | 修改：新增「事件串」章节 |

**客户端（memos_local）**

| 文件 | 责任 |
|------|------|
| `lib/data/models/thread_entry.dart` | 新建：`ThreadEntry` 集合与 `ThreadStatus` 枚举 |
| `lib/data/database/database_service.dart` | 修改：注册 schema + 事件串 CRUD |
| `lib/data/database/thread_membership_policy.dart` | 新建：同步决策纯函数（成员名映射、pull 动作判定） |
| `lib/services/api/memos_api_service.dart` | 修改：threads 接口 |
| `lib/services/sync/sync_service.dart` | 修改：`_pullThreads` / `_pushPendingThreads` |
| `lib/features/threads/threads_view.dart` | 新建：事件串列表页（数据加载） |
| `lib/features/threads/widgets/thread_card.dart` | 新建：列表卡片（无状态，可测） |
| `lib/features/threads/thread_detail_page.dart` | 新建：事件串详情时间线 |
| `lib/features/threads/thread_picker_sheet.dart` | 新建：选择/新建事件串 + 搜索批量加入 |
| `lib/features/memo_detail/widgets/thread_nav_bar.dart` | 新建：上/下一篇导航条（无状态，可测） |
| `lib/shared/widgets/main_scaffold.dart` | 修改：Tab 改版 |
| `lib/features/home/home_view.dart` | 修改：抽屉加「文章」入口 |
| `lib/shared/constants/app_constants.dart` | 修改：新增文案常量 |
| `test/data/database/thread_membership_policy_test.dart` | 新建 |
| `test/features/threads/thread_card_test.dart` | 新建 |
| `test/features/memo_detail/thread_nav_bar_test.dart` | 新建 |

---

# Part A — 服务端

### Task 1: 建表、Thread 模型与测试夹具

**Files:**
- Modify: `db/migrate.go`（`schema` 常量末尾，第 146 行 `idx_revision_details_log` 之后）
- Create: `model/thread.go`
- Create: `model/thread_test.go`
- Create: `handler/testutil_test.go`

**Interfaces:**
- Consumes: `model.FormatID(int64) string`、`db.Open(path, key string) (*sql.DB, error)`
- Produces:
  - `model.Thread{ID, UserID, Title, Summary, SummarySource, Status, CreatedTs, UpdatedTs, RowStatus int64/string}`
  - `func (t *model.Thread) ResourceName() string`
  - `model.ThreadStats{MemberCount int, StartedTs, LastTs int64}`
  - `model.ThreadMember{MemoID int64, Snippet string, DisplayTs int64}`
  - `func (t *model.Thread) ToJSON(stats ThreadStats, members []ThreadMember) map[string]interface{}`（`members` 为 nil 时不输出 `members` 键）
  - `func model.Snippet(content string) string`
  - `func newTestDB(t *testing.T) *sql.DB`
  - `func newTestUser(t *testing.T, database *sql.DB, name string) *model.User`
  - `func newTestContext(t *testing.T, method, target, body string, u *model.User) (echo.Context, *httptest.ResponseRecorder)`

- [ ] **Step 1: 写失败的模型测试**

创建 `model/thread_test.go`：

```go
package model

import "testing"

func TestThreadToJSONOmitsMembersWhenNil(t *testing.T) {
	thread := &Thread{
		ID: 123, UserID: 1, Title: "工位蛐蛐", Summary: "找了两晚没找到",
		SummarySource: "AI", Status: "ACTIVE",
		CreatedTs: 1755000000, UpdatedTs: 1755100000, RowStatus: "NORMAL",
	}

	result := thread.ToJSON(ThreadStats{}, nil)

	if result["name"] != "threads/123" {
		t.Fatalf("name = %v，期望 threads/123", result["name"])
	}
	if result["title"] != "工位蛐蛐" {
		t.Fatalf("title = %v", result["title"])
	}
	if result["memberCount"] != 0 {
		t.Fatalf("memberCount = %v，期望 0", result["memberCount"])
	}
	if _, ok := result["members"]; ok {
		t.Fatal("members 为 nil 时不应输出该键")
	}
	if _, ok := result["startedTime"]; ok {
		t.Fatal("无成员时不应输出 startedTime")
	}
}

func TestThreadToJSONIncludesStatsAndMembers(t *testing.T) {
	thread := &Thread{ID: 123, Title: "工位蛐蛐", Status: "ACTIVE", CreatedTs: 1, UpdatedTs: 2}
	stats := ThreadStats{MemberCount: 2, StartedTs: 1755000000, LastTs: 1755200000}
	members := []ThreadMember{
		{MemoID: 1001, Snippet: "工位附近有蛐蛐", DisplayTs: 1755000000},
		{MemoID: 1002, Snippet: "找了一会没找到", DisplayTs: 1755200000},
	}

	result := thread.ToJSON(stats, members)

	if result["memberCount"] != 2 {
		t.Fatalf("memberCount = %v，期望 2", result["memberCount"])
	}
	if result["startedTime"] != "2025-08-12T13:20:00Z" {
		t.Fatalf("startedTime = %v", result["startedTime"])
	}
	list, ok := result["members"].([]map[string]interface{})
	if !ok || len(list) != 2 {
		t.Fatalf("members = %#v", result["members"])
	}
	if list[0]["memo"] != "memos/1001" {
		t.Fatalf("members[0].memo = %v", list[0]["memo"])
	}
	if list[0]["snippet"] != "工位附近有蛐蛐" {
		t.Fatalf("members[0].snippet = %v", list[0]["snippet"])
	}
}

func TestSnippetCollapsesNewlinesAndTruncates(t *testing.T) {
	if got := Snippet("第一行\n第二行"); got != "第一行 第二行" {
		t.Fatalf("Snippet = %q", got)
	}

	long := ""
	for i := 0; i < 120; i++ {
		long += "字"
	}
	got := Snippet(long)
	if len([]rune(got)) != 100 {
		t.Fatalf("截断后长度 = %d，期望 100", len([]rune(got)))
	}
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./model/ -run TestThread -v
```

Expected: 编译失败，`undefined: Thread`

- [ ] **Step 3: 实现 Thread 模型**

创建 `model/thread.go`：

```go
package model

import (
	"strings"
	"time"
)

// snippetRuneLimit 是成员摘要保留的最大字符数。
const snippetRuneLimit = 100

// Thread 对应 threads 表，表示一条跨多篇日记的事件串。
// 在 API 中以 "threads/{id}" 资源名暴露，属 IsleLog 扩展，标准 Memos 服务端不提供。
type Thread struct {
	ID            int64
	UserID        int64
	Title         string
	Summary       string
	SummarySource string // AI / MANUAL，MANUAL 后 AI 不再覆盖（Phase 2 使用）
	Status        string // ACTIVE / RESOLVED
	CreatedTs     int64
	UpdatedTs     int64
	RowStatus     string // NORMAL / DELETED（软删，供客户端同步删除检测）
}

// ResourceName 返回 API 资源名称，格式为 "threads/{id}"。
func (t *Thread) ResourceName() string {
	return "threads/" + FormatID(t.ID)
}

// ThreadStats 是列表与详情接口现算的聚合值。
//
// 刻意不落库：这些值冗余自成员 memo 的 display_ts，而用户随时可改日记日期，
// 落库会在改期后静默过期且无处触发重算。
type ThreadStats struct {
	MemberCount int
	StartedTs   int64
	LastTs      int64
}

// ThreadMember 是详情接口输出的单个成员。
type ThreadMember struct {
	MemoID    int64
	Snippet   string
	DisplayTs int64
}

// ToJSON 构建事件串的 API 响应 map。
// members 为 nil 时不输出 members 键（列表接口不返回成员详情）。
func (t *Thread) ToJSON(stats ThreadStats, members []ThreadMember) map[string]interface{} {
	result := map[string]interface{}{
		"name":          t.ResourceName(),
		"title":         t.Title,
		"summary":       t.Summary,
		"summarySource": t.SummarySource,
		"status":        t.Status,
		"memberCount":   stats.MemberCount,
		"createTime":    time.Unix(t.CreatedTs, 0).UTC().Format(time.RFC3339),
		"updateTime":    time.Unix(t.UpdatedTs, 0).UTC().Format(time.RFC3339),
	}

	if stats.MemberCount > 0 {
		result["startedTime"] = time.Unix(stats.StartedTs, 0).UTC().Format(time.RFC3339)
		result["lastTime"] = time.Unix(stats.LastTs, 0).UTC().Format(time.RFC3339)
	}

	if members != nil {
		list := make([]map[string]interface{}, 0, len(members))
		for _, m := range members {
			list = append(list, map[string]interface{}{
				"memo":        "memos/" + FormatID(m.MemoID),
				"snippet":     m.Snippet,
				"displayTime": time.Unix(m.DisplayTs, 0).UTC().Format(time.RFC3339),
			})
		}
		result["members"] = list
	}

	return result
}

// Snippet 将日记正文压成单行摘要，换行折叠为空格，超过 100 字符截断。
func Snippet(content string) string {
	flat := strings.Join(strings.Fields(content), " ")
	runes := []rune(flat)
	if len(runes) > snippetRuneLimit {
		return string(runes[:snippetRuneLimit])
	}
	return flat
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./model/ -run "TestThread|TestSnippet" -v
```

Expected: PASS

- [ ] **Step 5: 追加建表语句**

在 `db/migrate.go` 的 `schema` 常量中，`CREATE INDEX IF NOT EXISTS idx_revision_details_log ON memo_revision_details(log_id);` 之后、结尾的反引号之前追加：

```sql

CREATE TABLE IF NOT EXISTS threads (
    id             INTEGER  PRIMARY KEY,
    user_id        INTEGER  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title          TEXT     NOT NULL,
    summary        TEXT     NOT NULL DEFAULT '',
    summary_source TEXT     NOT NULL DEFAULT 'AI',
    status         TEXT     NOT NULL DEFAULT 'ACTIVE',
    created_ts     INTEGER  NOT NULL,
    updated_ts     INTEGER  NOT NULL,
    row_status     TEXT     NOT NULL DEFAULT 'NORMAL'
);

CREATE INDEX IF NOT EXISTS idx_threads_user ON threads(user_id);

CREATE TABLE IF NOT EXISTS thread_members (
    thread_id  INTEGER NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    memo_id    INTEGER NOT NULL REFERENCES memos(id) ON DELETE CASCADE,
    created_ts INTEGER NOT NULL,
    PRIMARY KEY (thread_id, memo_id)
);

CREATE INDEX IF NOT EXISTS idx_thread_members_memo ON thread_members(memo_id);
```

同时在 `schema` 常量上方的表说明注释中追加两行：

```
//	threads             — 事件串：把跨多篇日记的同一件事串成有序时间线
//	thread_members      — 事件串与日记的多对多关系
```

- [ ] **Step 6: 创建测试夹具**

创建 `handler/testutil_test.go`：

```go
package handler

import (
	"database/sql"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"islelog-server/db"
	"islelog-server/middleware"
	"islelog-server/model"
	"islelog-server/util"

	"github.com/labstack/echo/v4"
)

// newTestDB 在临时目录创建一个已完成 schema 迁移的 SQLite 数据库。
// 走默认（非 sqlcipher）构建标签，因此 key 传空字符串。
func newTestDB(t *testing.T) *sql.DB {
	t.Helper()
	path := filepath.Join(t.TempDir(), "test.db")
	database, err := db.Open(path, "")
	if err != nil {
		t.Fatalf("打开测试数据库失败：%v", err)
	}
	t.Cleanup(func() { _ = database.Close() })
	return database
}

// newTestUser 插入一个用户并返回其 model.User。
func newTestUser(t *testing.T, database *sql.DB, name string) *model.User {
	t.Helper()
	now := time.Now().Unix()
	u := &model.User{
		ID: util.NewID(), Name: name, DisplayName: name,
		PasswordHash: "x", Role: "USER",
		CreatedTs: now, UpdatedTs: now, Extra: "{}",
	}
	_, err := database.Exec(
		`INSERT INTO users (id, name, display_name, email, password_hash, role, created_ts, updated_ts, extra)
		 VALUES (?, ?, ?, '', ?, ?, ?, ?, ?)`,
		u.ID, u.Name, u.DisplayName, u.PasswordHash, u.Role, u.CreatedTs, u.UpdatedTs, u.Extra)
	if err != nil {
		t.Fatalf("插入测试用户失败：%v", err)
	}
	return u
}

// newTestMemo 插入一条日记并返回其 ID。
func newTestMemo(t *testing.T, database *sql.DB, u *model.User, content string, displayTs int64) int64 {
	t.Helper()
	id := util.NewID()
	_, err := database.Exec(
		`INSERT INTO memos (id, user_id, content, visibility, row_status, pinned, tags, type, title,
		                    display_ts, created_ts, updated_ts, extra)
		 VALUES (?, ?, ?, 'PRIVATE', 'NORMAL', 0, '[]', 'MEMO', '', ?, ?, ?, '{}')`,
		id, u.ID, content, displayTs, displayTs, displayTs)
	if err != nil {
		t.Fatalf("插入测试日记失败：%v", err)
	}
	return id
}

// newTestContext 构造一个已注入当前用户的 Echo Context。
func newTestContext(t *testing.T, method, target, body string, u *model.User) (echo.Context, *httptest.ResponseRecorder) {
	t.Helper()
	e := echo.New()
	request := httptest.NewRequest(method, target, strings.NewReader(body))
	if body != "" {
		request.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	}
	recorder := httptest.NewRecorder()
	c := e.NewContext(request, recorder)
	c.Set(middleware.UserContextKey, u)
	return c, recorder
}
```

- [ ] **Step 7: 写一个夹具自检测试并运行**

在 `handler/testutil_test.go` 末尾追加：

```go
func TestTestDBHasThreadTables(t *testing.T) {
	database := newTestDB(t)

	for _, table := range []string{"threads", "thread_members"} {
		var name string
		err := database.QueryRow(
			`SELECT name FROM sqlite_master WHERE type='table' AND name=?`, table).Scan(&name)
		if err != nil {
			t.Fatalf("表 %s 不存在：%v", table, err)
		}
	}
}
```

运行：

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./handler/ -run TestTestDBHasThreadTables -v
```

Expected: PASS

- [ ] **Step 8: 提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server
git add db/migrate.go model/thread.go model/thread_test.go handler/testutil_test.go
git commit -m "feat: 新增事件串 threads/thread_members 表与 Thread 模型"
```

---

### Task 2: 事件串 CRUD 接口

**Files:**
- Create: `handler/thread.go`
- Create: `handler/thread_test.go`
- Modify: `main.go`（第 160 行 folders 路由之后）

**Interfaces:**
- Consumes: Task 1 的 `model.Thread` / `ThreadStats` / `ThreadMember` / `Snippet`、`newTestDB` / `newTestUser` / `newTestMemo` / `newTestContext`；既有 `writeChangeLog(db *sql.DB, userID, entityID int64, entity, action string)`（定义于 `handler/memo.go:30`）、`middleware.GetCurrentUser(c) *model.User`、`util.NewID() int64`
- Produces:
  - `func NewThreadHandler(db *sql.DB) *ThreadHandler`
  - `func (h *ThreadHandler) ListThreads(c echo.Context) error`
  - `func (h *ThreadHandler) CreateThread(c echo.Context) error`
  - `func (h *ThreadHandler) GetThread(c echo.Context) error`
  - `func (h *ThreadHandler) UpdateThread(c echo.Context) error`
  - `func (h *ThreadHandler) DeleteThread(c echo.Context) error`
  - `func (h *ThreadHandler) loadThread(id int64) (*model.Thread, error)`（供 Task 3 复用）
  - `func (h *ThreadHandler) loadStats(threadID int64) (model.ThreadStats, error)`（供 Task 3 复用）
  - changelog entity 取值 `"thread"`

- [ ] **Step 1: 写失败的测试**

创建 `handler/thread_test.go`：

```go
package handler

import (
	"encoding/json"
	"net/http"
	"testing"
)

func decodeJSON(t *testing.T, body []byte) map[string]interface{} {
	t.Helper()
	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		t.Fatalf("解析响应失败：%v；原文：%s", err, string(body))
	}
	return result
}

func TestCreateThreadRejectsEmptyTitle(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)

	c, rec := newTestContext(t, http.MethodPost, "/api/v1/threads", `{"title":""}`, u)
	if err := h.CreateThread(c); err != nil {
		t.Fatalf("处理失败：%v", err)
	}

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("状态码 = %d，期望 400", rec.Code)
	}
}

func TestCreateThreadPersistsAndWritesChangeLog(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)

	c, rec := newTestContext(t, http.MethodPost, "/api/v1/threads",
		`{"title":"工位蛐蛐","summary":"刚开始"}`, u)
	if err := h.CreateThread(c); err != nil {
		t.Fatalf("处理失败：%v", err)
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("状态码 = %d，期望 200；响应：%s", rec.Code, rec.Body.String())
	}

	result := decodeJSON(t, rec.Body.Bytes())
	if result["title"] != "工位蛐蛐" {
		t.Fatalf("title = %v", result["title"])
	}
	if result["status"] != "ACTIVE" {
		t.Fatalf("status = %v，期望 ACTIVE", result["status"])
	}
	if result["memberCount"] != float64(0) {
		t.Fatalf("memberCount = %v，期望 0", result["memberCount"])
	}

	var count int
	if err := database.QueryRow(
		`SELECT COUNT(*) FROM change_log WHERE entity='thread' AND action='CREATE'`).Scan(&count); err != nil {
		t.Fatalf("查询 change_log 失败：%v", err)
	}
	if count != 1 {
		t.Fatalf("change_log 条数 = %d，期望 1", count)
	}
}

func TestCreateThreadAcceptsInitialMembers(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	memoID := newTestMemo(t, database, u, "工位附近有蛐蛐在叫", 1755000000)
	h := NewThreadHandler(database)

	body := `{"title":"工位蛐蛐","memos":["memos/` + itoa(memoID) + `"]}`
	c, rec := newTestContext(t, http.MethodPost, "/api/v1/threads", body, u)
	if err := h.CreateThread(c); err != nil {
		t.Fatalf("处理失败：%v", err)
	}

	result := decodeJSON(t, rec.Body.Bytes())
	if result["memberCount"] != float64(1) {
		t.Fatalf("memberCount = %v，期望 1", result["memberCount"])
	}
	if result["startedTime"] != "2025-08-12T13:20:00Z" {
		t.Fatalf("startedTime = %v", result["startedTime"])
	}
}

func TestGetThreadReturnsMembersOrderedByDisplayTs(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	later := newTestMemo(t, database, u, "第三晚又听到了", 1755200000)
	earlier := newTestMemo(t, database, u, "工位附近有蛐蛐在叫", 1755000000)
	h := NewThreadHandler(database)

	body := `{"title":"工位蛐蛐","memos":["memos/` + itoa(later) + `","memos/` + itoa(earlier) + `"]}`
	c, rec := newTestContext(t, http.MethodPost, "/api/v1/threads", body, u)
	if err := h.CreateThread(c); err != nil {
		t.Fatalf("创建失败：%v", err)
	}
	created := decodeJSON(t, rec.Body.Bytes())
	threadID := trimResourcePrefix(created["name"].(string), "threads/")

	c2, rec2 := newTestContext(t, http.MethodGet, "/api/v1/threads/"+threadID, "", u)
	c2.SetParamNames("thread")
	c2.SetParamValues(threadID)
	if err := h.GetThread(c2); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if rec2.Code != http.StatusOK {
		t.Fatalf("状态码 = %d；响应：%s", rec2.Code, rec2.Body.String())
	}

	result := decodeJSON(t, rec2.Body.Bytes())
	members, ok := result["members"].([]interface{})
	if !ok || len(members) != 2 {
		t.Fatalf("members = %#v", result["members"])
	}
	first := members[0].(map[string]interface{})
	if first["memo"] != "memos/"+itoa(earlier) {
		t.Fatalf("首个成员应为最早的日记，实际 = %v", first["memo"])
	}
	if first["snippet"] != "工位附近有蛐蛐在叫" {
		t.Fatalf("snippet = %v", first["snippet"])
	}
}

func TestGetThreadRejectsOtherUsersThread(t *testing.T) {
	database := newTestDB(t)
	owner := newTestUser(t, database, "alice")
	intruder := newTestUser(t, database, "bob")
	h := NewThreadHandler(database)

	c, rec := newTestContext(t, http.MethodPost, "/api/v1/threads", `{"title":"私密事件"}`, owner)
	if err := h.CreateThread(c); err != nil {
		t.Fatalf("创建失败：%v", err)
	}
	threadID := trimResourcePrefix(decodeJSON(t, rec.Body.Bytes())["name"].(string), "threads/")

	c2, rec2 := newTestContext(t, http.MethodGet, "/api/v1/threads/"+threadID, "", intruder)
	c2.SetParamNames("thread")
	c2.SetParamValues(threadID)
	if err := h.GetThread(c2); err != nil {
		t.Fatalf("处理失败：%v", err)
	}
	if rec2.Code != http.StatusForbidden {
		t.Fatalf("状态码 = %d，期望 403", rec2.Code)
	}
}

func TestUpdateThreadMarksSummaryManual(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)

	c, rec := newTestContext(t, http.MethodPost, "/api/v1/threads", `{"title":"工位蛐蛐"}`, u)
	if err := h.CreateThread(c); err != nil {
		t.Fatalf("创建失败：%v", err)
	}
	threadID := trimResourcePrefix(decodeJSON(t, rec.Body.Bytes())["name"].(string), "threads/")

	c2, rec2 := newTestContext(t, http.MethodPatch, "/api/v1/threads/"+threadID,
		`{"summary":"我自己写的简介","status":"RESOLVED"}`, u)
	c2.SetParamNames("thread")
	c2.SetParamValues(threadID)
	if err := h.UpdateThread(c2); err != nil {
		t.Fatalf("更新失败：%v", err)
	}

	result := decodeJSON(t, rec2.Body.Bytes())
	if result["summary"] != "我自己写的简介" {
		t.Fatalf("summary = %v", result["summary"])
	}
	if result["summarySource"] != "MANUAL" {
		t.Fatalf("summarySource = %v，期望 MANUAL", result["summarySource"])
	}
	if result["status"] != "RESOLVED" {
		t.Fatalf("status = %v", result["status"])
	}
}

func TestUpdateThreadRejectsInvalidStatus(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)

	c, rec := newTestContext(t, http.MethodPost, "/api/v1/threads", `{"title":"工位蛐蛐"}`, u)
	if err := h.CreateThread(c); err != nil {
		t.Fatalf("创建失败：%v", err)
	}
	threadID := trimResourcePrefix(decodeJSON(t, rec.Body.Bytes())["name"].(string), "threads/")

	c2, rec2 := newTestContext(t, http.MethodPatch, "/api/v1/threads/"+threadID, `{"status":"DONE"}`, u)
	c2.SetParamNames("thread")
	c2.SetParamValues(threadID)
	if err := h.UpdateThread(c2); err != nil {
		t.Fatalf("处理失败：%v", err)
	}
	if rec2.Code != http.StatusBadRequest {
		t.Fatalf("状态码 = %d，期望 400", rec2.Code)
	}
}

func TestDeleteThreadSoftDeletesAndHidesFromList(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)

	c, rec := newTestContext(t, http.MethodPost, "/api/v1/threads", `{"title":"工位蛐蛐"}`, u)
	if err := h.CreateThread(c); err != nil {
		t.Fatalf("创建失败：%v", err)
	}
	threadID := trimResourcePrefix(decodeJSON(t, rec.Body.Bytes())["name"].(string), "threads/")

	c2, _ := newTestContext(t, http.MethodDelete, "/api/v1/threads/"+threadID, "", u)
	c2.SetParamNames("thread")
	c2.SetParamValues(threadID)
	if err := h.DeleteThread(c2); err != nil {
		t.Fatalf("删除失败：%v", err)
	}

	var rowStatus string
	if err := database.QueryRow(`SELECT row_status FROM threads WHERE id=?`, threadID).Scan(&rowStatus); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if rowStatus != "DELETED" {
		t.Fatalf("row_status = %s，期望 DELETED（软删）", rowStatus)
	}

	c3, rec3 := newTestContext(t, http.MethodGet, "/api/v1/threads", "", u)
	if err := h.ListThreads(c3); err != nil {
		t.Fatalf("列表失败：%v", err)
	}
	list := decodeJSON(t, rec3.Body.Bytes())["threads"].([]interface{})
	if len(list) != 0 {
		t.Fatalf("已软删的事件串不应出现在列表中，实际 %d 条", len(list))
	}
}

func TestListThreadsFiltersByStatus(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)

	for _, title := range []string{"A", "B"} {
		c, _ := newTestContext(t, http.MethodPost, "/api/v1/threads", `{"title":"`+title+`"}`, u)
		if err := h.CreateThread(c); err != nil {
			t.Fatalf("创建失败：%v", err)
		}
	}
	var someID int64
	if err := database.QueryRow(`SELECT id FROM threads WHERE title='B'`).Scan(&someID); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if _, err := database.Exec(`UPDATE threads SET status='RESOLVED' WHERE id=?`, someID); err != nil {
		t.Fatalf("更新失败：%v", err)
	}

	c, rec := newTestContext(t, http.MethodGet, "/api/v1/threads?status=ACTIVE", "", u)
	if err := h.ListThreads(c); err != nil {
		t.Fatalf("列表失败：%v", err)
	}
	list := decodeJSON(t, rec.Body.Bytes())["threads"].([]interface{})
	if len(list) != 1 {
		t.Fatalf("ACTIVE 事件串 = %d 条，期望 1", len(list))
	}
	if list[0].(map[string]interface{})["title"] != "A" {
		t.Fatalf("返回的事件串 = %v", list[0])
	}
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./handler/ -run "TestCreateThread|TestGetThread|TestUpdateThread|TestDeleteThread|TestListThreads" -v
```

Expected: 编译失败，`undefined: NewThreadHandler`、`undefined: itoa`、`undefined: trimResourcePrefix`

- [ ] **Step 3: 实现 ThreadHandler**

创建 `handler/thread.go`：

```go
package handler

import (
	"database/sql"
	"net/http"
	"strconv"
	"strings"
	"time"

	"islelog-server/middleware"
	"islelog-server/model"
	"islelog-server/util"

	"github.com/labstack/echo/v4"
)

type ThreadHandler struct {
	db *sql.DB
}

func NewThreadHandler(db *sql.DB) *ThreadHandler {
	return &ThreadHandler{db: db}
}

// itoa 是 strconv.FormatInt 的短别名，用于拼接资源名。
func itoa(id int64) string { return strconv.FormatInt(id, 10) }

// trimResourcePrefix 去掉资源名前缀，如 "memos/123" → "123"。
// 不带前缀时原样返回，便于兼容裸 ID。
func trimResourcePrefix(name, prefix string) string {
	return strings.TrimPrefix(name, prefix)
}

// parseMemoNames 把 ["memos/1","memos/2"] 解析为去重后的 ID 列表，忽略无法解析的项。
func parseMemoNames(names []string) []int64 {
	seen := map[int64]bool{}
	ids := make([]int64, 0, len(names))
	for _, n := range names {
		id, err := strconv.ParseInt(trimResourcePrefix(n, "memos/"), 10, 64)
		if err != nil || seen[id] {
			continue
		}
		seen[id] = true
		ids = append(ids, id)
	}
	return ids
}

func badRequest(c echo.Context, message string) error {
	return c.JSON(http.StatusBadRequest, map[string]interface{}{"code": 400, "message": message})
}

func serverError(c echo.Context, message string) error {
	return c.JSON(http.StatusInternalServerError, map[string]interface{}{"code": 500, "message": message})
}

// loadThread 按 ID 读取事件串，不做权限判断。
func (h *ThreadHandler) loadThread(id int64) (*model.Thread, error) {
	t := &model.Thread{}
	err := h.db.QueryRow(
		`SELECT id, user_id, title, summary, summary_source, status, created_ts, updated_ts, row_status
		 FROM threads WHERE id=?`, id).
		Scan(&t.ID, &t.UserID, &t.Title, &t.Summary, &t.SummarySource, &t.Status,
			&t.CreatedTs, &t.UpdatedTs, &t.RowStatus)
	if err != nil {
		return nil, err
	}
	return t, nil
}

// loadStats 现算成员数与时间跨度，只统计未删除的日记。
func (h *ThreadHandler) loadStats(threadID int64) (model.ThreadStats, error) {
	var count int
	var started, last sql.NullInt64
	err := h.db.QueryRow(
		`SELECT COUNT(m.id), MIN(m.display_ts), MAX(m.display_ts)
		 FROM thread_members tm
		 JOIN memos m ON m.id = tm.memo_id AND m.row_status = 'NORMAL'
		 WHERE tm.thread_id = ?`, threadID).Scan(&count, &started, &last)
	if err != nil {
		return model.ThreadStats{}, err
	}
	return model.ThreadStats{
		MemberCount: count,
		StartedTs:   started.Int64,
		LastTs:      last.Int64,
	}, nil
}

// loadMembers 按 display_ts 升序返回成员，只含未删除的日记。
func (h *ThreadHandler) loadMembers(threadID int64) ([]model.ThreadMember, error) {
	rows, err := h.db.Query(
		`SELECT m.id, m.content, m.display_ts
		 FROM thread_members tm
		 JOIN memos m ON m.id = tm.memo_id AND m.row_status = 'NORMAL'
		 WHERE tm.thread_id = ?
		 ORDER BY m.display_ts ASC`, threadID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	members := []model.ThreadMember{}
	for rows.Next() {
		var id, displayTs int64
		var content string
		if err := rows.Scan(&id, &content, &displayTs); err != nil {
			continue
		}
		members = append(members, model.ThreadMember{
			MemoID: id, Snippet: model.Snippet(content), DisplayTs: displayTs,
		})
	}
	return members, nil
}

// resolveThread 读取事件串并校验归属，返回值第二项为 false 时响应已写出。
func (h *ThreadHandler) resolveThread(c echo.Context) (*model.Thread, bool) {
	u := middleware.GetCurrentUser(c)
	id, err := strconv.ParseInt(c.Param("thread"), 10, 64)
	if err != nil {
		_ = badRequest(c, "无效ID")
		return nil, false
	}
	t, err := h.loadThread(id)
	if err == sql.ErrNoRows || (err == nil && t.RowStatus == "DELETED") {
		_ = c.JSON(http.StatusNotFound, map[string]interface{}{"code": 404, "message": "未找到"})
		return nil, false
	}
	if err != nil {
		_ = serverError(c, "查询失败")
		return nil, false
	}
	if t.UserID != u.ID {
		_ = c.JSON(http.StatusForbidden, map[string]interface{}{"code": 403, "message": "无权访问"})
		return nil, false
	}
	return t, true
}

func (h *ThreadHandler) ListThreads(c echo.Context) error {
	u := middleware.GetCurrentUser(c)

	query := `SELECT id, user_id, title, summary, summary_source, status, created_ts, updated_ts, row_status
	          FROM threads WHERE user_id=? AND row_status='NORMAL'`
	args := []interface{}{u.ID}
	if status := c.QueryParam("status"); status == "ACTIVE" || status == "RESOLVED" {
		query += ` AND status=?`
		args = append(args, status)
	}
	query += ` ORDER BY updated_ts DESC`

	rows, err := h.db.Query(query, args...)
	if err != nil {
		return serverError(c, "查询失败")
	}
	defer rows.Close()

	threads := []map[string]interface{}{}
	for rows.Next() {
		t := &model.Thread{}
		if err := rows.Scan(&t.ID, &t.UserID, &t.Title, &t.Summary, &t.SummarySource,
			&t.Status, &t.CreatedTs, &t.UpdatedTs, &t.RowStatus); err != nil {
			continue
		}
		stats, err := h.loadStats(t.ID)
		if err != nil {
			continue
		}
		threads = append(threads, t.ToJSON(stats, nil))
	}

	return c.JSON(http.StatusOK, map[string]interface{}{"threads": threads})
}

func (h *ThreadHandler) CreateThread(c echo.Context) error {
	u := middleware.GetCurrentUser(c)

	var req struct {
		Title   string   `json:"title"`
		Summary string   `json:"summary"`
		Memos   []string `json:"memos"`
	}
	if err := c.Bind(&req); err != nil {
		return badRequest(c, "请求格式错误")
	}
	if strings.TrimSpace(req.Title) == "" {
		return badRequest(c, "title 不能为空")
	}

	now := time.Now().Unix()
	t := &model.Thread{
		ID: util.NewID(), UserID: u.ID,
		Title: req.Title, Summary: req.Summary,
		SummarySource: "AI", Status: "ACTIVE",
		CreatedTs: now, UpdatedTs: now, RowStatus: "NORMAL",
	}
	if req.Summary != "" {
		// 创建时带入的简介来自用户输入，AI 不应覆盖
		t.SummarySource = "MANUAL"
	}

	tx, err := h.db.Begin()
	if err != nil {
		return serverError(c, "创建失败")
	}
	defer func() { _ = tx.Rollback() }()

	if _, err := tx.Exec(
		`INSERT INTO threads (id, user_id, title, summary, summary_source, status, created_ts, updated_ts, row_status)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		t.ID, t.UserID, t.Title, t.Summary, t.SummarySource, t.Status, t.CreatedTs, t.UpdatedTs, t.RowStatus); err != nil {
		return serverError(c, "创建失败")
	}
	if err := replaceMembersTx(tx, t.ID, u.ID, parseMemoNames(req.Memos), now); err != nil {
		return serverError(c, "创建失败")
	}
	if err := tx.Commit(); err != nil {
		return serverError(c, "创建失败")
	}

	writeChangeLog(h.db, u.ID, t.ID, "thread", "CREATE")

	stats, err := h.loadStats(t.ID)
	if err != nil {
		return serverError(c, "查询失败")
	}
	return c.JSON(http.StatusOK, t.ToJSON(stats, nil))
}

func (h *ThreadHandler) GetThread(c echo.Context) error {
	t, ok := h.resolveThread(c)
	if !ok {
		return nil
	}
	stats, err := h.loadStats(t.ID)
	if err != nil {
		return serverError(c, "查询失败")
	}
	members, err := h.loadMembers(t.ID)
	if err != nil {
		return serverError(c, "查询失败")
	}
	return c.JSON(http.StatusOK, t.ToJSON(stats, members))
}

func (h *ThreadHandler) UpdateThread(c echo.Context) error {
	u := middleware.GetCurrentUser(c)
	t, ok := h.resolveThread(c)
	if !ok {
		return nil
	}

	var req struct {
		Title   *string `json:"title"`
		Summary *string `json:"summary"`
		Status  *string `json:"status"`
	}
	if err := c.Bind(&req); err != nil {
		return badRequest(c, "请求格式错误")
	}

	if req.Title != nil {
		if strings.TrimSpace(*req.Title) == "" {
			return badRequest(c, "title 不能为空")
		}
		t.Title = *req.Title
	}
	if req.Summary != nil {
		t.Summary = *req.Summary
		// 用户手动改过简介后，Phase 2 的 AI 不再覆盖
		t.SummarySource = "MANUAL"
	}
	if req.Status != nil {
		if *req.Status != "ACTIVE" && *req.Status != "RESOLVED" {
			return badRequest(c, "status 只能为 ACTIVE 或 RESOLVED")
		}
		t.Status = *req.Status
	}
	t.UpdatedTs = time.Now().Unix()

	if _, err := h.db.Exec(
		`UPDATE threads SET title=?, summary=?, summary_source=?, status=?, updated_ts=? WHERE id=?`,
		t.Title, t.Summary, t.SummarySource, t.Status, t.UpdatedTs, t.ID); err != nil {
		return serverError(c, "更新失败")
	}
	writeChangeLog(h.db, u.ID, t.ID, "thread", "UPDATE")

	stats, err := h.loadStats(t.ID)
	if err != nil {
		return serverError(c, "查询失败")
	}
	return c.JSON(http.StatusOK, t.ToJSON(stats, nil))
}

func (h *ThreadHandler) DeleteThread(c echo.Context) error {
	u := middleware.GetCurrentUser(c)
	t, ok := h.resolveThread(c)
	if !ok {
		return nil
	}

	// 软删：thread_members 原样保留，便于恢复
	if _, err := h.db.Exec(
		`UPDATE threads SET row_status='DELETED', updated_ts=? WHERE id=?`,
		time.Now().Unix(), t.ID); err != nil {
		return serverError(c, "删除失败")
	}
	writeChangeLog(h.db, u.ID, t.ID, "thread", "DELETE")

	return c.JSON(http.StatusOK, map[string]interface{}{})
}
```

注意：`replaceMembersTx` 由 Task 3 实现。为让本任务可独立编译通过，先在 `handler/thread.go` 末尾加入其最小实现（Task 3 会补充测试并保持该实现不变）：

```go
// replaceMembersTx 在事务内全量替换事件串成员，只接受属于 userID 的日记。
func replaceMembersTx(tx *sql.Tx, threadID, userID int64, memoIDs []int64, now int64) error {
	if _, err := tx.Exec(`DELETE FROM thread_members WHERE thread_id=?`, threadID); err != nil {
		return err
	}
	for _, memoID := range memoIDs {
		var ownerID int64
		err := tx.QueryRow(`SELECT user_id FROM memos WHERE id=? AND row_status='NORMAL'`, memoID).Scan(&ownerID)
		if err == sql.ErrNoRows || (err == nil && ownerID != userID) {
			// 静默跳过不存在或不属于当前用户的日记
			continue
		}
		if err != nil {
			return err
		}
		if _, err := tx.Exec(
			`INSERT INTO thread_members (thread_id, memo_id, created_ts) VALUES (?, ?, ?)`,
			threadID, memoID, now); err != nil {
			return err
		}
	}
	return nil
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./handler/ -run "TestCreateThread|TestGetThread|TestUpdateThread|TestDeleteThread|TestListThreads" -v
```

Expected: 全部 PASS

- [ ] **Step 5: 注册路由**

在 `main.go` 第 160 行（`api.DELETE("/folders/:folder", folderH.DeleteFolder)`）之后追加：

```go
	// 事件串（IsleLog 扩展）
	threadH := handler.NewThreadHandler(database)
	api.GET("/threads", threadH.ListThreads)
	api.POST("/threads", threadH.CreateThread)
	api.GET("/threads/:thread", threadH.GetThread)
	api.PATCH("/threads/:thread", threadH.UpdateThread)
	api.DELETE("/threads/:thread", threadH.DeleteThread)
```

若 `main.go` 中数据库变量名不是 `database`，改用该文件实际使用的变量名（与 `folderH := handler.NewFolderHandler(...)` 一行保持一致）。

- [ ] **Step 6: 确认整体编译与全量测试通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go build ./... && go test ./...
```

Expected: 编译成功，所有测试 PASS

- [ ] **Step 7: 提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server
git add handler/thread.go handler/thread_test.go main.go
git commit -m "feat: 新增事件串 CRUD 接口"
```

---

### Task 3: 成员全量替换接口

**Files:**
- Modify: `handler/thread.go`（新增 `SetThreadMembers`）
- Modify: `handler/thread_test.go`（追加测试）
- Modify: `main.go`（追加一条路由）

**Interfaces:**
- Consumes: Task 2 的 `replaceMembersTx(tx *sql.Tx, threadID, userID int64, memoIDs []int64, now int64) error`、`parseMemoNames([]string) []int64`、`h.resolveThread(c)`、`h.loadStats(id)`、`h.loadMembers(id)`
- Produces: `func (h *ThreadHandler) SetThreadMembers(c echo.Context) error`，路由 `PUT /api/v1/threads/:thread/members`，响应体与 `GetThread` 一致（含 `members`）

- [ ] **Step 1: 写失败的测试**

在 `handler/thread_test.go` 末尾追加：

```go
func createThreadForTest(t *testing.T, h *ThreadHandler, u *model.User, title string) string {
	t.Helper()
	c, rec := newTestContext(t, http.MethodPost, "/api/v1/threads", `{"title":"`+title+`"}`, u)
	if err := h.CreateThread(c); err != nil {
		t.Fatalf("创建事件串失败：%v", err)
	}
	return trimResourcePrefix(decodeJSON(t, rec.Body.Bytes())["name"].(string), "threads/")
}

func setMembers(t *testing.T, h *ThreadHandler, u *model.User, threadID, body string) map[string]interface{} {
	t.Helper()
	c, rec := newTestContext(t, http.MethodPut, "/api/v1/threads/"+threadID+"/members", body, u)
	c.SetParamNames("thread")
	c.SetParamValues(threadID)
	if err := h.SetThreadMembers(c); err != nil {
		t.Fatalf("设置成员失败：%v", err)
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("状态码 = %d；响应：%s", rec.Code, rec.Body.String())
	}
	return decodeJSON(t, rec.Body.Bytes())
}

func TestSetThreadMembersReplacesWholeList(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)
	first := newTestMemo(t, database, u, "第一篇", 1755000000)
	second := newTestMemo(t, database, u, "第二篇", 1755100000)
	third := newTestMemo(t, database, u, "第三篇", 1755200000)
	threadID := createThreadForTest(t, h, u, "工位蛐蛐")

	setMembers(t, h, u, threadID, `{"memos":["memos/`+itoa(first)+`","memos/`+itoa(second)+`"]}`)
	result := setMembers(t, h, u, threadID, `{"memos":["memos/`+itoa(third)+`"]}`)

	if result["memberCount"] != float64(1) {
		t.Fatalf("memberCount = %v，期望 1（全量替换应移除旧成员）", result["memberCount"])
	}
	members := result["members"].([]interface{})
	if members[0].(map[string]interface{})["memo"] != "memos/"+itoa(third) {
		t.Fatalf("成员 = %v", members[0])
	}
}

func TestSetThreadMembersIsIdempotent(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)
	memoID := newTestMemo(t, database, u, "第一篇", 1755000000)
	threadID := createThreadForTest(t, h, u, "工位蛐蛐")
	body := `{"memos":["memos/` + itoa(memoID) + `"]}`

	setMembers(t, h, u, threadID, body)
	result := setMembers(t, h, u, threadID, body)

	if result["memberCount"] != float64(1) {
		t.Fatalf("重复提交同一列表应幂等，memberCount = %v", result["memberCount"])
	}
}

func TestSetThreadMembersDeduplicatesInput(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)
	memoID := newTestMemo(t, database, u, "第一篇", 1755000000)
	threadID := createThreadForTest(t, h, u, "工位蛐蛐")

	result := setMembers(t, h, u, threadID,
		`{"memos":["memos/`+itoa(memoID)+`","memos/`+itoa(memoID)+`"]}`)

	if result["memberCount"] != float64(1) {
		t.Fatalf("重复 ID 应去重，memberCount = %v", result["memberCount"])
	}
}

func TestSetThreadMembersSkipsForeignMemos(t *testing.T) {
	database := newTestDB(t)
	owner := newTestUser(t, database, "alice")
	other := newTestUser(t, database, "bob")
	h := NewThreadHandler(database)
	mine := newTestMemo(t, database, owner, "我的日记", 1755000000)
	theirs := newTestMemo(t, database, other, "别人的日记", 1755100000)
	threadID := createThreadForTest(t, h, owner, "工位蛐蛐")

	result := setMembers(t, h, owner, threadID,
		`{"memos":["memos/`+itoa(mine)+`","memos/`+itoa(theirs)+`"]}`)

	if result["memberCount"] != float64(1) {
		t.Fatalf("他人日记应被跳过，memberCount = %v", result["memberCount"])
	}
}

func TestSetThreadMembersWritesChangeLogAndBumpsUpdatedTs(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)
	memoID := newTestMemo(t, database, u, "第一篇", 1755000000)
	threadID := createThreadForTest(t, h, u, "工位蛐蛐")

	if _, err := database.Exec(`UPDATE threads SET updated_ts=0 WHERE id=?`, threadID); err != nil {
		t.Fatalf("重置 updated_ts 失败：%v", err)
	}
	setMembers(t, h, u, threadID, `{"memos":["memos/`+itoa(memoID)+`"]}`)

	var updatedTs int64
	if err := database.QueryRow(`SELECT updated_ts FROM threads WHERE id=?`, threadID).Scan(&updatedTs); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if updatedTs == 0 {
		t.Fatal("成员变更后应 bump threads.updated_ts")
	}

	var count int
	if err := database.QueryRow(
		`SELECT COUNT(*) FROM change_log WHERE entity='thread' AND action='UPDATE'`).Scan(&count); err != nil {
		t.Fatalf("查询 change_log 失败：%v", err)
	}
	if count != 1 {
		t.Fatalf("thread UPDATE changelog = %d 条，期望 1", count)
	}
}

func TestSetThreadMembersDoesNotTouchMemoUpdatedTs(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)
	memoID := newTestMemo(t, database, u, "第一篇", 1755000000)
	threadID := createThreadForTest(t, h, u, "工位蛐蛐")

	var before int64
	if err := database.QueryRow(`SELECT updated_ts FROM memos WHERE id=?`, memoID).Scan(&before); err != nil {
		t.Fatalf("查询失败：%v", err)
	}

	setMembers(t, h, u, threadID, `{"memos":["memos/`+itoa(memoID)+`"]}`)

	var after int64
	if err := database.QueryRow(`SELECT updated_ts FROM memos WHERE id=?`, memoID).Scan(&after); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if after != before {
		t.Fatal("成员变更不应改动 memo.updated_ts（否则会把无关日记卷入增量同步）")
	}

	var memoLogs int
	if err := database.QueryRow(
		`SELECT COUNT(*) FROM change_log WHERE entity='memo'`).Scan(&memoLogs); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if memoLogs != 0 {
		t.Fatalf("成员变更不应写 memo 的 changelog，实际 %d 条", memoLogs)
	}
}
```

同时在 `handler/thread_test.go` 的 import 块中加入 `"islelog-server/model"`。

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./handler/ -run TestSetThreadMembers -v
```

Expected: 编译失败，`h.SetThreadMembers undefined`

- [ ] **Step 3: 实现 SetThreadMembers**

在 `handler/thread.go` 的 `DeleteThread` 之后追加：

```go
// SetThreadMembers 全量替换事件串的成员列表。
//
// 刻意不提供单成员的增删接口：离线客户端在恢复网络时需要把一批增删一次性推上来，
// 单条接口会让事件串停在「加了两篇、还差一篇和一个删除」的中间状态，
// 而客户端只有一个 syncStatus 标记位，无法表达这种进度。
// PUT 整个列表则一次原子写、天然幂等，失败原样重发即可。
func (h *ThreadHandler) SetThreadMembers(c echo.Context) error {
	u := middleware.GetCurrentUser(c)
	t, ok := h.resolveThread(c)
	if !ok {
		return nil
	}

	var req struct {
		Memos []string `json:"memos"`
	}
	if err := c.Bind(&req); err != nil {
		return badRequest(c, "请求格式错误")
	}

	now := time.Now().Unix()
	tx, err := h.db.Begin()
	if err != nil {
		return serverError(c, "更新失败")
	}
	defer func() { _ = tx.Rollback() }()

	if err := replaceMembersTx(tx, t.ID, u.ID, parseMemoNames(req.Memos), now); err != nil {
		return serverError(c, "更新失败")
	}
	// 成员变更 bump 事件串自身的 updated_ts，但不触碰成员 memo 的 updated_ts
	if _, err := tx.Exec(`UPDATE threads SET updated_ts=? WHERE id=?`, now, t.ID); err != nil {
		return serverError(c, "更新失败")
	}
	if err := tx.Commit(); err != nil {
		return serverError(c, "更新失败")
	}
	t.UpdatedTs = now

	writeChangeLog(h.db, u.ID, t.ID, "thread", "UPDATE")

	stats, err := h.loadStats(t.ID)
	if err != nil {
		return serverError(c, "查询失败")
	}
	members, err := h.loadMembers(t.ID)
	if err != nil {
		return serverError(c, "查询失败")
	}
	return c.JSON(http.StatusOK, t.ToJSON(stats, members))
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./handler/ -run TestSetThreadMembers -v
```

Expected: 全部 PASS

- [ ] **Step 5: 注册路由**

在 `main.go` 的 `api.DELETE("/threads/:thread", threadH.DeleteThread)` 之后追加：

```go
	api.PUT("/threads/:thread/members", threadH.SetThreadMembers)
```

- [ ] **Step 6: 全量测试**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go build ./... && go test ./...
```

Expected: 全部 PASS

- [ ] **Step 7: 提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server
git add handler/thread.go handler/thread_test.go main.go
git commit -m "feat: 事件串成员全量替换接口"
```

---

### Task 4: 删除日记时级联清理成员

**Files:**
- Modify: `handler/memo.go`（`DeleteMemo`，第 443-447 行附近）
- Modify: `handler/thread_test.go`（追加测试）

**Interfaces:**
- Consumes: Task 2 的 changelog entity `"thread"`；既有 `h.memoSvc.SoftDelete(id)`、`writeChangeLog`
- Produces: `func cascadeRemoveMemoFromThreads(db *sql.DB, userID, memoID int64) error` —— 从所有事件串中移除该日记，为每个受影响的事件串 bump `updated_ts` 并写一条 `thread` 的 UPDATE changelog

- [ ] **Step 1: 写失败的测试**

在 `handler/thread_test.go` 末尾追加：

```go
func TestCascadeRemoveMemoFromThreadsUpdatesAffectedThreads(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	h := NewThreadHandler(database)
	memoID := newTestMemo(t, database, u, "被删的日记", 1755000000)
	keptID := newTestMemo(t, database, u, "保留的日记", 1755100000)

	threadA := createThreadForTest(t, h, u, "事件A")
	threadB := createThreadForTest(t, h, u, "事件B")
	setMembers(t, h, u, threadA, `{"memos":["memos/`+itoa(memoID)+`","memos/`+itoa(keptID)+`"]}`)
	setMembers(t, h, u, threadB, `{"memos":["memos/`+itoa(memoID)+`"]}`)

	if _, err := database.Exec(`DELETE FROM change_log`); err != nil {
		t.Fatalf("清空 change_log 失败：%v", err)
	}
	if _, err := database.Exec(`UPDATE threads SET updated_ts=0`); err != nil {
		t.Fatalf("重置 updated_ts 失败：%v", err)
	}

	if err := cascadeRemoveMemoFromThreads(database, u.ID, memoID); err != nil {
		t.Fatalf("级联清理失败：%v", err)
	}

	var remaining int
	if err := database.QueryRow(
		`SELECT COUNT(*) FROM thread_members WHERE memo_id=?`, memoID).Scan(&remaining); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if remaining != 0 {
		t.Fatalf("成员行应被清除，实际剩余 %d 行", remaining)
	}

	var keptRows int
	if err := database.QueryRow(
		`SELECT COUNT(*) FROM thread_members WHERE memo_id=?`, keptID).Scan(&keptRows); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if keptRows != 1 {
		t.Fatalf("其他成员不应受影响，实际 %d 行", keptRows)
	}

	var logs int
	if err := database.QueryRow(
		`SELECT COUNT(*) FROM change_log WHERE entity='thread' AND action='UPDATE'`).Scan(&logs); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if logs != 2 {
		t.Fatalf("两个受影响的事件串各应写一条 changelog，实际 %d 条", logs)
	}

	var stale int
	if err := database.QueryRow(`SELECT COUNT(*) FROM threads WHERE updated_ts=0`).Scan(&stale); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if stale != 0 {
		t.Fatal("受影响的事件串应 bump updated_ts")
	}
}

func TestCascadeRemoveMemoWithNoThreadsIsNoop(t *testing.T) {
	database := newTestDB(t)
	u := newTestUser(t, database, "alice")
	memoID := newTestMemo(t, database, u, "孤立日记", 1755000000)

	if err := cascadeRemoveMemoFromThreads(database, u.ID, memoID); err != nil {
		t.Fatalf("无归属时不应报错：%v", err)
	}

	var logs int
	if err := database.QueryRow(`SELECT COUNT(*) FROM change_log`).Scan(&logs); err != nil {
		t.Fatalf("查询失败：%v", err)
	}
	if logs != 0 {
		t.Fatalf("无归属时不应写 changelog，实际 %d 条", logs)
	}
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go test ./handler/ -run TestCascadeRemoveMemo -v
```

Expected: 编译失败，`undefined: cascadeRemoveMemoFromThreads`

- [ ] **Step 3: 实现级联清理**

在 `handler/thread.go` 末尾追加：

```go
// cascadeRemoveMemoFromThreads 在日记被删除时，把它从所有事件串中摘掉。
//
// 走 idx_thread_members_memo 反查受影响的事件串，逐个 bump updated_ts 并写
// changelog，使客户端能通过增量同步感知成员变化。
func cascadeRemoveMemoFromThreads(database *sql.DB, userID, memoID int64) error {
	rows, err := database.Query(`SELECT thread_id FROM thread_members WHERE memo_id=?`, memoID)
	if err != nil {
		return err
	}
	threadIDs := []int64{}
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			continue
		}
		threadIDs = append(threadIDs, id)
	}
	rows.Close()

	if len(threadIDs) == 0 {
		return nil
	}

	now := time.Now().Unix()
	if _, err := database.Exec(`DELETE FROM thread_members WHERE memo_id=?`, memoID); err != nil {
		return err
	}
	for _, threadID := range threadIDs {
		if _, err := database.Exec(
			`UPDATE threads SET updated_ts=? WHERE id=?`, now, threadID); err != nil {
			return err
		}
		writeChangeLog(database, userID, threadID, "thread", "UPDATE")
	}
	return nil
}
```

- [ ] **Step 4: 接入 DeleteMemo**

在 `handler/memo.go` 的 `DeleteMemo` 中，`writeChangeLog(h.db, u.ID, id, "memo", "DELETE")`（第 447 行）**之前**插入：

```go
	// 日记被删除后从所有事件串中摘掉，并让受影响的事件串进入增量同步
	if err := cascadeRemoveMemoFromThreads(h.db, u.ID, id); err != nil {
		log.Printf("cascade remove memo from threads error: %v", err)
	}
```

`handler/memo.go` 已 import `"log"`，无需新增 import。

- [ ] **Step 5: 运行测试确认通过**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go build ./... && go test ./...
```

Expected: 全部 PASS

- [ ] **Step 6: 提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server
git add handler/thread.go handler/thread_test.go handler/memo.go
git commit -m "feat: 删除日记时从事件串中级联移除"
```

---

### Task 5: 补充 API 文档并端到端验证服务端

这是**服务端检查点** —— 完成后服务端可独立于客户端验证。

**Files:**
- Modify: `server-API.md`（在「文件夹」章节之后、「变更日志」章节之前）

- [ ] **Step 1: 补充 API 文档**

在 `server-API.md` 的 `## 变更日志（增量同步）` 一行之前插入：

````markdown
## 事件串

> **仅适用于 IsleLog 自建服务**，不属于标准 Memos v0.25 API。
>
> 事件串把跨多篇日记的同一件事串成有序时间线。成员按日记的 `displayTime` 升序排列，
> 服务端不存顺序字段。`memberCount` / `startedTime` / `lastTime` 均为查询时现算。

### 列表
`GET /api/v1/threads` **[IsleLog 扩展]**

| 参数 | 类型 | 说明 |
|------|------|------|
| `status` | string | `ACTIVE` / `RESOLVED`，不传返回全部 |

按 `updateTime` 倒序返回，不含 `members`。

**响应**
```json
{ "threads": [ /* Thread 对象数组 */ ] }
```

---

### 创建
`POST /api/v1/threads` **[IsleLog 扩展]**

**请求体**
```json
{
  "title": "工位蛐蛐",
  "summary": "",
  "memos": ["memos/1001", "memos/1002"]
}
```

`title` 必填非空。`memos` 可选，传入则作为初始成员；不属于当前用户或已删除的日记被静默跳过。
`summary` 非空时 `summarySource` 记为 `MANUAL`。

---

### 获取单条
`GET /api/v1/threads/:id` **[IsleLog 扩展]**

响应含 `members` 数组。已软删的事件串返回 404。

---

### 更新
`PATCH /api/v1/threads/:id` **[IsleLog 扩展]**

| 字段 | 说明 |
|------|------|
| `title` | 标题，传入时不可为空 |
| `summary` | 简介；一旦传入，`summarySource` 置为 `MANUAL` |
| `status` | `ACTIVE` / `RESOLVED`，其他值返回 400 |

---

### 删除
`DELETE /api/v1/threads/:id` **[IsleLog 扩展]**

软删除（`row_status=DELETED`），成员关系原样保留以便恢复。写入 `thread` 的 DELETE 变更日志。

---

### 设置成员
`PUT /api/v1/threads/:id/members` **[IsleLog 扩展]**

**请求体**
```json
{ "memos": ["memos/1001", "memos/1002"] }
```

全量替换成员列表，天然幂等；输入自动去重，不属于当前用户或已删除的日记被静默跳过。
响应与「获取单条」一致（含 `members`）。

> 刻意不提供单成员的增删接口：离线客户端需把一批增删一次性推上来，
> 单条接口会让事件串停在中间状态而客户端无法表达该进度。
>
> 成员变更只 bump `threads.updated_ts` 并写 `thread` 的 UPDATE 变更日志，
> **不触碰成员 memo 的 `updated_ts`**，避免把无关日记卷入增量同步。

---

## Thread 响应结构

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
    {
      "memo": "memos/1001",
      "snippet": "工位附近有蛐蛐在叫……",
      "displayTime": "2026-08-11T09:00:00Z"
    }
  ]
}
```

> `members` 仅在「获取单条」和「设置成员」的响应中输出。
> `memberCount` 为 0 时不输出 `startedTime` / `lastTime`。

---
````

同时更新 `server-API.md` 的「变更日志」章节中 entity 取值说明，把：

```
> `action` 取值：`CREATE` / `UPDATE` / `DELETE`。`entity` 取值：`memo` / `article` / `comment` / `attachment`。
```

改为：

```
> `action` 取值：`CREATE` / `UPDATE` / `DELETE`。`entity` 取值：`memo` / `article` / `comment` / `attachment` / `thread`。
>
> `entity=thread` 时，`entityId` 格式为 `threads/{id}`，用 `GET /api/v1/threads/{id}` 拉取（响应含全部成员，无需成员级增量）。
```

- [ ] **Step 2: 启动服务端**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server && go run . &
```

等待启动后确认健康检查：

```bash
curl -s http://localhost:8080/healthz
```

Expected: `{"status":"ok"}`

（若端口不是 8080，以 `config/config.go` 中的默认值为准。）

- [ ] **Step 3: 端到端手动验证**

用真实账号登录取 token，然后依次执行。把 `$TOKEN`、`$M1`、`$M2` 换成实际值：

```bash
# 1. 创建两篇日记，记下返回的 name
curl -s -X POST http://localhost:8080/api/v1/memos \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"content":"工位附近有蛐蛐在叫 #日常","createTime":"2026-08-11T09:00:00Z"}'

curl -s -X POST http://localhost:8080/api/v1/memos \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"content":"晚上去找了一会没找到","createTime":"2026-08-11T22:00:00Z"}'

# 2. 创建事件串并带入两篇日记
curl -s -X POST http://localhost:8080/api/v1/threads \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d "{\"title\":\"工位蛐蛐\",\"memos\":[\"$M1\",\"$M2\"]}"

# 3. 详情应返回按时间升序的两个成员
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/threads/$THREAD_ID

# 4. 全量替换为只剩一篇
curl -s -X PUT http://localhost:8080/api/v1/threads/$THREAD_ID/members \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d "{\"memos\":[\"$M1\"]}"

# 5. changelog 中应出现 thread 条目
curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:8080/api/v1/changelogs?sinceId=-1" | grep thread
```

逐条核对：

- [ ] 步骤 2 返回的 `memberCount` 为 2，`startedTime` 为最早日记的时间
- [ ] 步骤 3 的 `members[0].memo` 是较早的那篇，`snippet` 为正文单行摘要
- [ ] 步骤 4 后 `memberCount` 变为 1
- [ ] 步骤 5 能查到 `"entity":"thread"` 的记录
- [ ] 删除一篇成员日记后，再查该事件串，`memberCount` 相应减少

- [ ] **Step 4: 提交**

```bash
cd /Users/cxb/Code/go/islelog-back/islelog-server
git add server-API.md
git commit -m "docs: 补充事件串接口文档"
```

**Phase 1 服务端到此完成。** 后续任务全部在 Flutter 仓库。

---

# Part B — 客户端

### Task 6: ThreadEntry 模型与数据库 CRUD

**Files:**
- Create: `lib/data/models/thread_entry.dart`
- Modify: `lib/data/database/database_service.dart`（第 33 行 schema 列表；文件末尾追加 CRUD）

**Interfaces:**
- Consumes: `SyncStatus`（定义于 `lib/data/models/memo_entry.dart`）
- Produces:
  - `enum ThreadStatus { active, resolved }`
  - `class ThreadEntry { int id; String? threadName; String title; String summary; bool summaryIsManual; ThreadStatus status; List<int> memberLocalIds; DateTime createdAt; DateTime updatedAt; SyncStatus syncStatus; DateTime? lastSyncAt; bool isDeleted; }`
  - `DatabaseService.saveThread(ThreadEntry, {bool skipTimestamp}) → Future<int>`
  - `DatabaseService.getThreadById(int) → Future<ThreadEntry?>`
  - `DatabaseService.getThreadByThreadName(String) → Future<ThreadEntry?>`
  - `DatabaseService.getAllThreads({bool includeDeleted}) → Future<List<ThreadEntry>>`
  - `DatabaseService.getThreadsForMemo(int memoLocalId) → Future<List<ThreadEntry>>`
  - `DatabaseService.getPendingSyncThreads() → Future<List<ThreadEntry>>`
  - `DatabaseService.getAllSyncedThreads() → Future<List<ThreadEntry>>`
  - `DatabaseService.softDeleteThread(int) → Future<void>`
  - `DatabaseService.hardDeleteThread(int) → Future<bool>`
  - `DatabaseService.removeMemoFromAllThreads(int memoLocalId) → Future<void>`

- [ ] **Step 1: 创建模型**

创建 `lib/data/models/thread_entry.dart`：

```dart
import 'package:isar/isar.dart';

import 'memo_entry.dart';

part 'thread_entry.g.dart';

/// 事件串状态
enum ThreadStatus {
  active,   // 进行中
  resolved, // 已完结
}

/// 事件串本地数据模型
///
/// 把跨多篇日记的同一件事串成有序时间线。成员按对应日记的 createdAt 排序，
/// 不存顺序字段——日记本身就是时间事件，再存手工顺序会与日期编辑打架。
@collection
class ThreadEntry {
  /// 本地自增主键
  Id id = Isar.autoIncrement;

  /// 远端资源名，格式为 "threads/{id}"，未同步时为 null
  ///
  /// 不设 unique 索引：未同步的事件串 threadName 均为 null，
  /// Isar 会将多个 null 视为重复键。
  @Index()
  String? threadName;

  /// 标题，如「工位蛐蛐」
  String title = '';

  /// 一句话进展简介（Phase 2 由 AI 生成）
  String summary = '';

  /// 用户是否手动改写过简介；为 true 时 Phase 2 的 AI 不再覆盖
  bool summaryIsManual = false;

  /// 事件串状态
  @enumerated
  ThreadStatus status = ThreadStatus.active;

  /// 成员日记的本地 id 列表
  ///
  /// 建 value 索引以支持「这篇日记属于哪些事件串」的反查。
  /// 不建独立的成员集合：事件串是几十个量级，正查反查都是一次索引查询。
  @Index(type: IndexType.value)
  List<int> memberLocalIds = [];

  /// 创建时间
  DateTime createdAt = DateTime.now();

  /// 最后更新时间（同步冲突判定依据）
  DateTime updatedAt = DateTime.now();

  /// 同步状态
  @enumerated
  SyncStatus syncStatus = SyncStatus.pending;

  /// 最后一次成功同步时间
  DateTime? lastSyncAt;

  /// 软删除标记
  bool isDeleted = false;
}
```

- [ ] **Step 2: 注册 schema 并运行代码生成**

修改 `lib/data/database/database_service.dart` 第 33 行：

```dart
      [MemoEntrySchema, TagStatSchema, CommentEntrySchema, ArticleEntrySchema, FolderEntrySchema, ThreadEntrySchema],
```

在该文件顶部 import 区加入：

```dart
import '../models/thread_entry.dart';
```

运行代码生成：

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: 生成 `lib/data/models/thread_entry.g.dart`，无错误

- [ ] **Step 3: 实现 CRUD**

在 `lib/data/database/database_service.dart` 末尾（类的最后一个方法之后、闭合大括号之前）追加：

```dart
  // ────────────────────────────────────────────────────────────────
  // 事件串（ThreadEntry）
  // ────────────────────────────────────────────────────────────────

  /// 新建或更新一个事件串。
  static Future<int> saveThread(ThreadEntry thread,
      {bool skipTimestamp = false}) async {
    final isar = await db;
    if (!skipTimestamp) thread.updatedAt = DateTime.now();
    final id = await isar.writeTxn(() => isar.threadEntrys.put(thread));
    debugPrint('[DB] saveThread → id=$id title="${thread.title}"');
    return id;
  }

  static Future<ThreadEntry?> getThreadById(int id) async {
    final isar = await db;
    return isar.threadEntrys.get(id);
  }

  static Future<ThreadEntry?> getThreadByThreadName(String threadName) async {
    final isar = await db;
    return isar.threadEntrys
        .filter()
        .threadNameEqualTo(threadName)
        .findFirst();
  }

  /// 返回全部未删除的事件串，按 updatedAt 倒序。
  static Future<List<ThreadEntry>> getAllThreads(
      {bool includeDeleted = false}) async {
    final isar = await db;
    final query = includeDeleted
        ? isar.threadEntrys.filter().idGreaterThan(-1)
        : isar.threadEntrys.filter().isDeletedEqualTo(false);
    final result = await query.sortByUpdatedAtDesc().findAll();
    debugPrint('[DB] getAllThreads → ${result.length} 个');
    return result;
  }

  /// 反查某篇日记所属的全部事件串（走 memberLocalIds 的 value 索引）。
  static Future<List<ThreadEntry>> getThreadsForMemo(int memoLocalId) async {
    final isar = await db;
    return isar.threadEntrys
        .filter()
        .isDeletedEqualTo(false)
        .memberLocalIdsElementEqualTo(memoLocalId)
        .sortByUpdatedAtDesc()
        .findAll();
  }

  static Future<List<ThreadEntry>> getPendingSyncThreads() async {
    final isar = await db;
    final result = await isar.threadEntrys
        .filter()
        .syncStatusEqualTo(SyncStatus.pending)
        .findAll();
    debugPrint('[DB] getPendingSyncThreads → ${result.length} 个待同步');
    return result;
  }

  static Future<List<ThreadEntry>> getAllSyncedThreads() async {
    final isar = await db;
    return isar.threadEntrys
        .filter()
        .syncStatusEqualTo(SyncStatus.synced)
        .findAll();
  }

  /// 软删除事件串（成员关系保留，便于恢复）。
  static Future<void> softDeleteThread(int id) async {
    final isar = await db;
    final thread = await isar.threadEntrys.get(id);
    if (thread == null) return;
    thread
      ..isDeleted = true
      ..syncStatus = SyncStatus.pending
      ..updatedAt = DateTime.now();
    await isar.writeTxn(() => isar.threadEntrys.put(thread));
    debugPrint('[DB] softDeleteThread: id=$id');
  }

  /// 物理删除事件串（同步确认后调用）。
  static Future<bool> hardDeleteThread(int id) async {
    final isar = await db;
    final deleted = await isar.writeTxn(() => isar.threadEntrys.delete(id));
    debugPrint('[DB] hardDeleteThread: id=$id, 成功=$deleted');
    return deleted;
  }

  /// 日记被删除时从所有事件串中摘掉，受影响的事件串置为 pending 待推送。
  static Future<void> removeMemoFromAllThreads(int memoLocalId) async {
    final isar = await db;
    final affected = await isar.threadEntrys
        .filter()
        .memberLocalIdsElementEqualTo(memoLocalId)
        .findAll();
    if (affected.isEmpty) return;

    await isar.writeTxn(() async {
      for (final thread in affected) {
        thread
          ..memberLocalIds =
              thread.memberLocalIds.where((e) => e != memoLocalId).toList()
          ..syncStatus = SyncStatus.pending
          ..updatedAt = DateTime.now();
      }
      await isar.threadEntrys.putAll(affected);
    });
    debugPrint('[DB] removeMemoFromAllThreads: memo=$memoLocalId，影响 ${affected.length} 个事件串');
  }
```

- [ ] **Step 4: 接入日记删除**

在 `lib/data/database/database_service.dart` 的 `softDelete`（软删除日记）方法末尾，返回之前调用：

```dart
    await removeMemoFromAllThreads(id);
```

若 `softDelete` 的参数名不是 `id`，改用其实际的日记本地 id 变量名。

- [ ] **Step 5: 确认编译通过**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter analyze
```

Expected: No issues found

- [ ] **Step 6: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/data/models/thread_entry.dart lib/data/models/thread_entry.g.dart lib/data/database/database_service.dart
git commit -m "feat: 新增 ThreadEntry 模型与事件串数据库操作"
```

---

### Task 7: 同步决策纯函数

把全部同步判定逻辑抽成不依赖 Isar 的纯函数，沿用 `memo_write_policy.dart` 的既有模式。

**Files:**
- Create: `lib/data/database/thread_membership_policy.dart`
- Create: `test/data/database/thread_membership_policy_test.dart`

**Interfaces:**
- Consumes: `SyncStatus`、`ThreadEntry`、`ThreadStatus`
- Produces:
  - `enum ThreadPullAction { insert, overwrite, markConflict, skip }`
  - `ThreadPullAction decideThreadPull({required ThreadEntry? local, required DateTime remoteUpdatedAt})`
  - `class ThreadMemberResolution { final List<String> memoNames; final bool complete; }`
  - `ThreadMemberResolution resolveThreadMemberNames(List<int> memberLocalIds, Map<int, String?> memosNameByLocalId)`
  - `List<int> mapRemoteMembersToLocalIds(List<String> memoNames, Map<String, int> localIdByMemosName)`

- [ ] **Step 1: 写失败的测试**

创建 `test/data/database/thread_membership_policy_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/database/thread_membership_policy.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/data/models/thread_entry.dart';

ThreadEntry _thread({
  required SyncStatus syncStatus,
  required DateTime updatedAt,
}) =>
    ThreadEntry()
      ..syncStatus = syncStatus
      ..updatedAt = updatedAt;

void main() {
  group('decideThreadPull', () {
    final remote = DateTime(2026, 8, 14, 10);

    test('inserts when there is no local copy', () {
      expect(
        decideThreadPull(local: null, remoteUpdatedAt: remote),
        ThreadPullAction.insert,
      );
    });

    test('overwrites a synced local copy', () {
      final local = _thread(
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 8, 14, 9),
      );
      expect(
        decideThreadPull(local: local, remoteUpdatedAt: remote),
        ThreadPullAction.overwrite,
      );
    });

    test('marks conflict when local is pending and remote is newer', () {
      final local = _thread(
        syncStatus: SyncStatus.pending,
        updatedAt: DateTime(2026, 8, 14, 9),
      );
      expect(
        decideThreadPull(local: local, remoteUpdatedAt: remote),
        ThreadPullAction.markConflict,
      );
    });

    test('skips when local pending edit is newer than remote', () {
      final local = _thread(
        syncStatus: SyncStatus.pending,
        updatedAt: DateTime(2026, 8, 14, 11),
      );
      expect(
        decideThreadPull(local: local, remoteUpdatedAt: remote),
        ThreadPullAction.skip,
      );
    });

    test('skips an already conflicted local copy', () {
      final local = _thread(
        syncStatus: SyncStatus.conflict,
        updatedAt: DateTime(2026, 8, 14, 9),
      );
      expect(
        decideThreadPull(local: local, remoteUpdatedAt: remote),
        ThreadPullAction.skip,
      );
    });
  });

  group('resolveThreadMemberNames', () {
    test('resolves every member when all memos are synced', () {
      final result = resolveThreadMemberNames(
        [1, 2],
        {1: 'memos/1001', 2: 'memos/1002'},
      );

      expect(result.complete, isTrue);
      expect(result.memoNames, ['memos/1001', 'memos/1002']);
    });

    test('reports incomplete when a member has not been pushed yet', () {
      final result = resolveThreadMemberNames(
        [1, 2],
        {1: 'memos/1001', 2: null},
      );

      expect(result.complete, isFalse);
      expect(result.memoNames, ['memos/1001']);
    });

    test('treats an unknown local id as unresolved', () {
      final result = resolveThreadMemberNames([1, 99], {1: 'memos/1001'});

      expect(result.complete, isFalse);
      expect(result.memoNames, ['memos/1001']);
    });

    test('is complete for an empty member list', () {
      final result = resolveThreadMemberNames([], {});

      expect(result.complete, isTrue);
      expect(result.memoNames, isEmpty);
    });
  });

  group('mapRemoteMembersToLocalIds', () {
    test('maps known remote names to local ids', () {
      final result = mapRemoteMembersToLocalIds(
        ['memos/1001', 'memos/1002'],
        {'memos/1001': 1, 'memos/1002': 2},
      );

      expect(result, [1, 2]);
    });

    test('drops members whose memo is missing locally', () {
      final result = mapRemoteMembersToLocalIds(
        ['memos/1001', 'memos/9999'],
        {'memos/1001': 1},
      );

      expect(result, [1]);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter test test/data/database/thread_membership_policy_test.dart
```

Expected: 编译失败，找不到 `thread_membership_policy.dart`

- [ ] **Step 3: 实现纯函数**

创建 `lib/data/database/thread_membership_policy.dart`：

```dart
import '../models/memo_entry.dart';
import '../models/thread_entry.dart';

/// Pull 时对单个远端事件串应采取的动作
enum ThreadPullAction {
  insert,       // 本地没有 → 新增
  overwrite,    // 本地已同步 → 覆盖为远端版本
  markConflict, // 本地有未推送改动且远端更新 → 保留本地并标记冲突
  skip,         // 本地更新或已处于冲突 → 不动
}

/// 判定 Pull 时对某个远端事件串的处理方式。
///
/// 事件串整体（标题/简介/状态/成员）按 last-write-wins 比较 [ThreadEntry.updatedAt]，
/// 与既有 memo 的冲突处理保持一致：冲突时保留本地版本，等用户处理后再推送。
ThreadPullAction decideThreadPull({
  required ThreadEntry? local,
  required DateTime remoteUpdatedAt,
}) {
  if (local == null) return ThreadPullAction.insert;
  switch (local.syncStatus) {
    case SyncStatus.synced:
      return ThreadPullAction.overwrite;
    case SyncStatus.conflict:
      return ThreadPullAction.skip;
    case SyncStatus.pending:
      return remoteUpdatedAt.isAfter(local.updatedAt)
          ? ThreadPullAction.markConflict
          : ThreadPullAction.skip;
  }
}

/// [resolveThreadMemberNames] 的结果
class ThreadMemberResolution {
  /// 已解析出远端资源名的成员
  final List<String> memoNames;

  /// 是否全部成员都解析成功；为 false 时本次推送应保持 pending，下轮补齐
  final bool complete;

  const ThreadMemberResolution({required this.memoNames, required this.complete});
}

/// 把成员的本地 memo id 映射为远端资源名。
///
/// 离线新建的日记还没有 memosName，此时无法作为成员推送。返回 [complete] = false，
/// 调用方应保持事件串为 pending，待日记推送成功后的下一轮同步再补齐。
ThreadMemberResolution resolveThreadMemberNames(
  List<int> memberLocalIds,
  Map<int, String?> memosNameByLocalId,
) {
  final names = <String>[];
  var complete = true;
  for (final localId in memberLocalIds) {
    final name = memosNameByLocalId[localId];
    if (name == null || name.isEmpty) {
      complete = false;
      continue;
    }
    names.add(name);
  }
  return ThreadMemberResolution(memoNames: names, complete: complete);
}

/// 把远端成员资源名映射回本地 memo id，本地不存在的成员被丢弃。
///
/// 丢弃是安全的：该日记要么还没拉下来（下轮同步补上），要么已在本地删除。
List<int> mapRemoteMembersToLocalIds(
  List<String> memoNames,
  Map<String, int> localIdByMemosName,
) {
  final ids = <int>[];
  for (final name in memoNames) {
    final localId = localIdByMemosName[name];
    if (localId != null) ids.add(localId);
  }
  return ids;
}
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
git commit -m "feat: 新增事件串同步决策纯函数"
```

---

### Task 8: API 客户端接口

**Files:**
- Modify: `lib/services/api/memos_api_service.dart`（在文件夹相关方法之后追加）

**Interfaces:**
- Consumes: 既有 `_dio`、`_wrap(DioException)`
- Produces:
  - `Future<List<Map<String, dynamic>>> listThreads({String? status})`
  - `Future<Map<String, dynamic>> getThread(String name)`
  - `Future<Map<String, dynamic>> createThread({required String title, String? summary, List<String>? memos})`
  - `Future<Map<String, dynamic>> updateThread({required String name, String? title, String? summary, String? status})`
  - `Future<void> deleteThread(String name)`
  - `Future<Map<String, dynamic>> setThreadMembers({required String name, required List<String> memos})`

其中 `name` 均为完整资源名 `threads/{id}`。

- [ ] **Step 1: 实现接口**

在 `lib/services/api/memos_api_service.dart` 的 `deleteFolder` 方法之后追加：

```dart
  // ────────────────────────────────────────────────────────────────
  // 事件串（IsleLog 扩展，标准 Memos 服务端返回 404）
  // ────────────────────────────────────────────────────────────────

  /// 列出事件串（不含成员详情）
  Future<List<Map<String, dynamic>>> listThreads({String? status}) async {
    debugPrint('[API] listThreads status=$status');
    try {
      final res = await _dio.get(
        '/api/v1/threads',
        queryParameters: {if (status != null) 'status': status},
      );
      final list = (res.data['threads'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      debugPrint('[API] listThreads → ${list.length} 个');
      return list;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 获取单个事件串（含 members 数组）
  Future<Map<String, dynamic>> getThread(String name) async {
    debugPrint('[API] getThread name=$name');
    try {
      final res = await _dio.get('/api/v1/$name');
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 创建事件串，可带初始成员
  Future<Map<String, dynamic>> createThread({
    required String title,
    String? summary,
    List<String>? memos,
  }) async {
    debugPrint('[API] createThread title="$title" members=${memos?.length ?? 0}');
    try {
      final body = <String, dynamic>{
        'title': title,
        if (summary != null) 'summary': summary,
        if (memos != null) 'memos': memos,
      };
      final res = await _dio.post('/api/v1/threads', data: body);
      final result = Map<String, dynamic>.from(res.data as Map);
      debugPrint('[API] createThread 成功 name=${result["name"]}');
      return result;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 更新事件串的标题/简介/状态
  Future<Map<String, dynamic>> updateThread({
    required String name,
    String? title,
    String? summary,
    String? status,
  }) async {
    debugPrint('[API] updateThread name=$name');
    try {
      final body = <String, dynamic>{
        if (title != null) 'title': title,
        if (summary != null) 'summary': summary,
        if (status != null) 'status': status,
      };
      final res = await _dio.patch('/api/v1/$name', data: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 删除事件串（服务端软删）
  Future<void> deleteThread(String name) async {
    debugPrint('[API] deleteThread name=$name');
    try {
      await _dio.delete('/api/v1/$name');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 全量替换事件串成员，响应含 members
  Future<Map<String, dynamic>> setThreadMembers({
    required String name,
    required List<String> memos,
  }) async {
    debugPrint('[API] setThreadMembers name=$name count=${memos.length}');
    try {
      final res = await _dio.put('/api/v1/$name/members', data: {'memos': memos});
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }
```

- [ ] **Step 2: 确认编译通过**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter analyze
```

Expected: No issues found

- [ ] **Step 3: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/services/api/memos_api_service.dart
git commit -m "feat: 新增事件串 API 客户端接口"
```

---

### Task 9: 事件串双向同步

**Files:**
- Modify: `lib/services/sync/sync_service.dart`（`_sync` 第 114-117 行；`_pushPending` 第 587 行附近；文件末尾追加两个方法）

**Interfaces:**
- Consumes: Task 6 的 `DatabaseService` 事件串方法；Task 7 的 `decideThreadPull` / `resolveThreadMemberNames` / `mapRemoteMembersToLocalIds`；Task 8 的 API 方法；既有 `DatabaseService.getMemoById` / `getMemoByMemosName`
- Produces:
  - `static Future<int> _pullThreads(MemosApiService api)`
  - `static Future<int> _pushPendingThreads(MemosApiService api)`

- [ ] **Step 1: 实现 Pull**

在 `lib/services/sync/sync_service.dart` 末尾（类闭合大括号之前）追加：

```dart
  // ────────────────────────────────────────────────────────────────
  // 事件串同步
  // ────────────────────────────────────────────────────────────────

  /// 把远端事件串的成员列表映射为本地 memo id。
  ///
  /// 远端成员形如 [{"memo": "memos/1001", ...}]；本地缺失的日记被丢弃
  /// （要么还没拉下来、下轮补上，要么已在本地删除）。
  static Future<List<int>> _resolveRemoteMembers(
      List<dynamic> remoteMembers) async {
    final names = remoteMembers
        .map((e) => (e as Map)['memo'] as String?)
        .whereType<String>()
        .toList();

    final localIdByName = <String, int>{};
    for (final name in names) {
      final memo = await DatabaseService.getMemoByMemosName(name);
      if (memo != null) localIdByName[name] = memo.id;
    }
    return mapRemoteMembersToLocalIds(names, localIdByName);
  }

  /// 把远端事件串数据写入本地实体（不含成员）。
  static void _applyRemoteThreadFields(
      ThreadEntry thread, Map<String, dynamic> data) {
    thread
      ..threadName = data['name'] as String?
      ..title = data['title'] as String? ?? ''
      ..summary = data['summary'] as String? ?? ''
      ..summaryIsManual = data['summarySource'] == 'MANUAL'
      ..status = data['status'] == 'RESOLVED'
          ? ThreadStatus.resolved
          : ThreadStatus.active;
  }

  /// 拉取远端事件串。
  ///
  /// 列表接口不含成员，因此对每个事件串再取一次详情——事件串是几十个量级，
  /// 且单次详情就带回全部成员，比做成员级增量便宜。
  static Future<int> _pullThreads(MemosApiService api) async {
    debugPrint('[Sync] _pullThreads 开始');
    int pulled = 0;
    try {
      final remoteList = await api.listThreads();
      final remoteNames = remoteList.map((t) => t['name'] as String).toSet();

      for (final summaryData in remoteList) {
        final name = summaryData['name'] as String;
        final local = await DatabaseService.getThreadByThreadName(name);
        final remoteUpdatedAt =
            DateTime.tryParse(summaryData['updateTime'] as String? ?? '')
                    ?.toLocal() ??
                DateTime.now();

        final action = decideThreadPull(
          local: local,
          remoteUpdatedAt: remoteUpdatedAt,
        );
        if (action == ThreadPullAction.skip) continue;

        if (action == ThreadPullAction.markConflict) {
          // 本地有未推送改动且远端更新：保留本地内容，标记冲突等待用户处理
          local!
            ..syncStatus = SyncStatus.conflict
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveThread(local, skipTimestamp: true);
          continue;
        }

        final detail = await api.getThread(name);
        final members =
            await _resolveRemoteMembers(detail['members'] as List<dynamic>? ?? []);

        final thread = action == ThreadPullAction.insert
            ? (ThreadEntry()..createdAt = remoteUpdatedAt)
            : local!;
        _applyRemoteThreadFields(thread, detail);
        thread
          ..memberLocalIds = members
          ..updatedAt = remoteUpdatedAt
          ..syncStatus = SyncStatus.synced
          ..lastSyncAt = DateTime.now()
          ..isDeleted = false;
        await DatabaseService.saveThread(thread, skipTimestamp: true);
        pulled++;
      }

      // 远端已删除检测：本地 synced 但远端列表中不存在
      final localSynced = await DatabaseService.getAllSyncedThreads();
      for (final local in localSynced) {
        if (local.threadName != null && !remoteNames.contains(local.threadName)) {
          await DatabaseService.hardDeleteThread(local.id);
          debugPrint('[Sync] 事件串远端已删除，本地物理删除 ${local.threadName}');
        }
      }
    } catch (e) {
      debugPrint('[Sync] _pullThreads 失败: $e');
    }
    debugPrint('[Sync] _pullThreads 完成，拉取 $pulled 个');
    return pulled;
  }
```

在该文件顶部 import 区加入：

```dart
import '../../data/database/thread_membership_policy.dart';
import '../../data/models/thread_entry.dart';
```

- [ ] **Step 2: 实现 Push**

紧接上一步，在 `_pullThreads` 之后追加：

```dart
  /// 推送所有 pending 事件串。
  ///
  /// 必须在 memo 推送之后调用：离线新建的日记要先拿到 memosName 才能作为成员上传。
  /// 成员未全部解析成功时保持 pending，下一轮同步补齐。
  static Future<int> _pushPendingThreads(MemosApiService api) async {
    final pending = await DatabaseService.getPendingSyncThreads();
    debugPrint('[Sync] _pushPendingThreads: ${pending.length} 个待推送');
    int pushed = 0;

    for (final thread in pending) {
      try {
        if (thread.isDeleted) {
          if (thread.threadName != null) {
            await api.deleteThread(thread.threadName!);
          }
          await DatabaseService.hardDeleteThread(thread.id);
          pushed++;
          continue;
        }

        // 解析成员的远端资源名
        final nameByLocalId = <int, String?>{};
        for (final localId in thread.memberLocalIds) {
          final memo = await DatabaseService.getMemoById(localId);
          nameByLocalId[localId] = memo?.memosName;
        }
        final resolution =
            resolveThreadMemberNames(thread.memberLocalIds, nameByLocalId);

        if (thread.threadName == null) {
          final data = await api.createThread(
            title: thread.title,
            summary: thread.summary,
            memos: resolution.memoNames,
          );
          thread.threadName = data['name'] as String?;
        } else {
          await api.updateThread(
            name: thread.threadName!,
            title: thread.title,
            summary: thread.summary,
            status: thread.status == ThreadStatus.resolved ? 'RESOLVED' : 'ACTIVE',
          );
          await api.setThreadMembers(
            name: thread.threadName!,
            memos: resolution.memoNames,
          );
        }

        // 成员没解析全时保持 pending，等日记推送成功后的下一轮补齐
        thread
          ..syncStatus =
              resolution.complete ? SyncStatus.synced : SyncStatus.pending
          ..lastSyncAt = DateTime.now();
        await DatabaseService.saveThread(thread, skipTimestamp: true);
        pushed++;

        if (!resolution.complete) {
          debugPrint('[Sync] 事件串 ${thread.threadName} 有成员尚未同步，保持 pending');
        }
      } catch (e) {
        debugPrint('[Sync] 推送事件串失败 id=${thread.id}: $e');
      }
    }

    debugPrint('[Sync] _pushPendingThreads 完成，推送 $pushed 个');
    return pushed;
  }
```

- [ ] **Step 3: 接入同步主流程**

在 `lib/services/sync/sync_service.dart` 的 `_sync` 中，第 115 行 `await _pullArticles(api);` 之后追加：

```dart
      // 事件串在日记之后拉取，保证成员能映射到本地 memo
      await _pullThreads(api);
```

在 `_pushPending` 内，第 588 行 `count += await _pushPendingFolders(api);` 所在的推送序列**末尾**（即所有 memo / 文件夹 / 文章推送完成之后）追加：

```dart
    // 事件串最后推送：成员需要日记已有 memosName
    count += await _pushPendingThreads(api);
```

- [ ] **Step 4: 确认编译与既有测试通过**

```bash
flutter analyze && flutter test
```

Expected: No issues found；所有测试 PASS

- [ ] **Step 5: 手动验证同步闭环**

需要 Part A 的服务端正在运行且客户端已配置服务器地址与 token。

- [ ] 在应用中通过 Task 12 之前的临时入口或直接调试代码创建一个事件串并加入两篇已同步的日记，触发同步，确认服务端 `GET /api/v1/threads` 能查到且 `memberCount` 正确
- [ ] 断网后新建一篇日记并加入该事件串，恢复网络触发同步，确认服务端成员数增加（验证「memo 先推、thread 后推」的顺序）
- [ ] 在服务端直接改事件串标题，客户端触发同步后本地标题更新

- [ ] **Step 6: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/services/sync/sync_service.dart
git commit -m "feat: 事件串双向同步"
```

---

### Task 10: 底部导航改版

**「文章」让位给「事件串」，文章移入侧边抽屉。**

**Files:**
- Modify: `lib/shared/constants/app_constants.dart`（第 179 行附近）
- Modify: `lib/shared/widgets/main_scaffold.dart`
- Modify: `lib/features/home/home_view.dart`（`_buildDrawer`）

**Interfaces:**
- Consumes: Task 11 的 `ThreadsView`（本任务先建一个占位实现，Task 11 填充）
- Produces: Tab 索引语义变为 `0=事件串 1=主页 2=日历 3=待办`

**本任务没有自动化测试。** `MainScaffold` 的子页面依赖已打开的 Isar 实例，widget test 中无法构造。以 `flutter analyze` 通过 + 手动运行确认为准。

- [ ] **Step 1: 新增文案常量**

在 `lib/shared/constants/app_constants.dart` 的 `navArticles` 一行之后追加：

```dart
  static const String navThreads = '事件串';
```

- [ ] **Step 2: 创建占位页面**

创建 `lib/features/threads/threads_view.dart`：

```dart
import 'package:flutter/material.dart';

import '../../shared/constants/app_constants.dart';

/// 事件串列表页（Task 11 填充内容）
class ThreadsView extends StatelessWidget {
  const ThreadsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.navThreads)),
      body: const Center(child: Text('事件串')),
    );
  }
}
```

- [ ] **Step 3: 改造 MainScaffold**

修改 `lib/shared/widgets/main_scaffold.dart`：

将第 4 行的 `import '../../features/articles/articles_view.dart';` 替换为：

```dart
import '../../features/threads/threads_view.dart';
```

将第 13 行的类文档注释改为：

```dart
/// 5 个 Tab：事件串 | 主页 | [FAB] | 日历 | 待办
```

将第 24-25 行的索引注释改为：

```dart
  /// 0=事件串  1=主页  2=日历  3=待办
```

将 `_buildNavRow` 中的第一个 `_NavItem`（原「待办」，第 54-60 行）改为：

```dart
        _NavItem(
          icon: Icons.timeline_outlined,
          activeIcon: Icons.timeline,
          label: AppStrings.navThreads,
          selected: _currentIndex == 0,
          onTap: () => setState(() => _currentIndex = 0),
        ),
```

将最后一个 `_NavItem`（原「文章」，第 77-83 行）改为：

```dart
        _NavItem(
          icon: Icons.check_box_outline_blank,
          activeIcon: Icons.check_box,
          label: AppStrings.navTodo,
          selected: _currentIndex == 3,
          onTap: () => setState(() => _currentIndex = 3),
        ),
```

将 `IndexedStack` 的 `children`（第 94-103 行）改为：

```dart
        children: [
          const ThreadsView(),
          const HomeView(),
          CalendarView(
            onSelectedDayChanged: (day) {
              _calendarSelectedDay = day;
            },
          ),
          const TodoView(),
        ],
```

`_showFab` 的判断（第 37 行）保持 `_currentIndex == 1 || _currentIndex == 2` 不变 —— 主页和日历的索引未变。

- [ ] **Step 4: 抽屉加入文章入口**

在 `lib/features/home/home_view.dart` 的 `_buildDrawer` 中，「设置」ListTile 之前插入：

```dart
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text(AppStrings.navArticles),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ArticlesView()),
                );
              },
            ),
```

在该文件顶部 import 区加入：

```dart
import '../articles/articles_view.dart';
```

若 `ArticlesView` 自身不带 `Scaffold`（原先作为 Tab 内容使用），需在此包一层：

```dart
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text(AppStrings.navArticles)),
                      body: const ArticlesView(),
                    ),
                  ),
```

先查看 `lib/features/articles/articles_view.dart` 的 `build` 方法确认是否已含 `Scaffold`，据此二选一。

- [ ] **Step 5: 确认编译与运行**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter analyze && flutter test
```

Expected: No issues found；所有测试 PASS

手动运行确认：

- [ ] 底部依次为 事件串 | 主页 | FAB | 日历 | 待办
- [ ] FAB 仍只在主页和日历显示
- [ ] 抽屉中能打开文章页，功能正常
- [ ] 切换 Tab 后各页状态保持（IndexedStack 生效）

- [ ] **Step 6: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/shared/constants/app_constants.dart lib/shared/widgets/main_scaffold.dart lib/features/home/home_view.dart lib/features/threads/threads_view.dart
git commit -m "feat: 底部导航新增事件串 Tab，文章移入抽屉"
```

---

### Task 11: 事件串列表页

**Files:**
- Create: `lib/features/threads/widgets/thread_card.dart`
- Create: `test/features/threads/thread_card_test.dart`
- Modify: `lib/features/threads/threads_view.dart`（替换 Task 10 的占位实现）

**Interfaces:**
- Consumes: Task 6 的 `ThreadEntry` / `ThreadStatus` / `DatabaseService.getAllThreads` / `getMemoById`；既有 `DatabaseService.watchDbChanges()`
- Produces:
  - `class ThreadCardData { final String title; final String summary; final int memberCount; final DateTime? startedAt; final DateTime? lastAt; }`
  - `class ThreadCard extends StatelessWidget { final ThreadCardData data; final VoidCallback? onTap; }` —— 无状态，可独立 widget test
  - `_ThreadsViewState._buildCardData(ThreadEntry) → Future<ThreadCardData>`（私有，现算成员数与时间跨度）

- [ ] **Step 1: 写失败的 widget 测试**

创建 `test/features/threads/thread_card_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/threads/widgets/thread_card.dart';

Future<void> _pump(WidgetTester tester, ThreadCardData data,
    {VoidCallback? onTap}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ThreadCard(data: data, onTap: onTap)),
    ),
  );
}

void main() {
  testWidgets('shows title, summary and member count', (tester) async {
    await _pump(
      tester,
      ThreadCardData(
        title: '工位蛐蛐',
        summary: '找了两晚没找到，第三晚又听到了',
        memberCount: 4,
        startedAt: DateTime(2026, 8, 11),
        lastAt: DateTime(2026, 8, 13),
      ),
    );

    expect(find.text('工位蛐蛐'), findsOneWidget);
    expect(find.text('找了两晚没找到，第三晚又听到了'), findsOneWidget);
    expect(find.textContaining('4 篇'), findsOneWidget);
    expect(find.textContaining('08月11日'), findsOneWidget);
    expect(find.textContaining('08月13日'), findsOneWidget);
  });

  testWidgets('shows a single date when the span covers one day',
      (tester) async {
    await _pump(
      tester,
      ThreadCardData(
        title: '单日事件',
        summary: '',
        memberCount: 1,
        startedAt: DateTime(2026, 8, 11),
        lastAt: DateTime(2026, 8, 11),
      ),
    );

    expect(find.textContaining('08月11日–'), findsNothing);
    expect(find.textContaining('08月11日'), findsOneWidget);
  });

  testWidgets('omits the date range when the thread has no members',
      (tester) async {
    await _pump(
      tester,
      const ThreadCardData(
        title: '空事件串',
        summary: '',
        memberCount: 0,
        startedAt: null,
        lastAt: null,
      ),
    );

    expect(find.textContaining('0 篇'), findsOneWidget);
    expect(find.textContaining('月'), findsNothing);
  });

  testWidgets('hides the summary row when the summary is empty',
      (tester) async {
    await _pump(
      tester,
      const ThreadCardData(
        title: '无简介',
        summary: '',
        memberCount: 2,
        startedAt: null,
        lastAt: null,
      ),
    );

    expect(find.byKey(const Key('thread_card_summary')), findsNothing);
  });

  testWidgets('invokes onTap when tapped', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      const ThreadCardData(
        title: '可点击',
        summary: '',
        memberCount: 0,
        startedAt: null,
        lastAt: null,
      ),
      onTap: () => tapped = true,
    );

    await tester.tap(find.byType(ThreadCard));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/features/threads/thread_card_test.dart
```

Expected: 编译失败，找不到 `thread_card.dart`

- [ ] **Step 3: 实现 ThreadCard**

创建 `lib/features/threads/widgets/thread_card.dart`：

```dart
import 'package:flutter/material.dart';

import '../../../shared/constants/app_constants.dart';

/// [ThreadCard] 的展示数据
///
/// 刻意与 ThreadEntry 解耦：时间跨度由成员日记现算得出，
/// 让卡片保持无状态、可独立测试。
class ThreadCardData {
  final String title;
  final String summary;
  final int memberCount;
  final DateTime? startedAt;
  final DateTime? lastAt;

  const ThreadCardData({
    required this.title,
    required this.summary,
    required this.memberCount,
    required this.startedAt,
    required this.lastAt,
  });
}

/// 事件串列表卡片
class ThreadCard extends StatelessWidget {
  final ThreadCardData data;
  final VoidCallback? onTap;

  const ThreadCard({super.key, required this.data, this.onTap});

  static String _formatDay(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}月${d.day.toString().padLeft(2, '0')}日';

  /// 无成员时不显示日期；同一天只显示一个日期。
  String _spanText() {
    final started = data.startedAt;
    final last = data.lastAt;
    if (started == null || last == null) return '${data.memberCount} 篇';

    final startText = _formatDay(started);
    final lastText = _formatDay(last);
    final span = startText == lastText ? startText : '$startText–$lastText';
    return '${data.memberCount} 篇 · $span';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
            if (data.summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                data.summary,
                key: const Key('thread_card_summary'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _spanText(),
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
```

注意配色 API：`AppColors` 中随主题切换的颜色都是**接收 context 的函数**（`app_constants.dart:38-56`）—— `surface(context)` / `textPrimary(context)` / `textBody(context)` / `textSecondary(context)` / `scaffoldBg(context)`。只有 `primary` / `primaryDark` / `primaryLight` / `primaryLighter` / `timelineBar` / `success` / `error` 是常量。不存在 `surfaceWhite`。

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter test test/features/threads/thread_card_test.dart
```

Expected: All tests passed

- [ ] **Step 5: 实现列表页**

用以下内容替换 `lib/features/threads/threads_view.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/thread_entry.dart';
import '../../shared/constants/app_constants.dart';
import 'thread_detail_page.dart';
import 'widgets/thread_card.dart';

/// 事件串列表页
///
/// 分「进行中」「已完结」两组。时间跨度由成员日记的 createdAt 现算，
/// 与服务端一致：不落库冗余统计，避免用户改日记日期后静默过期。
class ThreadsView extends StatefulWidget {
  const ThreadsView({super.key});

  @override
  State<ThreadsView> createState() => _ThreadsViewState();
}

class _ThreadsViewState extends State<ThreadsView> {
  List<(ThreadEntry, ThreadCardData)> _active = [];
  List<(ThreadEntry, ThreadCardData)> _resolved = [];
  bool _loading = true;
  StreamSubscription<void>? _dbSub;

  @override
  void initState() {
    super.initState();
    _load();
    _watch();
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    super.dispose();
  }

  Future<void> _watch() async {
    final stream = await DatabaseService.watchDbChanges();
    _dbSub = stream.listen((_) {
      if (mounted) _load();
    });
  }

  /// 现算卡片数据：成员数与时间跨度都来自成员日记本身。
  Future<ThreadCardData> _buildCardData(ThreadEntry thread) async {
    final dates = <DateTime>[];
    for (final localId in thread.memberLocalIds) {
      final memo = await DatabaseService.getMemoById(localId);
      if (memo != null && !memo.isDeleted) dates.add(memo.createdAt);
    }
    dates.sort();
    return ThreadCardData(
      title: thread.title,
      summary: thread.summary,
      memberCount: dates.length,
      startedAt: dates.isEmpty ? null : dates.first,
      lastAt: dates.isEmpty ? null : dates.last,
    );
  }

  Future<void> _load() async {
    final threads = await DatabaseService.getAllThreads();
    final active = <(ThreadEntry, ThreadCardData)>[];
    final resolved = <(ThreadEntry, ThreadCardData)>[];
    for (final thread in threads) {
      final data = await _buildCardData(thread);
      if (thread.status == ThreadStatus.resolved) {
        resolved.add((thread, data));
      } else {
        active.add((thread, data));
      }
    }
    if (!mounted) return;
    setState(() {
      _active = active;
      _resolved = resolved;
      _loading = false;
    });
  }

  void _open(ThreadEntry thread) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ThreadDetailPage(threadId: thread.id)),
    ).then((_) => _load());
  }

  Widget _sectionHeader(String label, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          '$label · $count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          AppStrings.navThreads,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_active.isEmpty && _resolved.isEmpty)
              ? const Center(
                  child: Text(
                    '还没有事件串\n在日记详情页把相关的几篇归到一起',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView(
                  children: [
                    if (_active.isNotEmpty) ...[
                      _sectionHeader('进行中', _active.length),
                      ..._active.map((e) => ThreadCard(
                            data: e.$2,
                            onTap: () => _open(e.$1),
                          )),
                    ],
                    if (_resolved.isNotEmpty) ...[
                      _sectionHeader('已完结', _resolved.length),
                      ..._resolved.map((e) => ThreadCard(
                            data: e.$2,
                            onTap: () => _open(e.$1),
                          )),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }
}
```

- [ ] **Step 6: 确认编译（Task 12 完成前 `ThreadDetailPage` 尚不存在，本步骤在 Task 12 后重跑）**

先创建一个最小 `lib/features/threads/thread_detail_page.dart` 让编译通过，Task 12 再填充：

```dart
import 'package:flutter/material.dart';

/// 事件串详情页（Task 12 填充内容）
class ThreadDetailPage extends StatelessWidget {
  final int threadId;

  const ThreadDetailPage({super.key, required this.threadId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('事件串')),
      body: const SizedBox.shrink(),
    );
  }
}
```

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter analyze && flutter test
```

Expected: No issues found；所有测试 PASS

- [ ] **Step 7: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/features/threads/ test/features/threads/
git commit -m "feat: 事件串列表页"
```

---

### Task 12: 事件串详情页

**Files:**
- Modify: `lib/features/threads/thread_detail_page.dart`（替换 Task 11 的占位实现）

**Interfaces:**
- Consumes: `DatabaseService.getThreadById` / `getMemoById` / `saveThread` / `softDeleteThread`；既有 `MemoDetailPage`
- Produces: `class ThreadDetailPage extends StatefulWidget { final int threadId; }`

- [ ] **Step 1: 实现详情页**

用以下内容替换 `lib/features/threads/thread_detail_page.dart`：

```dart
import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../data/models/thread_entry.dart';
import '../../shared/constants/app_constants.dart';
import '../memo_detail/memo_detail_page.dart';

/// 事件串详情页：把成员日记按时间升序排成一条时间线
class ThreadDetailPage extends StatefulWidget {
  final int threadId;

  const ThreadDetailPage({super.key, required this.threadId});

  @override
  State<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends State<ThreadDetailPage> {
  ThreadEntry? _thread;
  List<MemoEntry> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final thread = await DatabaseService.getThreadById(widget.threadId);
    final members = <MemoEntry>[];
    if (thread != null) {
      for (final localId in thread.memberLocalIds) {
        final memo = await DatabaseService.getMemoById(localId);
        if (memo != null && !memo.isDeleted) members.add(memo);
      }
      // 按日记时间升序——事件串的顺序始终来自日记本身
      members.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    if (!mounted) return;
    setState(() {
      _thread = thread;
      _members = members;
      _loading = false;
    });
  }

  Future<void> _editText({
    required String title,
    required String initial,
    required ValueChanged<String> onSave,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) onSave(result);
  }

  Future<void> _saveThread() async {
    final thread = _thread;
    if (thread == null) return;
    thread.syncStatus = SyncStatus.pending;
    await DatabaseService.saveThread(thread);
    await _load();
  }

  Future<void> _toggleResolved() async {
    final thread = _thread;
    if (thread == null) return;
    thread.status = thread.status == ThreadStatus.resolved
        ? ThreadStatus.active
        : ThreadStatus.resolved;
    await _saveThread();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除事件串'),
        content: const Text('只删除这条事件串，日记本身不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await DatabaseService.softDeleteThread(widget.threadId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _removeMember(MemoEntry memo) async {
    final thread = _thread;
    if (thread == null) return;
    thread.memberLocalIds =
        thread.memberLocalIds.where((e) => e != memo.id).toList();
    await _saveThread();
  }

  String _formatDay(DateTime d) =>
      '${d.year}年${d.month.toString().padLeft(2, '0')}月${d.day.toString().padLeft(2, '0')}日';

  Widget _buildMemberTile(int index, MemoEntry memo) {
    final lines = memo.content.split('\n').take(3).join('\n');
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MemoDetailPage(memo: memo)),
        ).then((_) => _load());
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDay(memo.createdAt),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  tooltip: '移出事件串',
                  onPressed: () => _removeMember(memo),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              lines,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: AppColors.textBody(context)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = _thread;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (thread == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('事件串不存在')),
      );
    }

    final resolved = thread.status == ThreadStatus.resolved;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(thread.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '改标题',
            onPressed: () => _editText(
              title: '事件串标题',
              initial: thread.title,
              onSave: (v) {
                thread.title = v;
                _saveThread();
              },
            ),
          ),
          IconButton(
            icon: Icon(resolved ? Icons.replay : Icons.check_circle_outline),
            tooltip: resolved ? '标记为进行中' : '标记完结',
            onPressed: _toggleResolved,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除事件串',
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: InkWell(
              onTap: () => _editText(
                title: '简介',
                initial: thread.summary,
                onSave: (v) {
                  thread
                    ..summary = v
                    ..summaryIsManual = true;
                  _saveThread();
                },
              ),
              child: Text(
                thread.summary.isEmpty ? '点击添加一句话简介' : thread.summary,
                style: TextStyle(
                  fontSize: 14,
                  color: thread.summary.isEmpty
                      ? Colors.grey[500]
                      : AppColors.textBody(context),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '${_members.length} 篇${resolved ? " · 已完结" : ""}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          if (_members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('还没有日记，去日记详情页加入',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
          for (var i = 0; i < _members.length; i++)
            _buildMemberTile(i, _members[i]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
```

`MemoDetailPage` 的签名是 `MemoDetailPage({required MemoEntry memo})`（`memo_detail_page.dart:31`），传整个实体而非 id。

- [ ] **Step 2: 确认编译与测试**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter analyze && flutter test
```

Expected: No issues found；所有测试 PASS

- [ ] **Step 3: 手动验证**

- [ ] 从事件串 Tab 点进详情，成员按时间升序排列，序号从 1 开始
- [ ] 改标题、改简介后返回列表，列表已更新
- [ ] 「标记完结」后事件串移到「已完结」分组
- [ ] 移出某个成员后成员数减少，日记本身仍在主页时间线上

- [ ] **Step 4: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/features/threads/thread_detail_page.dart
git commit -m "feat: 事件串详情页时间线"
```

---

### Task 13: 日记详情页的事件串 chip 与上/下一篇导航

**这是解决核心痛点的任务**：单看一篇不再丢上下文，因为前后文永远在手边。

**Files:**
- Create: `lib/features/memo_detail/widgets/thread_nav_bar.dart`
- Create: `test/features/memo_detail/thread_nav_bar_test.dart`
- Modify: `lib/features/memo_detail/memo_detail_page.dart`

**Interfaces:**
- Consumes: `DatabaseService.getThreadsForMemo(int)` / `getMemoById`；`MemoDetailPage({required MemoEntry memo})`
- Produces:
  - `class ThreadNavData { final String threadTitle; final int position; final int total; final bool hasPrevious; final bool hasNext; }`
  - `class ThreadNavBar extends StatelessWidget { final ThreadNavData data; final VoidCallback? onPrevious; final VoidCallback? onNext; final VoidCallback? onOpenThread; }`

- [ ] **Step 1: 写失败的 widget 测试**

创建 `test/features/memo_detail/thread_nav_bar_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/memo_detail/widgets/thread_nav_bar.dart';

Future<void> _pump(
  WidgetTester tester,
  ThreadNavData data, {
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  VoidCallback? onOpenThread,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ThreadNavBar(
          data: data,
          onPrevious: onPrevious,
          onNext: onNext,
          onOpenThread: onOpenThread,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the thread title and position', (tester) async {
    await _pump(
      tester,
      const ThreadNavData(
        threadTitle: '工位蛐蛐',
        position: 3,
        total: 4,
        hasPrevious: true,
        hasNext: true,
      ),
    );

    expect(find.textContaining('工位蛐蛐'), findsOneWidget);
    expect(find.textContaining('3/4'), findsOneWidget);
  });

  testWidgets('disables previous on the first entry', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      const ThreadNavData(
        threadTitle: '工位蛐蛐',
        position: 1,
        total: 4,
        hasPrevious: false,
        hasNext: true,
      ),
      onPrevious: () => tapped = true,
    );

    final previous = tester.widget<IconButton>(
      find.byKey(const Key('thread_nav_previous')),
    );
    expect(previous.onPressed, isNull);
    expect(tapped, isFalse);
  });

  testWidgets('disables next on the last entry', (tester) async {
    await _pump(
      tester,
      const ThreadNavData(
        threadTitle: '工位蛐蛐',
        position: 4,
        total: 4,
        hasPrevious: true,
        hasNext: false,
      ),
      onNext: () {},
    );

    final next = tester.widget<IconButton>(
      find.byKey(const Key('thread_nav_next')),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('invokes callbacks when navigating', (tester) async {
    var previousTapped = false;
    var nextTapped = false;
    var titleTapped = false;

    await _pump(
      tester,
      const ThreadNavData(
        threadTitle: '工位蛐蛐',
        position: 2,
        total: 4,
        hasPrevious: true,
        hasNext: true,
      ),
      onPrevious: () => previousTapped = true,
      onNext: () => nextTapped = true,
      onOpenThread: () => titleTapped = true,
    );

    await tester.tap(find.byKey(const Key('thread_nav_previous')));
    await tester.tap(find.byKey(const Key('thread_nav_next')));
    await tester.tap(find.byKey(const Key('thread_nav_title')));
    await tester.pump();

    expect(previousTapped, isTrue);
    expect(nextTapped, isTrue);
    expect(titleTapped, isTrue);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/features/memo_detail/thread_nav_bar_test.dart
```

Expected: 编译失败，找不到 `thread_nav_bar.dart`

- [ ] **Step 3: 实现 ThreadNavBar**

创建 `lib/features/memo_detail/widgets/thread_nav_bar.dart`：

```dart
import 'package:flutter/material.dart';

import '../../../shared/constants/app_constants.dart';

/// [ThreadNavBar] 的展示数据
class ThreadNavData {
  final String threadTitle;

  /// 当前日记在事件串中的序号，从 1 开始
  final int position;
  final int total;
  final bool hasPrevious;
  final bool hasNext;

  const ThreadNavData({
    required this.threadTitle,
    required this.position,
    required this.total,
    required this.hasPrevious,
    required this.hasNext,
  });
}

/// 日记详情页底部的事件串导航条
///
/// 形如：← 上一篇 · 事件串「工位蛐蛐」3/4 · 下一篇 →
/// 让单看一篇日记时仍能顺着事件读到前后文。
class ThreadNavBar extends StatelessWidget {
  final ThreadNavData data;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onOpenThread;

  const ThreadNavBar({
    super.key,
    required this.data,
    this.onPrevious,
    this.onNext,
    this.onOpenThread,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLighter,
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('thread_nav_previous'),
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一篇',
            onPressed: data.hasPrevious ? onPrevious : null,
          ),
          Expanded(
            child: InkWell(
              key: const Key('thread_nav_title'),
              onTap: onOpenThread,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '「${data.threadTitle}」${data.position}/${data.total}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('thread_nav_next'),
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一篇',
            onPressed: data.hasNext ? onNext : null,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter test test/features/memo_detail/thread_nav_bar_test.dart
```

Expected: All tests passed

- [ ] **Step 5: 接入日记详情页**

在 `lib/features/memo_detail/memo_detail_page.dart` 的 `_MemoDetailPageState` 中新增状态与加载逻辑（放在类的字段声明区）：

```dart
  /// 本篇日记所属的全部事件串（多归属时并排显示）
  List<ThreadEntry> _threads = [];

  /// 当前展示导航条的事件串（默认第一个）及其按时间升序的成员
  ThreadEntry? _navThread;
  List<MemoEntry> _navMembers = [];

  Future<void> _loadThreads() async {
    final threads = await DatabaseService.getThreadsForMemo(memo.id);
    ThreadEntry? navThread = threads.isEmpty ? null : threads.first;
    final members = <MemoEntry>[];
    if (navThread != null) {
      for (final localId in navThread.memberLocalIds) {
        final m = await DatabaseService.getMemoById(localId);
        if (m != null && !m.isDeleted) members.add(m);
      }
      members.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    if (!mounted) return;
    setState(() {
      _threads = threads;
      _navThread = navThread;
      _navMembers = members;
    });
  }

  /// 构造导航条数据；当前日记不在成员中（刚被移出）时返回 null
  ThreadNavData? _buildNavData() {
    final thread = _navThread;
    if (thread == null || _navMembers.isEmpty) return null;
    final index = _navMembers.indexWhere((m) => m.id == memo.id);
    if (index < 0) return null;
    return ThreadNavData(
      threadTitle: thread.title,
      position: index + 1,
      total: _navMembers.length,
      hasPrevious: index > 0,
      hasNext: index < _navMembers.length - 1,
    );
  }

  void _jumpToMember(int offset) {
    final index = _navMembers.indexWhere((m) => m.id == memo.id);
    final target = index + offset;
    if (target < 0 || target >= _navMembers.length) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MemoDetailPage(memo: _navMembers[target]),
      ),
    );
  }
```

在 `initState` 中调用 `_loadThreads();`。

在文件顶部 import 区加入：

```dart
import '../../data/models/thread_entry.dart';
import '../threads/thread_detail_page.dart';
import 'widgets/thread_nav_bar.dart';
```

在 `build` 方法中，`body: Column(` 的 `children:` 内、`Expanded(` **之前**（即第 305 行位置）插入事件串 chip 行：

```dart
          if (_threads.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final thread in _threads.take(2))
                    ActionChip(
                      label: Text(
                        thread.title,
                        style: const TextStyle(fontSize: 12),
                      ),
                      avatar: const Icon(Icons.timeline, size: 14),
                      backgroundColor: AppColors.primaryLight,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ThreadDetailPage(threadId: thread.id),
                          ),
                        ).then((_) => _loadThreads());
                      },
                    ),
                  if (_threads.length > 2)
                    Chip(
                      label: Text(
                        '+${_threads.length - 2}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: AppColors.primaryLight,
                    ),
                ],
              ),
            ),
```

在同一个 `Scaffold` 上新增底部导航条 —— 在 `body:` 参数**之后**追加：

```dart
      bottomNavigationBar: () {
        final navData = _buildNavData();
        if (navData == null) return null;
        return ThreadNavBar(
          data: navData,
          onPrevious: () => _jumpToMember(-1),
          onNext: () => _jumpToMember(1),
          onOpenThread: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ThreadDetailPage(threadId: _navThread!.id),
              ),
            ).then((_) => _loadThreads());
          },
        );
      }(),
```

若该 `Scaffold` 已有 `bottomNavigationBar`（例如评论输入框），则把 `ThreadNavBar` 包进现有底部区域的 `Column` 顶部，而不是新增参数。

- [ ] **Step 6: 确认编译与全部测试**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter analyze && flutter test
```

Expected: No issues found；所有测试 PASS

- [ ] **Step 7: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/features/memo_detail/ test/features/memo_detail/thread_nav_bar_test.dart
git commit -m "feat: 日记详情页事件串 chip 与上下篇导航"
```

---

### Task 14: 事件串选择器与批量加入

**手动是主路径** —— Phase 1 不含 AI，全靠这个入口把日记归到事件串里。

**Files:**
- Create: `lib/features/threads/thread_picker_sheet.dart`
- Modify: `lib/features/memo_detail/memo_detail_page.dart`（AppBar 增加入口）
- Modify: `lib/features/threads/threads_view.dart`（AppBar 增加「新建」）

**Interfaces:**
- Consumes: `DatabaseService.getAllThreads` / `saveThread` / `searchMemos` / `getMemoById`
- Produces:
  - `Future<bool?> showThreadPickerSheet(BuildContext context, {required int memoLocalId})` —— 为某篇日记选择/新建事件串，返回 true 表示有改动
  - `Future<bool?> showThreadCreateSheet(BuildContext context)` —— 新建事件串并搜索批量加入历史日记

- [ ] **Step 1: 实现选择器**

创建 `lib/features/threads/thread_picker_sheet.dart`：

```dart
import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../data/models/thread_entry.dart';
import '../../shared/constants/app_constants.dart';

/// 把一篇日记挂到事件串上（可多选，支持就地新建）。
///
/// 返回 true 表示归属有变化，调用方应刷新。
Future<bool?> showThreadPickerSheet(
  BuildContext context, {
  required int memoLocalId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ThreadPickerSheet(memoLocalId: memoLocalId),
  );
}

class _ThreadPickerSheet extends StatefulWidget {
  final int memoLocalId;

  const _ThreadPickerSheet({required this.memoLocalId});

  @override
  State<_ThreadPickerSheet> createState() => _ThreadPickerSheetState();
}

class _ThreadPickerSheetState extends State<_ThreadPickerSheet> {
  List<ThreadEntry> _threads = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final threads = await DatabaseService.getAllThreads();
    if (!mounted) return;
    setState(() {
      _threads = threads;
      _selected
        ..clear()
        ..addAll(threads
            .where((t) => t.memberLocalIds.contains(widget.memoLocalId))
            .map((t) => t.id));
      _loading = false;
    });
  }

  Future<void> _toggle(ThreadEntry thread, bool selected) async {
    final members = List<int>.from(thread.memberLocalIds);
    if (selected) {
      if (!members.contains(widget.memoLocalId)) members.add(widget.memoLocalId);
    } else {
      members.remove(widget.memoLocalId);
    }
    thread
      ..memberLocalIds = members
      ..syncStatus = SyncStatus.pending;
    await DatabaseService.saveThread(thread);
    _changed = true;
    await _load();
  }

  Future<void> _createAndAdd() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建事件串'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如：工位蛐蛐',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;

    final thread = ThreadEntry()
      ..title = title
      ..memberLocalIds = [widget.memoLocalId]
      ..syncStatus = SyncStatus.pending;
    await DatabaseService.saveThread(thread);
    _changed = true;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 16),
                const Text('归入事件串',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _createAndAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建'),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const Divider(height: 1),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (_threads.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('还没有事件串，点右上角新建',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final thread in _threads)
                      CheckboxListTile(
                        value: _selected.contains(thread.id),
                        title: Text(thread.title),
                        subtitle: Text(
                          '${thread.memberLocalIds.length} 篇'
                          '${thread.status == ThreadStatus.resolved ? " · 已完结" : ""}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        activeColor: AppColors.primary,
                        onChanged: (v) => _toggle(thread, v ?? false),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton(
                onPressed: () => Navigator.pop(context, _changed),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 新建事件串并一次性搜索加入多篇历史日记。
///
/// 纯手动创建路线下这是必需配套：否则「工位蛐蛐」那几篇要一篇篇挂上，不可用。
Future<bool?> showThreadCreateSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ThreadCreateSheet(),
  );
}

class _ThreadCreateSheet extends StatefulWidget {
  const _ThreadCreateSheet();

  @override
  State<_ThreadCreateSheet> createState() => _ThreadCreateSheetState();
}

class _ThreadCreateSheetState extends State<_ThreadCreateSheet> {
  final _titleController = TextEditingController();
  final _searchController = TextEditingController();
  List<MemoEntry> _results = [];
  final Set<int> _picked = {};
  bool _searching = false;

  @override
  void dispose() {
    _titleController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    final results = await DatabaseService.searchMemos(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  Future<void> _create() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final thread = ThreadEntry()
      ..title = title
      ..memberLocalIds = _picked.toList()
      ..syncStatus = SyncStatus.pending;
    await DatabaseService.saveThread(thread);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '事件串标题',
                  hintText: '例如：工位蛐蛐',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  labelText: '搜索要加入的日记',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ),
              ),
            ),
            if (_picked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('已选 ${_picked.length} 篇',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final memo in _results)
                      CheckboxListTile(
                        value: _picked.contains(memo.id),
                        activeColor: AppColors.primary,
                        title: Text(
                          memo.content.split('\n').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${memo.createdAt.year}-'
                          '${memo.createdAt.month.toString().padLeft(2, '0')}-'
                          '${memo.createdAt.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onChanged: (v) => setState(() {
                          if (v ?? false) {
                            _picked.add(memo.id);
                          } else {
                            _picked.remove(memo.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  TextButton(onPressed: _create, child: const Text('创建')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 在日记详情页加入口**

在 `lib/features/memo_detail/memo_detail_page.dart` 的 `AppBar` `actions` 中，编辑按钮之前插入：

```dart
          IconButton(
            icon: const Icon(Icons.timeline_outlined),
            tooltip: '归入事件串',
            onPressed: () async {
              final changed =
                  await showThreadPickerSheet(context, memoLocalId: memo.id);
              if (changed == true) await _loadThreads();
            },
          ),
```

并在 import 区加入：

```dart
import '../threads/thread_picker_sheet.dart';
```

- [ ] **Step 3: 在事件串列表页加「新建」**

在 `lib/features/threads/threads_view.dart` 的 `AppBar` 中追加：

```dart
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建事件串',
            onPressed: () async {
              final created = await showThreadCreateSheet(context);
              if (created == true) await _load();
            },
          ),
        ],
```

并在 import 区加入：

```dart
import 'thread_picker_sheet.dart';
```

- [ ] **Step 4: 确认编译与全部测试**

```bash
cd /Users/cxb/Code/flutter/memos_local && flutter analyze && flutter test
```

Expected: No issues found；所有测试 PASS

- [ ] **Step 5: Phase 1 完整验收**

按 spec §9 的 Phase 1 验收标准逐条走一遍：

- [ ] 在事件串 Tab 点「新建」，标题填「工位蛐蛐」，搜索关键词一次勾选并加入 4 篇历史日记
- [ ] 打开其中任一篇的详情页，正文上方显示「工位蛐蛐」chip
- [ ] 详情页底部显示 `←  「工位蛐蛐」3/4  →`，点箭头能前后跳转，首篇的「上一篇」和末篇的「下一篇」为禁用态
- [ ] 点中间的标题跳进事件串详情页，4 篇按时间升序排列
- [ ] 断网新建一篇日记，通过详情页的「归入事件串」加入该事件串；恢复网络触发同步后，服务端 `GET /api/v1/threads/{id}` 返回 5 个成员（验证 memo 先推、thread 后推的顺序）
- [ ] 在另一台设备（或清空本地库后重新全量同步）拉取，该事件串及其全部成员正确恢复
- [ ] 删除其中一篇日记，事件串成员数减少，其余成员不受影响

- [ ] **Step 6: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/features/threads/thread_picker_sheet.dart lib/features/threads/threads_view.dart lib/features/memo_detail/memo_detail_page.dart
git commit -m "feat: 事件串选择器与批量加入"
```

---

### Task 15: 编辑器工具栏的事件串入口

spec §7.6 要求手动挂载的主入口在**编辑器工具栏**（§8 列为 Phase 1 交付项）。Task 14 的详情页入口只覆盖了「读到一半想起来要归类」的场景，写的时候顺手挂上仍需本任务。

**Files:**
- Modify: `lib/features/memo_editor/memo_editor_page.dart`

**Interfaces:**
- Consumes: Task 14 的 `showThreadPickerSheet`；`DatabaseService.getAllThreads` / `saveThread` / `getThreadsForMemo`
- Produces: 编辑器状态字段 `Set<int> _pendingThreadIds`；`Future<void> _attachPendingThreads(int memoLocalId)`

**为什么不能直接复用 `showThreadPickerSheet`**：新建日记在保存前没有本地 id，无法作为成员写入。因此编辑器只**记录选择**，等 `saveMemo` 拿到 id 后再落库。

- [ ] **Step 1: 新增状态与落库方法**

在 `_MemoEditorPageState` 的字段声明区加入：

```dart
  /// 编辑器中已选但尚未落库的事件串本地 id
  ///
  /// 新建日记在保存前没有 id，无法作为成员写入，因此先记录选择、保存后再挂。
  final Set<int> _pendingThreadIds = {};

  /// 把当前日记挂到已选事件串上；幂等，重复调用无副作用。
  Future<void> _attachPendingThreads(int memoLocalId) async {
    if (_pendingThreadIds.isEmpty) return;
    for (final threadId in _pendingThreadIds) {
      final thread = await DatabaseService.getThreadById(threadId);
      if (thread == null) continue;
      if (thread.memberLocalIds.contains(memoLocalId)) continue;
      thread
        ..memberLocalIds = [...thread.memberLocalIds, memoLocalId]
        ..syncStatus = SyncStatus.pending;
      await DatabaseService.saveThread(thread);
    }
    debugPrint('[MemoEditor] 已挂载 ${_pendingThreadIds.length} 个事件串');
  }
```

在 import 区加入：

```dart
import '../../data/models/thread_entry.dart';
```

- [ ] **Step 2: 编辑已有日记时预填已有归属**

在 `initState`（或既有的初始化方法）中，若是编辑模式（已有 `memo.id`），加入：

```dart
    DatabaseService.getThreadsForMemo(widget.memo!.id).then((threads) {
      if (!mounted) return;
      setState(() => _pendingThreadIds.addAll(threads.map((t) => t.id)));
    });
```

若编辑器判断编辑模式的字段名不是 `widget.memo`，改用其实际字段（查看该文件顶部 `MemoEditorPage` 的构造参数）。

- [ ] **Step 3: 工具栏加按钮**

在编辑器工具栏（附件/录音/位置那一行）追加一个按钮：

```dart
          IconButton(
            icon: Icon(
              Icons.timeline_outlined,
              color: _pendingThreadIds.isEmpty
                  ? null
                  : AppColors.primary,
            ),
            tooltip: '事件串',
            onPressed: _pickThreads,
          ),
```

并新增选择方法（不复用 `showThreadPickerSheet`，因为此时可能还没有 memo id）：

```dart
  Future<void> _pickThreads() async {
    final threads = await DatabaseService.getAllThreads();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('归入事件串',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              if (threads.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('还没有事件串，可在事件串页新建',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final thread in threads)
                        CheckboxListTile(
                          value: _pendingThreadIds.contains(thread.id),
                          title: Text(thread.title),
                          activeColor: AppColors.primary,
                          onChanged: (v) {
                            setSheetState(() {
                              if (v ?? false) {
                                _pendingThreadIds.add(thread.id);
                              } else {
                                _pendingThreadIds.remove(thread.id);
                              }
                            });
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 4: 保存后落库**

在 `_save()` 方法内，**每一处** `await DatabaseService.saveMemo(memo...)` 之后（当前为第 1285、1347、1370、1382 行，行号会随本任务的插入而变化）紧接着插入：

```dart
      await _attachPendingThreads(memo.id);
```

`_attachPendingThreads` 是幂等的（已是成员则跳过），因此在多条保存分支上重复调用无副作用。

- [ ] **Step 5: 确认编译与全部测试**

```bash
flutter analyze && flutter test
```

Expected: No issues found；所有测试 PASS

- [ ] **Step 6: 手动验证**

- [ ] 新建日记时在工具栏选中「工位蛐蛐」，保存后该事件串成员数 +1
- [ ] 编辑已属于某事件串的日记，打开工具栏按钮时该事件串已勾选
- [ ] 取消勾选后保存，日记仍在事件串中（本任务只做加入，移出走详情页或事件串详情页）—— 这是刻意的：编辑器的取消勾选不触发移除，避免误操作删掉归属

- [ ] **Step 7: 提交**

```bash
cd /Users/cxb/Code/flutter/memos_local
git add lib/features/memo_editor/memo_editor_page.dart
git commit -m "feat: 编辑器工具栏事件串入口"
```

---

## Phase 1 完成标志

- 服务端：`threads` + `thread_members` 两表、6 个接口、`thread` changelog entity、`server-API.md` 已更新
- 客户端：`ThreadEntry` 集合、双向同步（含离线成员映射与冲突）、事件串 Tab、列表页、详情页、日记详情页 chip 与上下篇导航、选择器与批量加入、编辑器工具栏入口
- 全部自动化测试通过：`go test ./...` 与 `flutter test`

**刻意延后到 Phase 2 的一项**：spec §7.5 的「时间线卡片右上角事件串 chip」。§8 的 Phase 1 交付清单未列入该项，且它的另一半（待确认建议的虚线 chip）本就属于 Phase 2 —— 两者共用同一块卡片区域，一起做能避免改两遍布局。

**不在 Phase 1 范围**：`thread_suggestions` 表、`memos.thread_scan_ts` 列、`/ai/thread-summary`、`/ai/thread-match`、后台分析 worker、前台抢占、建议横幅与虚线 chip。这些属于 Phase 2，见 spec §8。
