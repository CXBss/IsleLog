import 'package:flutter/material.dart';

import '../../services/ai/ai_api_client.dart';
import '../../services/ai/ai_models.dart';
import '../../services/ai/ai_profile_models.dart';
import '../../services/ai/ai_service.dart';
import '../../services/api/memos_api_service.dart';
import '../../services/settings/settings_service.dart';
import '../../shared/constants/app_constants.dart';
import 'ai_profile_edit_page.dart';

/// AI 模型设置页
///
/// 在这里添加本地模型和任意 OpenAI 兼容的云端模型，并选定一个全局模型：
/// 所有 AI 功能（编辑器、记忆检索、往年今日、事件串夜间分析）都使用它。
/// 配置保存在服务端，API Key 只上传不回读。
class AiSettingsPage extends StatefulWidget {
  /// 测试注入的网关；为 null 时从 [AiService] 解析真实客户端。
  final AiProfileGateway? profileGateway;
  final AiGateway? gateway;

  const AiSettingsPage({super.key, this.profileGateway, this.gateway});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  late Future<AiProfileSettings> _settings;
  AiProviderStatus? _embedding;

  bool? _threadAiEnabled;
  bool _running = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _settings = _load();
    _loadEmbedding();
    _loadThreadAi();
  }

  Future<AiProfileGateway> _profiles() async =>
      widget.profileGateway ?? await AiService().createProfileGateway();

  Future<AiProfileSettings> _load() async => (await _profiles()).listProfiles();

  void _refresh() {
    setState(() {
      _settings = _load();
    });
    _loadEmbedding();
  }

  Future<void> _loadEmbedding() async {
    try {
      final gateway = widget.gateway ?? await AiService().createGateway();
      final statuses = await gateway.listProviders();
      final embedding = statuses
          .where((s) => s.name == AiProvider.localEmbedding)
          .firstOrNull;
      if (mounted) setState(() => _embedding = embedding);
    } catch (_) {
      // 语义检索状态只是附加信息，取不到不影响本页
    }
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
    if (widget.profileGateway != null) return; // 测试环境不访问真实服务端
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
        _snack('设置失败：$e');
      }
    }
  }

  Future<void> _runNow() async {
    final api = await _api();
    if (api == null) return;
    if (mounted) setState(() => _running = true);
    try {
      await api.runThreadBatch();
      if (mounted) _snack('分析完成');
    } catch (e) {
      if (mounted) _snack('分析失败：$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 选定全局模型。切到云端模型时说明清楚：所有 AI 功能都会把日记内容发给该服务商。
  Future<void> _select(AiModelProfile profile) async {
    if (profile.isCloud) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('使用 ${profile.displayName}？'),
          content: const Text(
            '选择后，所有 AI 功能（编辑器润色与标签、记忆检索、往年今日、'
            '事件串夜间分析）都会把相关日记内容发送到这个云端服务商。\n\n'
            '带敏感标签的日记和隐私空间不受影响，始终只用本地模型。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认使用'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _save(
      () async =>
          (await _profiles()).updateSettings(activeProfile: profile.name),
    );
  }

  Future<void> _save(Future<AiProfileSettings> Function() action) async {
    setState(() => _saving = true);
    try {
      final updated = await action();
      if (mounted) {
        setState(() {
          _settings = Future.value(updated);
        });
      }
    } on AiApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit({AiModelProfile? existing, AiProfileKind? kind}) async {
    final gateway = await _profiles();
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AiProfileEditPage(
          gateway: gateway,
          existing: existing,
          kind: existing?.kind ?? kind ?? AiProfileKind.cloud,
        ),
      ),
    );
    if (saved == true) _refresh();
  }

  Future<void> _delete(AiModelProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('删除「${profile.displayName}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await (await _profiles()).deleteProfile(profile.name);
      _refresh();
    } on AiApiException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  Future<void> _editSensitiveTags(List<String> current) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _SensitiveTagsDialog(initial: current.join(' ')),
    );
    if (result == null) return;
    final tags = result
        .split(RegExp(r'[\s,，]+'))
        .map((t) => t.replaceFirst(RegExp(r'^#+'), '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    await _save(
      () async => (await _profiles()).updateSettings(sensitiveTags: tags),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI 模型',
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
      body: FutureBuilder<AiProfileSettings>(
        future: _settings,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error, onRetry: _refresh);
          }
          final settings = snapshot.data!;
          final locals = settings.profiles.where((p) => !p.isCloud).toList();
          final clouds = settings.profiles.where((p) => p.isCloud).toList();
          return AbsorbPointer(
            absorbing: _saving,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ActiveBanner(active: settings.active),
                const SizedBox(height: 16),
                const _SectionTitle('本地模型'),
                for (final p in locals)
                  _ProfileTile(
                    profile: p,
                    selected: p.name == settings.activeProfile,
                    onSelect: () => _select(p),
                    onEdit: () => _edit(existing: p),
                    onDelete: () => _delete(p),
                  ),
                _AddButton(
                  label: '添加本地模型',
                  onTap: () => _edit(kind: AiProfileKind.local),
                ),
                const SizedBox(height: 16),
                const _SectionTitle('云端模型'),
                for (final p in clouds)
                  _ProfileTile(
                    profile: p,
                    selected: p.name == settings.activeProfile,
                    onSelect: () => _select(p),
                    onEdit: () => _edit(existing: p),
                    onDelete: () => _delete(p),
                  ),
                _AddButton(
                  label: '添加云端模型',
                  onTap: () => _edit(kind: AiProfileKind.cloud),
                ),
                const Divider(height: 32),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('敏感标签'),
                  subtitle: Text(
                    settings.sensitiveTags.isEmpty
                        ? '未设置'
                        : settings.sensitiveTags.map((t) => '#$t').join('  '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editSensitiveTags(settings.sensitiveTags),
                ),
                if (_embedding != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.hub_outlined),
                    title: const Text('语义检索模型'),
                    subtitle: Text(
                      !_embedding!.enabled
                          ? '服务端未启用'
                          : '${_embedding!.model} · '
                                '${_embedding!.available ? '可用' : '暂时离线'}'
                                ' · 固定本地',
                    ),
                  ),
                if (_threadAiEnabled != null) ...[
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _threadAiEnabled!,
                    activeColor: AppColors.primary,
                    title: const Text('自动分析事件关联'),
                    subtitle: const Text('每晚 4:00 生成事件串简介并发现可能的关联，使用当前 AI 模型'),
                    onChanged: _toggleThreadAi,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
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
            ),
          );
        },
      ),
    );
  }
}

