import 'package:flutter/material.dart';

import '../../../data/database/database_service.dart';
import '../../../services/ai/ai_api_client.dart';
import '../../../services/ai/ai_models.dart';
import '../../../services/ai/ai_service.dart';
import '../../../shared/constants/app_constants.dart';
import '../memo_detail_page.dart';

/// 详情页"相关记忆"区块。
///
/// 纯向量相似度计算，不调用任何生成模型，打开详情页时懒加载即可。
/// [pending] 结果展示"正在分析"占位；无结果且非 pending 时整块不渲染，
/// 不留一个空盒子。加载失败时也整块不渲染——这是锦上添花的功能，不该用
/// 一条错误提示打断用户阅读日记。
class RelatedMemoriesSection extends StatefulWidget {
  final String memoName;

  /// 测试注入的网关；为 null 时从 [AiService] 解析真实客户端。
  final AiGateway? gateway;

  const RelatedMemoriesSection({
    super.key,
    required this.memoName,
    this.gateway,
  });

  @override
  State<RelatedMemoriesSection> createState() => _RelatedMemoriesSectionState();
}

enum _LoadState { loading, pending, ready, empty, failed }

class _RelatedMemoriesSectionState extends State<RelatedMemoriesSection> {
  _LoadState _state = _LoadState.loading;
  List<RelatedMemory> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RelatedMemoriesSection old) {
    super.didUpdateWidget(old);
    if (old.memoName != widget.memoName) _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final gateway = widget.gateway ?? await AiService().createGateway();
      final result = await gateway.relatedMemories(memoName: widget.memoName);
      if (!mounted) return;
      setState(() {
        if (result.pending) {
          _state = _LoadState.pending;
        } else if (result.relatedMemos.isEmpty) {
          _state = _LoadState.empty;
        } else {
          _items = result.relatedMemos;
          _state = _LoadState.ready;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _state = _LoadState.failed);
    }
  }

  Future<void> _open(String memoName) async {
    final memo = await DatabaseService.getMemoByMemosName(memoName);
    if (memo == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemoDetailPage(memo: memo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _LoadState.loading:
        return const SizedBox.shrink();
      case _LoadState.failed:
      case _LoadState.empty:
        return const SizedBox.shrink();
      case _LoadState.pending:
        return _SectionShell(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '正在分析关联记忆…',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ),
        );
      case _LoadState.ready:
        return _SectionShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in _items)
                _RelatedMemoryTile(item: item, onTap: () => _open(item.memo)),
            ],
          ),
        );
    }
  }
}

class _SectionShell extends StatelessWidget {
  final Widget child;

  const _SectionShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 15, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text(
                '相关记忆',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _RelatedMemoryTile extends StatelessWidget {
  final RelatedMemory item;
  final VoidCallback onTap;

  const _RelatedMemoryTile({required this.item, required this.onTap});

  String get _dateLabel {
    final d = item.displayTime;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _dateLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.matchReason,
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.snippet,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey[300]),
          ],
        ),
      ),
    );
  }
}
