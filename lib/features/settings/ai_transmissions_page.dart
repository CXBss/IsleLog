import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../services/ai/ai_api_client.dart';
import '../../services/ai/ai_models.dart';
import '../../services/ai/ai_service.dart';
import '../../shared/constants/app_constants.dart';
import '../memo_detail/memo_detail_page.dart';

/// AI 发送记录：什么时候、哪个功能、把哪些日记交给了哪个模型。
///
/// 全局选定模型之后不再逐次授权，所以这里是事后核对「发了什么给谁」的地方。
class AiTransmissionsPage extends StatefulWidget {
  /// 测试注入；为 null 时从 [AiService] 解析真实客户端。
  final AiProfileGateway? gateway;

  const AiTransmissionsPage({super.key, this.gateway});

  @override
  State<AiTransmissionsPage> createState() => _AiTransmissionsPageState();
}

class _AiTransmissionsPageState extends State<AiTransmissionsPage> {
  final List<AiTransmission> _items = [];
  String? _next;
  bool _loading = true;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    try {
      final gateway =
          widget.gateway ?? await AiService().createProfileGateway();
      final page = await gateway.listTransmissions(pageToken: _next);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _next = page.nextPageToken;
        _done = page.nextPageToken == null;
        _loading = false;
      });
    } on AiApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text(
          'AI 发送记录',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
          ? Center(child: Text(_error!))
          : _items.isEmpty
          ? const Center(
              child: Text('还没有发送过日记', style: TextStyle(color: Colors.grey)),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (!_done &&
                    !_loading &&
                    n.metrics.pixels > n.metrics.maxScrollExtent - 200) {
                  _loading = true;
                  _loadMore();
                }
                return false;
              },
              child: ListView.separated(
                itemCount: _items.length + 1,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  if (i == _items.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _done ? '没有更早的记录了' : '加载中…',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    );
                  }
                  return _TransmissionTile(item: _items[i]);
                },
              ),
            ),
    );
  }
}

class _TransmissionTile extends StatelessWidget {
  final AiTransmission item;

  const _TransmissionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = item.time;
    final time =
        '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
    final what = item.memos.isNotEmpty
        ? '${item.memos.length} 篇日记'
        : '编辑器正文 ${item.chars} 字';
    return ListTile(
      leading: Icon(
        item.cloud ? Icons.cloud_outlined : Icons.computer_outlined,
        color: item.cloud ? Colors.orange[700] : AppColors.primary,
      ),
      title: Text('${item.featureLabel} · $what'),
      subtitle: Text(
        '$time · ${item.model.isEmpty ? '未知模型' : item.model}'
        '${item.cloud ? '（云端）' : '（本地）'}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: item.memos.isEmpty ? null : const Icon(Icons.chevron_right),
      onTap: item.memos.isEmpty
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _SentMemosPage(item: item, time: time),
              ),
            ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// 一次发送里具体是哪些日记（按本机的内容显示摘要）。
class _SentMemosPage extends StatelessWidget {
  final AiTransmission item;
  final String time;

  const _SentMemosPage({required this.item, required this.time});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          '${item.featureLabel} · $time',
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: ListView.builder(
        itemCount: item.memos.length,
        itemBuilder: (context, i) => FutureBuilder(
          future: DatabaseService.getMemoByMemosName(item.memos[i]),
          builder: (context, snap) {
            final memo = snap.data;
            if (memo == null) {
              return ListTile(
                dense: true,
                title: Text(
                  snap.connectionState == ConnectionState.done
                      ? '本机没有这篇日记（${item.memos[i]}）'
                      : '…',
                  style: const TextStyle(color: Colors.grey),
                ),
              );
            }
            final line = memo.content.trim().split('\n').first;
            final d = memo.createdAt;
            return ListTile(
              dense: true,
              title: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${d.year}-${d.month}-${d.day}'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => MemoDetailPage(memo: memo)),
              ),
            );
          },
        ),
      ),
    );
  }
}
