import 'package:flutter/material.dart';

/// 展示云端模型单次授权确认弹窗。
///
/// 每次 DeepSeek 操作都必须重新调用，授权结果不持久化。
/// 返回 `true` 表示用户允许本次请求，`false` 表示拒绝。
Future<bool> showCloudAiConsentDialog({
  required BuildContext context,
  required String model,
  required int recordCount,
  required int characterCount,
  required String contentModeLabel,
  required List<String> includedMetadata,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('使用云端模型'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本次操作将通过 DeepSeek（$model）处理，请确认：',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          _InfoRow(label: '记录数', value: '$recordCount 条'),
          const SizedBox(height: 6),
          _InfoRow(label: '字符数', value: '$characterCount 字符'),
          const SizedBox(height: 6),
          _InfoRow(label: '内容模式', value: contentModeLabel),
          if (includedMetadata.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in includedMetadata)
                  Chip(
                    label: Text(item, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: Colors.blueGrey.withValues(alpha: 0.08),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            '授权仅对本次请求有效，服务端不会保存你的日记内容。',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('仅本次允许'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
