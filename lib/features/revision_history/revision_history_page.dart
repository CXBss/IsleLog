import 'package:flutter/material.dart';

import '../../data/models/memo_revision.dart';
import '../../services/api/memos_api_service.dart';
import '../../services/settings/settings_service.dart';
import '../../shared/constants/app_constants.dart';
import 'revision_detail_page.dart';

/// 版本历史列表页
///
/// 显示指定 memo/文章的所有编辑版本，点击可查看 diff 详情。
class RevisionHistoryPage extends StatefulWidget {
  /// 资源名，如 `"memos/42"` 或 `"articles/7"`
  final String memoName;

  /// 用于标题显示
  final String title;

  const RevisionHistoryPage({
    super.key,
    required this.memoName,
    required this.title,
  });

  @override
  State<RevisionHistoryPage> createState() => _RevisionHistoryPageState();
}

class _RevisionHistoryPageState extends State<RevisionHistoryPage> {
  List<MemoRevision>? _revisions;
  String? _error;
  bool _loading = true;

  static String _fmt(DateTime dt) {
    final d = dt.toLocal();
    final y = d.year;
    final mo = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$y-$mo-$day $h:$mi';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final url = await SettingsService.serverUrl;
      final token = await SettingsService.accessToken;
      if (url == null || url.isEmpty || token == null || token.isEmpty) {
        setState(() {
          _error = '未配置服务器，无法查看编辑历史';
          _loading = false;
        });
        return;
      }
      final api = MemosApiService(baseUrl: url, token: token);
      final revisions = await api.listMemoRevisions(widget.memoName);
      // 按版本号降序
      revisions.sort((a, b) => b.version.compareTo(a.version));
      setState(() {
        _revisions = revisions;
        _loading = false;
      });
    } on MemosApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '获取编辑历史失败，请检查网络连接';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(widget.title.isEmpty ? '编辑历史' : '编辑历史 · ${widget.title}'),
        backgroundColor: AppColors.surface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_revisions == null || _revisions!.isEmpty) {
      return const Center(
        child: Text('暂无编辑历史', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _revisions!.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, i) {
        final rev = _revisions![i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primaryLight,
            child: Text(
              'v${rev.version}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark),
            ),
          ),
          title: Text(_fmt(rev.createTime)),
          subtitle: rev.changedFields.isEmpty
              ? null
              : Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: rev.changedFields
                      .map((f) => _FieldChip(label: _fieldLabel(f)))
                      .toList(),
                ),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RevisionDetailPage(
                  memoName: widget.memoName,
                  version: rev.version,
                  createTime: rev.createTime,
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _fieldLabel(String field) {
    const map = {
      'content': '内容',
      'visibility': '可见性',
      'parent_folder': '文件夹',
      'title': '标题',
      'pinned': '置顶',
      'tags': '标签',
    };
    return map[field] ?? field;
  }
}

class _FieldChip extends StatelessWidget {
  final String label;
  const _FieldChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 11, color: AppColors.primaryDark)),
    );
  }
}
