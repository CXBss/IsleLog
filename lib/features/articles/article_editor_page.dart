import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../data/database/database_service.dart';
import '../../data/models/article_entry.dart';
import '../../data/models/folder_entry.dart';
import '../../data/models/memo_entry.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/constants/app_constants.dart';

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

  /// 当前选中的文件夹（null = 根目录）
  FolderEntry? _selectedFolder;
  List<FolderEntry> _allFolders = [];

  String _visibility = 'PRIVATE';

  bool get _isEditing => widget.editingArticle != null;

  @override
  void initState() {
    super.initState();
    final article = widget.editingArticle;
    _titleCtrl = TextEditingController(text: article?.title ?? '');
    _contentCtrl = TextEditingController(text: article?.content ?? '');
    _contentFocus = FocusNode(onKeyEvent: (node, event) {
      // Desktop: Ctrl+S 保存
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.keyS &&
          HardwareKeyboard.instance.isControlPressed) {
        _save();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    });
    _visibility = article?.visibility ?? 'PRIVATE';
    _selectedFolder = widget.initialFolder;
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
      await DatabaseService.saveArticle(article);
      // 后台静默推送（静默失败，不阻塞保存）
      unawaited(SyncService.pushPendingBackground());
      if (mounted) Navigator.pop(context, true);
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
      selection: TextSelection.collapsed(offset: sel.start + prefix.length + selected.length + suffix.length),
    );
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
  }

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
          // 格式化工具栏
          if (!_previewMode) _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 44,
      color: AppColors.surface(context),
      child: SingleChildScrollView(
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
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
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

