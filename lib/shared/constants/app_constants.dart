import 'package:flutter/material.dart';

/// 应用全局常量
///
/// 集中管理颜色、文字标签、尺寸等，避免在各处散落硬编码值。
/// 使用时直接引用对应命名空间，例如 AppColors.primary、AppStrings.save。

// ─────────────────────────────────────────────────────────────────────────────
// 颜色
// ─────────────────────────────────────────────────────────────────────────────

/// 应用主题颜色
abstract final class AppColors {
  /// 主绿色（品牌色，FAB / 高亮 / 按钮等）
  static const Color primary = Color(0xFF4CAF50);

  /// 深绿（今日日期文字、标签文字）
  static const Color primaryDark = Color(0xFF2E7D32);

  /// 极浅绿背景（今日日期格子背景、标签 Chip 背景）
  static const Color primaryLight = Color(0xFFE8F5E9);

  /// 更浅绿背景（有事件的日期格子背景）
  static const Color primaryLighter = Color(0xFFF1F8E9);

  /// 时间轴连线颜色
  static const Color timelineBar = Color(0xFFC8E6C9);

  /// 成功绿（SnackBar）
  static const Color success = Colors.green;

  /// 错误红（SnackBar / 删除）
  static const Color error = Colors.red;

  // ── 以下颜色随主题自动切换，通过 context 读取 ──────────────────

  /// 页面背景色（浅色：灰白；深色：近黑）
  static Color scaffoldBg(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  /// AppBar / 卡片 / 输入框背景（浅色：白；深色：深灰）
  static Color surface(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  /// 正文主色
  static Color textPrimary(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  /// 卡片正文颜色（比 textPrimary 略浅）
  static Color textBody(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
}

// ─────────────────────────────────────────────────────────────────────────────
// 文字字符串（UI 标签、提示、按钮名称等）
// ─────────────────────────────────────────────────────────────────────────────

/// 应用内所有 UI 文字（中文）
abstract final class AppStrings {
  // ── 通用 ──────────────────────────────────────────────────────────────────
  static const String save = '保存';
  static const String cancel = '取消';
  static const String confirm = '确认';
  static const String delete = '删除';
  static const String edit = '编辑';
  static const String undo = '撤销';
  static const String loading = '加载中...';
  static const String syncNow = '立即同步';
  static const String syncing = '同步中...';
  static const String settings = '设置';

  // ── 主页（HomeView）─────────────────────────────────────────────────────
  static const String homeTitle = '时间线';
  static const String homeEmpty = '还没有日记';
  static const String homeEmptyHint = '点击下方 + 开始记录';
  static const String homeLoadError = '加载失败：';
  static const String homeSyncTooltip = '立即同步';
  static const String homeSettingsTooltip = '设置';

  // ── 日历视图（CalendarView）──────────────────────────────────────────────
  static const String calendarToday = '今日';
  static const String calendarShare = '分享月历';
  static const String calendarEmpty = '这天没有记录';
  static const String calendarPrevMonth = '上月';
  static const String calendarNextMonth = '下月';

  // ── 编辑器（MemoEditorPage）──────────────────────────────────────────────
  static const String editorNewTitle = '新建日记';
  static const String editorEditTitle = '编辑日记';
  static const String editorContentHint = '写点什么...\n\n支持 Markdown 格式和 #标签';
  static const String editorLocationHint = '添加位置（可选）';
  static const String editorEmptyWarning = '内容不能为空';
  static const String editorSaveFailed = '保存失败：';

  // ── 时间线卡片（MemoTimelineCard）────────────────────────────────────────
  static const String cardDelete = '删除';
  static const String cardEdit = '编辑';
  static const String cardDeleted = '日记已删除';
  static const String cardUndoDelete = '撤销';

  // ── 设置页（SettingsPage）────────────────────────────────────────────────
  static const String settingsTitle = '服务器设置';
  static const String settingsSectionServer = 'Memos 服务器';
  static const String settingsSectionActions = '操作';
  static const String settingsUrlLabel = '服务器地址';
  static const String settingsUrlHint = 'https://memos.example.com';
  static const String settingsTokenLabel = 'Access Token';
  static const String settingsTokenHint = '在 Memos → 设置 → Token 中生成';
  static const String settingsTokenHelp =
      '在 Memos Web → 设置 → 个人中心 → Access Tokens 中创建 Token';
  static const String settingsTestConnection = '测试连接';
  static const String settingsTesting = '测试中...';
  static const String settingsSaved = '设置已保存';
  static const String settingsConnectOk = '连接成功！当前用户：';
  static const String settingsConnectFail = '连接失败：';
  static const String settingsLastSync = '上次同步：';
  static const String settingsNeverSynced = '从未同步';
  static const String settingsUrlRequired = '请输入服务器地址';
  static const String settingsUrlInvalid = '地址需以 http:// 或 https:// 开头';
  static const String settingsTokenRequired = '请输入 Access Token';
  static const String settingsUnknownUser = '未知用户';

  // ── 底部导航（MainScaffold）──────────────────────────────────────────────
  static const String navHome = '主页';
  static const String navCalendar = '日历';

  // ── 同步结果（SyncService）───────────────────────────────────────────────
  static const String syncNoConfig = '未配置服务器，请先在设置页填写服务器地址和 Token';
}

// ─────────────────────────────────────────────────────────────────────────────
// 尺寸 / 间距
// ─────────────────────────────────────────────────────────────────────────────

/// 布局常用尺寸常量
abstract final class AppDimens {
  /// 时间线视图最大宽度（平板 / 桌面端约束）
  static const double timelineMaxWidth = 680;

  /// FAB 占位宽度（BottomAppBar 中间留空）
  static const double fabPlaceholder = 64;

  /// 底部导航栏高度
  static const double bottomBarHeight = 44;

  /// 卡片圆角
  static const double cardRadius = 10;

  /// 按钮圆角
  static const double buttonRadius = 8;

  /// 时间轴圆点直径
  static const double timelineDotSize = 10;

  /// 时间轴线宽
  static const double timelineBarWidth = 2;
}
