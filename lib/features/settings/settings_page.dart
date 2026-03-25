import 'package:flutter/material.dart';

import '../../services/api/memos_api_service.dart';
import '../../services/settings/settings_service.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/constants/app_constants.dart';

/// 服务器配置页面
///
/// 功能：
/// - 填写并保存 Memos 服务器地址和 Access Token
/// - 测试连接（验证配置是否正确，返回当前用户名）
/// - 手动触发完整双向同步
/// - 显示上次同步时间
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();

  /// Form 用于统一校验 URL 和 Token 输入框
  final _formKey = GlobalKey<FormState>();

  /// Token 明文 / 密文切换标志
  bool _tokenVisible = false;

  /// 是否正在测试连接
  bool _testing = false;

  /// 是否正在同步
  bool _syncing = false;

  /// 上次成功同步时间（null 表示从未同步）
  DateTime? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  /// 从 SharedPreferences 加载已保存的配置并填入输入框
  Future<void> _loadSettings() async {
    debugPrint('[Settings] 加载本地配置...');
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    final lastSync = await SettingsService.lastSyncTime;
    if (mounted) {
      setState(() {
        if (url != null) _urlCtrl.text = url;
        if (token != null) _tokenCtrl.text = token;
        _lastSyncTime = lastSync;
      });
      debugPrint('[Settings] 配置加载完成，url=$url, lastSync=$lastSync');
    }
  }

  /// 保存当前表单输入到 SharedPreferences
  Future<void> _save() async {
    // 表单校验不通过时直接返回
    if (!(_formKey.currentState?.validate() ?? false)) return;
    debugPrint('[Settings] 保存配置，url=${_urlCtrl.text}');
    await SettingsService.setServerUrl(_urlCtrl.text);
    await SettingsService.setAccessToken(_tokenCtrl.text);
    debugPrint('[Settings] 配置保存成功');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.settingsSaved)),
      );
    }
  }

  /// 非空字符串辅助方法（空串视为 null）
  String? _nonEmpty(String? s) => (s != null && s.isNotEmpty) ? s : null;

  /// 测试服务器连接
  ///
  /// 先保存当前输入，再调用 [MemosApiService.testConnection]，
  /// 成功时展示用户名，失败时展示具体错误信息。
  Future<void> _testConnection() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    debugPrint('[Settings] 测试连接，url=${_urlCtrl.text}');
    setState(() => _testing = true);

    // 先持久化当前输入，确保 API 实例读到最新值
    await SettingsService.setServerUrl(_urlCtrl.text);
    await SettingsService.setAccessToken(_tokenCtrl.text);

    try {
      final api = MemosApiService(
        baseUrl: _urlCtrl.text.trim(),
        token: _tokenCtrl.text.trim(),
      );
      final user = await api.testConnection();
      debugPrint('[Settings] 连接成功，用户数据：$user');

      // Memos v0.25 字段优先级：displayName > username > name
      final name = _nonEmpty(user['displayName'] as String?) ??
          _nonEmpty(user['username'] as String?) ??
          _nonEmpty(user['name'] as String?) ??
          AppStrings.settingsUnknownUser;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppStrings.settingsConnectOk}$name'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on MemosApiException catch (e) {
      debugPrint('[Settings] 连接失败：${e.message}（code=${e.statusCode}）');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppStrings.settingsConnectFail}${e.message}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// 手动触发完整双向同步
  ///
  /// 同步前先保存配置，确保使用最新的服务器地址和 Token。
  Future<void> _syncNow() async {
    debugPrint('[Settings] 手动触发同步...');
    await _save(); // 确保配置是最新的
    setState(() => _syncing = true);

    final result = await SyncService.syncAll();
    debugPrint('[Settings] 同步结果：$result');

    if (mounted) {
      setState(() {
        _syncing = false;
        // 同步成功时更新显示的上次同步时间
        if (result.success) _lastSyncTime = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.toString()),
          backgroundColor:
              result.success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  /// 将 [time] 格式化为友好的相对时间字符串
  ///
  /// 小于 60 秒 → "刚刚"；小于 1 小时 → "X 分钟前"；
  /// 小于 1 天 → "X 小时前"；更早 → "MM-DD HH:mm"。
  String _formatSyncTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceWhite,
        title: const Text(AppStrings.settingsTitle,
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          // 右上角保存按钮
          TextButton(
            onPressed: _save,
            child: const Text(AppStrings.save,
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 服务器信息区域 ──────────────────────────────────
            _SectionHeader(label: AppStrings.settingsSectionServer),
            const SizedBox(height: 8),
            _buildCard(children: [
              // 服务器 URL 输入框
              TextFormField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: AppStrings.settingsUrlLabel,
                  hintText: AppStrings.settingsUrlHint,
                  prefixIcon: Icon(Icons.link_outlined),
                  border: InputBorder.none,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return AppStrings.settingsUrlRequired;
                  }
                  if (!v.trim().startsWith('http')) {
                    return AppStrings.settingsUrlInvalid;
                  }
                  return null;
                },
              ),
              const Divider(height: 1, indent: 52),
              // Access Token 输入框（支持明文切换）
              TextFormField(
                controller: _tokenCtrl,
                obscureText: !_tokenVisible,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: AppStrings.settingsTokenLabel,
                  hintText: AppStrings.settingsTokenHint,
                  prefixIcon: const Icon(Icons.key_outlined),
                  // Token 显示/隐藏切换按钮
                  suffixIcon: IconButton(
                    icon: Icon(_tokenVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () {
                      debugPrint('[Settings] 切换 Token 显示状态：${!_tokenVisible}');
                      setState(() => _tokenVisible = !_tokenVisible);
                    },
                  ),
                  border: InputBorder.none,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? AppStrings.settingsTokenRequired
                    : null,
              ),
            ]),

            const SizedBox(height: 8),
            // Token 获取说明
            Text(
              AppStrings.settingsTokenHelp,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),

            const SizedBox(height: 24),

            // ── 操作区域 ──────────────────────────────────────
            _SectionHeader(label: AppStrings.settingsSectionActions),
            const SizedBox(height: 8),

            // 测试连接按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering_outlined),
                label: Text(_testing
                    ? AppStrings.settingsTesting
                    : AppStrings.settingsTestConnection),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: AppColors.primary),
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimens.buttonRadius)),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // 立即同步按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _syncing ? null : _syncNow,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.surfaceWhite))
                    : const Icon(Icons.sync),
                label: Text(
                    _syncing ? AppStrings.syncing : AppStrings.syncNow),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.surfaceWhite,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimens.buttonRadius)),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 上次同步时间
            Center(
              child: Text(
                '${AppStrings.settingsLastSync}'
                '${_lastSyncTime != null ? _formatSyncTime(_lastSyncTime!) : AppStrings.settingsNeverSynced}',
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建白色圆角卡片容器（用于分组表单项）
  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      ),
      child: Column(children: children),
    );
  }
}

/// 分区标题组件
///
/// 用灰色小字体显示分区名称，如 "Memos 服务器"、"操作"。
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[500]),
      );
}