/// 编辑敏感标签的对话框。控制器由对话框自己持有，随对话框一起销毁——
/// 在外面 await 之后立刻 dispose，会赶上关闭动画仍在重建输入框。
class _SensitiveTagsDialog extends StatefulWidget {
  final String initial;

  const _SensitiveTagsDialog({required this.initial});

  @override
  State<_SensitiveTagsDialog> createState() => _SensitiveTagsDialogState();
}

class _SensitiveTagsDialogState extends State<_SensitiveTagsDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('敏感标签'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '带这些标签（含子标签）的日记不会交给云端模型：检索类功能直接跳过，'
            '编辑器里改用本地模型。多个标签用空格分隔。',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '私密 健康'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _ActiveBanner extends StatelessWidget {
  final AiModelProfile? active;

  const _ActiveBanner({required this.active});

  @override
  Widget build(BuildContext context) {
    final p = active;
    final color = p == null
        ? Colors.grey
        : (p.isCloud ? Colors.orange : AppColors.primary);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      ),
      child: Row(
        children: [
          Icon(
            p == null
                ? Icons.help_outline
                : (p.isCloud ? Icons.cloud_outlined : Icons.dns_outlined),
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p == null
                  ? '尚未配置 AI 模型'
                  : '当前使用：${p.displayName}'
                        '${p.isCloud ? '（云端，日记内容会发往服务商）' : '（本地）'}',
              style: TextStyle(fontSize: 14, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final AiModelProfile profile;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProfileTile({
    required this.profile,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  (String, Color) get _state {
    if (profile.keyUnreadable) return ('Key 需重新填写', Colors.red);
    final status = profile.status;
    if (status == null) return ('未检测', Colors.grey);
    return status.available
        ? ('可用', AppColors.primary)
        : ('暂时离线', Colors.orange);
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = _state;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onSelect,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? AppColors.primary : Colors.grey,
        ),
        title: Text(profile.displayName),
        subtitle: Text(
          '${profile.model} · ${_formatContext(profile.contextLength)}'
          '${profile.isCloud && profile.apiKeyHint.isNotEmpty ? ' · Key ${profile.apiKeyHint}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: color)),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatContext(int tokens) =>
      tokens >= 1000 ? '${(tokens / 1000).round()}k 上下文' : '$tokens 上下文';
}

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AddButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add),
        label: Text(label),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final message = error is AiApiException
        ? (error as AiApiException).message
        : '$error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              '无法获取模型配置\n$message',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新检测'),
            ),
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
        '· 所有 AI 功能统一使用上面选中的模型\n'
        '· 隐私空间和带敏感标签的日记始终只用本地模型\n'
        '· 模型调用失败不会自动换成其他模型\n'
        '· API Key 加密保存在服务端，不会再显示原文\n'
        '· AI 只返回建议，不会直接修改内容',
        style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.7),
      ),
    );
  }
}
