# 内链（日记 ↔ 文章互相引用）设计

日期：2026-09-06
分支：`server-feat`（API 参考 `server-API.md`）
涉及仓库：仅本仓库（Flutter 客户端），服务端无需任何改动

---

## 1. 问题

写日记时经常要回指另一条日记或一篇文章——「跟三月那场暴雨那天一样」「详见《海岛日志设计稿》」。现在只能靠文字描述，读的时候得自己回去翻。

要的是：编辑时能按日期或关键字搜出目标条目并插入一个链接，阅读时点一下直接跳过去。

## 2. 范围

**在范围内**

- 日记编辑器、文章编辑器都能插入链接
- 链接目标可以是日记，也可以是文章（四个方向全通）
- 日记详情页、文章预览模式里的链接可点击跳转

**明确排除**

- **私密空间完全不参与**。Vault 编辑器没有插链接的入口，选择器搜不到 vault 条目，`VaultDetailPage` 不挂点击处理。上一次提交刚切断了明文出口，链接是个新的潜在出口，这里主动关掉。
- 归档条目不出现在选择器搜索结果里（但已归档的条目仍可作为跳转目标被打开，见 6.3）
- 评论输入框不加插入入口（评论区目前没有工具栏）
- 反向链接（「哪些条目引用了这一条」）不做。方案不排斥以后加：正文即事实来源，需要时正则扫一遍就能建索引，不用改数据格式。

## 3. 链接格式

正文里存**标准 Markdown 链接**，目标 URI 用自定义 scheme：

```
[03-12 深圳暴雨地铁停…](islelog://memo/memos/123?lid=45)     已同步的日记
[草稿：年终总结](islelog://memo?lid=45)                        未同步的日记
[《海岛日志设计稿》](islelog://article/articles/7?lid=12)       已同步的文章
[新写的稿子](islelog://article?lid=12)                         未同步的文章
```

`Uri.parse` 之后：

| 部件 | 含义 |
|---|---|
| `scheme` | 固定 `islelog` |
| `host` | 目标类型：`memo` / `article` |
| `path` | 远端资源名（`/memos/123`、`/articles/7`），未同步时为空 |
| `lid` | 目标在本机 Isar 的自增主键 |

远端名整段放进 path，不做 `memos/123` ↔ `memos-123` 这类字符替换。

### 为什么是双标识

这是离线优先带来的核心矛盾：本地新建但还没推送的条目没有 `memosName` / `articleName`，而 Isar 自增 id 各设备互不相同。

- 目标已同步 → 两个标识都写，跨设备可解析
- 目标未同步 → 只写 `lid`，本机可用；换设备打开时给一句明确提示
- 目标后来同步了 → **不回写引用方的正文**。回写意味着同步过程要改别的条目的 content，会污染版本历史、可能触发冲突，代价远大于收益。此时 `lid` 兜底仍然在本机有效。

### 为什么不用 `[[wiki 链接]]`

正文会同步到服务端，也可能被别的 Memos 客户端打开。标准 Markdown 链接在那些地方仍是一个可读的链接（只是点不动），`[[...]]` 则是一坨裸文本。而且 `[[` 和中文输入法、正文里已有的方括号会打架。

副作用是好的：复制 Markdown、版本历史、冲突三方 Diff 全都不用改。

## 4. 模块划分

### 新增

| 文件 | 职责 |
|---|---|
| `lib/services/link/memo_link.dart` | 纯函数。`build()` 构造 URI，`parse()` 解析，`labelFor()` 生成显示文字 |
| `lib/services/link/link_resolver.dart` | `resolveTarget()` 纯函数判定；导航薄层负责 `Navigator.push` 和失效提示 |
| `lib/features/link_picker/link_query.dart` | 纯函数：搜索框输入 → 日期区间 或 关键字 |
| `lib/features/link_picker/link_picker_sheet.dart` | 选择器 BottomSheet，返回一个选中目标 |

`memo_link.dart` / `link_query.dart` 是零依赖纯函数模块，与 `memo_write_policy.dart`、`thread_membership_policy.dart`、`tag_insertion.dart` 同类，沿用它们的测试方式。

### 改动

| 文件 | 改动 |
|---|---|
| `memo_editor_page.dart` | 格式化按钮行增加 `Icons.add_link` 按钮 |
| `article_editor_page.dart` | `_buildToolbar()` 增加同一个按钮；`Markdown`（:622）挂 `onTapLink`；新增 `openInPreview` 构造参数（默认 `false`） |
| `memo_detail_page.dart` | `MarkdownBody`（:480）挂 `onTapLink` |
| `database_service.dart` | 新增 `searchLinkTargets()`，内部复用已有的 `searchMemos` / `searchArticles` |
| `memo_timeline_card.dart` | **不改**。卡片里的链接只有样式、不响应点击 |

文章编辑器已经有一个 `Icons.link` 按钮表示普通外链（插入 `[](url)`），内链按钮用 `Icons.add_link`，两者必须在图标和 tooltip 上区分开。

查目标用的 `getMemoByMemosName` / `getMemoById` / `getArticleByArticleName` / `getArticleById` 都已存在，直接用。

## 5. 选择器

入口：编辑器工具栏的内链按钮 → `showModalBottomSheet`（`isScrollControlled`，约 3/4 屏高，键盘弹起时自适应）。

