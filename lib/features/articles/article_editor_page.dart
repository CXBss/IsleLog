import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database/database_service.dart';
import '../../data/models/article_entry.dart';
import '../../data/models/attachment_info.dart';
import '../../data/models/folder_entry.dart';
import '../../data/models/memo_entry.dart';
import '../../services/api/memos_api_service.dart';
import '../../services/attachment/attachment_service.dart';
import '../../services/settings/settings_service.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/constants/app_constants.dart';
import '../conflict/article_conflict_overview_page.dart';
import '../revision_history/revision_history_page.dart';

/// 文章新建 / 编辑页面
///
/// - [editingArticle] 为 null → 新建模式
/// - [editingArticle] 不为 null → 编辑模式
///
/// 保存后立即写本地 Isar（离线优先），后台静默推送到远端。
class ArticleEditorPage extends StatefulWidget {
  final ArticleEntry? editingArticle;
  /// 新建时可预设文件夹
  final FolderEntry? initialFolder;

  const ArticleEditorPage({super.key, this.editingArticle, this.initialFolder});

  @override
  State<ArticleEditorPage> createState() => _ArticleEditorPageState();
}

class _ArticleEditorPageState extends State<ArticleEditorPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late final FocusNode _contentFocus;

  bool _saving = false;
  bool _previewMode = false;
  bool _uploading = false;

  /// 当前选中的文件夹（null = 根目录）
  FolderEntry? _selectedFolder;
  List<FolderEntry> _allFolders = [];

  String _visibility = 'PRIVATE';

  /// 本次编辑的附件列表
  final List<AttachmentInfo> _pendingAttachments = [];

  /// 编辑模式下被移除的旧附件
  final List<AttachmentInfo> _removedAttachments = [];

  bool get _isEditing => widget.editingArticle != null;

  static bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  static bool get _isDesktop => !_isMobile;

  @override
  void initState() {
    super.initState();
    final article = widget.editingArticle;
    _titleCtrl = TextEditingController(text: article?.title ?? '');
    _contentCtrl = TextEditingController(text: article?.content ?? '');
    _contentFocus = FocusNode(onKeyEvent: _onKeyEvent);
    _visibility = article?.visibility ?? 'PRIVATE';
    _selectedFolder = widget.initialFolder;

    if (article != null) {
      _pendingAttachments.addAll(article.attachments);
      // 记录编辑前快照，供冲突三方对比使用
      article.originalContent = article.content;
      article.originalTitle = article.title;
    }

    _loadFolders(article);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _loadFolders(ArticleEntry? article) async {
    final folders = await DatabaseService.getAllFolders();
    FolderEntry? currentFolder;
    if (article != null) {
      if (article.folderName != null) {
        currentFolder = folders.firstWhere(
          (f) => f.folderName == article.folderName,
          orElse: () => folders.firstWhere(
              (f) => f.id == article.localFolderId,
              orElse: () => FolderEntry()),
        );
        if (currentFolder.title.isEmpty) currentFolder = null;
      } else if (article.localFolderId != null) {
        try {
          currentFolder = folders.firstWhere((f) => f.id == article.localFolderId);
        } catch (_) {
          currentFolder = null;
        }
      }
    }
    if (mounted) {
      setState(() {
        _allFolders = folders;
        if (_selectedFolder == null && currentFolder != null) {
          _selectedFolder = currentFolder;
        }
      });
    }
  }

  // ── 键盘快捷键 ─────────────────────────────────────────────────

  bool _pasteBusy = false;
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Ctrl+S 或 Cmd/Ctrl+Enter 保存
    final isCtrlOrCmdPressed = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (isCtrlOrCmdPressed && event.logicalKey == LogicalKeyboardKey.keyS) {
      _save();
      return KeyEventResult.handled;
    }
    if (isCtrlOrCmdPressed && event.logicalKey == LogicalKeyboardKey.enter) {
      _save();
      return KeyEventResult.handled;
    }

    // Ctrl/Cmd+V：桌面端先判断剪贴板是否有图片
    if (_isDesktop) {
      final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;
      if (isCtrlOrCmd && event.logicalKey == LogicalKeyboardKey.keyV) {
        if (_pasteBusy) return KeyEventResult.handled;
        _pasteBusy = true;
        _handlePasteImage().then((handled) {
          _pasteBusy = false;
          if (!handled) _pasteText();
        });
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final text = _contentCtrl.text;
    final sel = _contentCtrl.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final newText = text.replaceRange(start, end, data.text!);
    _contentCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + data.text!.length),
    );
  }

  Future<bool> _handlePasteImage() async {
    if (!_isDesktop) return false;
    try {
      final bytes = await Pasteboard.image;
      if (bytes != null && bytes.isNotEmpty) {
        final filename = 'paste_${DateTime.now().millisecondsSinceEpoch}.png';
        final tempDir = await getTemporaryDirectory();
        await tempDir.create(recursive: true);
        final tempFile = File('${tempDir.path}/$filename');
        await tempFile.writeAsBytes(bytes);
        await _processFile(tempFile, filename, compress: true);
        return true;
      }
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        for (final path in files) {
          final file = File(path);
          if (file.existsSync()) {
            final filename = p.basename(path);
            await _processFile(file, filename, compress: _isImageFile(filename));
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[ArticleEditor] 粘贴失败：$e');
      return false;
    }
  }

  // ── 附件选择与上传 ─────────────────────────────────────────────

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
              leading: const Icon(Icons.attach_file),
              title: const Text('其他文件'),
              onTap: () => Navigator.pop(context, _AttachType.file),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    if (choice == _AttachType.camera) {
      await _takePhoto();
      return;
    }

    FileType fileType;
    switch (choice) {
      case _AttachType.image:
        fileType = FileType.image;
      case _AttachType.camera:
        return;
      case _AttachType.file:
        fileType = FileType.any;
    }

    final result = await FilePicker.platform.pickFiles(
      type: fileType,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.path == null) return;

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
      if (useCompress == null) return;
      compress = useCompress;
    }

    await _processFile(File(picked.path!), picked.name, compress: compress);
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    XFile? photo;
    try {
      photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
      );
    } catch (e) {
      debugPrint('[ArticleEditor] 拍照失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法访问相机：$e')),
        );
      }
      return;
    }
    if (photo == null) return;
    final filename = photo.name.isNotEmpty
        ? photo.name
        : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _processFile(File(photo.path), filename, compress: true);
  }

  Future<void> _processFile(File file, String filename, {bool compress = true}) async {
    setState(() => _uploading = true);
    try {
      final configured = await SettingsService.isConfigured;
      AttachmentInfo info;
      if (configured) {
        try {
          info = await AttachmentService.uploadToServer(file, filename: filename, compress: compress);
        } catch (e) {
          debugPrint('[ArticleEditor] 在线上传失败，降级本地存储：$e');
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
      if (mounted) setState(() => _pendingAttachments.add(info));
    } catch (e) {
      debugPrint('[ArticleEditor] 附件处理失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('附件处理失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removeAttachment(AttachmentInfo att) {
    setState(() => _pendingAttachments.remove(att));
    _removedAttachments.add(att);
  }

  static bool _isImageFile(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'}.contains(ext);
  }

  // ── 保存 ───────────────────────────────────────────────────────

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
      final article = _isEditing ? widget.editingArticle! : ArticleEntry();
      article.title = title;
      article.content = content;
      article.visibility = _visibility;
      article.syncStatus = SyncStatus.pending;
      article.folderName = _selectedFolder?.folderName;
      article.localFolderId = _selectedFolder?.id;
      article.attachments = _pendingAttachments;
      await DatabaseService.saveArticle(article);

      // 保存成功后才删除被移除的附件
      for (final att in _removedAttachments) {
        if (att.remoteResName != null) AttachmentService.deleteRemote(att.remoteResName!);
        if (att.localPath != null) AttachmentService.deleteLocal(att.localPath!);
      }

      final configured = await SettingsService.isConfigured;
      if (configured && _isEditing && article.articleName != null) {
        await _checkConflictAndPushOrNavigate(article);
      } else if (configured) {
        unawaited(SyncService.pushPendingBackground());
        if (mounted) Navigator.pop(context, true);
      } else {
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 拉取线上文章内容，三方对比决定是否弹出冲突处理流程
  ///
  /// 无冲突（远端 title+content == originalTitle+originalContent）→ 直接推送并返回
  /// 有冲突 → 跳转概览页，由用户处理后再推送
  Future<void> _checkConflictAndPushOrNavigate(ArticleEntry article) async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || token == null) {
      unawaited(SyncService.pushPendingBackground());
      if (mounted) Navigator.pop(context, true);
      return;
    }

    try {
      final api = MemosApiService(baseUrl: url, token: token);
      // articleName 格式为 "memos/xxx" 或 "articles/xxx"，getArticle 只需数字 id
      final articleId = article.articleName!.split('/').last;
      final remoteData = await api.getArticle(articleId);
      final remoteTitle = remoteData['title'] as String? ?? '';
      final remoteContent = remoteData['content'] as String? ?? '';
      final originalTitle = article.originalTitle ?? '';
      final originalContent = article.originalContent ?? '';

      // 三方对比：远端与编辑前快照相同 → 无冲突
      if (remoteTitle == originalTitle && remoteContent == originalContent) {
        debugPrint('[ArticleEditor] 无冲突，直接推送');
        article.originalTitle = null;
        article.originalContent = null;
        await DatabaseService.saveArticle(article, skipTimestamp: true);
        await SyncService.pushSingleArticle(article);
        if (mounted) Navigator.pop(context, true);
        return;
      }

      // 有冲突，跳转概览页
      debugPrint('[ArticleEditor] 发现冲突，进入冲突处理流程');
      article.conflictRemoteTitle = remoteTitle;
      article.conflictRemoteContent = remoteContent;
      article.syncStatus = SyncStatus.conflict;
      await DatabaseService.saveArticle(article, skipTimestamp: true);

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArticleConflictOverviewPage(
            article: article,
            remoteTitle: remoteTitle,
            remoteContent: remoteContent,
            onResolved: (resolvedTitle, resolvedContent) async {
              article.title = resolvedTitle;
              article.content = resolvedContent;
              article.originalTitle = null;
              article.originalContent = null;
              article.syncStatus = SyncStatus.pending;
              article.conflictRemoteTitle = null;
              article.conflictRemoteContent = null;
              await DatabaseService.saveArticle(article);
              await SyncService.pushSingleArticle(article);
            },
          ),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[ArticleEditor] 冲突检测失败，降级后台推送：$e');
      article.originalTitle = null;
      article.originalContent = null;
      await DatabaseService.saveArticle(article, skipTimestamp: true);
      unawaited(SyncService.pushPendingBackground());
      if (mounted) Navigator.pop(context, true);
    }
  }

  // ── 格式化工具 ─────────────────────────────────────────────────

  void _wrapSelection(String prefix, String suffix) {
    final ctrl = _contentCtrl;
    final sel = ctrl.selection;
    if (!sel.isValid) {
      ctrl.text = ctrl.text + prefix + suffix;
      return;
    }
    final selected = sel.textInside(ctrl.text);
    final newText = ctrl.text.replaceRange(sel.start, sel.end, '$prefix$selected$suffix');
    ctrl.value = ctrl.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(
          offset: sel.start + prefix.length + selected.length + suffix.length),
    );
    _contentFocus.requestFocus();
  }

  void _insertAtCursor(String text) {
    final ctrl = _contentCtrl;
    final sel = ctrl.selection;
    final pos = sel.isValid ? sel.baseOffset : ctrl.text.length;
    final newText = ctrl.text.substring(0, pos) + text + ctrl.text.substring(pos);
    ctrl.value = ctrl.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + text.length),
    );
    _contentFocus.requestFocus();
  }

  void _insertLinePrefix(String prefix) {
    final ctrl = _contentCtrl;
    final sel = ctrl.selection;
    final pos = sel.isValid ? sel.baseOffset : ctrl.text.length;
    final lineStart = ctrl.text.lastIndexOf('\n', pos - 1) + 1;
    final newText = ctrl.text.substring(0, lineStart) + prefix + ctrl.text.substring(lineStart);
    ctrl.value = ctrl.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + prefix.length),
    );
    _contentFocus.requestFocus();
  }

  // ── build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: TextField(
          controller: _titleCtrl,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: '文章标题',
            hintStyle: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.normal),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _contentFocus.requestFocus(),
        ),
        actions: [
          // 预览/编辑切换
          IconButton(
            icon: Icon(_previewMode ? Icons.edit_outlined : Icons.preview_outlined),
            tooltip: _previewMode ? '编辑' : '预览',
            onPressed: () => setState(() => _previewMode = !_previewMode),
          ),
          // 文件夹选择
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: '选择文件夹',
            onPressed: _showFolderPicker,
          ),
          // 可见性
          _VisibilityButton(
            visibility: _visibility,
            onChanged: (v) => setState(() => _visibility = v),
          ),
          // 编辑历史
          if (_isEditing && widget.editingArticle!.articleName != null)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: '编辑历史',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RevisionHistoryPage(
                    memoName: widget.editingArticle!.articleName!,
                    title: widget.editingArticle!.title,
                  ),
                ),
              ),
            ),
          // 保存
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text('保存',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
        ],
      ),
      body: Column(
        children: [
          // 文件夹路径提示
          if (_selectedFolder != null)
            Container(
              width: double.infinity,
              color: AppColors.primaryLight,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.folder, size: 14, color: AppColors.primaryDark),
                  const SizedBox(width: 4),
                  Text(_selectedFolder!.title,
                      style: const TextStyle(fontSize: 12, color: AppColors.primaryDark)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _selectedFolder = null),
                    child: const Icon(Icons.close, size: 14, color: AppColors.primaryDark),
                  ),
                ],
              ),
            ),
          // 编辑区 / 预览区
          Expanded(
            child: _previewMode
                ? Markdown(
                    data: _contentCtrl.text.isEmpty ? '*（内容为空）*' : _contentCtrl.text,
                    padding: const EdgeInsets.all(16),
                  )
                : TextField(
                    controller: _contentCtrl,
                    focusNode: _contentFocus,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(fontSize: 15, height: 1.6),
                    decoration: InputDecoration(
                      hintText: '开始写作...\n\n支持 Markdown 格式',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
          ),
          // 附件预览条（有附件时展示）
          if (_pendingAttachments.isNotEmpty)
            _AttachmentBar(
              attachments: _pendingAttachments,
              onRemove: _removeAttachment,
            ),
          // 格式化工具栏
          if (!_previewMode) _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.surface(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1),
            // 格式化按钮行
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  _ToolbarBtn(icon: Icons.title, tooltip: '标题',
                      onTap: () => _insertLinePrefix('# ')),
                  _ToolbarBtn(label: 'B', tooltip: '粗体',
                      onTap: () => _wrapSelection('**', '**')),
                  _ToolbarBtn(label: 'I', tooltip: '斜体',
                      onTap: () => _wrapSelection('*', '*')),
                  _ToolbarBtn(label: '`', tooltip: '行内代码',
                      onTap: () => _wrapSelection('`', '`')),
                  _ToolbarBtn(icon: Icons.code, tooltip: '代码块',
                      onTap: () => _insertAtCursor('```\n\n```')),
                  _ToolbarBtn(icon: Icons.link, tooltip: '链接',
                      onTap: () => _wrapSelection('[', '](url)')),
                  _ToolbarBtn(icon: Icons.format_list_numbered, tooltip: '有序列表',
                      onTap: () => _insertLinePrefix('1. ')),
                  _ToolbarBtn(icon: Icons.format_list_bulleted, tooltip: '无序列表',
                      onTap: () => _insertLinePrefix('- ')),
                  _ToolbarBtn(icon: Icons.check_box_outlined, tooltip: '待办项',
                      onTap: () => _insertLinePrefix('- [ ] ')),
                  _ToolbarBtn(icon: Icons.horizontal_rule, tooltip: '分隔线',
                      onTap: () => _insertAtCursor('\n---\n')),
                  _ToolbarBtn(icon: Icons.format_quote, tooltip: '引用',
                      onTap: () => _insertLinePrefix('> ')),
                ],
              ),
            ),
            // 附件操作行
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Row(
                children: [
                  // 拍照（仅移动端）
                  if (_isMobile)
                    IconButton(
                      icon: const Icon(Icons.camera_alt_outlined),
                      color: Colors.grey[600],
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: '拍照',
                      onPressed: _uploading ? null : _takePhoto,
                    ),
                  // 添加附件 / 上传中指示
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
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          tooltip: '添加附件',
                          onPressed: _pickAttachment,
                        ),
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFolderPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _FolderPickerSheet(
        folders: _allFolders,
        selected: _selectedFolder,
        onSelect: (folder) {
          setState(() => _selectedFolder = folder);
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

// ── 附件类型枚举 ───────────────────────────────────────────────────

enum _AttachType { camera, image, file }

// ── 附件预览条 ─────────────────────────────────────────────────────

class _AttachmentBar extends StatelessWidget {
  final List<AttachmentInfo> attachments;
  final ValueChanged<AttachmentInfo> onRemove;

  const _AttachmentBar({required this.attachments, required this.onRemove});

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
        separatorBuilder: (ctx, i) => const SizedBox(width: 8),
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
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => widget.onRemove(attachment),
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
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
              errorBuilder: (ctx, err, st) => _iconFallback());
        }
      }
      final url = attachment.fullUrl(_baseUrl);
      if (url != null && url.isNotEmpty) {
        return Image.network(url, fit: BoxFit.cover,
            errorBuilder: (ctx, err, st) => _iconFallback());
      }
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

// ────────────────────────────────────────────────────────────────
// 辅助 widget
// ────────────────────────────────────────────────────────────────

class _ToolbarBtn extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarBtn({this.icon, this.label, required this.tooltip, required this.onTap})
      : assert(icon != null || label != null);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 36,
          height: 44,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 18, color: Colors.grey[700])
                : Text(label!,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700])),
          ),
        ),
      ),
    );
  }
}

