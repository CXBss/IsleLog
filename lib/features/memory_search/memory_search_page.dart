import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../services/ai/ai_api_client.dart';
import '../../services/ai/ai_models.dart';
import '../../services/ai/ai_service.dart';
import '../../shared/constants/app_constants.dart';
import '../memo_editor/ai/ai_action_sheet.dart' show aiModelLabel;
import '../memo_detail/memo_detail_page.dart';

/// 记忆检索问答页
///
/// 自然语言提问，答案只依据检索到的日记生成，并附来源日记可跳转查看；
/// 找不到依据时展示明确的空态，而不是让页面看起来像出错了。
/// 问答记录只保留在本次会话中（不持久化，关闭页面后清空）。
class MemorySearchPage extends StatefulWidget {
  /// 测试注入的网关；为 null 时从 [AiService] 解析真实客户端。
  final AiGateway? gateway;

  const MemorySearchPage({super.key, this.gateway});

  @override
  State<MemorySearchPage> createState() => _MemorySearchPageState();
}

class _QaTurn {
  final String query;
  bool loading = true;
  String? error;
  MemorySearchResult? result;

  _QaTurn({required this.query});
}

class _MemorySearchPageState extends State<MemorySearchPage> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<_QaTurn> _turns = [];

  List<AiProviderStatus> _statuses = [];
  bool _loadingStatuses = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<AiGateway> _resolveGateway() async {
    final injected = widget.gateway;
    if (injected != null) return injected;
    return AiService().createGateway();
  }

  AiProviderStatus? _statusFor(AiProvider name) {
    for (final s in _statuses) {
      if (s.name == name) return s;
    }
    return null;
  }

  bool get _embeddingEnabled {
    final status = _statusFor(AiProvider.localEmbedding);
    return status != null && status.enabled && status.available;
  }

  /// 这次会用哪个模型（设置里的全局模型），仅用于展示。
  String? get _modelLabel => aiModelLabel(_statuses);

  Future<void> _loadStatuses() async {
    setState(() => _loadingStatuses = true);
    try {
      final gateway = await _resolveGateway();
      final statuses = await gateway.listProviders();
      if (mounted) setState(() => _statuses = statuses);
    } on AiApiException {
      // 探测失败时保持空列表，下方按"未启用"处理，用户可下拉刷新页面重试。
    } finally {
      if (mounted) setState(() => _loadingStatuses = false);
    }
  }

  Future<void> _submit() async {
    final query = _inputCtrl.text.trim();
    if (query.isEmpty || _sending) return;

    final gateway = await _resolveGateway();
    final turn = _QaTurn(query: query);
    setState(() {
      _turns.add(turn);
      _inputCtrl.clear();
      _sending = true;
    });
    _scrollToBottom();

    try {
      // 模型由设置里的全局选择决定；带敏感标签的日记服务端不会作为候选
      final result = await gateway.memorySearch(query: query);
      if (!mounted) return;
      setState(() {
        turn.loading = false;
        turn.result = result;
      });
    } on AiRequestCancelled {
      if (!mounted) return;
      setState(() {
        turn.loading = false;
        turn.error = '已取消';
      });
    } on AiApiException catch (e) {
      if (!mounted) return;
      setState(() {
        turn.loading = false;
        turn.error = e.message;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openSource(String memoName) async {
    final memo = await DatabaseService.getMemoByMemosName(memoName);
    if (memo == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemoDetailPage(memo: memo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text(
          '记忆检索',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: _loadingStatuses
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: _embeddingEnabled
                        ? _buildTurnList()
                        : _buildDisabledState(),
                  ),
                  if (_embeddingEnabled) _buildInputBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildDisabledState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology_alt_outlined,
              size: 56,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              '记忆检索尚未启用',
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              '需要先在服务端配置语义检索模型',
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _loadStatuses,
              icon: const Icon(Icons.refresh),
              label: const Text('重新检测'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnList() {
    if (_turns.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.psychology_alt_outlined,
                size: 56,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                '用自己的话问问过去',
                style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                '例如"去年夏天我去过哪些地方？"\n答案只会依据你写过的日记生成',
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _turns.length,
      itemBuilder: (context, i) =>
          _TurnView(turn: _turns[i], onOpenSource: _openSource),
    );
  }

  Widget _buildInputBar() {
    return Material(
      color: AppColors.surface(context),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_modelLabel != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    '使用 $_modelLabel',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: '问问你的日记……',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppColors.scaffoldBg(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _sending
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send),
                          color: AppColors.primary,
                          onPressed: _submit,
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnView extends StatelessWidget {
  final _QaTurn turn;
  final void Function(String memoName) onOpenSource;

  const _TurnView({required this.turn, required this.onOpenSource});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(turn.query, style: const TextStyle(fontSize: 14)),
            ),
          ),
          const SizedBox(height: 8),
          _buildAnswer(context),
        ],
      ),
    );
  }

  Widget _buildAnswer(BuildContext context) {
    if (turn.loading) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            '正在检索相关日记…',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      );
    }
    if (turn.error != null) {
      return _AnswerBubble(
        child: Text(
          turn.error!,
          style: const TextStyle(fontSize: 14, color: Colors.redAccent),
        ),
      );
    }
    final result = turn.result;
    if (result == null) return const SizedBox.shrink();
    if (result.insufficientEvidence) {
      return _AnswerBubble(
        child: Row(
          children: [
            Icon(Icons.search_off, size: 16, color: Colors.grey[400]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '没有找到相关日记，换个问法试试？',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AnswerBubble(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.indexIncomplete)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '部分日记尚未完成索引，结果可能不全',
                    style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                  ),
                ),
              Text(result.answer, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
        if (result.sources.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: result.sources.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final source = result.sources[i];
                return _SourceCard(
                  source: source,
                  onTap: () => onOpenSource(source.memo),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _AnswerBubble extends StatelessWidget {
  final Widget child;

  const _AnswerBubble({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _SourceCard extends StatelessWidget {
  final MemorySource source;
  final VoidCallback onTap;

  const _SourceCard({required this.source, required this.onTap});

  String get _dateLabel {
    final d = source.displayTime;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primaryLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _dateLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                source.snippet,
                style: const TextStyle(fontSize: 12),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
