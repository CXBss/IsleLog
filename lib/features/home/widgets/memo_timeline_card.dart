import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../data/database/database_service.dart';
import '../../../data/models/memo_entry.dart';
import '../../../features/memo_editor/memo_editor_page.dart';

/// 时间线中的单条日记卡片（含时间轴线、时间标签和内容卡片）
class MemoTimelineCard extends StatelessWidget {
  final MemoEntry memo;

  /// 是否是当天最后一条（决定时间线下方是否绘制延伸线）
  final bool isLast;

  const MemoTimelineCard({
    super.key,
    required this.memo,
    this.isLast = false,
  });

  String get _timeLabel {
    final h = memo.createdAt.hour.toString().padLeft(2, '0');
    final m = memo.createdAt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 去除正文中的 #标签，保留 Markdown 其他格式供渲染
  String get _displayContent {
    var text = memo.content;
    for (final tag in memo.tags) {
      text = text.replaceAll('#$tag', '');
    }
    // 压缩多余空行
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 时间轴线 + 圆点 ──────────────────────────────
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(width: 2, height: 20, color: const Color(0xFFC8E6C9)),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF4CAF50),
                  ),
                ),
                if (!isLast)
                  Expanded(child: Container(width: 2, color: const Color(0xFFC8E6C9))),
              ],
            ),
          ),

          const SizedBox(width: 6),

          // ── 时间标签 ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12, right: 8),
            child: Text(
              _timeLabel,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // ── 内容卡片 ──────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MemoCard(memo: memo, displayContent: _displayContent),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoCard extends StatelessWidget {
  final MemoEntry memo;
  final String displayContent;

  const _MemoCard({required this.memo, required this.displayContent});

  void _showMenu(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MemoEditorPage(editingMemo: memo),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                await DatabaseService.softDelete(memo.id);
                messenger.showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Expanded(child: Text('日记已删除')),
                        TextButton(
                          onPressed: () async {
                            memo.isDeleted = false;
                            memo.syncStatus = SyncStatus.pending;
                            await DatabaseService.saveMemo(memo);
                            messenger.hideCurrentSnackBar();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.greenAccent,
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('撤销'),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => messenger.hideCurrentSnackBar(),
                          child: const Icon(Icons.close, size: 18, color: Colors.white70),
                        ),
                      ],
                    ),
                    duration: const Duration(seconds: 5),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Markdown 正文 ──
            if (displayContent.isNotEmpty)
              MarkdownBody(
                data: displayContent,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF333333)),
                  blockquote: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Colors.grey[300]!, width: 3),
                    ),
                  ),
                ),
              ),

            // ── 位置信息 ──
            if (memo.location != null && memo.location!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 13, color: Colors.blueGrey[400]),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      memo.location!,
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey[400]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // ── 标签 Chips ──
            if (memo.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: memo.tags.map((tag) => _TagChip(tag: tag)).toList(),
              ),
            ],

            // ── 操作行 ──
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => _showMenu(context),
                  child: Icon(Icons.more_horiz, size: 18, color: Colors.grey[400]),
                ),
                const SizedBox(width: 14),
                Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 3),
                Text('0', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String tag;
  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '#$tag',
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF2E7D32),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
