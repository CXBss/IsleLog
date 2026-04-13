# IsleLog

离线优先的跨平台日记应用，以 IsleLog 自定义服务端（兼容 [Memos](https://github.com/usememos/memos) v0.25 API）作为云端同步后端。

---

## 特性

- **离线优先** — 本地 Isar 数据库，无网络时完整可用
- **双向同步** — 增量/全量同步，自动冲突检测与三方 Diff 处理
- **多维记录** — 位置、天气、心情、待办事项、Markdown、标签
- **富媒体** — 图片（拍照/相册）、音频录制播放、任意文件附件
- **文章管理** — 独立文章系统 + 文件夹层级组织
- **版本历史** — 完整编辑历史与 Diff 展示
- **评论系统** — 离线创建，自动同步
- **全文搜索** — 日记 + 评论，关键词高亮
- **日历视图** — 月份高亮 + 农历显示
- **往年今日** — 历史同日日记聚合展示
- **待办汇总** — `- [ ]` / `- [x]` 自动识别与就地勾选
- **多平台** — Android / iOS / macOS / Linux / Windows

---

## 快速开始

### 依赖要求

- Flutter 3.x（Dart 3.10.4+）
- macOS 构建需要 macOS 11.0+（gal 包要求）

### 安装运行

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

### 配置云端同步（可选）

应用可完全离线使用。如需云端同步：

1. 部署 IsleLog 服务端（或兼容的 Memos v0.25+ 实例）
2. IsleLog → 侧边栏 → 设置 → 服务器设置
3. 填写服务器地址和 Access Token，点击"测试连接"验证

---

## 技术栈

| 分类 | 技术 |
|------|------|
| UI 框架 | Flutter + Material 3（绿色主题） |
| 本地数据库 | [Isar](https://isar.dev/) 3.x |
| 网络请求 | [Dio](https://pub.dev/packages/dio) 5.x |
| 响应式 | [RxDart](https://pub.dev/packages/rxdart) |
| Markdown | [flutter_markdown](https://pub.dev/packages/flutter_markdown) |
| 日历 | [table_calendar](https://pub.dev/packages/table_calendar) + [lunar](https://pub.dev/packages/lunar) |
| 音频 | [record](https://pub.dev/packages/record) + [just_audio](https://pub.dev/packages/just_audio) |
| 位置 | [geolocator](https://pub.dev/packages/geolocator) + 高德/天地图逆地理编码 |
| 天气 | 和风天气 API（优先）+ 高德天气 API |
| 路由 | [go_router](https://pub.dev/packages/go_router) 14.x |
| Diff | [diff_match_patch](https://pub.dev/packages/diff_match_patch)（冲突三方对比） |

---

## 同步机制

### 增量同步（日常）
基于 `lastSyncTime` 过滤，仅拉取有更新的条目，再推送本地 pending 条目。

### 全量同步（手动）
拉取全部远端条目，检测本地已同步但远端已删除的条目并物理删除。适用于首次使用或服务器迁移。

### 冲突处理
本地 `pending` + 远端也有更新 → 标记 `conflict`，保留本地版本，`conflictRemoteContent` 存储远端版本。用户在冲突页面进行三方 Diff 对比后选择处理方式。

---

## 项目结构

```
lib/
├── main.dart                              # 入口：DB 初始化 → 种子数据 → 后台同步 → runApp
├── data/
│   ├── models/
│   │   └── memo_entry.dart               # MemoEntry / ArticleEntry / CommentEntry / FolderEntry / TagStat / AttachmentInfo
│   └── database/
│       └── database_service.dart         # 所有 CRUD 入口（Isar 单例）
├── services/
│   ├── api/memos_api_service.dart         # Memos REST API 客户端
│   ├── sync/sync_service.dart             # 双向同步引擎
│   ├── attachment/attachment_service.dart # 附件上传/本地缓存
│   ├── weather/weather_service.dart       # 天气服务
│   ├── location/location_service.dart     # GPS + 逆地理编码
│   └── settings/settings_service.dart    # 配置持久化
├── features/
│   ├── home/                              # 主页时间线（分页、标签筛选、冲突/置顶展示）
│   ├── calendar/                          # 日历视图（月份高亮、农历、日期详情）
│   ├── memo_editor/                       # 编辑器（格式工具栏、附件、位置、天气、心情）
│   ├── memo_detail/                       # 详情页（Markdown、附件、评论区）
│   ├── articles/                          # 文章 + 文件夹管理（文件浏览器样式）
│   ├── todo/                              # 待办汇总（就地勾选）
│   ├── on_this_day/                       # 往年今日
│   ├── conflict/                          # 冲突处理（三方 Diff）
│   ├── revision_history/                  # 版本历史
│   ├── archive/                           # 归档列表
│   └── settings/                          # 服务器 + API Key 配置
└── shared/
    ├── widgets/main_scaffold.dart         # 主骨架：5-Tab 底部导航 + 居中 FAB
    └── constants/app_constants.dart       # 颜色 / 字符串 / 尺寸常量
```

---

## 第三方 API 配置（可选）

在设置 → API 设置中配置：

| 服务 | 用途 | 申请地址 |
|------|------|------|
| 高德地图 Web 服务 Key | 逆地理编码 + 天气 | [高德开放平台](https://lbs.amap.com/) |
| 和风天气 API Key | 天气（优先级更高） | [和风天气](https://dev.qweather.com/) |
| 天地图 Key | 逆地理编码（备选） | [天地图开发者平台](https://uums.tianditu.gov.cn/) |

未配置时，位置显示经纬度坐标，天气功能不可用。

---

## 权限说明

| 平台 | 权限 | 用途 |
|------|------|------|
| Android / iOS | 相机 | 拍照附件 |
| Android / iOS | 相册读写 | 选图、保存图片 |
| Android / iOS | 麦克风 | 录制音频 |
| Android / iOS | 位置 | 自动获取当前位置 |

---

## License

MIT
