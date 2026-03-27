import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../data/database/database_service.dart';
import '../../../data/models/attachment_info.dart';
import '../../../data/models/memo_entry.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../data/database/database_service.dart' as db_svc;
import '../../../features/memo_detail/memo_detail_page.dart';
import '../../../features/memo_editor/memo_editor_page.dart';
import '../../../services/settings/settings_service.dart'; // Bearer Token 用于图片认证
import '../../../shared/constants/app_constants.dart';
import 'audio_player_widget.dart';
import 'file_chip_widget.dart';

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

  /// 点击标签时的回调（为 null 时标签不可点击）
  final void Function(String tag)? onTagTap;

  /// 是否显示左侧时间轴（竖线 + 圆点）。置顶区块中设为 false。
  final bool showTimeline;

  const MemoTimelineCard({
    super.key,
    required this.memo,
    this.isLast = false,
    this.showTime = false,
    this.showTimeline = true,
    this.onTagTap,
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
  static const double _axisWidth = 14;

  String get _dateTimeLabel {
    final d = memo.createdAt;
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '$date $_timeLabel';
  }

  @override
  Widget build(BuildContext context) {
    // 无时间轴模式（置顶区块）：直接返回卡片，无 Stack/竖线/圆点
    if (!showTimeline) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _MemoCard(
          memo: memo,
          displayContent: _displayContent,
          onTagTap: onTagTap,
          headerLabel: _dateTimeLabel,
        ),
      );
    }

    // Stack 高度 = 唯一非 Positioned 子项（内容 Row）的高度。
    // Positioned 的 top/bottom 可以相对 Stack 填满，Clip.none 让竖线向下
    // 溢出 12px（bottom padding），与下一条卡片竖线顶端平滑连接。
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── 背景层：竖线 ─────────────────────────────────────────
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
                    maxLines: 1,
                    overflow: TextOverflow.clip,
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

            const SizedBox(width: 3),

            // 内容卡片
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MemoCard(memo: memo, displayContent: _displayContent, onTagTap: onTagTap),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// 时间标签列宽度（showTime = true 时使用）
const double _kTimeColumnWidth = 40;
// 时间标签与轴线之间的间距
const double _kTimeGap = 4;
// 圆点距 Stack 顶部的偏移（与卡片顶部对齐，视觉居中）
const double _kDotOffsetTop = 20;

/// 日记内容卡片
class _MemoCard extends StatefulWidget {
  final MemoEntry memo;
  final String displayContent;
  final void Function(String tag)? onTagTap;
  /// 卡片顶部的日期时间标签（置顶模式使用）
  final String? headerLabel;

  const _MemoCard({required this.memo, required this.displayContent, this.onTagTap, this.headerLabel});

  @override
  State<_MemoCard> createState() => _MemoCardState();
}

class _MemoCardState extends State<_MemoCard> {
  MemoEntry get memo => widget.memo;
  String get displayContent => widget.displayContent;

  List<AttachmentInfo> get _imageAttachments =>
      memo.attachments.where((a) => a.isImage).toList();
  List<AttachmentInfo> get _audioAttachments =>
      memo.attachments.where((a) => a.isAudio).toList();
  List<AttachmentInfo> get _fileAttachments =>
      memo.attachments.where((a) => !a.isImage && !a.isAudio).toList();

  static const int _kMaxLines = 6;

  bool get _isTruncated => displayContent.split('\n').length > _kMaxLines;

  String get _markdownContent {
    var text = displayContent.replaceAll('\r\n', '\n');
    final lines = text.split('\n');
    if (lines.length > _kMaxLines) {
      text = lines.take(_kMaxLines).join('\n');
    }
    // 单换行 → Markdown 强制换行
    text = text.replaceAll('\n\n', '\x00');
    text = text.replaceAll('\n', '  \n');
    text = text.replaceAll('\x00', '\n\n');
    return text;
  }

  /// 切换第 [lineIndex] 个 todo 行的勾选状态并保存
  Future<void> _toggleTodo(int lineIndex, bool checked) async {
    final lines = memo.content.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    final line = lines[lineIndex];
    if (checked) {
      lines[lineIndex] = line.replaceFirst('- [ ]', '- [x]');
    } else {
      lines[lineIndex] = line.replaceFirst('- [x]', '- [ ]');
    }
    memo.content = lines.join('\n');
    memo.updatedAt = DateTime.now();
    memo.syncStatus = SyncStatus.pending;
    await db_svc.DatabaseService.saveMemo(memo);
    if (mounted) setState(() {});
  }

  void _openDetail(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => MemoDetailPage(memo: memo)));
  }

  void _openEdit(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => MemoEditorPage(editingMemo: memo)));
  }

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
              title: const Text(AppStrings.cardEdit),
              onTap: () {
                Navigator.pop(context);
                _openEdit(context);
              },
            ),
            ListTile(
              leading: Icon(memo.isPinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin),
              title: Text(memo.isPinned ? '取消置顶' : '置顶'),
              onTap: () async {
                Navigator.pop(context);
                if (memo.isPinned) {
                  await DatabaseService.unpinMemo(memo.id);
                  messenger.showSnackBar(const SnackBar(content: Text('已取消置顶')));
                } else {
                  await DatabaseService.pinMemo(memo.id);
                  messenger.showSnackBar(const SnackBar(content: Text('已置顶')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(memo.isArchived ? '取消归档' : '归档'),
              onTap: () async {
                Navigator.pop(context);
                if (memo.isArchived) {
                  await DatabaseService.unarchiveMemo(memo.id);
                  messenger.showSnackBar(const SnackBar(content: Text('已取消归档')));
                } else {
                  await DatabaseService.archiveMemo(memo.id);
                  messenger.showSnackBar(const SnackBar(content: Text('已归档')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text(AppStrings.cardDelete,
                  style: TextStyle(color: AppColors.error)),
              onTap: () async {
                Navigator.pop(context);
                await DatabaseService.softDelete(memo.id);
                messenger.showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Expanded(child: Text(AppStrings.cardDeleted)),
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

  MarkdownStyleSheet _mdStyle(BuildContext context) =>
      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.textBody),
        blockquote: const TextStyle(
            fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: Colors.grey[300]!, width: 3)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openDetail(context),
      onDoubleTap: () => _openEdit(context),
      child: Container(
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
              // ── 日期时间头（置顶模式）────────────────────────────
              if (widget.headerLabel != null) ...[
                Text(
                  widget.headerLabel!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              // ── 正文预览（Markdown 渲染，超行截断）─────────────
              if (displayContent.isNotEmpty) ...[
                _PreviewMarkdown(
                  content: _markdownContent,
                  rawContent: memo.content,
                  styleSheet: _mdStyle(context),
                  onToggleTodo: _toggleTodo,
                ),
                if (_isTruncated)
                  GestureDetector(
                    onTap: () => _openDetail(context),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        '展示更多',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],

              // ── 图片附件区 ────────────────────────────────────
              if (_imageAttachments.isNotEmpty) ...[
                const SizedBox(height: 6),
                _ImageGrid(attachments: _imageAttachments),
              ],

              // ── 音频附件区 ────────────────────────────────────
              ..._audioAttachments.map((a) =>
                  AudioPlayerWidget(key: ValueKey(a.localId), attachment: a)),

              // ── 其他文件附件区 ────────────────────────────────
              if (_fileAttachments.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  children: _fileAttachments
                      .map((a) => FileChipWidget(attachment: a))
                      .toList(),
                ),
              ],

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
                  children: memo.tags
                      .map((tag) => _TagChip(
                            tag: tag,
                            onTap: widget.onTagTap != null
                                ? () => widget.onTagTap!(tag)
                                : null,
                          ))
                      .toList(),
                ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (memo.isPinned) ...[
                    Icon(Icons.push_pin, size: 13, color: AppColors.primary),
                    const SizedBox(width: 2),
                  ],
                  IconButton(
                    onPressed: () => _showMenu(context),
                    icon: Icon(Icons.more_horiz, color: Colors.grey[400]),
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chat_bubble_outline,
                      size: 16, color: Colors.grey[400]),
                  const SizedBox(width: 3),
                  Text('0',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[400])),
                  const SizedBox(width: 4),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Markdown 预览区：固定最大高度，超出截断并显示底部渐变遮罩。
/// 用 OverflowBox 让内部渲染不受高度约束，避免 flutter_markdown Column overflow。
/// todo 项支持点击切换状态。
class _PreviewMarkdown extends StatelessWidget {
  final String content;
  final String rawContent; // 原始内容，用于计算 todo 行号
  final MarkdownStyleSheet styleSheet;
  final Future<void> Function(int lineIndex, bool checked) onToggleTodo;

  const _PreviewMarkdown({
    required this.content,
    required this.rawContent,
    required this.styleSheet,
    required this.onToggleTodo,
  });

  @override
  Widget build(BuildContext context) {
    // checkboxBuilder 没有 index 参数，用外部计数器在 build 时追踪
    var checkboxIdx = 0;
    final body = MarkdownBody(
      data: content,
      styleSheet: styleSheet,
      checkboxBuilder: (checked) {
        final idx = checkboxIdx++;
        return GestureDetector(
          onTap: () {
            final lineIndex = _findTodoLineIndex(rawContent, idx);
            onToggleTodo(lineIndex, !checked);
          },
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
              color: checked ? AppColors.primary : Colors.grey[500],
            ),
          ),
        );
      },
    );

    return body;
  }

  /// 找到原始内容中第 [checkboxIndex] 个 todo 行的行号
  static int _findTodoLineIndex(String raw, int checkboxIndex) {
    final lines = raw.split('\n');
    int count = -1;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('- [ ]') || trimmed.startsWith('- [x]')) {
        count++;
        if (count == checkboxIndex) return i;
      }
    }
    return -1;
  }
}

class _TagChip extends StatelessWidget {
  final String tag;
  final VoidCallback? onTap;
  const _TagChip({required this.tag, this.onTap});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
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
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}

/// 图片附件网格
///
/// 1 张：全宽展示；2 张：左右各半；3+ 张：第一张占左侧，右侧上下两张（最多展示 3 张，多余显示数量角标）。
/// 点击任意图片打开全屏查看器，支持多图左右翻页。
class _ImageGrid extends StatelessWidget {
  final List<AttachmentInfo> attachments;

  const _ImageGrid({required this.attachments});

  void _openViewer(BuildContext context, int index) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) =>
            _ImageViewer(attachments: attachments, initialIndex: index),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = attachments.length;
    const radius = BorderRadius.all(Radius.circular(8));
    const height = 140.0;

    if (count == 1) {
      return GestureDetector(
        onTap: () => _openViewer(context, 0),
        child: ClipRRect(
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: _NetImg(attachment: attachments[0], fit: BoxFit.contain,
                width: double.infinity),
          ),
        ),
      );
    }

    if (count == 2) {
      return SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(child: GestureDetector(
              onTap: () => _openViewer(context, 0),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)),
                child: _NetImg(attachment: attachments[0],
                    fit: BoxFit.cover, height: height),
              ),
            )),
            const SizedBox(width: 2),
            Expanded(child: GestureDetector(
              onTap: () => _openViewer(context, 1),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
                child: _NetImg(attachment: attachments[1],
                    fit: BoxFit.cover, height: height),
              ),
            )),
          ],
        ),
      );
    }

    // 3 张及以上：左大右小布局，最多渲染 3 张
    final extra = count - 3;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _openViewer(context, 0),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)),
                child: _NetImg(attachment: attachments[0],
                    fit: BoxFit.cover, height: height),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Expanded(child: GestureDetector(
                  onTap: () => _openViewer(context, 1),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8)),
                    child: _NetImg(attachment: attachments[1],
                        fit: BoxFit.cover, width: double.infinity),
                  ),
                )),
                const SizedBox(height: 2),
                Expanded(child: GestureDetector(
                  onTap: () => _openViewer(context, 2),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                        bottomRight: Radius.circular(8)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _NetImg(attachment: attachments[2],
                            fit: BoxFit.cover, width: double.infinity),
                        if (extra > 0)
                          Container(
                            color: Colors.black54,
                            alignment: Alignment.center,
                            child: Text('+$extra',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 全屏图片查看器，支持多图左右翻页，点击背景关闭
class _ImageViewer extends StatefulWidget {
  final List<AttachmentInfo> attachments;
  final int initialIndex;

  const _ImageViewer({required this.attachments, required this.initialIndex});

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.attachments.length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Stack(
          children: [
            // 背景
            Container(color: Colors.black87),

            // 图片翻页
            PageView.builder(
              controller: _pageCtrl,
              itemCount: total,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) => GestureDetector(
                // 点击图片本身不关闭
                onTap: () {},
                child: Center(
                  child: _NetImg(
                    attachment: widget.attachments[i],
                    fit: BoxFit.contain,
                    width: MediaQuery.sizeOf(context).width,
                  ),
                ),
              ),
            ),

            // 页码指示（多图时显示）
            if (total > 1)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_current + 1} / $total',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),

            // 关闭按钮
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单张图片（支持本地路径和需认证的远端 URL）
///
/// 远端图片用 Dio 携带 Bearer Token 下载字节后用 [Image.memory] 渲染，
/// 避免 [Image.network] 不支持自定义请求头的问题。
class _NetImg extends StatefulWidget {
  final AttachmentInfo attachment;
  final BoxFit fit;
  final double? width;
  final double? height;

  const _NetImg({
    required this.attachment,
    required this.fit,
    this.width,
    this.height,
  });

  @override
  State<_NetImg> createState() => _NetImgState();
}

class _NetImgState extends State<_NetImg> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_NetImg old) {
    super.didUpdateWidget(old);
    if (old.attachment.remoteUrl != widget.attachment.remoteUrl ||
        old.attachment.localPath != widget.attachment.localPath) {
      setState(() { _bytes = null; _loading = true; _error = false; });
      _load();
    }
  }

  Future<void> _load() async {
    final localPath = widget.attachment.localPath;

    if (localPath != null) {
      // 本地文件直接读字节
      final file = File(localPath);
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        if (mounted) setState(() { _bytes = bytes; _loading = false; });
      } else {
        if (mounted) setState(() { _loading = false; _error = true; });
      }
      return;
    }

    final baseUrl = await SettingsService.serverUrl ?? '';
    final url = widget.attachment.fullUrl(baseUrl);
    if (url == null || url.isEmpty) {
      if (mounted) setState(() { _loading = false; _error = true; });
      return;
    }

    try {
      final token = await SettingsService.accessToken;
      final encodedUrl = Uri.encodeFull(url);
      final dio = Dio();
      final resp = await dio.get<List<int>>(
        encodedUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: token != null ? {'Authorization': 'Bearer $token'} : null,
        ),
      );
      if (mounted) {
        setState(() {
          _bytes = Uint8List.fromList(resp.data!);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[NetImg] 加载失败 url=$url err=$e');
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget img;
    if (_loading) {
      img = _placeholder();
    } else if (_error || _bytes == null) {
      img = _errorWidget();
    } else {
      img = Image.memory(_bytes!, fit: widget.fit,
          width: widget.width, height: widget.height,
          errorBuilder: (_, __, ___) => _errorWidget());
    }
    if (widget.width != null || widget.height != null) {
      return SizedBox(width: widget.width, height: widget.height, child: img);
    }
    return img;
  }

  Widget _placeholder() => Container(
      color: Colors.grey[100],
      child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)));

  Widget _errorWidget() => Container(
      color: Colors.grey[100],
      child: Center(child: Icon(Icons.broken_image_outlined,
          size: 24, color: Colors.grey[400])));
}
