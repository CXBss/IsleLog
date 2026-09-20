import 'package:flutter/material.dart';

import '../../services/ai/ai_api_client.dart';
import '../../services/ai/ai_models.dart';
import '../../services/ai/ai_service.dart';
import '../../services/api/memos_api_service.dart';
import '../../services/settings/settings_service.dart';
import '../../shared/constants/app_constants.dart';

/// AI 编辑辅助设置页
///
/// 只展示 Provider 状态和重新检测能力；API Key 在服务端环境变量中配置，
/// 本页不存在任何密钥输入框。
class AiSettingsPage extends StatefulWidget {
  /// 测试注入的网关；为 null 时从 [AiService] 解析真实客户端。
  final AiGateway? gateway;

  const AiSettingsPage({super.key, this.gateway});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  late Future<List<AiProviderStatus>> _statuses;

  bool? _threadAiEnabled;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _statuses = _load();
    _loadThreadAi();
  }

  Future<List<AiProviderStatus>> _load() async {
    final gateway = widget.gateway ?? await AiService().createGateway();
    return gateway.listProviders();
  }

  void _refresh() {
    setState(() {
      _statuses = _load();
    });
  }

  Future<MemosApiService?> _api() async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return MemosApiService(baseUrl: url, token: token);
  }

  Future<void> _loadThreadAi() async {
    final api = await _api();
    if (api == null) return;
    try {
      final data = await api.getThreadAiStatus();
      if (mounted) setState(() => _threadAiEnabled = data['enabled'] == true);
    } catch (_) {
      // 服务端不支持或离线时不显示该项
    }
  }

  Future<void> _toggleThreadAi(bool value) async {
    final api = await _api();
    if (api == null) return;
    if (mounted) setState(() => _threadAiEnabled = value);
    try {
      await api.setThreadAiEnabled(value);
    } catch (e) {
      if (mounted) {
        setState(() => _threadAiEnabled = !value);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置失败：$e')));
      }
    }
  }

  Future<void> _runNow() async {
    final api = await _api();
    if (api == null) return;
    if (mounted) setState(() => _running = true);
    try {
      await api.runThreadBatch();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('分析完成')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分析失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI 编辑辅助',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新检测',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<AiProviderStatus>>(
        future: _statuses,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 48,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '无法获取模型状态\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新检测'),
                    ),
                  ],
                ),
              ),
            );
          }
          final statuses = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final status in statuses) ...[
                _ProviderCard(status: status),
                const SizedBox(height: 8),
              ],
              if (_threadAiEnabled != null) ...[
                const Divider(height: 24),
                SwitchListTile(
                  value: _threadAiEnabled!,
                  activeColor: AppColors.primary,
                  title: const Text('自动分析事件关联'),
                  subtitle: const Text('每晚 4:00 生成事件串简介并发现可能的关联，仅使用本地模型'),
                  onChanged: _toggleThreadAi,
                ),
                ListTile(
                  leading: _running
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_circle_outline),
                  title: const Text('立即分析'),
                  subtitle: const Text('不想等到凌晨时手动跑一次'),
                  onTap: _running ? null : _runNow,
                ),
              ],
              const SizedBox(height: 8),
              const _PrivacyNotice(),
            ],
          );
        },
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final AiProviderStatus status;

  const _ProviderCard({required this.status});

  String get _title => switch (status.name) {
    AiProvider.local => '私有 Qwen',
    AiProvider.deepSeek => 'DeepSeek',
    AiProvider.localEmbedding => '语义检索模型',
  };

  String get _stateLabel {
    if (!status.enabled) return '服务端未启用';
    return status.available ? '可用' : '暂时离线';
  }

  @override
  Widget build(BuildContext context) {
    final color = !status.enabled
        ? Colors.grey
        : (status.available ? AppColors.primary : Colors.orange);
    return Material(
      color: AppColors.surface(context),
      borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _stateLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  size: 16,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    status.enabled && status.model.isNotEmpty
                        ? '模型：${status.model}（上下文 ${status.contextLength}）'
                        : '模型由服务端环境变量配置',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
            if (status.message != null && status.message!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                status.message!,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '· 本地模型失败不会自动切换云端\n'
        '· 云端模型每次操作都需要单独确认\n'
        '· AI 只返回建议，不会直接修改内容',
        style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.7),
      ),
    );
  }
}
