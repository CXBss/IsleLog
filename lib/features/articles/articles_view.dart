import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/article_entry.dart';
import '../../data/models/folder_entry.dart';
import '../../data/models/memo_entry.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/constants/app_constants.dart';
import 'article_editor_page.dart';

/// 文章主页
///
/// 以文件夹树形结构展示文章，支持离线创建/编辑/删除。
/// 顶部搜索，长按文件夹/文章打开操作菜单。
class ArticlesView extends StatefulWidget {
  const ArticlesView({super.key});

  @override
  State<ArticlesView> createState() => _ArticlesViewState();
}

class _ArticlesViewState extends State<ArticlesView> {
  List<FolderEntry> _folders = [];
  // 文件夹 id → 文章列表（已展开的文件夹）
  final Map<int?, List<ArticleEntry>> _articlesByFolder = {};
  // 展开状态：null = 根目录，folder.id = 对应文件夹
  final Set<int?> _expanded = {null}; // 根目录默认展开

  bool _loading = true;
  bool _syncing = false;
  final TextEditingController _searchCtrl = TextEditingController();
  List<ArticleEntry> _searchResults = [];
  bool _searching = false;

  StreamSubscription<void>? _dbSub;

  @override
  void initState() {
    super.initState();
    _load();
    _watchDb();
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final folders = await DatabaseService.getAllFolders();
    // 加载所有已展开文件夹的文章（包括根目录）
    final newMap = <int?, List<ArticleEntry>>{};
    for (final key in _expanded) {
      if (key == null) {
        newMap[null] = await DatabaseService.getArticlesPaged(rootOnly: true);
      } else {
        final folder = folders.firstWhere((f) => f.id == key, orElse: () => FolderEntry());
        if (folder.title.isNotEmpty) {
          newMap[key] = await DatabaseService.getArticlesPaged(
            folderName: folder.folderName,
            localFolderId: folder.folderName == null ? key : null,
          );
        }
      }
    }
    if (mounted) {
      setState(() {
        _folders = folders;
        _articlesByFolder.clear();
        _articlesByFolder.addAll(newMap);
        _loading = false;
      });
    }
  }

  Future<void> _watchDb() async {
    final stream = await DatabaseService.watchDbChanges();
    _dbSub = stream.listen((_) => _load());
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    await SyncService.syncAll();
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _toggleFolder(int? folderId) async {
    if (_expanded.contains(folderId)) {
      setState(() {
        _expanded.remove(folderId);
        _articlesByFolder.remove(folderId);
      });
    } else {
      _expanded.add(folderId);
      if (folderId == null) {
        final articles = await DatabaseService.getArticlesPaged(rootOnly: true);
        if (mounted) setState(() => _articlesByFolder[null] = articles);
      } else {
        final folder = _folders.firstWhere((f) => f.id == folderId, orElse: () => FolderEntry());
        final articles = await DatabaseService.getArticlesPaged(
          folderName: folder.folderName,
          localFolderId: folder.folderName == null ? folderId : null,
        );
        if (mounted) setState(() => _articlesByFolder[folderId] = articles);
      }
    }
  }

  void _onSearchChanged(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _searching = false; _searchResults = []; });
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
                    width: 20, height: 20,
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
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
        tooltip: '新建文章',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _searching
              ? _buildSearchResults()
              : _buildTree(),
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

  Widget _buildTree() {
    final rootArticles = _articlesByFolder[null] ?? [];
    final isEmpty = _folders.isEmpty && rootArticles.isEmpty;

    if (isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('还没有文章', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
            const SizedBox(height: 4),
            Text('点击右下角 + 开始写作', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // 文件夹列表
        ..._folders.map((folder) => _FolderTile(
          folder: folder,
          expanded: _expanded.contains(folder.id),
          articles: _articlesByFolder[folder.id] ?? [],
          onToggle: () => _toggleFolder(folder.id),
          onNewArticle: () => _openEditor(folder: folder),
          onLongPress: () => _showFolderMenu(folder),
          onArticleTap: (a) => _openEditor(article: a),
          onArticleLongPress: (a) => _showArticleMenu(a),
        )),
        // 根目录分区
        _RootSection(
          expanded: _expanded.contains(null),
          articles: rootArticles,
          onToggle: () => _toggleFolder(null),
          onArticleTap: (a) => _openEditor(article: a),
          onArticleLongPress: (a) => _showArticleMenu(a),
        ),
      ],
    );
  }

  void _openEditor({ArticleEntry? article, FolderEntry? folder}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArticleEditorPage(
          editingArticle: article,
          initialFolder: folder,
        ),
      ),
    );
    _load();
  }

  void _showCreateFolderDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final title = ctrl.text.trim();
              if (title.isEmpty) return;
              final folder = FolderEntry()..title = title;
              await DatabaseService.saveFolder(folder);
              unawaited(SyncService.pushPendingBackground());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('创建'),
          ),
        ],
      ),
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
      builder: (ctx) => AlertDialog(
        title: const Text('重命名文件夹'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final title = ctrl.text.trim();
              if (title.isEmpty) return;
              folder.title = title;
              folder.syncStatus = SyncStatus.pending;
              await DatabaseService.saveFolder(folder);
              unawaited(SyncService.pushPendingBackground());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFolder(FolderEntry folder) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件夹'),
        content: Text('确定删除「${folder.title}」？\n文件夹内的文章将移至根目录。'),
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

// ────────────────────────────────────────────────────────────────
// 文件夹 Tile
// ────────────────────────────────────────────────────────────────

class _FolderTile extends StatelessWidget {
  final FolderEntry folder;
  final bool expanded;
  final List<ArticleEntry> articles;
  final VoidCallback onToggle;
  final VoidCallback onNewArticle;
  final VoidCallback onLongPress;
  final ValueChanged<ArticleEntry> onArticleTap;
  final ValueChanged<ArticleEntry> onArticleLongPress;

  const _FolderTile({
    required this.folder,
    required this.expanded,
    required this.articles,
    required this.onToggle,
    required this.onNewArticle,
    required this.onLongPress,
    required this.onArticleTap,
    required this.onArticleLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
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
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                if (folder.syncStatus == SyncStatus.pending)
                  const Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          if (articles.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 44, bottom: 8),
              child: Text('暂无文章',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400])),
            )
          else
            ...articles.map((a) => Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _ArticleListItem(
                article: a,
                onTap: () => onArticleTap(a),
                onLongPress: () => onArticleLongPress(a),
              ),
            )),
          const Divider(height: 1, indent: 16),
        ],
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────
// 根目录分区
// ────────────────────────────────────────────────────────────────

class _RootSection extends StatelessWidget {
  final bool expanded;
  final List<ArticleEntry> articles;
  final VoidCallback onToggle;
  final ValueChanged<ArticleEntry> onArticleTap;
  final ValueChanged<ArticleEntry> onArticleLongPress;

  const _RootSection({
    required this.expanded,
    required this.articles,
    required this.onToggle,
    required this.onArticleTap,
    required this.onArticleLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (articles.isEmpty && !expanded) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(expanded ? Icons.home : Icons.home_outlined,
                    color: Colors.grey[600], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('根目录',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: Colors.grey),
              ],
            ),
          ),
        ),
        if (expanded)
          ...articles.map((a) => _ArticleListItem(
            article: a,
            onTap: () => onArticleTap(a),
            onLongPress: () => onArticleLongPress(a),
          )),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────
// 文章列表项
// ────────────────────────────────────────────────────────────────

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
              const Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
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
