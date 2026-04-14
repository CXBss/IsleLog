import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

import '../../data/models/memo_entry.dart';
import '../../shared/constants/app_constants.dart';
import 'conflict_editor_page.dart';

/// 冲突概览页
///
/// 展示本地新内容与远端内容的 diff，供用户了解冲突详情后进入编辑页处理。
///
/// [memo]：本地 MemoEntry（content 为用户编辑后的新内容，originalContent 为编辑前快照）
/// [remoteContent]：从服务端拉取的最新内容
/// [onResolved]：冲突处理完成后的回调（传入最终 content）
class ConflictOverviewPage extends StatelessWidget {
  final MemoEntry memo;
  final String remoteContent;
  final Future<void> Function(String resolvedContent) onResolved;

  const ConflictOverviewPage({
    super.key,
    required this.memo,
    required this.remoteContent,
    required this.onResolved,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('发现冲突'),
        backgroundColor: AppColors.surface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 提示横幅
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF3E0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFE65100), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '本地修改与服务端版本存在冲突，请查看差异后选择如何处理。',
                    style: TextStyle(
                        fontSize: 13, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection(
                  title: '内容变更',
                  child: _buildContentDiff(context),
                ),
              ],
            ),
          ),
          // 底部操作区
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('暂不处理'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('处理冲突'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ConflictEditorPage(
                              memo: memo,
                              remoteContent: remoteContent,
                              onResolved: (resolved) async {
                                await onResolved(resolved);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark)),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _buildContentDiff(BuildContext context) {
    final base = memo.originalContent ?? '';
    final local = memo.content;
    final remote = remoteContent;

    final dmp = DiffMatchPatch();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDiffBlock(
          label: '本地修改',
          labelColor: const Color(0xFF1565C0),
          labelBg: const Color(0xFFE3F2FD),
          diffs: dmp.diff(base, local),
        ),
        const Divider(height: 20),
        _buildDiffBlock(
          label: '远端修改',
          labelColor: const Color(0xFF4E342E),
          labelBg: const Color(0xFFFBE9E7),
          diffs: dmp.diff(base, remote),
        ),
      ],
    );
  }

  Widget _buildDiffBlock({
    required String label,
    required Color labelColor,
    required Color labelBg,
    required List<Diff> diffs,
  }) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: labelBg,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: labelColor)),
        ),
        const SizedBox(height: 6),
        diffs.isEmpty || diffs.every((d) => d.operation == DIFF_EQUAL)
            ? Text('（无修改）',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic))
            : RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 13, height: 1.6, color: Color(0xFF333333)),
                  children: spans,
                ),
              ),
      ],
    );
  }
}
