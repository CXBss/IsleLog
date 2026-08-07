# IsleLog 桌面端重写规格文档（Wails + Go）

> 本文档基于对 Flutter 版 IsleLog 源码的完整分析，供 Wails 桌面端重写参考。

---

## 一、项目概述

**IsleLog** 是一个离线优先的日记/备忘录应用，以 [Memos](https://github.com/usememos/memos) 作为云端同步后端。

- **Flutter 版本**：v1.1.0，全平台（Android/iOS/macOS/Linux/Windows）
- **重写目标**：Wails（Go 后端 + Web 前端），专注桌面端（macOS/Linux/Windows）
- **API 后端**：`server-API.md` 中定义的 IsleLog 自定义服务端（兼容 Memos v0.25 API）

---

## 二、数据模型

### 2.1 Memo（日记）

本地持久化对象，对应服务端 `Memo` 资源。

```
id                  int64       本地主键（自增）
memosName           string?     服务端资源名 "memos/{id}"，未同步时为空
content             string      正文（Markdown + #标签）
createdAt           time.Time   创建时间（排序依据，带索引）
updatedAt           time.Time   更新时间
tags                []string    从 content 自动解析的 #标签
location            string?     地址文本（逆地理编码结果）
latitude            float64?    WGS84 纬度
longitude           float64?    WGS84 经度
syncStatus          SyncStatus  pending | synced | conflict
lastSyncAt          time.Time?  上次成功同步时间
isDeleted           bool        软删除标记
isArchived          bool        归档标记
isPinned            bool        置顶标记
attachmentsJson     []string    附件列表（JSON 序列化的 AttachmentInfo 数组）
conflictRemoteContent string?   冲突时保存的远端版本正文
originalContent     string?     编辑前内容快照（三方 Diff 对比用）
todoStatus          TodoStatus  none | hasPending | allDone（带索引）
pendingTodoCount    int         未完成待办数量
weatherJson         string?     天气信息（JSON 序列化的 WeatherInfo）
mood                string?     心情（"happy"/"sad"/"calm"... 见下文）
```

**SyncStatus 枚举**：
```
pending   本地有变更，待推送到服务端
synced    已与服务端同步
conflict  本地 pending 且服务端也有更新，需用户处理
```

**TodoStatus 枚举**：
```
none        无待办项（- [ ] / - [x]）
hasPending  有至少一条未完成的 - [ ]
allDone     全部完成，只有 - [x]
```

**标签解析规则**：
- 扫描 content 中所有 `#标签`（不含特殊字符）
- 存入 tags 字段
- 保存时自动触发

**待办扫描规则**：
- `- [ ]` 计入 pendingTodoCount
- `- [x]` 或 `- [X]` 为已完成
- 扫描结果更新 todoStatus

### 2.2 Article（文章）

独立的文章对象，带文件夹层级。

```
id                  int64
articleName         string?     "articles/{id}"
title               string      文章标题
content             string      Markdown 正文
folderName          string?     "folders/{id}"（所属文件夹）
localFolderId       int64?      本地文件夹 ID（离线时关联用）
visibility          string      PRIVATE | PROTECTED | PUBLIC
isPinned            bool
isDeleted           bool
isArchived          bool
createdAt           time.Time
updatedAt           time.Time
syncStatus          SyncStatus
lastSyncAt          time.Time?
conflictRemoteContent string?
conflictRemoteTitle   string?
originalContent     string?
originalTitle       string?
attachmentsJson     []string
```

### 2.3 Comment（评论）

日记的评论，服务端本质也是 memo。

```
id                  int64
memosName           string?     评论自身的服务端资源名 "memos/{id}"
parentMemosName     string?     父日记的服务端资源名（带索引）
memoId              int64?      父日记的本地 ID（离线关联用）
content             string      评论内容（Markdown）
creatorName         string      "users/{id}"
location            string?     发评论时的地理位置
createdAt           time.Time
updatedAt           time.Time
syncStatus          SyncStatus
lastSyncAt          time.Time?
isDeleted           bool
```

### 2.4 Folder（文件夹）

```
id                  int64
folderName          string?     "folders/{id}"
title               string      文件夹名称
parentFolderName    string?     父文件夹 "folders/{id}"
localParentFolderId int64?      离线关联
isDeleted           bool
createdAt           time.Time
updatedAt           time.Time
syncStatus          SyncStatus
lastSyncAt          time.Time?
```

### 2.5 AttachmentInfo（附件，非独立集合）

序列化为 JSON 字符串，存入 memo/article 的 `attachmentsJson` 字段。

```go
type AttachmentInfo struct {
    LocalId        string  // UUID，本地生命周期唯一
    RemoteResName  string  // "attachments/{id}"，上传后填充
    LocalPath      string  // 本地文件绝对路径
    RemoteUrl      string  // 服务端相对/完整 URL
    Filename       string  // 原始文件名
    MimeType       string  // MIME 类型
    SizeBytes      int64
    UploadFailed   bool
}
```

**辅助方法**：
- `FullUrl(baseUrl string) string` - 拼接完整 URL
- `MarkdownLink(baseUrl string) string` - 生成 Markdown 引用
- `IsImage() bool`
- `IsAudio() bool`

### 2.6 WeatherInfo（天气，嵌套 JSON）

```go
type WeatherInfo struct {
    Condition string  // "晴"/"多云"/"雨"...
    Detail    string  // "多云，15°C，南风≤3级，湿度60%"（展示字符串）
}
```

### 2.7 TagStat（标签统计缓存）

```
name    string  标签名（唯一键，upsert）
count   int     关联日记数量
```

### 2.8 心情选项（MoodOption）

```
key:      "happy" | "excited" | "calm" | "tired" | "anxious" | "sad" | "angry" | "sick" | "grateful"
label:    "开心" | "兴奋" | "平静" | "疲惫" | "焦虑" | "难过" | "生气" | "不适" | "感恩"
icon:     对应的图标（emoji 或 SVG）
color:    HEX 颜色值
```

---

## 三、本地数据库

推荐使用 **SQLite**（via `gorm` 或 `modernc.org/sqlite`）。

### 3.1 表结构映射

直接按 §2 数据模型建表，以下字段需要注意：

- `tags`：JSON 数组字符串，需要自己解析（或用 FTS5 Virtual Table 支持全文搜索）
- `attachmentsJson`：JSON 字符串数组
- `syncStatus`、`todoStatus`：存整数枚举
- 所有 `*time.Time` 字段存 UTC ISO8601 字符串或 Unix 时间戳

### 3.2 关键查询

```sql
-- 分页（不含删除/归档）
SELECT * FROM memos WHERE is_deleted=0 AND is_archived=0 ORDER BY created_at DESC LIMIT ? OFFSET ?

-- 置顶
SELECT * FROM memos WHERE is_pinned=1 AND is_deleted=0 ORDER BY created_at DESC

-- 冲突
SELECT * FROM memos WHERE sync_status=2 AND is_deleted=0

-- 按标签筛选（SQLite JSON 解析）
SELECT * FROM memos WHERE json_each.value=? AND is_deleted=0

-- 全文搜索（content + tags）
SELECT * FROM memos WHERE content LIKE '%' || ? || '%' AND is_deleted=0

-- 日历某月有记录的天
SELECT DISTINCT date(created_at) FROM memos WHERE created_at >= ? AND created_at < ? AND is_deleted=0

-- 往年今日（同月同日）
SELECT * FROM memos WHERE strftime('%m-%d', created_at)=strftime('%m-%d', ?) AND is_deleted=0

-- 待办列表
SELECT * FROM memos WHERE todo_status != 0 AND is_deleted=0

-- 全文搜索（推荐 FTS5）
CREATE VIRTUAL TABLE memos_fts USING fts5(content, content=memos, content_rowid=id);
```

### 3.3 数据库服务接口（DatabaseService）

```go
// 日记 CRUD
func SaveMemo(memo *Memo, skipTimestamp bool) error
func SoftDeleteMemo(id int64) error      // 软删除，syncStatus=pending
func HardDeleteMemo(id int64) error      // 物理删除
func ArchiveMemo(id int64) error
func UnarchiveMemo(id int64) error
func PinMemo(id int64) error
func UnpinMemo(id int64) error
func MarkAllPending() error              // 强制全量推送

// 日记查询
func GetMemosPaged(offset, limit int) ([]*Memo, error)
func GetMemoCount() (int, error)
func GetPinnedMemos() ([]*Memo, error)
func GetConflictMemos() ([]*Memo, error)
func GetPendingSyncMemos() ([]*Memo, error)
func GetAllSyncedMemos() ([]*Memo, error)
func GetMemoById(id int64) (*Memo, error)
func GetMemoByMemosName(name string) (*Memo, error)
func GetMemosByDate(date time.Time) ([]*Memo, error)
func GetDaysWithMemoInMonth(year, month int) ([]int, error)
func GetMemosOnThisDay(date time.Time) ([]*Memo, error)
func GetMemosByTag(tag string) ([]*Memo, error)
func SearchMemos(query string) ([]*Memo, error)
func SearchArchivedMemos(query string) ([]*Memo, error)
func GetArchivedMemos() ([]*Memo, error)

// 标签统计
func GetCachedTagStats() ([]*TagStat, error)
func SaveTagStats(counts map[string]int) error
func GetAllTagCounts() (map[string]int, error)  // 本地扫描统计

// 评论
func SaveComment(comment *Comment, skipTimestamp bool) error
func GetCommentsForMemo(memoId int64) ([]*Comment, error)
func DeleteCommentForMemo(id int64) error
func GetPendingSyncComments() ([]*Comment, error)

// 文章
func SaveArticle(article *Article, skipTimestamp bool) error
func GetArticlesPaged(offset, limit int) ([]*Article, error)
func GetArticleCount() (int, error)
func SearchArticles(query string) ([]*Article, error)
func GetPendingSyncArticles() ([]*Article, error)

// 文件夹
func SaveFolder(folder *Folder, skipTimestamp bool) error
func GetFoldersByParent(parentName string) ([]*Folder, error)
func GetPendingSyncFolders() ([]*Folder, error)

// 数据库工具
func WatchDbChanges() <-chan struct{}  // 监听变更，返回 channel（300ms debounce）
func SeedIfEmpty(mocks []*Memo) error // 首次启动种子数据
func ClearAll() error                 // 清空所有数据
```

---

## 四、API 服务（MemosApiService）

> **重要**：所有 API 细节以 `server-API.md` 为准，以下是接口摘要。

认证方式：`Authorization: Bearer {token}`

### 4.1 Memo CRUD

```go
func ListMemos(pageSize int, pageToken, filter, state string) (*ListMemosResponse, error)
func ListAllMemos(filter, state string) ([]*RemoteMemo, error)   // 自动翻页
func GetMemo(id string) (*RemoteMemo, error)
func CreateMemo(req *CreateMemoRequest) (*RemoteMemo, error)
func UpdateMemo(name string, req *UpdateMemoRequest) (*RemoteMemo, error)
func DeleteMemo(name string) error
func ArchiveMemo(name string) error
func UnarchiveMemo(name string) error
func PinMemo(name string) error
func UnpinMemo(name string) error
```

**CreateMemoRequest 关键字段**：
```go
type CreateMemoRequest struct {
    Content         string
    Visibility      string   // PRIVATE | PROTECTED | PUBLIC
    AttachmentNames []string // ["attachments/123"]
    DisplayTime     *time.Time
    Location        *Location
    Mood            string
    Weather         *WeatherInfo
}
```

### 4.2 评论

```go
func ListMemoComments(memoName string) ([]*RemoteMemo, error)
func CreateMemoComment(memoName, content string) (*RemoteMemo, error)
```

### 4.3 附件

```go
func UploadAttachment(data []byte, filename, mimeType, memoName string) (*RemoteAttachment, error)
func DeleteAttachment(name string) error
```

### 4.4 文章

```go
func ListArticles(pageSize int, pageToken, state string) (*ListArticlesResponse, error)
func ListAllArticles(state string) ([]*RemoteArticle, error)
func GetArticle(id string) (*RemoteArticle, error)
func CreateArticle(req *CreateArticleRequest) (*RemoteArticle, error)
func UpdateArticle(name string, req *UpdateArticleRequest) (*RemoteArticle, error)
func DeleteArticle(name string) error
```

### 4.5 文件夹

```go
func ListFolders() ([]*RemoteFolder, error)
func GetFolder(id string) (*RemoteFolder, error)
func CreateFolder(title, parentName string) (*RemoteFolder, error)
func UpdateFolder(name, title, parentName string) (*RemoteFolder, error)
func DeleteFolder(name string) error
```

### 4.6 统计与配置

```go
func GetUserStats(userName string) (*UserStats, error)   // 标签统计等
func TestConnection() (*UserInfo, error)                 // 测试连接，返回用户信息
```

### 4.7 变更日志（增量同步游标）

```go
func GetLatestChangelog() (*Changelog, error)
func ListChangelogs(sinceId int64) ([]*Changelog, error)
```

### 4.8 版本历史

```go
func ListMemoRevisions(memoName string) ([]*MemoRevision, error)
func GetMemoRevisionDetail(memoName string, version int) (*MemoRevisionDetail, error)
```

---

## 五、设置服务（SettingsService）

使用 SQLite 单独一张表或 JSON 文件持久化。

| 配置项 | 类型 | 说明 |
|---|---|---|
| `serverUrl` | string | Memos 服务器地址，不含末尾斜杠 |
| `accessToken` | string | Bearer Token |
| `lastSyncTime` | time.Time | 上次成功同步时间（UTC） |
| `amapKey` | string | 高德 API Key（天气+地理编码） |
| `qweatherKey` | string | 和风天气 API Key |
| `tiandituKey` | string | 天地图 API Key |
| `favoriteCities` | []string | 常用城市列表 |
| `lastChangelogId` | int64 | 增量同步游标 |
| `themeMode` | string | "system" \| "light" \| "dark" |
| `isConfigured` | bool | 是否已配置服务器 |

---

## 六、同步引擎（SyncService）

### 6.1 同步模式

```
SyncAll()   增量同步（基于 lastSyncTime 过滤，Push + Pull）
SyncFull()  全量同步（拉取全部，检测远端删除，保存 changelogId）
```

### 6.2 Push 阶段

遍历所有 `syncStatus == pending` 的条目：

1. `isDeleted == true && memosName != ""`
   → `api.DeleteMemo(memosName)` → 本地 `HardDeleteMemo(id)`

2. `memosName == ""`（新建）
   → 上传附件（先传附件，再写 memo）
   → `api.CreateMemo(...)` → 回写 `memosName`
   → `syncStatus = synced`

3. 其他（更新）
   → 上传附件
   → `api.UpdateMemo(...)` + 按需 pin/unpin
   → `syncStatus = synced`

### 6.3 Pull 阶段（合并规则）

| 情况 | 处理 |
|---|---|
| 远端有，本地无 | 新增到本地，skipTimestamp=true |
| 本地 synced，远端有更新 | 覆盖为远端版本，skipTimestamp=true |
| 本地 pending，远端也有更新 | 标记 conflict，conflictRemoteContent=远端内容，originalContent 设为编辑前快照 |
| 本地有（synced），远端无（仅全量）| 物理删除本地 |

### 6.4 文章/文件夹同步

- 先同步文件夹（处理本地 pending，回写 folderName）
- 再同步文章（用 localFolderId 找到对应 folderName）

### 6.5 评论同步

```go
func SyncMemoComments(memoName string) error  // 详情页进入时调用
```

### 6.6 单条推送

```go
func PushSingleMemo(memo *Memo) error  // 冲突解决后直接推送
```

### 6.7 后台推送

```go
func PushPendingBackground()  // 保存后静默后台推送，失败不报错
```

### 6.8 返回值

```go
type SyncResult struct {
    Pushed  int
    Pulled  int
    Deleted int
    Error   error
}
```

---

## 七、功能页面规格

### 7.1 主页时间线（HomeView）

**展示结构（从上到下）**：
1. **冲突条目** - 可折叠，红色警告提示
2. **置顶条目** - 可折叠
3. **普通时间线** - 虚拟滚动/分页加载

**功能**：
- 标签筛选（侧边栏/下拉，显示标签名+数量）
- 搜索（日记 content + 评论 content 全文）
- 同步按钮（触发 `SyncAll()`）
- 新建按钮（进入编辑器）
- 数据库变更自动刷新（debounce 300ms）

**时间线卡片内容**：
- 日期时间（右上角，格式：今天/昨天/具体日期）
- 正文（Markdown 预览，最多 6 行，超出"展示更多"）
- 图片缩略图（最多 3 张，超出 "+N" 角标）
- 标签 Chip（`#标签` 样式）
- 底部行：位置/天气/心情图标 + 同步状态图标 + 评论数 + 菜单
- 置顶图标（右上角）

**卡片菜单**：编辑 | 删除（确认弹窗）| 置顶/取消置顶 | 归档 | 版本历史

### 7.2 日历视图（CalendarView）

- 月度视图（每格显示公历日期 + 农历）
- 有日记的日期显示浅绿背景高亮
- 点击某天展开该天的日记列表
- 月份切换时查询当月有记录天数
- "往年今日"入口

### 7.3 日记编辑器（MemoEditorPage）

**新建模式**：
- 初始日期：今天（或日历传入的日期）
- 自动后台获取当前位置（桌面端可选）
- 可选获取天气

**编辑模式**：
- 加载已有日记内容
- 显示已有位置/天气

**工具栏第一行**（格式化）：
- `#` 标题 | **B** 粗体 | *I* 斜体 | `` ` `` 代码 | 有序列表 | 无序列表 | 待办项 | 时间戳

**工具栏第二行**（插入）：
- 录音 | 拍照/选图 | 文件附件 | 位置图标+文本 | 天气选择 | 心情选择

**心情选择**：9 种预设（开心/兴奋/平静/疲惫/焦虑/难过/生气/不适/感恩）

**标签提示**：输入 `#` 时弹出候选标签下拉（从本地标签统计匹配）

**快捷键**（桌面）：
- `Ctrl/Cmd + S` - 保存
- `Ctrl/Cmd + Enter` - 保存并关闭

**保存流程**：
1. 解析标签 → 更新 tags
2. 扫描待办 → 更新 todoStatus / pendingTodoCount
3. 保存到本地 DB（SaveMemo）
4. 后台静默推送（PushPendingBackground）

### 7.4 日记详情页（MemoDetailPage）

**展示内容**：
- Markdown 渲染正文
- 图片附件（网格，支持点击放大、保存、分享）
- 音频附件（内嵌播放器）
- 文件附件（Chip，点击用系统默认应用打开）
- 元信息：位置/天气/心情/标签
- 创建/更新时间

**操作**：
- 编辑按钮 → 跳转编辑器
- 删除按钮 → 确认弹窗 → 软删除
- 版本历史按钮 → 打开版本历史页

**评论区**：
- 评论列表（Markdown 渲染）
- 底部固定输入框
- 右键/长按评论 → 编辑/删除菜单
- 编辑模式：输入框显示蓝色"正在编辑"提示
- `Ctrl/Cmd + Enter` 提交评论

**进入时后台操作**：
- 拉取最新评论（`SyncMemoComments`）
- 获取当前位置（用于评论附加位置）

### 7.5 冲突处理（ConflictPage）

**三方对比**：
- originalContent（编辑前快照）
- content（本地当前版本）
- conflictRemoteContent（服务端版本）

**处理方式**：
1. **保留本地** → 跳转编辑器（可调整）→ 推送
2. **覆盖为远端** → content = conflictRemoteContent → 推送
3. **编辑合并** → 手动编辑文本 → 推送

**Diff 算法**：使用 [sergi/go-diff](https://github.com/sergi/go-diff) 计算文本差异，op 对应 `Equal/Insert/Delete`。

### 7.6 版本历史（RevisionHistoryPage）

- 调用 `api.ListMemoRevisions(memoName)` 获取列表
- 列表展示：版本号、时间、变更字段名称
- 点击版本 → 调用 `api.GetMemoRevisionDetail` 获取详情
- 详情展示：每个字段的旧值/新值，文本字段显示 Diff 高亮

### 7.7 文章管理（ArticlesView）

**文件浏览器样式**：
- 面包屑导航（根 → 文件夹1 → 文件夹2 → ...）
- 文件夹行（点击进入，点击展开图标原地展开）
- 文章行（点击进入编辑器）
- 搜索（全文）
- DB 变更自动刷新

**文章编辑器（ArticleEditorPage）**：
- 标题输入框
- 正文编辑器（Markdown，工具栏与日记编辑器相同）
- 文件夹选择器（可离线新建文件夹）
- 可见性（PRIVATE/PROTECTED/PUBLIC）
- 置顶/归档开关
- 附件管理

### 7.8 待办视图（TodoView）

- 汇总所有 `todoStatus != none` 的日记
- 筛选：全部 / 有未完成 / 全部完成
- 待办项可就地勾选（直接修改 content 中的 `- [ ]` / `- [x]`）
- 显示每条日记的剩余待办数

### 7.9 往年今日（OnThisDayPage）

- 展示历史上与当前选中日期相同月日的所有日记
- 按年份分组（新→旧）
- 日期选择器 + 前一天/后一天导航
- "返回今天"按钮

### 7.10 归档视图（ArchiveView）

- 所有已归档日记列表（倒序）
- 搜索
- 点击进入详情

### 7.11 设置页

**服务器设置（ServerSettings）**：
- 服务器地址（URL 输入 + 测试连接按钮）
- Access Token（密码输入框）
- 连接状态展示（用户名/头像）

**API 设置（ApiSettings）**：
- 高德 API Key
- 和风天气 API Key
- 天地图 API Key
- 常用城市列表

**数据管理**：
- 强制全量推送（标记所有条目 pending，再 SyncFull）
- 清除本地缓存（确认弹窗 → ClearAll）
- 导出日志

**外观**：
- 主题切换（跟随系统/亮色/暗色）

---

## 八、天气服务

### 8.1 优先级
1. 和风天气 API（`qweatherKey`）
2. 高德天气 API（`amapKey`，需 WGS84→GCJ-02 转换）

### 8.2 接口

```go
func FetchWeatherByCoords(lat, lng float64) (*WeatherInfo, error)
func FetchWeatherByCity(cityName string) (*WeatherInfo, error)
```

### 8.3 缓存

同一坐标/城市 30 分钟内不重复请求。

---

## 九、地理位置服务

### 9.1 接口

```go
type LocationInfo struct {
    Latitude  float64
    Longitude float64
    Address   string  // 逆地理编码结果
}

func GetLocation() (*LocationInfo, error)
func OpenMapFromCoords(lat, lng float64, label string) error  // 系统地图跳转
```

### 9.2 逆地理编码优先级

1. 高德 API（WGS84→GCJ-02 转换后查询）
2. 天地图 API（WGS84 直接查询）

### 9.3 桌面端说明

- macOS：使用 `CoreLocation` 系统框架（需要权限）
- Windows：使用 Windows Location API
- Linux：使用 GeoClue2 或直接调用 IP 定位降级

---

## 十、附件服务

### 10.1 在线上传

```go
func UploadToServer(filePath, filename, mimeType, memoName string) (*AttachmentInfo, error)
// 1. 读取文件（可选压缩图片）
// 2. 复制到本地备份目录
// 3. 上传到服务端
// 4. 返回含 localPath + remoteUrl 的 AttachmentInfo
```

### 10.2 离线存储

```go
func SaveLocally(filePath, filename, mimeType string) (*AttachmentInfo, error)
// 1. 复制到本地目录（{AppData}/isle_attachments/{uuid}/）
// 2. 返回仅含 localPath 的 AttachmentInfo
```

### 10.3 本地存储路径

```
{AppData}/isle_attachments/{localId}/
    ├── original.jpg
    ├── compressed.jpg  （可选）
    └── metadata.json
```

### 10.4 批量补传（同步时调用）

```go
func UploadPendingAttachments(attachments []AttachmentInfo, apiService *MemosApiService) ([]AttachmentInfo, error)
// 遍历 remoteResName 为空但 localPath 非空的附件，批量上传
```

---

## 十一、主应用结构（Wails 视角）

### 11.1 Go 后端导出方法

Wails 通过 `app.go` 暴露给前端的核心方法：

```go
// 日记
GetMemosPaged(offset, limit int) ([]*Memo, error)
GetPinnedMemos() ([]*Memo, error)
GetConflictMemos() ([]*Memo, error)
SaveMemo(memo *Memo) error
DeleteMemo(id int64) error
ArchiveMemo(id int64) error
PinMemo(id int64, pin bool) error
SearchMemos(query string) ([]*Memo, error)
GetMemosByDate(date string) ([]*Memo, error)
GetDaysWithMemoInMonth(year, month int) ([]int, error)
GetMemosOnThisDay(date string) ([]*Memo, error)

// 评论
GetCommentsForMemo(memoId int64) ([]*Comment, error)
SaveComment(comment *Comment) error
DeleteComment(id int64) error

// 文章
GetArticlesPaged(offset, limit int) ([]*Article, error)
SaveArticle(article *Article) error
GetFoldersByParent(parentName string) ([]*Folder, error)
SaveFolder(folder *Folder) error

// 同步
SyncAll() (SyncResult, error)
SyncFull() (SyncResult, error)
TestConnection() (*UserInfo, error)

// 标签统计
GetTagStats() ([]*TagStat, error)

// 设置
GetSettings() (*Settings, error)
SaveSettings(settings *Settings) error

// 附件
UploadFile(filePath, memoName string) (*AttachmentInfo, error)
PickFile() (string, error)              // 系统文件选择对话框

// 天气
GetWeather(lat, lng float64) (*WeatherInfo, error)
GetWeatherByCity(city string) (*WeatherInfo, error)

// 位置
GetCurrentLocation() (*LocationInfo, error)
OpenMapFromCoords(lat, lng float64, label string) error

// 版本历史
GetMemoRevisions(memoName string) ([]*MemoRevision, error)
GetMemoRevisionDetail(memoName string, version int) (*MemoRevisionDetail, error)

// 工具
ClearAllData() error                    // 危险操作，需前端确认
MarkAllPending() error
```

### 11.2 前端事件（数据库变更通知）

Go 后端通过 Wails Events 通知前端刷新：

```go
runtime.EventsEmit(ctx, "db:changed")  // 任何数据库写操作后发出
```

前端监听 `db:changed` 事件，debounce 300ms 后刷新当前视图。

### 11.3 应用启动流程

```go
func (a *App) startup(ctx context.Context) {
    // 1. 初始化 SQLite 数据库
    db, _ := InitDatabase()
    a.db = db

    // 2. 首次启动写入模拟数据
    db.SeedIfEmpty(mockMemos)

    // 3. 加载设置
    settings, _ := db.GetSettings()
    a.apiService = NewMemosApiService(settings.ServerUrl, settings.AccessToken)
    a.syncService = NewSyncService(a.apiService, a.db)

    // 4. 后台增量同步
    if settings.IsConfigured {
        go a.syncService.SyncAll()
    }
}
```

---

## 十二、颜色主题

使用绿色主题，支持亮色/暗色切换。

```css
/* CSS 变量 */
--color-primary: #4CAF50;
--color-primary-dark: #2E7D32;
--color-primary-light: #E8F5E9;
--color-primary-lighter: #F1F8E9;
--color-timeline-bar: #C8E6C9;
--color-scaffold-bg: #F2F4F6;
--color-surface: #FFFFFF;
--color-text-body: #333333;
--color-error: #F44336;
```

---

## 十三、键盘快捷键

| 快捷键 | 功能 |
|---|---|
| `Ctrl/Cmd + N` | 新建日记 |
| `Ctrl/Cmd + S` | 保存日记/文章 |
| `Ctrl/Cmd + Enter` | 保存并关闭 / 提交评论 |
| `Ctrl/Cmd + F` | 搜索 |
| `Ctrl/Cmd + R` | 刷新/同步 |
| `Escape` | 关闭当前弹窗 |

---

## 十四、重写注意事项

### 14.1 必须保留的逻辑

1. **`memosName` 不设 unique 约束**：未同步的日记 memosName 均为空，多条可以并存
2. **skipTimestamp 标志**：同步写入时不更新 updatedAt，避免触发再次同步
3. **冲突三方对比**：originalContent（改前）/ content（本地新）/ conflictRemoteContent（远端）
4. **离线文件夹关联**：通过 localFolderId 关联，同步后用 folderName 替代
5. **附件先上传再写 memo**：createMemo/updateMemo 的 attachmentNames 需要服务端 resName

### 14.2 与 Flutter 版的差异点

1. **平台**：桌面端无需考虑移动端 UI 模式（无 BottomNavigationBar）
2. **定位**：桌面端定位 API 不同，需要平台特定实现
3. **音频录制**：桌面端需要不同的录音库
4. **文件系统**：桌面端附件路径使用用户 AppData 目录
5. **推送通知**：桌面端可以使用系统托盘 + 原生通知
6. **后台同步**：可以通过定时器（`time.Ticker`）实现定期自动同步

### 14.3 推荐技术选型（仅供参考）

| 需求 | 推荐库 |
|---|---|
| Web 框架 | Vue 3 + TypeScript |
| 状态管理 | Pinia |
| Markdown 渲染 | marked + highlight.js |
| Markdown 编辑 | CodeMirror 6 |
| Diff | google/diff-match-patch（JS 版） |
| 日历 | FullCalendar 或 自实现 |
| 虚拟滚动 | vue-virtual-scroller |
| SQLite（Go）| modernc.org/sqlite（纯 Go，无 CGO） |
| HTTP 客户端（Go）| net/http 标准库 |
| 图片处理（Go）| github.com/disintegration/imaging |
| Diff（Go）| github.com/sergi/go-diff |

---

## 十五、功能优先级建议

**Phase 1（核心可用）**：
- [ ] SQLite 数据库 + CRUD 接口
- [ ] Memos API 客户端
- [ ] 增量/全量双向同步引擎
- [ ] 主页时间线（分页、冲突、置顶）
- [ ] 日记编辑器（文字 + Markdown）
- [ ] 日记详情页
- [ ] 冲突处理

**Phase 2（功能完整）**：
- [ ] 日历视图
- [ ] 标签筛选与统计
- [ ] 评论系统
- [ ] 文件附件（图片、文件）
- [ ] 搜索
- [ ] 归档、待办视图

**Phase 3（高级功能）**：
- [ ] 天气集成
- [ ] 地理位置
- [ ] 心情记录
- [ ] 文章管理（文件夹+编辑）
- [ ] 版本历史
- [ ] 往年今日
- [ ] 音频录制/播放
