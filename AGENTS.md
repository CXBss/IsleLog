# IsleLog - Codex 工作指南

## 分支说明

| 分支 | 定位 | API 参考文档 |
|------|------|-------------|
| `main` | 完全适配标准 Memos 服务端（v0.25） | `memos-openapi.yaml` |
| `server-feat` | 在 main 基础上增加大量自建服务功能（文章/文件夹/版本历史/天气心情等） | `server-API.md` |

**切换分支前务必确认当前所在分支，在哪个分支工作就参考对应的 API 文档，不得混用。**

---

## 强制规则

**服务端 API**：涉及 API 字段/接口/请求体/响应结构，必须先确认当前分支，再查阅对应文档（`main` → `memos-openapi.yaml`，`server-feat` → `server-API.md`），不得凭记忆猜测。

**Isar 模型修改**：修改任何 `@collection` 模型后必须运行：
```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## 项目概览

**IsleLog** — 离线优先日记/备忘录，以自定义 IsleLog 服务端（兼容 Memos v0.25 API）为云端同步后端。

技术栈：Flutter + Material 3 | Isar 3.x（本地 DB）| Dio 5.x | RxDart | go_router 14.x

---

## 关键文件

```
lib/
├── main.dart                              # DB 初始化 → 种子数据 → 后台同步 → runApp
├── data/
│   ├── models/memo_entry.dart             # MemoEntry、ArticleEntry、CommentEntry、FolderEntry、TagStat、AttachmentInfo
│   └── database/database_service.dart    # 所有 CRUD 入口
├── services/
│   ├── api/memos_api_service.dart         # Memos REST API（Dio + Bearer Token）
│   ├── sync/sync_service.dart             # 双向同步引擎（增量/全量/冲突处理）
│   ├── attachment/attachment_service.dart # 附件上传/本地存储
│   ├── weather/weather_service.dart       # 天气（和风优先，高德备选）
│   ├── location/location_service.dart     # GPS + 逆地理编码（高德/天地图）
│   └── settings/settings_service.dart    # SharedPreferences 封装
├── features/
│   ├── home/                              # 主页时间线
│   ├── calendar/                          # 日历视图
│   ├── memo_editor/                       # 编辑器
│   ├── memo_detail/                       # 详情页 + 评论区
│   ├── articles/                          # 文章 + 文件夹管理
│   ├── todo/                              # 待办汇总
│   ├── on_this_day/                       # 往年今日
│   ├── conflict/                          # 冲突处理（三方 Diff）
│   ├── revision_history/                  # 版本历史
│   ├── archive/                           # 归档列表
│   └── settings/                          # 设置页
└── shared/
    ├── widgets/main_scaffold.dart         # 底部 5-Tab + 居中 FAB
    └── constants/app_constants.dart       # AppColors / AppStrings / AppDimens
```

---

## 数据模型要点

**MemoEntry** 关键字段：
- `syncStatus`：`pending` / `synced` / `conflict`
- `conflictRemoteContent`：冲突时的远端版本
- `originalContent`：编辑前快照（三方 Diff 用）
- `todoStatus`：`none` / `hasPending` / `allDone`（自动扫描 `- [ ]` / `- [x]`）
- `weatherJson` / `mood`：天气（JSON）/ 心情字符串

**ArticleEntry** / **FolderEntry**：独立集合，支持离线创建（`localFolderId` 关联）

**`memosName` 不设 unique 索引**：未同步条目均为 null，多条可并存

---

## 核心逻辑

**同步（SyncService）**：
- `syncAll()` — 增量（Pull 先行检测冲突 → Push pending）
- `syncFull()` — 全量（拉取全部 + 远端删除检测）
- `pushPendingBackground()` — 保存后静默后台推送

**冲突规则**：本地 `pending` + 远端有更新 → `conflict`，保留本地，`conflictRemoteContent` = 远端内容

**同步写入**：所有 `saveMemo(skipTimestamp: true)` 避免更新 `updatedAt`

**附件生命周期**：离线时 `saveLocally()`（仅存本地路径），联网后 `_uploadPendingAttachments()` 补传

---

## 颜色常量

```dart
AppColors.primary        #4CAF50  AppColors.primaryDark    #2E7D32
AppColors.primaryLight   #E8F5E9  AppColors.primaryLighter #F1F8E9
AppColors.timelineBar    #C8E6C9  AppColors.scaffoldBg     #F2F4F6
AppColors.surfaceWhite   #FFFFFF  AppColors.textBody       #333333
```

---

## 开发注意事项

- 新增 API 接口：先确认分支（main 查 `memos-openapi.yaml`，server-feat 查 `server-API.md`）→ 加到 `MemosApiService` → 同步逻辑加到 `SyncService`
- Push 逻辑在 `_pushPending`，Pull 合并逻辑在 `_applyRemoteMemo`
- 音频播放优先本地，远端流需带 `Authorization` header
- macOS 最低版本 11.0（gal 包要求）
- 附件路径用 `p.basename()` 取文件名，避免双层目录