### 输入识别

按顺序匹配，命中即走日期筛选，全不命中走关键字全文搜索：

| 输入 | 解释为 |
|---|---|
| `3-12` `3/12` `03-12` | 今年 3 月 12 日 |
| `2025-03-12` `2025/3/12` `2025年3月12日` | 该日 |
| `2025-03` `2025年3月` | 该月整月 |
| `今天` `昨天` `前天` | 相对日 |
| 其它（含单独的 `2025`） | 关键字 |

单独四位数字不当年份——它更可能是正文里的字。日期比对用 `createdAt`。

搜索框右侧的日历图标弹系统 `showDatePicker`，选完把 `yyyy-MM-dd` 填回输入框，与手输走同一条路。

### 列表

- 顶部三个筛选 chip：全部 / 日记 / 文章
- 搜索框为空时列最近更新的 20 条（日记与文章按 `updatedAt` 混排），不输入也能选
- 日记行 `📝 03-12  深圳暴雨，地铁停运…`；文章行 `📄 《海岛日志设计稿》  03-12`
- 关键字命中部分高亮，沿用 `memo_search_card` 现有做法
- 未同步的条目行尾一个灰色小字「未同步」。不禁用——只是告知这条链接暂时只在本机有效
- 排除：vault 条目、已归档、已软删除，以及**正在编辑的这一条自己**（避免自链）

选择器接受一个可注入的搜索回调，默认走 `DatabaseService`。这是为了 widget 测试不必拖起 Isar。

### 显示文字

`MemoLink.labelFor()` 生成：

- 文章 → `title`
- 日记 → `MM-DD ` + 正文首行摘要；跨年时写成 `YYYY-MM-DD`
- 首行先去掉 Markdown 标记（`#` 标题、`- [ ]` 待办、`>` 引用、`*`/`` ` `` 等行内标记）
- 截断到 12 个字符，超出补 `…`
- **必须清洗掉 `[` `]` `\n`**，否则会撑破 Markdown 链接语法。这是最容易漏的一条

插入的是普通 Markdown 文本，用户想改文字直接在正文里改即可，不额外弹确认框。

### 插入行为

选中后关闭 sheet，在光标处插入 `[标签](islelog://…)`，光标落到插入内容之后，焦点还给正文输入框。不额外补空格，与现有 `_insertAtCursor` 行为一致。

## 6. 跳转与失效处理

### 6.1 解析顺序

1. 不是 `islelog://`（`http` / `https` 等）→ 交给 `url_launcher`。**顺带修**：详情页现在完全没有 `onTapLink`，普通外链点了没反应，这次一并修好
2. URI 有远端名 → `getMemoByMemosName` / `getArticleByArticleName`
3. 查不到再用 `lid` 兜底 → `getMemoById` / `getArticleById`
4. **兜底命中后校验**：若查到的条目自身有远端名、且与链接里的不一致，判定为「不是同一条」，按失效处理。换设备后本地 id 会撞车，没有这一步会跳到完全无关的日记
5. 命中 → `Navigator.push`：日记开 `MemoDetailPage`，文章开 `ArticleEditorPage(openInPreview: true)`

### 6.2 失效提示

两种原因分开说，因为用户能做的事不同：

| 情况 | 提示 |
|---|---|
| 链接只有 `lid`，没有远端名 | 「这条日记还没同步到本设备」 |
| 有远端名但库里查不到 | 「链接的条目已不存在或已被删除」 |

用 SnackBar，不阻断阅读。

### 6.3 边界

- 目标**已归档** → 照常打开。是用户主动点的，读得到才合理
- 目标**已软删除** → 按失效处理
- A ↔ B 互相链接会一路 push 页面栈，不做去重，靠返回键退出。这里用 `push` 而非事件串翻页那种 `pushReplacement`——「点进另一篇」应当可回溯
- 时间线卡片里的链接不可点：卡片是 6 行截断预览，点卡片任意位置都是进本条详情，两个点击区重叠在小屏上极易误触

## 7. 测试

先写测试再写实现。

| 测试文件 | 覆盖 |
|---|---|
| `test/services/link/memo_link_test.dart` | `build` ↔ `parse` 往返；缺 `lid`、缺远端名、非法 URI、非 `islelog` scheme；`labelFor` 的标记清洗（含 `[` `]` `\n`）、截断、同年省年份 |
| `test/features/link_picker/link_query_test.dart` | 第 5 节输入识别表逐行验证，含「单独 `2025` 走关键字」 |
| `test/services/link/link_resolver_test.dart` | `resolveTarget(uri, lookup)` 四个分支：命中日记 / 命中文章 / 未同步 / 已失效；含 6.1 第 4 步的远端名不一致校验 |
| `test/features/link_picker/link_picker_sheet_test.dart` | widget test：输入 `3-12` 只列当天；点选返回正确目标；vault 与归档条目不出现 |

验证：`flutter test` + `flutter analyze`。

已知无关问题：`widget_test.dart` 的 `tearDownAll` 超时是既有问题，与本次改动无关。

## 8. 不做的事

- 不改任何服务端接口，不加任何数据库字段
- 不在同步流程里回写引用方正文
- 不做反向链接、不做链接图谱
- 不做 `[[` 内联触发（中文输入法下光标与候选层定位不可靠，且无法表达「按日期找」）
