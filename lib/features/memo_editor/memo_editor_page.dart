import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/attachment_info.dart';
import '../../data/models/memo_entry.dart';
import '../../data/models/tag_stat.dart';
import '../../services/attachment/attachment_service.dart';
import '../../services/settings/settings_service.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/constants/app_constants.dart';

/// 新建 / 编辑日记页面
///
/// - [editingMemo] 为 null → 新建模式，保存时创建新 [MemoEntry]
/// - [editingMemo] 不为 null → 编辑模式，保存时更新该条目
///
/// 保存成功后会在后台静默推送到远端（如已配置服务器），不阻塞 UI。
class MemoEditorPage extends StatefulWidget {
  /// 编辑模式时传入目标日记，新建模式不传
  final MemoEntry? editingMemo;

  const MemoEditorPage({super.key, this.editingMemo});

  @override
  State<MemoEditorPage> createState() => _MemoEditorPageState();
}

class _MemoEditorPageState extends State<MemoEditorPage> {
  late final TextEditingController _contentCtrl;
  late final TextEditingController _locationCtrl;
  late final FocusNode _contentFocus;

  /// 是否正在保存（控制保存按钮 loading 状态）
  bool _saving = false;

  /// 是否正在上传附件
  bool _uploading = false;

  /// 本次编辑的附件列表（保存时写入 MemoEntry）
  final List<AttachmentInfo> _pendingAttachments = [];

  /// 编辑模式下被移除的旧附件（仅保存成功后才真正删除远端资源）
  final List<AttachmentInfo> _removedAttachments = [];

  /// 是否为编辑模式（影响标题文字）
  bool get _isEditing => widget.editingMemo != null;

  // ── 标签提示 ──────────────────────────────────────────────────

  /// 当前正在输入的 # 前缀（null = 不显示提示）
  String? _tagPrefix;

  /// 所有可用标签（从本地缓存加载）
  List<TagStat> _allTags = [];

  /// 当前过滤后的候选标签
  List<TagStat> get _tagSuggestions {
    if (_tagPrefix == null) return [];
    final prefix = _tagPrefix!.toLowerCase();
    return _allTags
        .where((t) => t.name.toLowerCase().startsWith(prefix))
        .take(6)
        .toList();
  }

  /// 内容输入框的 GlobalKey，用于定位浮层位置
  final GlobalKey _contentFieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    debugPrint('[MemoEditor] 初始化，模式=${_isEditing ? "编辑" : "新建"}，'
        'id=${widget.editingMemo?.id}');

    _contentCtrl =
        TextEditingController(text: widget.editingMemo?.content ?? '');
    _locationCtrl =
        TextEditingController(text: widget.editingMemo?.location ?? '');
    _contentFocus = FocusNode();

    if (widget.editingMemo != null) {
      _pendingAttachments.addAll(widget.editingMemo!.attachments);
    }

    _contentCtrl.addListener(_onContentChanged);

