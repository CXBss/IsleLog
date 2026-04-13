import 'package:flutter/material.dart';

import '../../services/settings/settings_service.dart';
import '../../shared/constants/app_constants.dart';

/// 第三方 API 配置页
///
/// 包含高德地图 Key 和天地图 Key 配置。
/// 逆地理编码优先高德，失败则天地图，都失败则只保存坐标。
class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final _amapKeyCtrl = TextEditingController();
  final _tdtKeyCtrl = TextEditingController();
  final _qweatherKeyCtrl = TextEditingController();
  List<String> _favCities = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amapKeyCtrl.dispose();
    _tdtKeyCtrl.dispose();
    _qweatherKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final amap = await SettingsService.amapKey;
    final tdt = await SettingsService.tiandituKey;
    final qw = await SettingsService.qweatherKey;
    final cities = await SettingsService.favoriteCities;
    if (mounted) {
      setState(() {
        if (amap != null) _amapKeyCtrl.text = amap;
        if (tdt != null) _tdtKeyCtrl.text = tdt;
        if (qw != null) _qweatherKeyCtrl.text = qw;
        _favCities = cities;
      });
    }
  }

  Future<void> _addCity() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加常用城市'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '如：深圳、北京、上海', border: OutlineInputBorder()),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    final city = ctrl.text.trim();
    if (confirmed == true && city.isNotEmpty && !_favCities.contains(city)) {
      setState(() => _favCities.add(city));
    }
  }

  Future<void> _save() async {
    await SettingsService.setAmapKey(_amapKeyCtrl.text);
    await SettingsService.setTiandituKey(_tdtKeyCtrl.text);
    await SettingsService.setQweatherKey(_qweatherKeyCtrl.text);
    await SettingsService.setFavoriteCities(_favCities);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.settingsSaved)),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          _SectionHeader(label: '天气'),
          const SizedBox(height: 4),
          Text(
            '获取天气时优先和风天气，未配置则回退高德。',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),
          _KeyField(
            controller: _qweatherKeyCtrl,
            label: '和风天气 Key',
            hint: 'QWeather API Key（优先使用）',
            icon: Icons.wb_sunny_outlined,
          ),
          const SizedBox(height: 8),
          Text(
            '在 dev.qweather.com 注册后获取免费开发版 Key。',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('常用城市', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[500])),
              const Spacer(),
              TextButton.icon(
                onPressed: _addCity,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary, visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          if (_favCities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('暂无常用城市', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _favCities.map((city) => Chip(
                label: Text(city, style: const TextStyle(fontSize: 13)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => setState(() => _favCities.remove(city)),
                backgroundColor: AppColors.primaryLight,
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
          const SizedBox(height: 16),
          _SectionHeader(label: '逆地理编码（位置名称）'),
          const SizedBox(height: 4),
          Text(
            '获取位置时自动解析地址名称。高德优先，失败则天地图，都失败则仅保存坐标。',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),
          _KeyField(
            controller: _amapKeyCtrl,
            label: '高德地图 Key',
            hint: '高德开放平台 Web 服务 Key',
            icon: Icons.map_outlined,
          ),
          const SizedBox(height: 8),
          Text(
            '在高德开放平台创建「Web 服务」类型应用后获取。',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          _KeyField(
            controller: _tdtKeyCtrl,
            label: '天地图 Key',
            hint: '天地图开放平台 Key（备用）',
            icon: Icons.public_outlined,
          ),
          const SizedBox(height: 8),
          Text(
            '在 lbs.tianditu.gov.cn 注册后获取，作为高德失败时的备用。',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

class _KeyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;

  const _KeyField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      ),
      child: TextField(
        controller: controller,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          border: InputBorder.none,
        ),
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
