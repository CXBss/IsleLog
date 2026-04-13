import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/article_entry.dart';
import '../../data/models/folder_entry.dart';
import '../../data/models/memo_entry.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/constants/app_constants.dart';
import '../revision_history/revision_history_page.dart';
import 'article_editor_page.dart';

/// 文章主页
///
/// 以文件浏览器方式展示文件夹和文章：
/// - 点击文件夹名/图标 → 进入该文件夹
/// - 点击最右侧展开图标 → 就地展开/收起子内容
/// - 顶部面包屑导航栏 → 点击跳回任意上级
class ArticlesView extends StatefulWidget {
  const ArticlesView({super.key});

  @override
  State<ArticlesView> createState() => _ArticlesViewState();
}

/// 面包屑条目
class _Crumb {
  final String label;
  final FolderEntry? folder; // null 表示根目录
  const _Crumb({required this.label, this.folder});
}

class _ArticlesViewState extends State<ArticlesView> {
  // 当前目录（null = 根目录）
  FolderEntry? _currentFolder;

  // 面包屑路径（第 0 项始终是根目录）
  final List<_Crumb> _breadcrumbs = [const _Crumb(label: '全部')];

  // 当前目录下的子文件夹
  List<FolderEntry> _subFolders = [];

  // 当前目录下的文章
  List<ArticleEntry> _articles = [];

  // 就地展开的文件夹（存 folder.id）
  final Map<int, _InlineExpansion> _expanded = {};

  bool _loading = true;
  bool _syncing = false;

  final TextEditingController _searchCtrl = TextEditingController();
  List<ArticleEntry> _searchResults = [];
  bool _searching = false;

  StreamSubscription<void>? _dbSub;