    DatabaseService.getCachedTagStats().then((tags) {
      if (mounted) setState(() => _allTags = tags);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final delay = defaultTargetPlatform == TargetPlatform.macOS
          ? const Duration(milliseconds: 300)
          : Duration.zero;
      Future.delayed(delay, () {
        if (mounted) {
          _contentFocus.requestFocus();
          debugPrint('[MemoEditor] 已请求正文焦点');
        }
      });
    });
  }

  @override
  void dispose() {
    debugPrint('[MemoEditor] 释放资源');
    _contentCtrl.removeListener(_onContentChanged);
    _contentCtrl.dispose();
    _locationCtrl.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  // ── 标签提示逻辑 ──────────────────────────────────────────────

  void _onContentChanged() {
    final text = _contentCtrl.text;
    final cursor = _contentCtrl.selection.baseOffset;
    if (cursor <= 0) {
      _setTagPrefix(null);
      return;
    }

    // 取光标前的文本，找最后一个 # 的位置
    final before = text.substring(0, cursor);
    final hashIdx = before.lastIndexOf('#');
    if (hashIdx == -1) {
      _setTagPrefix(null);
      return;
    }

    final segment = before.substring(hashIdx + 1); // # 之后到光标的内容
    // 遇到空格/换行则关闭提示
    if (segment.contains(' ') || segment.contains('\n')) {
      _setTagPrefix(null);
      return;
    }

    _setTagPrefix(segment); // 可能是空字符串（刚输入 # 时）
  }

  void _setTagPrefix(String? prefix) {
    if (_tagPrefix == prefix) return;
    setState(() => _tagPrefix = prefix);
  }

  /// 点击候选标签：替换光标前的 #xxx 片段
  void _acceptTag(String tagName) {
    final text = _contentCtrl.text;
    final cursor = _contentCtrl.selection.baseOffset;
    final before = text.substring(0, cursor);
    final hashIdx = before.lastIndexOf('#');
    if (hashIdx == -1) return;

    final after = text.substring(cursor);
    final newText = '${text.substring(0, hashIdx)}#$tagName $after';
    final newCursor = hashIdx + tagName.length + 2; // # + name + 空格

    _contentCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    setState(() => _tagPrefix = null);
    _contentFocus.requestFocus();
  }

  // ── 附件选择与上传 ────────────────────────────────────────────

  /// 弹出附件类型选择菜单，然后选择并处理文件
  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<_AttachType>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('图片'),
              onTap: () => Navigator.pop(context, _AttachType.image),
            ),
            ListTile(
              leading: const Icon(Icons.music_note_outlined),
              title: const Text('音频'),
              onTap: () => Navigator.pop(context, _AttachType.audio),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('其他文件'),
              onTap: () => Navigator.pop(context, _AttachType.file),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    FileType fileType;
    List<String>? allowedExtensions;
    switch (choice) {
      case _AttachType.image:
        fileType = FileType.image;
      case _AttachType.audio:
        fileType = FileType.audio;
      case _AttachType.file:
        fileType = FileType.any;
    }

    final result = await FilePicker.platform.pickFiles(
      type: fileType,
      allowedExtensions: allowedExtensions,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    if (picked.path == null) return;

    // 图片类型询问是否压缩
    bool compress = true;
    if (choice == _AttachType.image && mounted) {
      final useCompress = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('图片质量'),
          content: const Text('压缩后上传可节省流量，原图保留完整画质。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('原图'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('压缩'),
            ),
          ],
        ),
      );
      if (useCompress == null) return; // 取消
      compress = useCompress;
    }

    await _processFile(File(picked.path!), picked.name, compress: compress);
  }

  /// 处理选中的文件：在线上传 or 离线存储
  ///
  /// 优先尝试在线上传；若服务器未配置或网络不通，自动降级到本地存储，
  /// 待下次联网同步时由 [SyncService] 补传。
  Future<void> _processFile(File file, String filename, {bool compress = true}) async {
    setState(() => _uploading = true);
    try {
      final configured = await SettingsService.isConfigured;
      AttachmentInfo info;

      if (configured) {
        try {
          info = await AttachmentService.uploadToServer(file, filename: filename, compress: compress);
          debugPrint('[MemoEditor] 在线上传成功：${info.filename}');
        } catch (e) {
          // 网络不通时降级到本地存储，等待联网后同步
          debugPrint('[MemoEditor] 在线上传失败，降级本地存储：$e');
          info = await AttachmentService.saveLocally(file, filename: filename, compress: compress);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('网络不可用，附件已本地保存，联网后自动上传')),
            );
          }
        }
      } else {
        info = await AttachmentService.saveLocally(file, filename: filename, compress: compress);
      }

      setState(() => _pendingAttachments.add(info));
      debugPrint('[MemoEditor] 附件已处理：${info.filename}');
    } catch (e) {
      debugPrint('[MemoEditor] 附件处理失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('附件处理失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 移除一个附件（延迟删除：保存成功后才真正删远端，取消编辑则不删）
  void _removeAttachment(AttachmentInfo att) {
    setState(() => _pendingAttachments.remove(att));
    _removedAttachments.add(att);
  }

  /// 保存日记
  ///
  /// 流程：
  /// 1. 校验正文不为空
  /// 2. 写入本地 DB（新建或更新）
  /// 3. 如已配置服务器，在后台推送到远端
  /// 4. 返回上一页（携带 true 表示有变更）
  Future<void> _save() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      debugPrint('[MemoEditor] 保存失败：内容为空');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.editorEmptyWarning)),
      );
      return;
    }

    debugPrint('[MemoEditor] 开始保存，内容长度=${content.length}');
    setState(() => _saving = true);
    try {
      // 新建模式使用全新 MemoEntry，编辑模式复用已有对象
      final memo = widget.editingMemo ?? MemoEntry();
      memo.content = content;
      memo.location = _locationCtrl.text.trim().isEmpty
          ? null
          : _locationCtrl.text.trim();
      memo.attachments = _pendingAttachments;
      // 编辑模式必须重置为 pending，否则同步引擎查不到该条目
      memo.syncStatus = SyncStatus.pending;

      await DatabaseService.saveMemo(memo);
      debugPrint('[MemoEditor] 本地保存成功，memo.id=${memo.id}');

      // 保存成功后才删除被移除的附件（避免用户取消编辑时误删）
      for (final att in _removedAttachments) {
        if (att.remoteResName != null) AttachmentService.deleteRemote(att.remoteResName!);
        if (att.localPath != null) AttachmentService.deleteLocal(att.localPath!);
      }

      // 后台静默推送到远端（fire-and-forget，不阻塞 UI 返回）
      final configured = await SettingsService.isConfigured;
      if (configured) {
        debugPrint('[MemoEditor] 服务器已配置，启动后台推送...');
        unawaited(SyncService.pushPendingBackground());
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[MemoEditor] 保存失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.editorSaveFailed}$e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 1,
        // 关闭按钮（取消编辑，直接返回）
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            debugPrint('[MemoEditor] 取消编辑，返回上一页');
            Navigator.pop(context);
          },
          tooltip: AppStrings.cancel,
        ),
        title: Text(
          _isEditing ? AppStrings.editorEditTitle : AppStrings.editorNewTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          // 保存中显示 loading，否则显示保存文字按钮
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text(
                    AppStrings.save,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
        ],
      ),
      // resizeToAvoidBottomInset=true（默认）让 Scaffold 在键盘弹起时自动收缩，
      // 底部工具栏随之上移，始终保持可见
      body: Column(
        children: [
          // ── 标签提示条（有候选时显示）────────────────────────────
          if (_tagPrefix != null && _tagSuggestions.isNotEmpty)
            _TagSuggestionBar(
              suggestions: _tagSuggestions,
              onSelect: _acceptTag,
            ),

          // ── 正文输入区（Markdown 格式提示）──────────────────────
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                key: _contentFieldKey,
                controller: _contentCtrl,
                focusNode: _contentFocus,
                maxLines: null,
                autofocus: false,
                style: const TextStyle(fontSize: 16, height: 1.7),
                decoration: const InputDecoration(
                  hintText: AppStrings.editorContentHint,
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Color(0xFFBDBDBD)),
                ),
              ),
            ),
          ),

          const Divider(height: 1),

          // ── 附件预览条（有附件时展示）────────────────────────────
          if (_pendingAttachments.isNotEmpty)
            _AttachmentBar(
              attachments: _pendingAttachments,
              onRemove: _removeAttachment,
            ),

          // ── 底部工具栏：附件按钮 + 位置输入 ──────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  // 附件按钮
                  _uploading
                      ? const SizedBox(
                          width: 36,
                          height: 36,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.attach_file),
                          color: Colors.grey[600],
                          iconSize: 22,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                          tooltip: '添加附件',
                          onPressed: _pickAttachment,
                        ),
                  const SizedBox(width: 4),
                  Icon(Icons.location_on_outlined,
                      size: 18, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _locationCtrl,
                      style:
                          TextStyle(fontSize: 14, color: Colors.grey[700]),
                      decoration: const InputDecoration(
                        hintText: AppStrings.editorLocationHint,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
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
}

// ── 附件类型枚举 ───────────────────────────────────────────────────

enum _AttachType { image, audio, file }

// ── 附件预览条 ─────────────────────────────────────────────────────

/// 编辑器中已添加附件的横向预览条
///
/// 图片显示缩略图，音频/文件显示图标+文件名，每项右上角有删除按钮。
class _AttachmentBar extends StatelessWidget {
  final List<AttachmentInfo> attachments;
  final ValueChanged<AttachmentInfo> onRemove;

  const _AttachmentBar({
    required this.attachments,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) =>
            _AttachThumb(attachment: attachments[i], onRemove: onRemove),
      ),
    );
  }
}

