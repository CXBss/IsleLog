import 'package:flutter/material.dart';

/// 记忆检索问答 / 往年今日对照的云端授权确认弹窗。
///
/// 与编辑器里的 [showCloudAiConsentDialog]（标签建议/润色）不同：这里发往云端的
/// 具体日记是服务端检索出来的，客户端在弹窗时还不知道确切条数和字符数，
/// 因此只说明"最多多少条""哪个范围"，不假装精确统计，避免误导。
/// 每次操作都必须重新调用，授权结果不持久化。
Future<bool> showMemoryCloudConsentDialog({
  required BuildContext context,
  required String model,
  required String scopeDescription,
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
          Text(
            scopeDescription,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
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
