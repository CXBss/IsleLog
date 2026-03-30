import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:gal/gal.dart';

import '../../data/database/database_service.dart';
import '../../data/models/attachment_info.dart';
import '../../data/models/memo_entry.dart';
import '../../services/location/location_service.dart';
import '../../services/settings/settings_service.dart';
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
        p: const TextStyle(fontSize: 15, height: 1.7, color: AppColors.textBody),
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
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(
          _dateTimeLabel,
          style: const TextStyle(fontSize: 15, color: Colors.grey),
        ),
        actions: [
          _syncIcon(memo.syncStatus),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: () => _openEdit(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 正文（完整 Markdown 渲染）────────────────────────
            if (_displayContent.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
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
          ],
        ),
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
  bool _saving = false;

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

  Future<void> _saveImage(BuildContext context) async {
    if (_saving) return;
    setState(() => _saving = true);
    final att = widget.attachments[_current];
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: false);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: false);
        if (!granted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('无相册写入权限')),
            );
          }
          return;
        }
      }
      if (att.localPath != null && File(att.localPath!).existsSync()) {
        await Gal.putImage(att.localPath!);
      } else {
        final url = _baseUrl != null ? att.fullUrl(_baseUrl!) : null;
        if (url == null) throw Exception('无法获取图片地址');
        final token = await SettingsService.accessToken;
        final dio = Dio();
        final resp = await dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: token != null ? {'Authorization': 'Bearer $token'} : null,
          ),
        );
        final bytes = Uint8List.fromList(resp.data!);
        await Gal.putImageBytes(bytes, name: att.filename);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                  onLongPress: () => _saveImage(context),
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