  @override
  void initState() {
    super.initState();
    _loadCurrentDir();
    _watchDb();
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _watchDb() async {
    final stream = await DatabaseService.watchDbChanges();
    _dbSub = stream.listen((_) => _loadCurrentDir());
  }

  // 加载当前目录的子文件夹和文章
  Future<void> _loadCurrentDir() async {
    final folder = _currentFolder;
    final subFolders = await DatabaseService.getFoldersByParent(
      parentFolderName: folder?.folderName,
      localParentFolderId: folder?.folderName == null ? folder?.id : null,
    );
    final articles = await DatabaseService.getArticlesPaged(
      folderName: folder?.folderName,
      localFolderId: (folder != null && folder.folderName == null) ? folder.id : null,
      rootOnly: folder == null,
    );

    // 重新加载所有已展开文件夹的内容
    final newExpanded = <int, _InlineExpansion>{};
    for (final entry in _expanded.entries) {
      if (!entry.value.open) {
        newExpanded[entry.key] = entry.value;
        continue;
      }
      final matches = subFolders.where((sf) => sf.id == entry.key).toList();
      if (matches.isEmpty) continue; // 文件夹已不存在
      final f = matches.first;
      final childFolders = await DatabaseService.getFoldersByParent(
        parentFolderName: f.folderName,
        localParentFolderId: f.folderName == null ? f.id : null,
      );
      final childArticles = await DatabaseService.getArticlesPaged(
        folderName: f.folderName,
        localFolderId: (f.folderName == null) ? f.id : null,
        rootOnly: false,
      );
      newExpanded[entry.key] = _InlineExpansion(
        open: true,
        subFolders: childFolders,
        articles: childArticles,
      );
    }

    if (mounted) {
      setState(() {
        _subFolders = subFolders;
        _articles = articles;
        _expanded.clear();
        _expanded.addAll(newExpanded);
        _loading = false;
      });
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    await SyncService.syncAll();
    if (mounted) setState(() => _syncing = false);
  }

  // 进入文件夹
  void _enterFolder(FolderEntry folder) {
    setState(() {
      _currentFolder = folder;
      _breadcrumbs.add(_Crumb(label: folder.title, folder: folder));
      _subFolders = [];
      _articles = [];
      _expanded.clear();
      _loading = true;
    });
    _loadCurrentDir();
  }

  // 面包屑导航：点击跳转到对应层级
  void _navigateToCrumb(int index) {
    if (index == _breadcrumbs.length - 1) return; // 已在此层
    setState(() {
      _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
      _currentFolder = _breadcrumbs[index].folder;
      _subFolders = [];
      _articles = [];
      _expanded.clear();
      _loading = true;
    });
    _loadCurrentDir();
  }

  // 就地展开/收起
  Future<void> _toggleInline(FolderEntry folder) async {
    final current = _expanded[folder.id];
    if (current != null && current.open) {
      setState(() => _expanded[folder.id] = const _InlineExpansion(open: false));
      return;
    }
    // 展开：加载子内容
    final childFolders = await DatabaseService.getFoldersByParent(
      parentFolderName: folder.folderName,
      localParentFolderId: folder.folderName == null ? folder.id : null,
    );
    final childArticles = await DatabaseService.getArticlesPaged(
      folderName: folder.folderName,
      localFolderId: (folder.folderName == null) ? folder.id : null,
      rootOnly: false,
    );
    if (mounted) {
      setState(() {
        _expanded[folder.id] = _InlineExpansion(
          open: true,
          subFolders: childFolders,
          articles: childArticles,
        );
      });
    }
  }

  void _onSearchChanged(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searching = false;
        _searchResults = [];
      });
      return;
    }
    setState(() => _searching = true);
    final results = await DatabaseService.searchArticles(query.trim());
    if (mounted) setState(() => _searchResults = results);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('文章'),
        backgroundColor: AppColors.surface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          _syncing
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.sync),
                  tooltip: '同步',
                  onPressed: _syncNow,
                ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '新建文件夹',
            onPressed: _showCreateFolderDialog,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: '搜索文章...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: AppColors.primaryLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_articles_new',
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.primary,
        tooltip: '新建文章',
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 面包屑导航（搜索时隐藏）
          if (!_searching) _buildBreadcrumb(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _searching
                    ? _buildSearchResults()
                    : _buildFileList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return Container(
      color: AppColors.surface(context),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            for (int i = 0; i < _breadcrumbs.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ),
              GestureDetector(
                onTap: () => _navigateToCrumb(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    _breadcrumbs[i].label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == _breadcrumbs.length - 1
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: i == _breadcrumbs.length - 1
                          ? AppColors.primaryDark
                          : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Text('没有匹配的文章', style: TextStyle(color: Colors.grey[500])),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) => _ArticleListItem(
        article: _searchResults[i],
        onTap: () => _openEditor(article: _searchResults[i]),
        onLongPress: () => _showArticleMenu(_searchResults[i]),
      ),
    );
  }

  Widget _buildFileList() {
    final isEmpty = _subFolders.isEmpty && _articles.isEmpty;
    if (isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('还没有内容', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
            const SizedBox(height: 4),
            Text('点击右下角 + 新建文章', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      );
    }

    final items = <Widget>[];

    // 子文件夹
    for (final folder in _subFolders) {
      items.add(_FolderRow(
        folder: folder,
        expanded: _expanded[folder.id]?.open ?? false,
        onEnter: () => _enterFolder(folder),
        onToggle: () => _toggleInline(folder),
        onLongPress: () => _showFolderMenu(folder),
      ));
      // 就地展开内容
      final exp = _expanded[folder.id];
      if (exp != null && exp.open) {
        for (final sf in exp.subFolders) {
          items.add(Padding(
            padding: const EdgeInsets.only(left: 24),
            child: _FolderRow(
              folder: sf,
              expanded: false,
              onEnter: () => _enterFolder(sf),
              onToggle: () {},
              onLongPress: () => _showFolderMenu(sf),
              showToggle: false,
            ),
          ));
        }
        for (final a in exp.articles) {
          items.add(Padding(
            padding: const EdgeInsets.only(left: 24),
            child: _ArticleListItem(
              article: a,
              onTap: () => _openEditor(article: a),
              onLongPress: () => _showArticleMenu(a),
            ),
          ));
        }
        if (exp.subFolders.isEmpty && exp.articles.isEmpty) {
          items.add(Padding(
            padding: const EdgeInsets.only(left: 48, bottom: 4),
            child: Text(
              '空文件夹',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ));
        }
        items.add(const Divider(height: 1, indent: 24));
      }
    }

    // 当前目录下的文章
    for (final article in _articles) {
      items.add(_ArticleListItem(
        article: article,
        onTap: () => _openEditor(article: article),
        onLongPress: () => _showArticleMenu(article),
      ));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: items,
    );
  }

  void _openEditor({ArticleEntry? article, FolderEntry? folder}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArticleEditorPage(
          editingArticle: article,
          initialFolder: folder ?? _currentFolder,
        ),
      ),
    );
    _loadCurrentDir();
  }

  void _showCreateFolderDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        Future<void> doCreate() async {
          final title = ctrl.text.trim();
          if (title.isEmpty) return;
          final folder = FolderEntry()
            ..title = title
            ..parentFolderName = _currentFolder?.folderName
            ..localParentFolderId =
                (_currentFolder?.folderName == null) ? _currentFolder?.id : null;
          await DatabaseService.saveFolder(folder);
          unawaited(SyncService.pushPendingBackground());
          if (ctx.mounted) Navigator.pop(ctx);
        }

        return AlertDialog(
          title: const Text('新建文件夹'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: '文件夹名称'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => doCreate(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(onPressed: doCreate, child: const Text('创建')),
          ],
        );
      },
    );
  }

  void _showFolderMenu(FolderEntry folder) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameFolderDialog(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('在此新建文章'),
              onTap: () {
                Navigator.pop(ctx);
                _openEditor(folder: folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('删除', style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteFolder(folder);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameFolderDialog(FolderEntry folder) {
    final ctrl = TextEditingController(text: folder.title);
    showDialog(
      context: context,
      builder: (ctx) {
        Future<void> doRename() async {
          final title = ctrl.text.trim();
          if (title.isEmpty) return;
          folder.title = title;
          folder.syncStatus = SyncStatus.pending;
          await DatabaseService.saveFolder(folder);
          unawaited(SyncService.pushPendingBackground());
          if (ctx.mounted) Navigator.pop(ctx);
        }

        return AlertDialog(
          title: const Text('重命名文件夹'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => doRename(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(onPressed: doRename, child: const Text('确认')),
          ],
        );
      },
    );
  }

  void _confirmDeleteFolder(FolderEntry folder) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件夹'),
        content: Text('确定删除「${folder.title}」？\n文件夹内的文章将移至上级目录。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await DatabaseService.softDeleteFolder(folder.id);
              unawaited(SyncService.pushPendingBackground());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showArticleMenu(ArticleEntry article) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                _openEditor(article: article);
              },
            ),
            if (article.articleName != null)
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('编辑历史'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RevisionHistoryPage(
                        memoName: article.articleName!,
                        title: article.title,
                      ),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('删除', style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteArticle(article);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteArticle(ArticleEntry article) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文章'),
        content: Text('确定删除「${article.title.isEmpty ? "无标题" : article.title}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await DatabaseService.softDeleteArticle(article.id);
              unawaited(SyncService.pushPendingBackground());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 就地展开状态
// ──────────────────────────────────────────────────────────────────

class _InlineExpansion {
  final bool open;
  final List<FolderEntry> subFolders;
  final List<ArticleEntry> articles;

  const _InlineExpansion({
    required this.open,
    this.subFolders = const [],
    this.articles = const [],
  });
}

// ──────────────────────────────────────────────────────────────────
// 文件夹行
// ──────────────────────────────────────────────────────────────────

class _FolderRow extends StatelessWidget {
  final FolderEntry folder;
  final bool expanded;
  final VoidCallback onEnter;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;
  final bool showToggle;

  const _FolderRow({
    required this.folder,
    required this.expanded,
    required this.onEnter,
    required this.onToggle,
    required this.onLongPress,
    this.showToggle = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEnter,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.folder_open : Icons.folder,
              color: AppColors.primaryDark,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                folder.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (folder.syncStatus == SyncStatus.pending)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.grey),
              ),
            // 进入文件夹的箭头
            Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
            // 展开/收起按钮
            if (showToggle)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: Colors.grey[500],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 文章列表项
// ──────────────────────────────────────────────────────────────────

class _ArticleListItem extends StatelessWidget {
  final ArticleEntry article;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ArticleListItem({
    required this.article,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = article.content.trim().isEmpty
        ? '（无内容）'
        : article.content.trim().replaceAll('\n', ' ');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.article_outlined, size: 18, color: Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title.isEmpty ? '（无标题）' : article.title,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (article.syncStatus == SyncStatus.pending)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.grey),
              ),
            Text(
              _formatDate(article.updatedAt),
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (dt.year == now.year) return '${dt.month}/${dt.day}';
    return '${dt.year}/${dt.month}/${dt.day}';
  }
}
