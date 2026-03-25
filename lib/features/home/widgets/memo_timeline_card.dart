import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../data/database/database_service.dart';
import '../../../data/models/memo_entry.dart';
import '../../../features/memo_editor/memo_editor_page.dart';
import '../../../shared/constants/app_constants.dart';

/// 时间线中的单条日记卡片
///
/// 由三部分组成：
/// - （可选）左侧时间标签（日历视图用，[showTime] = true 时显示）
/// - 中间时间轴线（竖线 + 圆点，用 [_TimelineBar] CustomPaint 绘制，无需 IntrinsicHeight）
/// - 右侧内容卡片 [_MemoCard]
///
/// ## 轴线绘制说明
///
/// 原先用 IntrinsicHeight + Expanded 让轴线撑满卡片高度，但 IntrinsicHeight
/// 嵌套在 ListView 的 Column 中，在快速滚动时会触发 "size: MISSING" 的 hit-test 报错。
///
/// 现改用 [Stack] + [_TimelineBar] CustomPainter 方案：
/// - 外层 Row 使用 crossAxisAlignment.start（不再需要 stretch）
/// - 轴线列用 [LayoutBuilder] 获取卡片实际渲染高度后由 CustomPaint 画线
/// - 视觉效果与原来完全一致，彻底消除 IntrinsicHeight 的 layout 竞态问题
class MemoTimelineCard extends StatelessWidget {
  final MemoEntry memo;

  /// 是否是当天最后一条（决定时间线圆点下方是否绘制延伸线）
  final bool isLast;

  /// 是否在轴线左侧显示时间（日历视图用）
  final bool showTime;

  const MemoTimelineCard({
    super.key,
    required this.memo,
    this.isLast = false,
    this.showTime = false,
  });

  String get _timeLabel {
    final h = memo.createdAt.hour.toString().padLeft(2, '0');
    final m = memo.createdAt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 去除正文中的 #标签，保留 Markdown 其余格式
  String get _displayContent {
    var text = memo.content;
    for (final tag in memo.tags) {
      text = text.replaceAll('#$tag', '');
    }
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      // start：各列独立高度，不强制拉伸，彻底消除对 IntrinsicHeight 的依赖
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 时间标签（仅日历视图）────────────────────────────────
        if (showTime)
          Padding(
            padding: const EdgeInsets.only(top: 12, right: 6),
            child: Text(
              _timeLabel,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

        // ── 时间轴列（CustomPaint 画线，随右侧卡片高度自适应）────
        _TimelineColumn(isLast: isLast),

        const SizedBox(width: 6),

        // ── 内容卡片 ──────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MemoCard(memo: memo, displayContent: _displayContent),
          ),
        ),
      ],
    );
  }
}

/// 时间轴列：圆点 + 上方线段 + 下方延伸线
///
/// 用 [CustomPaint] 绘制，宽度固定为 20px，高度由父级 Row 决定（与右侧卡片等高）。
/// 圆点固定在距顶部 20px 处，上方画一小段线，下方若非最后一条则画到底部。
class _TimelineColumn extends StatelessWidget {
  final bool isLast;
  const _TimelineColumn({required this.isLast});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      // LayoutBuilder 获取父级给出的高度约束，传给 CustomPaint
      child: LayoutBuilder(
        builder: (_, constraints) {
          // 父级 Row(crossAxisAlignment.start) 的高度由右侧卡片决定，
          // constraints.maxHeight 即为右侧卡片+底部 padding 的实际高度。
          // 若约束为无限大（极少数情况），退回到固定值避免绘制异常。
          final height =
              constraints.maxHeight.isFinite ? constraints.maxHeight : 60.0;
          return CustomPaint(
            size: Size(20, height),
            painter: _TimelinePainter(
              isLast: isLast,
              barColor: AppColors.timelineBar,
              dotColor: AppColors.primary,
              dotTopOffset: 20, // 圆点距顶部的距离
              dotRadius: AppDimens.timelineDotSize / 2,
              barWidth: AppDimens.timelineBarWidth,
            ),
          );
        },
      ),
    );
  }
}

/// 时间轴 CustomPainter
///
/// 在固定坐标处绘制：
/// - 顶部 → 圆点：竖线（上方连接线）
/// - 圆点（实心圆）
/// - 圆点 → 底部：竖线（下方延伸线，[isLast] 为 true 时不绘制）
class _TimelinePainter extends CustomPainter {
  final bool isLast;
  final Color barColor;
  final Color dotColor;
  final double dotTopOffset; // 圆点圆心距顶部距离
  final double dotRadius;
  final double barWidth;

  const _TimelinePainter({
    required this.isLast,
    required this.barColor,
    required this.dotColor,
    required this.dotTopOffset,
    required this.dotRadius,
    required this.barWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2; // 轴线水平中心
    final cy = dotTopOffset;   // 圆点圆心 Y 坐标

    final linePaint = Paint()
      ..color = barColor
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()..color = dotColor;

    // 上方连接线：从顶部到圆心上边缘
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, cy - dotRadius),
      linePaint,
    );

    // 圆点
    canvas.drawCircle(Offset(cx, cy), dotRadius, dotPaint);

    // 下方延伸线：从圆心下边缘到底部（最后一条不画）
    if (!isLast) {
      canvas.drawLine(
        Offset(cx, cy + dotRadius),
        Offset(cx, size.height),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.isLast != isLast ||
      old.barColor != barColor ||
      old.dotColor != dotColor;
}

/// 日记内容卡片
class _MemoCard extends StatelessWidget {
  final MemoEntry memo;
  final String displayContent;

  const _MemoCard({required this.memo, required this.displayContent});

  void _showMenu(BuildContext context) {
    debugPrint('[MemoCard] 显示操作菜单，memo.id=${memo.id}');
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text(AppStrings.cardEdit),
              onTap: () {
                debugPrint('[MemoCard] 选择编辑，memo.id=${memo.id}');
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
              leading:
                  const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text(AppStrings.cardDelete,
                  style: TextStyle(color: AppColors.error)),
              onTap: () async {
                debugPrint('[MemoCard] 选择删除，memo.id=${memo.id}');
                Navigator.pop(context);
                await DatabaseService.softDelete(memo.id);
                debugPrint('[MemoCard] 软删除完成，memo.id=${memo.id}');
                messenger.showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Expanded(child: Text(AppStrings.cardDeleted)),
                        TextButton(
                          onPressed: () async {
                            debugPrint(
                                '[MemoCard] 撤销删除，memo.id=${memo.id}');
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
                          child: const Text(AppStrings.cardUndoDelete),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => messenger.hideCurrentSnackBar(),
                          child: const Icon(Icons.close,
                              size: 18, color: Colors.white70),
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
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
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
            if (displayContent.isNotEmpty)
              MarkdownBody(
                data: displayContent,
                styleSheet:
                    MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.textBody),
                  blockquote: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(
                      left:
                          BorderSide(color: Colors.grey[300]!, width: 3),
                    ),
                  ),
                ),
              ),
            if (memo.location != null && memo.location!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 13, color: Colors.blueGrey[400]),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      memo.location!,
                      style: TextStyle(
                          fontSize: 12, color: Colors.blueGrey[400]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (memo.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children:
                    memo.tags.map((tag) => _TagChip(tag: tag)).toList(),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => _showMenu(context),
                  child: Icon(Icons.more_horiz,
                      size: 18, color: Colors.grey[400]),
                ),
                const SizedBox(width: 14),
                Icon(Icons.chat_bubble_outline,
                    size: 14, color: Colors.grey[400]),
                const SizedBox(width: 3),
                Text('0',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[400])),
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
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '#$tag',
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
