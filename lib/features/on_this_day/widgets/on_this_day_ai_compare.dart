import 'package:flutter/material.dart';

import '../../../services/ai/ai_api_client.dart';
import '../../../services/ai/ai_models.dart';
import '../../../services/ai/ai_service.dart';
import '../../../shared/constants/app_constants.dart';

/// "往年今日"单条历史记录下方的 AI 对照入口。
///
/// 用户主动点击才发起请求（当天可能有多条历史年份的记录，不会一次性
/// 批量为每条都调用模型）。使用设置里选定的全局模型；带敏感标签的日记
/// 服务端不会交给模型。
class OnThisDayAiCompare extends StatefulWidget {
  final String memoName;

  /// 测试注入的网关；为 null 时从 [AiService] 解析真实客户端。
  final AiGateway? gateway;

  const OnThisDayAiCompare({super.key, required this.memoName, this.gateway});

  @override
  State<OnThisDayAiCompare> createState() => _OnThisDayAiCompareState();
}

enum _CompareState { collapsed, loading, ready, failed }

class _OnThisDayAiCompareState extends State<OnThisDayAiCompare> {
  _CompareState _state = _CompareState.collapsed;
  OnThisDayCompareResult? _result;
  String? _error;

  Future<AiGateway> _resolveGateway() async {
    final injected = widget.gateway;
    if (injected != null) return injected;
    return AiService().createGateway();
  }

  Future<void> _toggle() async {
    if (_state == _CompareState.ready || _state == _CompareState.failed) {
      setState(() => _state = _CompareState.collapsed);
      return;
    }
    if (_state == _CompareState.loading) return;
    await _run();
  }

  Future<void> _run() async {
    final gateway = await _resolveGateway();
    if (!mounted) return;
    setState(() {
      _state = _CompareState.loading;
      _error = null;
    });
    try {
      final result = await gateway.onThisDayCompare(memoName: widget.memoName);
      if (!mounted) return;
      setState(() {
        _result = result;
        _state = _CompareState.ready;
      });
    } on AiApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _state = _CompareState.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _toggle,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _state == _CompareState.ready
                            ? Icons.expand_less
                            : Icons.auto_awesome_outlined,
                        size: 15,
                        color: AppColors.primaryDark,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _state == _CompareState.ready ? '收起 AI 对照' : '查看 AI 对照',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_state == _CompareState.loading) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_state == _CompareState.ready) _buildResult(context),
          if (_state == _CompareState.failed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error ?? '生成失败，请稍后再试',
                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CompareRow(label: '当时', text: result.pastSummary),
          const SizedBox(height: 8),
          if (result.now.available)
            _CompareRow(label: '现在', text: result.now.summary)
          else
            Text(
              '最近没有记录，暂时无法对照',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  final String label;
  final String text;

  const _CompareRow({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