class _VisibilityButton extends StatelessWidget {
  final String visibility;
  final ValueChanged<String> onChanged;

  const _VisibilityButton({required this.visibility, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final icon = switch (visibility) {
      'PUBLIC' => Icons.public,
      'PROTECTED' => Icons.people_outline,
      _ => Icons.lock_outline,
    };
    final options = ['PRIVATE', 'PROTECTED', 'PUBLIC'];
    final labels = ['私密', '好友可见', '公开'];
    return PopupMenuButton<String>(
      icon: Icon(icon, size: 20),
      tooltip: '可见性',
      itemBuilder: (_) => List.generate(
        options.length,
        (i) => PopupMenuItem(value: options[i], child: Text(labels[i])),
      ),
      onSelected: onChanged,
    );
  }
}

class _FolderPickerSheet extends StatelessWidget {
  final List<FolderEntry> folders;
  final FolderEntry? selected;
  final ValueChanged<FolderEntry?> onSelect;

  const _FolderPickerSheet({
    required this.folders,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('选择文件夹', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('根目录'),
            selected: selected == null,
            selectedColor: AppColors.primary,
            onTap: () => onSelect(null),
          ),
          ...folders.map((f) => ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(f.title),
            selected: selected?.id == f.id,
            selectedColor: AppColors.primary,
            onTap: () => onSelect(f),
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
