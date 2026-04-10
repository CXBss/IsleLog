import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

import '../../data/models/article_entry.dart';
import '../../shared/constants/app_constants.dart';

/// 文章冲突编辑页
///
/// 上半屏：只读 diff 预览（本地 vs 远端，绿=新增，红=删除）
/// 下半屏：可编辑的标题 + 正文，用户参考 diff 后决定最终内容
///
/// 点击保存后调用 [onResolved] 将最终 title/content 交回调用方处理推送。
class ArticleConflictEditorPage extends StatefulWidget {
  final ArticleEntry article;
  final String remoteTitle;
  final String remoteContent;
  final Future<void> Function(String resolvedTitle, String resolvedContent) onResolved;

  const ArticleConflictEditorPage({
    super.key,
    required this.article,
    required this.remoteTitle,
    required this.remoteContent,
    required this.onResolved,
  });

  @override
  State<ArticleConflictEditorPage> createState() => _ArticleConflictEditorPageState();
}

class _ArticleConflictEditorPageState extends State<ArticleConflictEditorPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  bool _saving = false;

  double _previewFlex = 1;
  double _editorFlex = 1;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.article.title);
    _contentCtrl = TextEditingController(text: widget.article.content);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标题和内容不能同时为空')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onResolved(title, content);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('处理冲突'),
        backgroundColor: AppColors.surface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text('保存',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
        ],
      ),
      body: Column(
        children: [
          Flexible(
            flex: _previewFlex.round(),
            child: _buildDiffPreview(),
          ),
          GestureDetector(
            onVerticalDragUpdate: (details) {
              final screenH = MediaQuery.of(context).size.height;
              final delta = details.delta.dy / screenH * 4;
              setState(() {
                _previewFlex = (_previewFlex + delta).clamp(0.3, 3.0);
                _editorFlex = (_editorFlex - delta).clamp(0.3, 3.0);
              });
            },
            child: Container(
              height: 28,
              color: AppColors.scaffoldBg(context),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('↕ 拖动调整',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade400)),
                ],
              ),
            ),
          ),
          Flexible(
            flex: _editorFlex.round(),
            child: _buildEditor(),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffPreview() {
    final dmp = DiffMatchPatch();
    // 合并 title + content 做预览（展示本地 vs 远端的差异）
    final localFull = '# ${widget.article.title}\n\n${widget.article.content}';
    final remoteFull = '# ${widget.remoteTitle}\n\n${widget.remoteContent}';
    final diffs = dmp.diff(remoteFull, localFull);
    dmp.diffCleanupSemantic(diffs);

    final spans = <TextSpan>[];
    for (final d in diffs) {
      switch (d.operation) {
        case DIFF_INSERT:
          spans.add(TextSpan(
            text: d.text,
            style: const TextStyle(
              backgroundColor: Color(0xFFC8E6C9),
              color: Color(0xFF1B5E20),
            ),
          ));
        case DIFF_DELETE:
          spans.add(TextSpan(
            text: d.text,
            style: const TextStyle(
              backgroundColor: Color(0xFFFFCDD2),
              color: Color(0xFFB71C1C),
              decoration: TextDecoration.lineThrough,
              decorationColor: Color(0xFFB71C1C),
            ),
          ));
        default:
          spans.add(TextSpan(
            text: d.text,
            style: const TextStyle(color: Color(0xFF333333)),
          ));
      }
    }

    return Container(
      color: AppColors.surface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('本地修改预览',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark)),
                ),
                const SizedBox(width: 8),
                Text('（绿色=新增，红色=删除，相对于远端）',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SelectableText.rich(
                TextSpan(
                  style: const TextStyle(
                      fontSize: 13, height: 1.6, color: Color(0xFF333333)),
                  children: spans,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('编辑区（最终保存内容）',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1565C0))),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _titleCtrl.text = widget.remoteTitle;
                    _contentCtrl.text = widget.remoteContent;
                  }),
                  icon: const Icon(Icons.cloud_download_outlined, size: 14),
                  label: const Text('采用远端', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          // 标题编辑
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: TextField(
              controller: _titleCtrl,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
              decoration: InputDecoration(
                hintText: '文章标题',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              textInputAction: TextInputAction.next,
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          // 正文编辑
          Expanded(
            child: TextField(
              controller: _contentCtrl,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                border: InputBorder.none,
                hintText: '编辑正文内容...',
              ),
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
