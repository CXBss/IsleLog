import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/utils/image_actions.dart' as img_actions;
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../data/database/database_service.dart';
import '../../data/models/attachment_info.dart';
import '../../data/models/comment_entry.dart';
import '../../data/models/memo_entry.dart';
import '../../services/location/location_service.dart';
import '../../services/settings/settings_service.dart';
import '../../services/sync/sync_service.dart';
import '../../features/home/widgets/audio_player_widget.dart';
import '../../features/home/widgets/file_chip_widget.dart';
import '../../features/memo_editor/memo_editor_page.dart';
import '../../shared/constants/app_constants.dart';

/// 日记详情页
///
/// 展示完整内容（Markdown 渲染）、附件、标签、位置等。
/// 单击从时间线卡片进入；右上角编辑按钮或双击卡片直接跳编辑页。
class MemoDetailPage extends StatefulWidget {
  final MemoEntry memo;

  const MemoDetailPage({super.key, required this.memo});

  @override
  State<MemoDetailPage> createState() => _MemoDetailPageState();
}

class _MemoDetailPageState extends State<MemoDetailPage> {
  MemoEntry get memo => widget.memo;

  // ── 评论 ──
  List<CommentEntry> _comments = [];
  final TextEditingController _commentCtrl = TextEditingController();
  late final FocusNode _commentFocus = FocusNode(
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final isMac = Platform.isMacOS;
      final trigger = isMac
          ? HardwareKeyboard.instance.isMetaPressed
          : HardwareKeyboard.instance.isControlPressed;
      if (trigger && event.logicalKey == LogicalKeyboardKey.enter) {
        _submitComment();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  bool _commentSaving = false;
  CommentEntry? _editingComment; // 非 null 时为编辑模式

  /// 预获取的位置（用于新建评论，后台静默获取）
  LocationInfo? _pendingLocation;

  String get _dateTimeLabel {
    final d = memo.createdAt;
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  String get _displayContent {
    var text = memo.content;
    for (final tag in memo.tags) {
      text = text.replaceAll('#$tag', '');
    }
    // 单换行 → Markdown 强制换行（末尾两空格）
    text = text.replaceAll('\r\n', '\n');
    text = text.replaceAll('\n\n', '\x00');
    text = text.replaceAll('\n', '  \n');
    text = text.replaceAll('\x00', '\n\n');
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  List<AttachmentInfo> get _imageAttachments =>
      memo.attachments.where((a) => a.isImage).toList();
  List<AttachmentInfo> get _audioAttachments =>
      memo.attachments.where((a) => a.isAudio).toList();
  List<AttachmentInfo> get _fileAttachments =>
      memo.attachments.where((a) => !a.isImage && !a.isAudio).toList();

  @override
  void initState() {
    super.initState();
    _loadComments();
    _prefetchLocation();
    _syncComments();
  }

  /// 后台同步评论（静默，完成后刷新列表）
  Future<void> _syncComments() async {
    await SyncService.syncMemoComments(memo);
    if (mounted) await _loadComments();
  }

  /// 后台静默获取位置，供新建评论时使用
  Future<void> _prefetchLocation() async {
    try {
      final info = await LocationService.getLocation();
      if (mounted) _pendingLocation = info;
    } catch (_) {
      // 获取不到就不加位置，静默忽略
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    List<CommentEntry> comments;
    if (memo.memosName != null) {
      comments = await DatabaseService.getCommentsByMemosName(memo.memosName!);
    } else {
      comments = await DatabaseService.getCommentsByMemoId(memo.id);
    }
    if (mounted) setState(() => _comments = comments);
  }

  Future<void> _submitComment() async {
    final content = _commentCtrl.text.trim();
    if (content.isEmpty) return;
    setState(() => _commentSaving = true);
    try {
      if (_editingComment != null) {
        // 编辑已有评论
        _editingComment!
          ..content = content
          ..syncStatus = SyncStatus.pending;
        await DatabaseService.saveComment(_editingComment!);
      } else {
        // 新建评论
        final comment = CommentEntry()
          ..parentMemosName = memo.memosName
          ..memoId = memo.memosName == null ? memo.id : null
          ..content = content
          ..location = _pendingLocation?.displayText
          ..syncStatus = SyncStatus.pending;
        await DatabaseService.saveComment(comment);
      }
      _commentCtrl.clear();
      _editingComment = null;
      _commentFocus.unfocus();
      await _loadComments();
    } finally {
      if (mounted) setState(() => _commentSaving = false);
    }
  }

  void _startEditComment(CommentEntry comment) {
    setState(() => _editingComment = comment);
    _commentCtrl.text = comment.content;
    _commentFocus.requestFocus();
  }

  Future<void> _deleteComment(CommentEntry comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除评论'),
        content: const Text('确认删除这条评论？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DatabaseService.softDeleteComment(comment.id);
    await _loadComments();
  }

  void _showCopyMenu(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.subject_outlined),
              title: const Text('复制纯文本'),
              onTap: () async {
                Navigator.pop(context);
                await Clipboard.setData(ClipboardData(text: _displayContent));
                messenger.showSnackBar(const SnackBar(content: Text('已复制纯文本')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.code_outlined),
              title: const Text('复制 Markdown'),
              onTap: () async {
                Navigator.pop(context);
                await Clipboard.setData(ClipboardData(text: memo.content));
                messenger.showSnackBar(const SnackBar(content: Text('已复制 Markdown')));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openEdit(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MemoEditorPage(editingMemo: memo)),
    );
  }

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
    await DatabaseService.saveMemo(memo);
    if (mounted) setState(() {});
  }

  MarkdownStyleSheet _mdStyle(BuildContext context) =>
      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: TextStyle(fontSize: 15, height: 1.7, color: AppColors.textBody(context)),
        blockquote: const TextStyle(
          fontSize: 14,
          color: Colors.grey,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: Colors.grey[300]!, width: 3),
          ),
        ),
        code: TextStyle(fontSize: 13, backgroundColor: Colors.grey[100]),
        codeblockDecoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(6),
        ),
      );

  @override
  Widget build(BuildContext context) {
    var checkboxIdx = 0;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(
          _dateTimeLabel,
          style: const TextStyle(fontSize: 15, color: Colors.grey),
        ),
        actions: [
          _syncIcon(memo.syncStatus),
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: '复制',
            onPressed: () => _showCopyMenu(context),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: () => _openEdit(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 正文（完整 Markdown 渲染）────────────────────────
            if (_displayContent.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(AppDimens.cardRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: MarkdownBody(
                  data: _displayContent,
                  styleSheet: _mdStyle(context),
                  checkboxBuilder: (checked) {
                    final idx = checkboxIdx++;
                    return GestureDetector(
                      onTap: () {
                        final lineIndex = _findTodoLineIndex(memo.content, idx);
                        _toggleTodo(lineIndex, !checked);
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          checked ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 18,
                          color: checked ? AppColors.primary : Colors.grey[500],
                        ),
                      ),
                    );
                  },
                ),
              ),

            // ── 冲突：远端版本 ────────────────────────────────────
            if (memo.conflictRemoteContent != null) ...[
              const SizedBox(height: 12),
              _ConflictRemoteBlock(
                remoteContent: memo.conflictRemoteContent!,
                mdStyle: _mdStyle(context),
              ),
            ],

            // ── 图片附件 ──────────────────────────────────────────
            if (_imageAttachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DetailImageGrid(attachments: _imageAttachments),
            ],

            // ── 音频附件 ──────────────────────────────────────────
            if (_audioAttachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._audioAttachments.map((a) =>
                  AudioPlayerWidget(key: ValueKey(a.localId), attachment: a)),
            ],

            // ── 文件附件 ──────────────────────────────────────────
            if (_fileAttachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _fileAttachments
                    .map((a) => FileChipWidget(attachment: a))
                    .toList(),
              ),
            ],

            // ── 位置 ──────────────────────────────────────────────
            if (memo.location != null && memo.location!.isNotEmpty) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: memo.latitude != null
                    ? () => openMapFromCoords(
                        memo.latitude, memo.longitude, memo.location)
                    : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(Icons.location_on_outlined,
                          size: 14,
                          color: memo.latitude != null
                              ? AppColors.primary
                              : Colors.blueGrey[400]),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        memo.location!,
                        style: TextStyle(
                          fontSize: 13,
                          color: memo.latitude != null
                              ? AppColors.primary
                              : Colors.blueGrey[400],
                          decoration: memo.latitude != null
                              ? TextDecoration.underline
                              : null,
                          decorationColor: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── 标签 ──────────────────────────────────────────────
            if (memo.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: memo.tags.map((tag) => _DetailTagChip(tag: tag)).toList(),
              ),
            ],

            // ── 底部元信息（修改时间 + 字数）─────────────────────
            const SizedBox(height: 16),
            _MetaInfoRow(memo: memo),

            // ── 评论区 ────────────────────────────────────────────
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 15, color: Colors.grey),
                const SizedBox(width: 6),
                Text('评论 ${_comments.length > 0 ? "(${_comments.length})" : ""}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
              ],
            ),
            if (_comments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('暂无评论', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 8),
                itemCount: _comments.length,
                itemBuilder: (_, i) => _CommentTile(
                  comment: _comments[i],
                  onEdit: () => _startEditComment(_comments[i]),
                  onDelete: () => _deleteComment(_comments[i]),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
          ),

          // ── 评论输入框（固定底部）────────────────────────────────
          _CommentInputBar(
            controller: _commentCtrl,
            focusNode: _commentFocus,
            isEditing: _editingComment != null,
            saving: _commentSaving,
            onSubmit: _submitComment,
            onCancelEdit: () {
              setState(() => _editingComment = null);
              _commentCtrl.clear();
              _commentFocus.unfocus();
            },
          ),
        ],
      ),
    );
  }
}

