import 'package:flutter/material.dart';

import '../../shared/constants/app_constants.dart';
import 'api_settings_page.dart';
import 'server_settings_page.dart';

/// 设置入口页
///
/// 列出各配置子项，点击进入对应子页。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text(AppStrings.settingsTitle,
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
            subtitle: '高德地图 Key',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ApiSettingsPage()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceWhite,
      borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
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
