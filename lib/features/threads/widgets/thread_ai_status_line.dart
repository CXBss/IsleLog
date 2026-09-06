import 'package:flutter/material.dart';

import '../../../shared/constants/app_constants.dart';

/// 夜间批次的可见状态
class ThreadAiStatusData {
  final bool enabled;
  final bool providerAvailable;
  final int pendingMemos;
  final int dirtyThreads;

  const ThreadAiStatusData({
    required this.enabled,
    required this.providerAvailable,
    required this.pendingMemos,
    required this.dirtyThreads,
  });

  bool get hasWork => pendingMemos > 0 || dirtyThreads > 0;
}

/// 事件串页顶部的一行分析状态。
///
/// 只在有待处理项时出现——空闲时整行不占位，避免常驻噪音。
/// 文案给确定的时间点而不是「分析中」，因为批次每晚固定 4 点跑。
class ThreadAiStatusLine extends StatelessWidget {
  final ThreadAiStatusData data;

  const ThreadAiStatusLine({super.key, required this.data});

  String? _label() {
    if (!data.hasWork) return null;
    if (!data.enabled) return '自动分析已关闭';
    if (!data.providerAvailable) return '模型离线，暂停分析';
    if (data.pendingMemos > 0 && data.dirtyThreads > 0) {
      return '${data.pendingMemos} 篇待分析 · ${data.dirtyThreads} 条简介待更新 · 今晚 4:00 处理';
    }
    if (data.pendingMemos > 0) {
      return '${data.pendingMemos} 篇待分析 · 今晚 4:00 处理';
    }
    return '${data.dirtyThreads} 条简介待更新 · 今晚 4:00 处理';
  }

  @override
  Widget build(BuildContext context) {
    final label = _label();
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
      ),
    );
  }
}
