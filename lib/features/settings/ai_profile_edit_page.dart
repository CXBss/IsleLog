import 'package:flutter/material.dart';

import '../../services/ai/ai_api_client.dart';
import '../../services/ai/ai_models.dart';
import '../../services/ai/ai_profile_models.dart';
import '../../shared/constants/app_constants.dart';

/// 添加或编辑一个模型配置。
///
/// 保存时服务端会先做一次真实的连接测试，通过才入库；因此「保存」本身就是
/// 最终校验，「测试连接」只是让用户提前看到结果。保存成功后 pop(true)。
class AiProfileEditPage extends StatefulWidget {
  final AiProfileGateway gateway;
  final AiModelProfile? existing;
  final AiProfileKind kind;

  const AiProfileEditPage({
    super.key,
    required this.gateway,
    required this.kind,
    this.existing,
  });

  @override
  State<AiProfileEditPage> createState() => _AiProfileEditPageState();
}

class _AiProfileEditPageState extends State<AiProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  final _apiKey = TextEditingController();
  late final TextEditingController _model;
  late final TextEditingController _context;
  late final TextEditingController _priceIn;
  late final TextEditingController _priceOut;

  AiProviderPreset _preset = AiProviderPreset.custom;
  List<String> _remoteModels = const [];
  bool _loadingModels = false;
  bool _testing = false;
  bool _saving = false;
  AiProfileTestResult? _testResult;

  bool get _isCloud => widget.kind == AiProfileKind.cloud;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.displayName ?? '');
    _baseUrl = TextEditingController(text: e?.baseUrl ?? '');
    _model = TextEditingController(text: e?.model ?? '');
    _context = TextEditingController(
      text: e == null ? '' : e.contextLength.toString(),
    );
    _priceIn = TextEditingController(text: e?.priceIn?.toString() ?? '');
    _priceOut = TextEditingController(text: e?.priceOut?.toString() ?? '');
    if (e != null) {
      _preset = AiProviderPreset.all.firstWhere(
        (p) => p.baseUrl.isNotEmpty && p.baseUrl == e.baseUrl,
        orElse: () => AiProviderPreset.custom,
      );
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _baseUrl,
      _apiKey,
      _model,
      _context,
      _priceIn,
      _priceOut,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPreset(AiProviderPreset preset) {
    setState(() {
      _preset = preset;
      if (preset.baseUrl.isNotEmpty) _baseUrl.text = preset.baseUrl;
      if (_name.text.isEmpty && preset != AiProviderPreset.custom) {
        _name.text = preset.label;
      }
      _remoteModels = const [];
    });
  }

  void _chooseModel(String model) {
    setState(() {
      _model.text = model;
      final known = _preset.contextLengths[model];
      if (known != null) _context.text = known.toString();
    });
  }

  /// 编辑时 Key 留空表示沿用库里的，由服务端借用。
  String? get _keyInput =>
      _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim();

  AiProfileDraft _draft() => AiProfileDraft(
    kind: widget.kind,
    displayName: _name.text.trim(),
    baseUrl: _baseUrl.text.trim(),
    apiKey: _keyInput,
    model: _model.text.trim(),
    contextLength: int.tryParse(_context.text.trim()) ?? 0,
    priceIn: double.tryParse(_priceIn.text.trim()),
    priceOut: double.tryParse(_priceOut.text.trim()),
  );

  Future<void> _fetchModels() async {
    if (_baseUrl.text.trim().isEmpty) {
      _snack('请先填写接口地址');
      return;
    }
    setState(() => _loadingModels = true);
    try {
      final models = await widget.gateway.listRemoteModels(
        baseUrl: _baseUrl.text.trim(),
        apiKey: _keyInput,
        existing: _keyInput == null ? widget.existing?.name : null,
      );
      if (!mounted) return;
      setState(() => _remoteModels = models);
      if (models.isEmpty) _snack('服务商没有返回模型，请手动填写模型名');
    } on AiApiException catch (e) {
      if (mounted) _snack('获取失败：${e.message}，可以手动填写模型名');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final result = await widget.gateway.testProfile(
        _draft(),
        existing: _keyInput == null ? widget.existing?.name : null,
      );
      if (mounted) setState(() => _testResult = result);
    } on AiApiException catch (e) {
      if (mounted) {
        setState(
          () => _testResult = AiProfileTestResult(
            ok: false,
            latencyMs: 0,
            jsonMode: false,
            message: e.message,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await widget.gateway.updateProfile(widget.existing!.name, _draft());
      } else {
        await widget.gateway.createProfile(_draft());
      }
      if (mounted) Navigator.pop(context, true);
    } on AiApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? '不能为空' : null;

  @override
  Widget build(BuildContext context) {
    final title = '${_isEdit ? '编辑' : '添加'}${_isCloud ? '云端' : '本地'}模型';
    final busy = _saving || _testing;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isCloud) ...[
              DropdownButtonFormField<AiProviderPreset>(
                initialValue: _preset,
                decoration: const InputDecoration(labelText: '服务商'),
                items: [
                  for (final p in AiProviderPreset.all)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (p) => p == null ? null : _applyPreset(p),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '显示名称',
                hintText: '如：DeepSeek V3',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: '接口地址（OpenAI 兼容）',
                hintText: _isCloud
                    ? 'https://api.example.com/v1'
                    : 'http://nas.local:8080/v1',
              ),
              validator: (v) {
                final err = _required(v);
                if (err != null) return err;
                final uri = Uri.tryParse(v!.trim());
                if (uri == null ||
                    !(uri.scheme == 'http' || uri.scheme == 'https') ||
                    uri.host.isEmpty) {
                  return '必须是 http(s) 地址';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _apiKey,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: _isCloud ? 'API Key' : 'API Key（可选）',
                hintText: _isEdit && widget.existing!.hasApiKey
                    ? (widget.existing!.keyUnreadable
                          ? '原 Key 已失效，请重新填写'
                          : '留空保持原 Key（${widget.existing!.apiKeyHint}）')
                    : null,
              ),
              validator: (v) {
                final keyless =
                    !_isEdit ||
                    !widget.existing!.hasApiKey ||
                    widget.existing!.keyUnreadable;
                if (_isCloud && keyless && (v == null || v.trim().isEmpty)) {
                  return '云端模型需要 API Key';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _model,
                    decoration: const InputDecoration(labelText: '模型'),
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: _loadingModels ? null : _fetchModels,
                    child: _loadingModels
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('获取列表'),
                  ),
                ),
              ],
            ),
            if (_remoteModels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in _remoteModels)
                    ChoiceChip(
                      label: Text(m, style: const TextStyle(fontSize: 12)),
                      selected: _model.text == m,
                      onSelected: (_) => _chooseModel(m),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _context,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '上下文长度（token）',
                helperText: '日记助手按它决定一次能处理多少日记',
              ),
              validator: (v) =>
                  (int.tryParse(v?.trim() ?? '') ?? 0) > 0 ? null : '请填写正整数',
            ),
            if (_isCloud) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceIn,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '输入单价（可选）',
                        helperText: '元 / 百万 token',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _priceOut,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '输出单价（可选）',
                        helperText: '用于估算费用',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            if (_testResult != null) _TestResultView(result: _testResult!),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _test,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: const Text('保存'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '保存前服务端会自动测试一次连接，测试不通过不会保存。'
              '${_isCloud ? 'API Key 加密保存在服务端，之后只显示末 4 位。' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestResultView extends StatelessWidget {
  final AiProfileTestResult result;

  const _TestResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.ok ? AppColors.primary : Colors.red;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      ),
      child: Text(
        result.ok
            ? '连接成功 · ${result.latencyMs} ms · '
                  '${result.jsonMode ? '支持 JSON 模式' : '不支持 JSON 模式（仍可使用）'}'
            : '连接失败：${result.message ?? '未知错误'}',
        style: TextStyle(fontSize: 13, color: color),
      ),
    );
  }
}
