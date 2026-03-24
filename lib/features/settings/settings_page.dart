import 'package:flutter/material.dart';

import '../../services/api/memos_api_service.dart';
import '../../services/settings/settings_service.dart';
import '../../services/sync/sync_service.dart';

/// 服务器配置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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
    _loadSettings();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
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
        const SnackBar(content: Text('设置已保存')),
      );
    }
  }

  String? _nonEmpty(String? s) => (s != null && s.isNotEmpty) ? s : null;

  Future<void> _testConnection() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _testing = true);

    // 先保存当前输入，再测试
    await SettingsService.setServerUrl(_urlCtrl.text);
    await SettingsService.setAccessToken(_tokenCtrl.text);

    try {
      final api = MemosApiService(
        baseUrl: _urlCtrl.text.trim(),
        token: _tokenCtrl.text.trim(),
      );
      final user = await api.testConnection();
      // v0.25 字段：displayName > username > name
      final name = _nonEmpty(user['displayName'] as String?) ??
          _nonEmpty(user['username'] as String?) ??
          _nonEmpty(user['name'] as String?) ??
          '未知用户';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接成功！当前用户：$name'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on MemosApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接失败：${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.toString()),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
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
      backgroundColor: const Color(0xFFF2F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('服务器设置',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存',
                style: TextStyle(
                    color: Color(0xFF4CAF50), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 服务器信息 ────────────────────────────────────
            _SectionHeader(label: 'Memos 服务器'),
            const SizedBox(height: 8),
            _buildCard(children: [
              // URL
              TextFormField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://memos.example.com',
                  prefixIcon: Icon(Icons.link_outlined),
                  border: InputBorder.none,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '请输入服务器地址';
                  if (!v.trim().startsWith('http')) return '地址需以 http:// 或 https:// 开头';
                  return null;
                },
              ),
              const Divider(height: 1, indent: 52),
              // Token
              TextFormField(
                controller: _tokenCtrl,
                obscureText: !_tokenVisible,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Access Token',
                  hintText: '在 Memos → 设置 → Token 中生成',
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
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入 Access Token' : null,
              ),
            ]),

            const SizedBox(height: 8),
            Text(
              '在 Memos Web → 设置 → 个人中心 → Access Tokens 中创建 Token',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),

            const SizedBox(height: 24),

            // ── 操作按钮 ──────────────────────────────────────
            _SectionHeader(label: '操作'),
            const SizedBox(height: 8),

            // 测试连接
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
                label: Text(_testing ? '测试中...' : '测试连接'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0xFF4CAF50)),
                  foregroundColor: const Color(0xFF4CAF50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // 立即同步
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _syncing ? null : _syncNow,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync),
                label: Text(_syncing ? '同步中...' : '立即同步'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 上次同步时间
            Center(
              child: Text(
                '上次同步：${_lastSyncTime != null ? _formatSyncTime(_lastSyncTime!) : "从未同步"}',
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: children),
    );
  }
}

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