Widget _syncIcon(SyncStatus status) {
  switch (status) {
    case SyncStatus.synced:
      return const SizedBox.shrink();
    case SyncStatus.pending:
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.cloud_upload_outlined, size: 18, color: Colors.grey),
      );
    case SyncStatus.conflict:
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange),
      );
  }
}

int _findTodoLineIndex(String raw, int checkboxIndex) {
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

class _DetailTagChip extends StatelessWidget {
  final String tag;
  const _DetailTagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '#$tag',
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 详情页图片网格（可全屏查看）
class _DetailImageGrid extends StatelessWidget {
  final List<AttachmentInfo> attachments;
  const _DetailImageGrid({required this.attachments});

  void _openViewer(BuildContext context, int index) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) =>
            _DetailImageViewer(attachments: attachments, initialIndex: index),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = attachments.length;
    if (count == 1) {
      return GestureDetector(
        onTap: () => _openViewer(context, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _DetailAttachThumb(
            attachment: attachments[0],
            width: double.infinity,
            height: 220,
          ),
        ),
      );
    }
    if (count == 2) {
      return Row(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: () => _openViewer(context, i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _DetailAttachThumb(
                      attachment: attachments[i], height: 160),
                ),
              ),
            ),
          ],
        ],
      );
    }
    // 3+: 左大右双
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _openViewer(context, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _DetailAttachThumb(attachment: attachments[0], height: 180),
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 100,
          height: 180,
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _openViewer(context, 1),
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.only(topRight: Radius.circular(8)),
                    child: _DetailAttachThumb(
                        attachment: attachments[1],
                        width: double.infinity,
                        height: double.infinity),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: GestureDetector(
                  onTap: () => _openViewer(context, 2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                            bottomRight: Radius.circular(8)),
                        child: _DetailAttachThumb(
                            attachment: attachments[2],
                            width: double.infinity,
                            height: double.infinity),
                      ),
                      if (count > 3)
                        ClipRRect(
                          borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(8)),
                          child: ColoredBox(
                            color: Colors.black45,
                            child: Center(
                              child: Text('+${count - 3}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 图片缩略图（异步加载 baseUrl）
class _DetailAttachThumb extends StatefulWidget {
  final AttachmentInfo attachment;
  final double? width;
  final double? height;
  const _DetailAttachThumb(
      {required this.attachment, this.width, this.height});

  @override
  State<_DetailAttachThumb> createState() => _DetailAttachThumbState();
}

class _DetailAttachThumbState extends State<_DetailAttachThumb> {
  String? _baseUrl;

  @override
  void initState() {
    super.initState();
    SettingsService.serverUrl.then((v) {
      if (mounted) setState(() => _baseUrl = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.attachment;
    final w = widget.width;
    final h = widget.height;

    if (att.localPath != null) {
      return Image.file(
        File(att.localPath!),
        width: w,
        height: h,
        fit: BoxFit.cover,
      );
    }
    if (_baseUrl != null && att.fullUrl(_baseUrl!) != null) {
      return _AuthImage(
        url: att.fullUrl(_baseUrl!)!,
        width: w,
        height: h,
      );
    }
    return SizedBox(
      width: w,
      height: h,
      child: const ColoredBox(color: Color(0xFFEEEEEE)),
    );
  }
}

/// 全屏图片查看器
class _DetailImageViewer extends StatefulWidget {
  final List<AttachmentInfo> attachments;
  final int initialIndex;
  const _DetailImageViewer(
      {required this.attachments, required this.initialIndex});

  @override
  State<_DetailImageViewer> createState() => _DetailImageViewerState();
}

class _DetailImageViewerState extends State<_DetailImageViewer> {
  late final PageController _ctrl;
  late int _current;
  String? _baseUrl;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
    SettingsService.serverUrl.then((v) {
      if (mounted) setState(() => _baseUrl = v);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: Stack(
          children: [
            PageView.builder(
              controller: _ctrl,
              itemCount: widget.attachments.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) {
                final att = widget.attachments[i];
                Widget content;
                if (att.localPath != null) {
                  content = InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: Image.file(File(att.localPath!), fit: BoxFit.contain),
                  );
                } else if (_baseUrl != null && att.fullUrl(_baseUrl!) != null) {
                  content = InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: _AuthImage(
                        url: att.fullUrl(_baseUrl!)!, fit: BoxFit.contain),
                  );
                } else {
                  return const SizedBox.shrink();
                }
                return GestureDetector(
                  onTap: () {},
                  onLongPress: () => img_actions.showImageActions(
                    context, att, baseUrl: _baseUrl,
                  ),
                  child: Center(child: content),
                );
              },
            ),
            if (widget.attachments.length > 1)
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.attachments.length,
                    (i) => Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _current ? Colors.white : Colors.white38,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 单条评论 tile（长按弹出编辑/删除菜单）
class _CommentTile extends StatelessWidget {
  final CommentEntry comment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CommentTile({
    required this.comment,
    required this.onEdit,
    required this.onDelete,
  });

  String get _timeLabel {
    final d = comment.createdAt;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String get _authorLabel {
    if (comment.creatorName.isEmpty) return '我';
    // "users/123" → 取最后一段；若为空则显示"我"
    final parts = comment.creatorName.split('/');
    return parts.last.isNotEmpty ? parts.last : '我';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showMenu(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 作者 + 时间 + 同步状态
            Row(
              children: [
                Icon(Icons.person_outline, size: 13, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(_authorLabel,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                const Spacer(),
                if (comment.syncStatus == SyncStatus.pending)
                  Icon(Icons.cloud_upload_outlined, size: 13, color: Colors.grey[400]),
                if (comment.syncStatus == SyncStatus.conflict)
                  Icon(Icons.warning_amber_rounded, size: 13, color: Colors.orange[400]),
                const SizedBox(width: 4),
                Text(_timeLabel, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
              ],
            ),
            const SizedBox(height: 6),
            // 内容（Markdown 渲染）
            MarkdownBody(
              data: comment.content,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textBody(context)),
                code: TextStyle(fontSize: 13, backgroundColor: Colors.grey[100]),
              ),
            ),
            // 位置（有则显示）
            if (comment.location != null && comment.location!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on_outlined, size: 12, color: Colors.blueGrey[400]),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      comment.location!,
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey[400]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () { Navigator.pop(ctx); onEdit(); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('删除', style: TextStyle(color: AppColors.error)),
              onTap: () { Navigator.pop(ctx); onDelete(); },
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部固定评论输入框
class _CommentInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isEditing;
  final bool saving;
  final VoidCallback onSubmit;
  final VoidCallback onCancelEdit;

  const _CommentInputBar({
    required this.controller,
    required this.focusNode,
    required this.isEditing,
    required this.saving,
    required this.onSubmit,
    required this.onCancelEdit,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isEditing)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.edit_outlined, size: 13, color: AppColors.primary),
                    const SizedBox(width: 4),
                    const Text('编辑评论', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                    const Spacer(),
                    GestureDetector(
                      onTap: onCancelEdit,
                      child: const Icon(Icons.close, size: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: 4,
                    minLines: 1,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '写评论…',
                      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                saving
                    ? const SizedBox(width: 36, height: 36,
                        child: Padding(padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                    : IconButton(
                        icon: const Icon(Icons.send_rounded, color: AppColors.primary),
                        onPressed: onSubmit,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部元信息行：修改时间 + 字数
class _MetaInfoRow extends StatelessWidget {
  final MemoEntry memo;
  const _MetaInfoRow({required this.memo});

  String get _updatedLabel {
    final d = memo.updatedAt;
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '修改于 $date $time';
  }

  int get _charCount => memo.content.trim().length;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, color: Colors.grey);
    return Row(
      children: [
        Text(_updatedLabel, style: style),
        const Spacer(),
        Text('$_charCount 字', style: style),
      ],
    );
  }
}

/// 带 Bearer Token 认证的网络图片
class _AuthImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  const _AuthImage(
      {required this.url,
      this.width,
      this.height,
      this.fit = BoxFit.cover});

  @override
  State<_AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<_AuthImage> {
  Uint8List? _bytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_AuthImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _bytes = null;
      _error = false;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final token = await SettingsService.accessToken;
      final dio = Dio();
      final resp = await dio.get<List<int>>(
        widget.url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: token != null && token.isNotEmpty
              ? {'Authorization': 'Bearer $token'}
              : null,
        ),
      );
      if (mounted) {
        setState(() => _bytes = Uint8List.fromList(resp.data!));
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const ColoredBox(
          color: Color(0xFFEEEEEE),
          child: Icon(Icons.broken_image_outlined, color: Colors.grey),
        ),
      );
    }
    if (_bytes == null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const ColoredBox(color: Color(0xFFEEEEEE)),
      );
    }
    return Image.memory(
      _bytes!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}

/// 冲突时展示远端版本内容的区块（虚线分隔 + 标签 + Markdown 渲染）
class _ConflictRemoteBlock extends StatelessWidget {
  final String remoteContent;
  final MarkdownStyleSheet mdStyle;

  const _ConflictRemoteBlock({
    required this.remoteContent,
    required this.mdStyle,
  });

  String get _displayContent {
    var text = remoteContent;
    text = text.replaceAll('\r\n', '\n');
    text = text.replaceAll('\n\n', '\x00');
    text = text.replaceAll('\n', '  \n');
    text = text.replaceAll('\x00', '\n\n');
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 虚线分隔
        CustomPaint(
          painter: _DashedLinePainter(color: Colors.orange.withValues(alpha: 0.6)),
          child: const SizedBox(height: 1, width: double.infinity),
        ),
        const SizedBox(height: 8),
        // 标签
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            '远端版本',
            style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 8),
        // 远端内容
        Opacity(
          opacity: 0.75,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppDimens.cardRadius),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
            ),
            child: MarkdownBody(
              data: _displayContent,
              styleSheet: mdStyle,
            ),
          ),
        ),
      ],
    );
  }
}

/// 虚线绘制器
class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}
