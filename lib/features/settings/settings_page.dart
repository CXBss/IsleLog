import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../main.dart' show themeModeNotifier;
import '../../services/attachment/attachment_service.dart';
import '../../services/debug/file_logger.dart';
import '../../services/settings/settings_service.dart';
import '../../shared/constants/app_constants.dart';
import 'api_settings_page.dart';
import 'server_settings_page.dart';

/// 设置入口页
///
/// 列出各配置子项，点击进入对应子页。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _markAllPending(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('强制全量推送'),
        content: const Text(
          '将把所有本地日记和评论标记为"待推送"状态。\n\n下次同步时会把本地内容全量推送到服务器（已有远端记录的会更新，本地新建的会创建）。\n\n确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final total = await DatabaseService.markAllPending();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已标记 $total 条记录为待推送，请执行同步')),
      );
    }
  }

  Future<void> _clearLocalCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除本地缓存'),
        content: const Text(
          '将删除本地所有日记、评论、附件文件及同步记录。\n\n数据不会从 Memos 服务器删除，重新同步后可恢复。\n\n确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await DatabaseService.clearAll();
    await AttachmentService.clearLocalCache();
    await SettingsService.clearLastSyncTime();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地缓存已清除，请重新同步')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.settingsTitle,
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ThemeModeItem(),
          const SizedBox(height: 8),
          _SettingsItem(
            icon: Icons.cloud_outlined,
            title: 'Memos 服务器',
            subtitle: '服务器地址、Access Token、同步',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ServerSettingsPage()),
            ),
          ),
          const SizedBox(height: 8),
          _SettingsItem(
            icon: Icons.api_outlined,
            title: '第三方 API',
            subtitle: '高德地图 Key、天地图 Key',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ApiSettingsPage()),
            ),
          ),
          const SizedBox(height: 8),
          _SettingsItem(
            icon: Icons.cloud_upload_outlined,
            title: '强制全量推送',
            subtitle: '将所有本地记录标记为待推送，下次同步时全量上传',
            onTap: () => _markAllPending(context),
          ),
          const SizedBox(height: 8),
          _SettingsItem(
            icon: Icons.delete_sweep_outlined,
            title: '清除本地缓存',
            subtitle: '删除所有本地数据，重新同步后可恢复',
            onTap: () => _clearLocalCache(context),
            destructive: true,
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            _SettingsItem(
              icon: Icons.bug_report_outlined,
              title: '调试日志',
              subtitle: '查看 API 和同步日志',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _DebugLogPage()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DebugLogPage extends StatefulWidget {
  const _DebugLogPage();

  @override
  State<_DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<_DebugLogPage> {
  String _log = '加载中...';
  String _path = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final log = await FileLogger.read();
    final path = await FileLogger.filePath;
    if (mounted) setState(() { _log = log.isEmpty ? '（暂无日志）' : log; _path = path; });
  }

  Future<void> _clear() async {
    await FileLogger.clear();
    if (mounted) setState(() => _log = '（已清空）');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('调试日志', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clear),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SelectableText(
              'adb pull $_path ~/Desktop/isle_log.txt',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey),
            ),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _log,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 外观（主题模式）切换卡片
class _ThemeModeItem extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (_, mode, __) {
        final isDark = mode == ThemeMode.dark ||
            (mode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        return Material(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(AppDimens.cardRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                    color: AppColors.primary, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('外观',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        mode == ThemeMode.system ? '跟随系统' : (mode == ThemeMode.dark ? '深色' : '浅色'),
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16)),
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto, size: 16)),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 16)),
                  ],
                  selected: {mode},
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (s) async {
                    final selected = s.first;
                    themeModeNotifier.value = selected;
                    await SettingsService.setThemeMode(selected);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.red : AppColors.primary;
    return Material(
      color: AppColors.surface(context),
      borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: destructive ? Colors.red : null)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
