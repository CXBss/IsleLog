import 'package:flutter/material.dart';

import '../../services/agent/agent_api_client.dart';
import '../../services/agent/agent_models.dart';
import '../../shared/constants/app_constants.dart';
import 'widgets/answer_view.dart' show formatDate;

/// 助手的历史对话。点一条返回它的名字，由助手页加载；可以删除。
class AssistantSessionListPage extends StatefulWidget {
  final AgentGateway gateway;

  /// 当前打开的会话，列表里标出来
  final String? current;

  const AssistantSessionListPage({
    super.key,
    required this.gateway,
    this.current,
  });

  @override
  State<AssistantSessionListPage> createState() =>
      _AssistantSessionListPageState();
}

class _AssistantSessionListPageState extends State<AssistantSessionListPage> {
  List<AgentSession>? _sessions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.gateway.listSessions();
      if (mounted) setState(() => _sessions = list);
    } on AgentApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _delete(AgentSession s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这段对话？'),
        content: const Text('只删除对话记录，已经应用到日记的改动不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.gateway.deleteSession(s.name);
      if (mounted) {
        setState(() => _sessions!.removeWhere((x) => x.name == s.name));
      }
    } on AgentApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text(
          '历史对话',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : sessions == null
          ? const Center(child: CircularProgressIndicator())
          : sessions.isEmpty
          ? const Center(
              child: Text('还没有对话', style: TextStyle(color: Colors.grey)),
            )
          : ListView.separated(
              itemCount: sessions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = sessions[i];
                final current = s.name == widget.current;
                return ListTile(
                  leading: Icon(
                    current ? Icons.chat_bubble : Icons.chat_bubble_outline,
                    color: current ? AppColors.primary : Colors.grey,
                  ),
                  title: Text(
                    s.title.isEmpty ? '（空对话）' : s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: s.updateTime == null
                      ? null
                      : Text(
                          formatDate(s.updateTime!.toLocal()),
                          style: const TextStyle(fontSize: 12),
                        ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '删除',
                    onPressed: () => _delete(s),
                  ),
                  onTap: () => Navigator.pop(context, s.name),
                );
              },
            ),
    );
  }
}
