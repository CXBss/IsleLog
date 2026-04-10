import 'package:flutter/material.dart';

import '../../data/models/memo_revision.dart';
import '../../services/api/memos_api_service.dart';
import '../../services/settings/settings_service.dart';
import '../../shared/constants/app_constants.dart';

/// 版本 Diff 详情页
///
/// 展示某个版本的字段变更，content 字段显示 inline diff（红/绿高亮），
/// 其他字段显示旧值 → 新值。
class RevisionDetailPage extends StatefulWidget {
  final String memoName;
  final int version;
  final DateTime createTime;

  const RevisionDetailPage({
    super.key,
    required this.memoName,
    required this.version,
    required this.createTime,
  });

  @override
  State<RevisionDetailPage> createState() => _RevisionDetailPageState();
}

class _RevisionDetailPageState extends State<RevisionDetailPage> {
  MemoRevisionDetail? _detail;
  String? _error;
  bool _loading = true;

  static String _fmt(DateTime dt) {
    final d = dt.toLocal();
    final y = d.year;
    final mo = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    final s = d.second.toString().padLeft(2, '0');
    return '$y-$mo-$day $h:$mi:$s';
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
      final detail =
          await api.getMemoRevision(widget.memoName, widget.version);
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on MemosApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '获取版本详情失败，请检查网络连接';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text('v${widget.version} · ${_fmt(widget.createTime)}'),
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
    if (_detail == null || _detail!.details.isEmpty) {
      return const Center(
        child: Text('该版本无字段变更记录', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _detail!.details.map(_buildFieldSection).toList(),
    );
  }

  Widget _buildFieldSection(RevisionFieldDetail field) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 字段名标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _fieldLabel(field.fieldName),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark),
              ),
            ),
            const SizedBox(height: 8),
            // content 字段用 inline diff，其他显示旧值→新值
            if (field.diff != null && field.diff!.isNotEmpty)
              _buildInlineDiff(field.diff!)
            else
              _buildValueChange(field.oldValue, field.newValue),
          ],
        ),
      ),
    );
  }

  /// 渲染 inline diff（绿色=新增，红色+删除线=删除，正常=不变）
  Widget _buildInlineDiff(List<DiffOp> diff) {
    final spans = <TextSpan>[];
    for (final op in diff) {
      if (op.text.isEmpty) continue;
      switch (op.op) {
        case 1: // 新增
          spans.add(TextSpan(
            text: op.text,
            style: const TextStyle(
              backgroundColor: Color(0xFFC8E6C9),
              color: Color(0xFF1B5E20),
            ),
          ));
        case -1: // 删除
          spans.add(TextSpan(
            text: op.text,
            style: const TextStyle(
              backgroundColor: Color(0xFFFFCDD2),
              color: Color(0xFFB71C1C),
              decoration: TextDecoration.lineThrough,
              decorationColor: Color(0xFFB71C1C),
            ),
          ));
        default: // 不变
          spans.add(TextSpan(
            text: op.text,
            style: const TextStyle(color: Color(0xFF333333)),
          ));
      }
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(
            fontSize: 14, height: 1.6, fontFamily: 'monospace'),
        children: spans,
      ),
    );
  }

  /// 非 content 字段：显示旧值 → 新值
  Widget _buildValueChange(String? oldValue, String? newValue) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (oldValue != null) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                oldValue,
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFB71C1C),
                    decoration: TextDecoration.lineThrough,
                    decorationColor: Color(0xFFB71C1C)),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
          ),
        ],
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              newValue ?? '（空）',
              style: const TextStyle(fontSize: 13, color: Color(0xFF1B5E20)),
            ),
          ),
        ),
      ],
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
