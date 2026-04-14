import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

import '../../data/models/memo_entry.dart';
import '../../shared/constants/app_constants.dart';

/// 冲突编辑页
///
/// 上半屏：只读 diff 预览（本地修改 vs 远端内容，绿=新增，红=删除）
/// 下半屏：可编辑文本框（初始内容为本地版本），用户参考 diff 后决定最终内容
///
/// 点击保存后调用 [onResolved] 将最终内容交回调用方处理推送。
class ConflictEditorPage extends StatefulWidget {
  final MemoEntry memo;
  final String remoteContent;
  final Future<void> Function(String resolvedContent) onResolved;

  const ConflictEditorPage({
    super.key,
    required this.memo,
    required this.remoteContent,
    required this.onResolved,
  });

  @override
  State<ConflictEditorPage> createState() => _ConflictEditorPageState();
}

class _ConflictEditorPageState extends State<ConflictEditorPage> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  // diff 预览面板高度比例（可拖拽调整）
  double _previewFlex = 1;
  double _editorFlex = 1;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.memo.content);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _ctrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('内容不能为空')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onResolved(content);
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
          // 上半：diff 预览（可滚动）
          Flexible(
            flex: _previewFlex.round(),
            child: _buildDiffPreview(),
          ),
          // 分隔拖拽条
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
          // 下半：编辑区
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
    // 展示"远端 vs 本地"的 diff，让用户看到远端改了什么
    final diffs = dmp.diff(widget.remoteContent, widget.memo.content);
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
                  onPressed: () =>
                      setState(() => _ctrl.text = widget.remoteContent),
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
          Expanded(
            child: TextField(
              controller: _ctrl,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                border: InputBorder.none,
                hintText: '编辑最终内容...',
              ),
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
