import 'package:flutter/material.dart';

import '../../services/api/memos_api_service.dart';
import '../../services/settings/settings_service.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/constants/app_constants.dart';

/// Memos 服务器配置页
///
/// 填写服务器地址和 Access Token，测试连接，手动同步。
class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _tokenVisible = false;
  bool _testing = false;
  bool _syncing = false;
  DateTime? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    final lastSync = await SettingsService.lastSyncTime;
    if (mounted) {
      setState(() {
        if (url != null) _urlCtrl.text = url;
        if (token != null) _tokenCtrl.text = token;
        _lastSyncTime = lastSync;
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await SettingsService.setServerUrl(_urlCtrl.text);
    await SettingsService.setAccessToken(_tokenCtrl.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.settingsSaved)),
      );
    }
  }

  String? _nonEmpty(String? s) => (s != null && s.isNotEmpty) ? s : null;

  Future<void> _testConnection() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _testing = true);
    await SettingsService.setServerUrl(_urlCtrl.text);
    await SettingsService.setAccessToken(_tokenCtrl.text);
    try {
      final api = MemosApiService(
        baseUrl: _urlCtrl.text.trim(),
        token: _tokenCtrl.text.trim(),
      );
      final user = await api.testConnection();
      final name = _nonEmpty(user['displayName'] as String?) ??
          _nonEmpty(user['username'] as String?) ??
          _nonEmpty(user['name'] as String?) ??
          AppStrings.settingsUnknownUser;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${AppStrings.settingsConnectOk}$name'),
          backgroundColor: AppColors.success,
        ));
      }
    } on MemosApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${AppStrings.settingsConnectFail}${e.message}'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _syncNow() async {
    await _save();
    setState(() => _syncing = true);
    final result = await SyncService.syncAll();
    if (mounted) {
      setState(() {
        _syncing = false;
        if (result.success) _lastSyncTime = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.toString()),
        backgroundColor: result.success ? AppColors.success : AppColors.error,
      ));
    }
  }

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
        title: const Text('Memos 服务器',
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionHeader(label: AppStrings.settingsSectionServer),
            const SizedBox(height: 8),
            _buildCard(children: [
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
              TextFormField(
                controller: _tokenCtrl,
                obscureText: !_tokenVisible,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: AppStrings.settingsTokenLabel,
                  hintText: AppStrings.settingsTokenHint,
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_tokenVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _tokenVisible = !_tokenVisible),
                  ),
                  border: InputBorder.none,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? AppStrings.settingsTokenRequired
                    : null,
              ),
            ]),
            const SizedBox(height: 8),
            Text(AppStrings.settingsTokenHelp,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),

            const SizedBox(height: 24),
            _SectionHeader(label: AppStrings.settingsSectionActions),
            const SizedBox(height: 8),

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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _syncing ? null : _syncNow,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.surfaceWhite))
                    : const Icon(Icons.sync),
                label: Text(_syncing ? AppStrings.syncing : AppStrings.syncNow),
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

  Widget _buildCard({required List<Widget> children}) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceWhite,
          borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        ),
        child: Column(children: children),
      );
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
