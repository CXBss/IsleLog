import 'package:flutter/material.dart';

import '../../services/settings/settings_service.dart';
import '../../shared/constants/app_constants.dart';

/// 第三方 API 配置页
///
/// 目前包含高德地图 API Key 配置。
class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final _amapKeyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amapKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = await SettingsService.amapKey;
    if (mounted && key != null) {
      setState(() => _amapKeyCtrl.text = key);
    }
  }

  Future<void> _save() async {
    await SettingsService.setAmapKey(_amapKeyCtrl.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.settingsSaved)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('第三方 API',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(AppStrings.save,
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(label: '高德地图'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceWhite,
              borderRadius: BorderRadius.circular(AppDimens.cardRadius),
            ),
            child: TextField(
              controller: _amapKeyCtrl,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: '高德开放平台 Web 服务 Key',
                prefixIcon: Icon(Icons.map_outlined),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '用于自动获取位置名称。在高德开放平台创建「Web 服务」类型应用后获取。',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) => Text(label,
      style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500]));
}
