import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../data/models/vault_entry.dart';
import '../../services/vault/vault_controller.dart';
import '../../services/vault/vault_migration.dart';
import '../../services/vault/vault_screen_guard.dart';
import '../../shared/constants/app_constants.dart';
import '../memo_detail/memo_detail_page.dart';
import 'vault_browse_model.dart';
import 'vault_calendar_view.dart';
import 'vault_detail_page.dart';
import 'vault_editor_page.dart';
import 'widgets/vault_entry_card.dart';
import 'widgets/vault_memo_card.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  final _searchController = TextEditingController();

  List<MemoEntry> _mainMemos = [];
  VaultBrowseFilter _filter = const VaultBrowseFilter();
  bool _showCalendar = false;
  DateTime _focusedMonth = DateTime.now();

  /// 合并筛选后的结果缓存。旧实现每次 setState 都重新 sort 全部 2000+ 条，
  /// 这里只在数据或筛选条件变化时重算。
  List<(String, List<VaultBrowseItem>)> _groups = const [];

  @override
  void initState() {
    super.initState();
    VaultScreenGuard.enable();
    // 后台超时锁定时必须把页面主动弹掉——否则会停在一个已经没有密钥、
    // 却仍在展示已解密内容的页面上。
    VaultController.instance.isUnlockedListenable.addListener(_onLockChanged);
    _loadMain();
  }

  void _onLockChanged() {
    if (!VaultController.instance.isUnlocked && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    VaultScreenGuard.disable();
    VaultController.instance.isUnlockedListenable.removeListener(
      _onLockChanged,
    );
    _searchController.dispose();
    VaultController.instance.lock(); // 离开页面即锁定
    super.dispose();
  }

  Future<void> _loadMain() async {
    final memos = await DatabaseService.getAllMemos();
    if (!mounted) return;
    setState(() => _mainMemos = memos);
    _recompute();
  }

  List<VaultEntry> get _vaultEntries => VaultController.instance.entries;

  void _recompute() {
    final items = VaultBrowseModel.apply(
      memos: _mainMemos,
      entries: _vaultEntries,
      filter: _filter,
    );
    setState(() => _groups = VaultBrowseModel.groupByDay(items));
  }

  void _updateFilter(VaultBrowseFilter next) {
    _filter = next;
    _recompute();
  }

  // ── 迁移 ──────────────────────────────────────────────────────

  Future<void> _moveIn(MemoEntry memo) async {
    final confirmed = await _confirm(
      title: '移入隐私空间？',
      body: '原日记及其评论将从主时间线永久移除。',
      action: '移入',
    );
    if (confirmed != true || !mounted) return;

    final result = await VaultMigration.moveIntoVault(memo);
    if (!mounted) return;
    switch (result) {
      case VaultMigrationResult.ok:
        await _loadMain();
      case VaultMigrationResult.blockedPendingSync:
        _toast('这条日记还有未同步的改动，请先完成同步');
      case VaultMigrationResult.blockedConflict:
        _toast('这条日记有冲突，请先在冲突页处理');
      case VaultMigrationResult.failed:
        _toast('移入失败，请稍后重试');
    }
  }

  /// vault 条目的长按菜单。
  ///
  /// 与主库时间线卡片的长按菜单对齐（memo_timeline_card.dart 的 _showMenu）。
  /// 此前长按被「移出」独占、菜单根本没建，删除按钮埋在 列表→详情→编辑 三层下，
  /// 只能靠「先移出、再去主库删」绕路。
  Future<void> _showVaultMenu(VaultEntry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.unarchive_outlined),
              title: const Text('移出隐私空间'),
              onTap: () => Navigator.pop(ctx, 'move_out'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('删除', style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'edit':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => VaultEditorPage(existing: entry)),
        );
        _recompute();
      case 'move_out':
        await _moveOut(entry);
      case 'delete':
        await _deleteEntry(entry);
    }
  }

  /// 删除 vault 条目。
  ///
  /// 主库的删除是软删 + SnackBar 撤销，这里不行：deleteEntry 是立即物理删除，
  /// 还会连带清掉 atc.bin 里的附件字节，服务端也没有回收站——撤不回来。
  /// 所以改用事前确认，而不是事后撤销。
  Future<void> _deleteEntry(VaultEntry entry) async {
    final confirmed = await _confirm(
      title: '删除这条隐私日记？',
      body: '连同它的附件一起永久删除，无法恢复。',
      action: '删除',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await VaultController.instance.deleteEntry(entry.id);
    if (!mounted) return;
    _recompute();
    _toast('已删除');
  }

  Future<void> _moveOut(VaultEntry entry) async {
    final confirmed = await _confirm(
      title: '移出隐私空间？',
      body: '这条日记（含附件）将恢复到主时间线。',
      action: '移出',
    );
    if (confirmed != true || !mounted) return;

    final result = await VaultMigration.moveOutOfVault(entry);
    if (!mounted) return;
    if (result == VaultMigrationResult.ok) {
      await _loadMain();
    } else {
      _toast('移出失败，请稍后重试');
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              action,
              style: destructive
                  ? const TextStyle(color: AppColors.error)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── 筛选交互 ──────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filter.day ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('zh'),
    );
    if (picked != null) _updateFilter(_filter.copyWith(day: picked));
  }

  Future<void> _pickTag() async {
    final counts = VaultBrowseModel.tagCounts(
      memos: _mainMemos,
      entries: _vaultEntries,
      scope: _filter.scope,
    );
    if (counts.isEmpty) {
      _toast('还没有任何标签');
      return;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (_filter.tag != null)
              ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('清除标签筛选'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
            ...sorted.map(
              (e) => ListTile(
                leading: const Icon(Icons.tag, size: 18),
                title: Text(e.key),
                trailing: Text('${e.value}'),
                selected: _filter.tag == e.key,
                onTap: () => Navigator.pop(ctx, e.key),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _updateFilter(
      picked.isEmpty
          ? _filter.copyWith(clearTag: true)
          : _filter.copyWith(tag: picked),
    );
  }

  void _clearFilters() {
    _searchController.clear();
    _updateFilter(VaultBrowseFilter(scope: _filter.scope));
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final vaultOnly = _filter.scope == VaultScope.vaultOnly;
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私空间'),
        actions: [
          IconButton(
            icon: Icon(_showCalendar ? Icons.view_list : Icons.calendar_month),
            tooltip: _showCalendar ? '时间线' : '日历',
            onPressed: () => setState(() => _showCalendar = !_showCalendar),
          ),
          IconButton(
            icon: Icon(
              vaultOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
            ),
            tooltip: vaultOnly ? '显示全部' : '仅看隐私',
            onPressed: () => _updateFilter(
              _filter.copyWith(
                scope: vaultOnly ? VaultScope.all : VaultScope.vaultOnly,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (_filter.hasAnyFilter) _buildFilterChips(),
          if (_showCalendar)
            VaultCalendarView(
              focusedMonth: _focusedMonth,
              selectedDay: _filter.day,
              daysWithEntries: VaultBrowseModel.daysWithEntriesInMonth(
                memos: _mainMemos,
                entries: _vaultEntries,
                scope: _filter.scope,
                year: _focusedMonth.year,
                month: _focusedMonth.month,
              ),
              onMonthChanged: (m) => setState(() => _focusedMonth = m),
              onDaySelected: (d) {
                _focusedMonth = d;
                _updateFilter(_filter.copyWith(day: d));
              },
            ),
          Expanded(child: _buildTimeline()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const VaultEditorPage()));
          _recompute();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(child: _buildSearchField()),
          IconButton(
            icon: Icon(
              Icons.event,
              color: _filter.day != null ? AppColors.primary : null,
            ),
            tooltip: '按日期筛选',
            onPressed: _pickDate,
          ),
          IconButton(
            icon: Icon(
              Icons.tag,
              color: _filter.tag != null ? AppColors.primary : null,
            ),
            tooltip: '按标签筛选',
            onPressed: _pickTag,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      // 隐私内容不进系统输入法的学习词库
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        hintText: '搜索日记…',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _updateFilter(_filter.copyWith(query: ''));
                },
              ),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onChanged: (v) => _updateFilter(_filter.copyWith(query: v)),
    );
  }

  Widget _buildFilterChips() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 6,
          children: [
            if (_filter.day != null)
              InputChip(
                label: Text(VaultBrowseModel.dayKey(_filter.day!)),
                avatar: const Icon(Icons.event, size: 16),
                onDeleted: () =>
                    _updateFilter(_filter.copyWith(clearDay: true)),
              ),
            if (_filter.tag != null)
              InputChip(
                label: Text('#${_filter.tag}'),
                onDeleted: () =>
                    _updateFilter(_filter.copyWith(clearTag: true)),
              ),
            ActionChip(label: const Text('清除全部'), onPressed: _clearFilters),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    if (_groups.isEmpty) {
      return Center(
        child: Text(
          _filter.hasAnyFilter ? '没有符合条件的日记' : '还没有条目',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    return ListView.builder(
      itemCount: _groups.length,
      itemBuilder: (ctx, i) {
        final (day, items) = _groups[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(
                day,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
            ...items.map(_buildItem),
          ],
        );
      },
    );
  }

  Widget _buildItem(VaultBrowseItem item) {
    return switch (item) {
      VaultBrowseVaultItem(:final entry) => VaultEntryCard(
        entry: entry,
        // 与主库时间线卡片一致：单击进详情、双击直接编辑、长按出菜单。
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => VaultDetailPage(entry: entry)),
          );
          _recompute();
        },
        onDoubleTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => VaultEditorPage(existing: entry)),
          );
          _recompute();
        },
        onLongPress: () => _showVaultMenu(entry),
      ),
      VaultBrowseMemo(:final memo) => VaultMemoCard(
        memo: memo,
        query: _filter.query,
        // 点击看全文，复用主页的详情页；长按才是移入。
        // 此前只接了 onLongPress，普通日记点了没反应，在隐私空间里
        // 根本没有途径读到全文，也就无从判断该不该移入。
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => MemoDetailPage(memo: memo)));
          if (mounted) await _loadMain();
        },
        onLongPress: () => _moveIn(memo),
      ),
    };
  }
}
