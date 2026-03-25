import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../data/database/database_service.dart';
import '../../../data/models/memo_entry.dart';
import '../../../features/memo_editor/memo_editor_page.dart';
import '../../../shared/constants/app_constants.dart';

/// 时间线中的单条日记卡片
///
/// 由三部分组成：
/// - 左侧时间轴（竖线 + 圆点），用 [_TimelineAxis] 绘制
/// - 右侧内容卡片 [_MemoCard]
///
/// ## 轴线实现说明
///
/// 彻底放弃 [IntrinsicHeight]，改用 [_TimelineAxis] + [CustomPaint] 方案：
/// - [_TimelineAxis] 是一个 [StatefulWidget]，在 [didChangeDependencies] 后
///   通过 [LayoutBuilder] 获取父 Row 分配给它的高度（由右侧卡片撑开）。
/// - 实际上：Row 使用 [CrossAxisAlignment.start]，轴线列高度默认等于自身内容高度。
///   为了让竖线延伸到卡片底部，把轴线列 + 卡片列一起放进一个
///   [IntrinsicHeight] Row —— 但这正是问题根源。
///
/// 最终可行方案：把竖线画在卡片的 [Stack] 背景层，用 [Positioned.fill] 填满，
/// 卡片用 [Padding(bottom:12)] 控制间距，竖线延伸到 bottom padding 底部与
/// 下一条卡片的竖线顶部对齐。圆点单独定位在距顶 20px 处。
///
/// 关键：[Stack] 的高度由唯一非 Positioned 子项（Row）决定，Positioned 可以
/// 用 top/bottom 填满整个 Stack，[Clip.none] 让竖线向下溢出 12px 覆盖间距。
class MemoTimelineCard extends StatelessWidget {
  final MemoEntry memo;

  /// 是否是当天最后一条（决定时间线圆点下方是否绘制延伸线）
  final bool isLast;

  /// 是否在轴线左侧显示时间（日历视图用，当前 home_view 已在外层处理时间）
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

  String get _displayContent {
    var text = memo.content;
    for (final tag in memo.tags) {
      text = text.replaceAll('#$tag', '');
    }
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  // 轴线列的固定宽度
  static const double _axisWidth = 20;

  @override
  Widget build(BuildContext context) {
    // Stack 高度 = 唯一非 Positioned 子项（内容 Row）的高度。
    // Positioned 的 top/bottom 可以相对 Stack 填满，Clip.none 让竖线向下
    // 溢出 12px（bottom padding），与下一条卡片竖线顶端平滑连接。
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── 背景层：竖线 ─────────────────────────────────────────
        // left 定位到轴线列中心，top/bottom 填满 Stack 高度并向下溢出
        Positioned(
          left: (showTime ? _kTimeColumnWidth + _kTimeGap : 0) +
              (_axisWidth - AppDimens.timelineBarWidth) / 2,
          top: 0,
          bottom: isLast ? null : -12,
          width: AppDimens.timelineBarWidth,
          height: isLast
              ? _kDotOffsetTop + AppDimens.timelineDotSize
              : null,
          child: const ColoredBox(color: AppColors.timelineBar),
        ),

        // ── 背景层：圆点（覆盖在竖线上）────────────────────────
        Positioned(
          left: (showTime ? _kTimeColumnWidth + _kTimeGap : 0) +
              (_axisWidth - AppDimens.timelineDotSize) / 2,
          top: _kDotOffsetTop,
          width: AppDimens.timelineDotSize,
          height: AppDimens.timelineDotSize,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
            ),
          ),
        ),

        // ── 前景层：内容 Row（决定 Stack 高度）──────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时间标签（仅日历视图）
            if (showTime)
              SizedBox(
                width: _kTimeColumnWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, right: _kTimeGap),
                  child: Text(
                    _timeLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

            // 轴线占位（透明，宽度与背景层对齐）
            const SizedBox(width: _axisWidth),

            const SizedBox(width: 6),

            // 内容卡片
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MemoCard(memo: memo, displayContent: _displayContent),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// 时间标签列宽度（showTime = true 时使用）
const double _kTimeColumnWidth = 36;
// 时间标签与轴线之间的间距
const double _kTimeGap = 4;
// 圆点距 Stack 顶部的偏移（与卡片顶部对齐，视觉居中）
const double _kDotOffsetTop = 20;

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
                      left: BorderSide(color: Colors.grey[300]!, width: 3),
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