class _AttachThumb extends StatefulWidget {
  final AttachmentInfo attachment;
  final ValueChanged<AttachmentInfo> onRemove;

  const _AttachThumb({required this.attachment, required this.onRemove});

  @override
  State<_AttachThumb> createState() => _AttachThumbState();
}

class _AttachThumbState extends State<_AttachThumb> {
  String _baseUrl = '';

  @override
  void initState() {
    super.initState();
    SettingsService.serverUrl.then((v) {
      if (mounted) setState(() => _baseUrl = v ?? '');
    });
  }

  AttachmentInfo get attachment => widget.attachment;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _buildThumbContent(),
          ),
        ),
        // 删除按钮
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => widget.onRemove(attachment),
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThumbContent() {
    if (attachment.isImage) {
      final path = attachment.localPath;
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) {
          return Image.file(file, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _iconFallback());
        }
      }
      final url = attachment.fullUrl(_baseUrl);
      if (url != null && url.isNotEmpty) {
        return Image.network(url, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _iconFallback());
      }
      return _iconFallback();
    }

    return _iconFallback();
  }

  Widget _iconFallback() {
    IconData icon;
    if (attachment.isAudio) {
      icon = Icons.music_note;
    } else if (attachment.mimeType == 'application/pdf') {
      icon = Icons.picture_as_pdf_outlined;
    } else if (attachment.isImage) {
      icon = Icons.image_outlined;
    } else {
      icon = Icons.insert_drive_file_outlined;
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: Colors.grey[500]),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              attachment.filename,
              style: TextStyle(fontSize: 8, color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 标签候选提示条 ─────────────────────────────────────────────────

/// 在编辑器键盘上方横向滚动显示匹配的标签候选
class _TagSuggestionBar extends StatelessWidget {
  final List<TagStat> suggestions;
  final ValueChanged<String> onSelect;

  const _TagSuggestionBar({
    required this.suggestions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final tag = suggestions[i];
          return GestureDetector(
            onTap: () => onSelect(tag.name),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#${tag.name}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${tag.count}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
