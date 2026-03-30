# IsleLog

一款离线优先的跨平台日记应用，以 [Memos](https://github.com/usememos/memos) 作为云端同步后端。

---

## 特性

- **离线优先** — 本地 Isar 数据库存储全部数据，无网络时完整可用
- **云端同步** — 与 Memos v0.25+ 服务器双向同步，支持增量和全量两种模式
- **富媒体支持** — 图片（拍照/相册）、音频录制播放、任意文件附件
- **Markdown 渲染** — 完整 Markdown 语法支持，含代码块、待办事项、引用
- **评论系统** — 日记详情页评论区，支持离线创建，自动同步到 Memos
- **标签分类** — 正文中 `#标签` 自动提取，支持侧边栏标签筛选
- **全文搜索** — 同时搜索日记正文和评论内容，关键词高亮
- **地理位置** — 自动获取 GPS 位置并逆地理编码，支持跳转地图
- **日历视图** — 月份日历展示，标注有记录的日期，含农历显示
- **置顶/归档** — 日记可置顶显示或归档整理
- **多平台** — Android / iOS / macOS / Linux / Windows

---

## 截图

> TODO

---

## 快速开始

### 依赖要求

- Flutter 3.x（Dart 3.10.4+）
- Android SDK / Xcode（按目标平台）
- macOS 构建需要 macOS 11.0+（gal 包要求）

### 安装运行

```bash
# 克隆项目
git clone <repo-url>
cd memos_local

# 安装依赖
flutter pub get

# 生成 Isar 代码（首次 / 模型变更后）
dart run build_runner build --delete-conflicting-outputs

# 运行
flutter run
```

### 配置云端同步（可选）

应用可完全离线使用。如需云端同步：

1. 自行部署 [Memos](https://github.com/usememos/memos)（v0.25+）
2. 进入 IsleLog → 侧边栏 → 设置 → 服务器设置
3. 填写服务器地址和 Access Token（在 Memos Web → 设置 → Access Tokens 中生成）
4. 点击"测试连接"验证，保存后即可同步

---

## 技术栈

| 分类 | 技术 |
|------|------|
| UI 框架 | Flutter + Material 3 |
| 本地数据库 | [Isar](https://isar.dev/) 3.x |
| 网络请求 | [Dio](https://pub.dev/packages/dio) 5.x |
| 响应式 | [RxDart](https://pub.dev/packages/rxdart) |
| Markdown | [flutter_markdown](https://pub.dev/packages/flutter_markdown) |
| 日历 | [table_calendar](https://pub.dev/packages/table_calendar) + [lunar](https://pub.dev/packages/lunar) |
| 音频录制 | [record](https://pub.dev/packages/record) |
| 音频播放 | [just_audio](https://pub.dev/packages/just_audio) |
| 位置服务 | [geolocator](https://pub.dev/packages/geolocator) |
| 相册保存 | [gal](https://pub.dev/packages/gal) |
| 配置持久化 | [shared_preferences](https://pub.dev/packages/shared_preferences) |

---

## 同步机制

### 增量同步（日常使用）
仅拉取自上次同步以来有变化的日记（通过 `updated_ts` CEL filter），配合推送本地 pending 条目，高效完成双向同步。

### 全量同步（手动触发）
忽略时间过滤，拉取远端全部日记，并检测删除（本地有但远端已不存在的已同步条目会被物理删除）。适合首次使用或服务器迁移后恢复一致性。

### 评论同步
- 进入日记详情页时，自动在后台拉取该篇日记的评论并更新本地
- 每次同步时，通过 `relations` 字段识别有评论的日记，批量拉取对应评论
- 本地离线创建的评论在下次同步时推送到远端

### 冲突处理
本地和远端均有修改时，标记为 `conflict` 状态并保留本地版本，等待用户手动处理（后续功能）。

---

## 位置服务配置（可选）

应用支持逆地理编码将坐标转为可读地址。需在设置页配置第三方 API Key（任选其一）：

- **高德地图**：在[高德开放平台](https://lbs.amap.com/)申请 Web 服务 Key
- **天地图**：在[天地图开发者平台](https://uums.tianditu.gov.cn/)申请 Key

未配置 API Key 时，位置信息显示为经纬度坐标。

---

## 项目结构

```
lib/
├── main.dart                     # 应用入口
├── data/
│   ├── models/                   # Isar 数据模型（MemoEntry / CommentEntry / TagStat）
│   └── database/                 # DatabaseService（本地 CRUD）
├── services/
│   ├── api/                      # Memos REST API 客户端
│   ├── sync/                     # 双向同步引擎
│   ├── attachment/               # 附件上传下载管理
│   ├── location/                 # 位置获取与逆地理编码
│   ├── settings/                 # 配置持久化
│   └── debug/                    # 文件日志（调试用）
├── features/
│   ├── home/                     # 主页时间线 + 搜索
│   ├── calendar/                 # 日历视图
│   ├── memo_editor/              # 日记编辑器
│   ├── memo_detail/              # 日记详情 + 评论区
│   ├── archive/                  # 归档列表
│   └── settings/                 # 设置页面
└── shared/
    ├── widgets/                  # 主骨架（底部导航 + FAB）
    └── constants/                # 全局颜色 / 字符串 / 尺寸常量
```

---

## 权限说明

| 平台 | 权限 | 用途 |
|------|------|------|
| Android / iOS | 相机 | 拍照添加附件 |
| Android / iOS | 相册读写 | 选取图片、保存图片到相册 |
| Android / iOS | 麦克风 | 录制音频日记 |
| Android / iOS | 位置 | 自动获取当前位置 |
| Android（≤29）| 外部存储写入 | 保存图片到相册 |

---

## License

MIT
