import 'package:flutter/material.dart';

import '../../../services/ai/ai_models.dart';

/// AI 编辑辅助动作类型。
enum AiActionType {
  suggestTags,
  polishLight,
  polishMedium,
  polishDeep,
  polishFormatOnly,
}

/// 用户在操作面板中作出的选择。
class AiActionSelection {
  final AiActionType type;
  final AiProvider provider;

  const AiActionSelection(this.type, this.provider);
}

/// 展示 AI 操作面板。
///
/// 每次打开默认选择本地模型 [AiProvider.local]；Provider 选择只存在于
/// 本次面板中，不持久化。点击动作后返回选择，取消返回 null。
Future<AiActionSelection?> showAiActionSheet(
  BuildContext context, {
  required List<AiProviderStatus> providers,
}) {
  return showModalBottomSheet<AiActionSelection>(
    context: context,
    builder: (ctx) => _AiActionSheet(providers: providers),
  );
}

class _AiActionSheet extends StatefulWidget {
  final List<AiProviderStatus> providers;

  const _AiActionSheet({required this.providers});

  @override
  State<_AiActionSheet> createState() => _AiActionSheetState();
}

class _AiActionSheetState extends State<_AiActionSheet> {
  late AiProvider _provider;

  /// 本次可选的已启用 Provider（至少一个；测试或无启用时退化为默认）。
  List<AiProvider> get _enabledProviders =>
      widget.providers.where((p) => p.enabled).map((p) => p.name).toList();

  /// 默认选择已启用的 Provider；LOCAL 启用时优先 LOCAL。
  /// 保证 DeepSeek-only 部署不会误请求 LOCAL 而得到 503。
  AiProvider get _initialProvider {
    final enabled = _enabledProviders;
    if (enabled.contains(AiProvider.local)) return AiProvider.local;
    if (enabled.isNotEmpty) return enabled.first;
    return AiProvider.local;
  }

  @override
  void initState() {
    super.initState();
    _provider = _initialProvider;
  }

  void _choose(AiActionType type) {
    Navigator.pop(context, AiActionSelection(type, _provider));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabledProviders;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'AI 助手',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            if (enabled.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: SegmentedButton<AiProvider>(
                  segments: [
                    for (final p in enabled)
                      ButtonSegment(
                        value: p,
                        label: Text(
                          p == AiProvider.local ? '私有 Qwen' : 'DeepSeek',
                        ),
                      ),
                  ],
                  selected: {_provider},
                  onSelectionChanged: (selection) =>
                      setState(() => _provider = selection.first),
                ),
              ),
            _ActionTile(
              icon: Icons.local_offer_outlined,
              title: '标签建议',
              subtitle: '根据正文生成候选标签',
              onTap: () => _choose(AiActionType.suggestTags),
            ),
            _ActionTile(
              icon: Icons.spellcheck_outlined,
              title: '轻度润色',
              subtitle: '只修正病句和错别字',
              onTap: () => _choose(AiActionType.polishLight),
            ),
            _ActionTile(
              icon: Icons.format_quote_outlined,
              title: '中度润色',
              subtitle: '保留原意，改善表达',
              onTap: () => _choose(AiActionType.polishMedium),
            ),
            _ActionTile(
              icon: Icons.auto_fix_high_outlined,
              title: '深度润色',
              subtitle: '允许较大结构和措辞调整',
              onTap: () => _choose(AiActionType.polishDeep),
            ),
            _ActionTile(
              icon: Icons.format_align_left_outlined,
              title: '整理格式',
              subtitle: '只调整空白和 Markdown 格式',
              onTap: () => _choose(AiActionType.polishFormatOnly),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.green),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      onTap: onTap,
    );
  }
}
