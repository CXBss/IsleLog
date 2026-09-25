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

/// 根据 `/ai/providers` 的状态描述这次会用哪个模型。
///
/// 服务端按用户配置返回：DEEPSEEK 槽位启用表示全局模型是云端模型，
/// 否则用 LOCAL 槽位的本地模型。[vault] 为 true 时只可能是本地模型。
String? aiModelLabel(List<AiProviderStatus> statuses, {bool vault = false}) {
  AiProviderStatus? slot(AiProvider name) =>
      statuses.where((s) => s.name == name && s.enabled).firstOrNull;
  final cloud = vault ? null : slot(AiProvider.deepSeek);
  if (cloud != null) {
    return '${cloud.model.isEmpty ? '云端模型' : cloud.model}（云端）';
  }
  final local = slot(AiProvider.local);
  if (local != null) {
    return '${local.model.isEmpty ? '本地模型' : local.model}（本地）';
  }
  return null;
}

/// 用户在操作面板中作出的选择。
class AiActionSelection {
  final AiActionType type;

  const AiActionSelection(this.type);
}

/// 展示 AI 操作面板。点击动作后返回选择，取消返回 null。
///
/// 不在这里选模型：所有 AI 功能统一使用设置里选定的全局模型。[modelLabel]
/// 只用来告诉用户这次会用哪个模型，例如「私有 Qwen3.8」或「DeepSeek（云端）」。
Future<AiActionSelection?> showAiActionSheet(
  BuildContext context, {
  String? modelLabel,
}) {
  return showModalBottomSheet<AiActionSelection>(
    context: context,
    builder: (ctx) => _AiActionSheet(modelLabel: modelLabel),
  );
}

class _AiActionSheet extends StatelessWidget {
  final String? modelLabel;

  const _AiActionSheet({this.modelLabel});

  @override
  Widget build(BuildContext context) {
    void choose(AiActionType type) =>
        Navigator.pop(context, AiActionSelection(type));
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
            if (modelLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  '使用 $modelLabel',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            _ActionTile(
              icon: Icons.local_offer_outlined,
              title: '标签建议',
              subtitle: '根据正文生成候选标签',
              onTap: () => choose(AiActionType.suggestTags),
            ),
            _ActionTile(
              icon: Icons.spellcheck_outlined,
              title: '轻度润色',
              subtitle: '只修正病句和错别字',
              onTap: () => choose(AiActionType.polishLight),
            ),
            _ActionTile(
              icon: Icons.format_quote_outlined,
              title: '中度润色',
              subtitle: '保留原意，改善表达',
              onTap: () => choose(AiActionType.polishMedium),
            ),
            _ActionTile(
              icon: Icons.auto_fix_high_outlined,
              title: '深度润色',
              subtitle: '允许较大结构和措辞调整',
              onTap: () => choose(AiActionType.polishDeep),
            ),
            _ActionTile(
              icon: Icons.format_align_left_outlined,
              title: '整理格式',
              subtitle: '只调整空白和 Markdown 格式',
              onTap: () => choose(AiActionType.polishFormatOnly),
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
