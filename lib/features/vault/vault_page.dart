import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../data/models/vault_entry.dart';
import '../../services/vault/vault_controller.dart';
import '../../services/vault/vault_migration.dart';
import '../../services/vault/vault_screen_guard.dart';
import 'vault_editor_page.dart';
import 'widgets/vault_entry_card.dart';

sealed class _TimelineItem {
  DateTime get time;
}

class _MainItem extends _TimelineItem {
  final MemoEntry memo;
  _MainItem(this.memo);
  @override
  DateTime get time => memo.createdAt;
}

class _VaultItem extends _TimelineItem {
  final VaultEntry entry;
  _VaultItem(this.entry);
  @override
  DateTime get time => entry.createdAt;
}

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  bool _vaultOnly = false;
  List<MemoEntry> _mainMemos = [];

  @override
  void initState() {
    super.initState();
    VaultScreenGuard.enable();
    _loadMain();
    // 后台超时锁定时必须把页面主动弹掉——否则会停在一个已经没有密钥、
    // 却仍在展示已解密内容的页面上。
    VaultController.instance.isUnlockedListenable.addListener(_onLockChanged);
  }

  void _onLockChanged() {
    if (!VaultController.instance.isUnlocked && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _loadMain() async {
    final memos = await DatabaseService.getAllMemos();
    if (mounted) setState(() => _mainMemos = memos);
  }

  @override
  void dispose() {
    VaultScreenGuard.disable();
    VaultController.instance.isUnlockedListenable.removeListener(
      _onLockChanged,
    );
    VaultController.instance.lock(); // 离开页面即锁定
    super.dispose();
  }

  Future<void> _moveIn(MemoEntry memo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移入隐私空间？'),
        content: const Text('原日记及其评论将从主时间线永久移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await VaultMigration.moveIntoVault(memo);
    if (!mounted) return;
    switch (result) {
      case VaultMigrationResult.ok:
        await _loadMain();
        setState(() {});
      case VaultMigrationResult.blockedPendingSync:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('这条日记还有未同步的改动，请先完成同步')));
      case VaultMigrationResult.blockedConflict:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('这条日记有冲突，请先在冲突页处理')));
      case VaultMigrationResult.failed:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('移入失败，请稍后重试')));
    }
  }

  Future<void> _moveOut(VaultEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移出隐私空间？'),
        content: const Text('这条日记（含附件）将恢复到主时间线。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await VaultMigration.moveOutOfVault(entry);
    if (!mounted) return;
    if (result == VaultMigrationResult.ok) {
      await _loadMain();
      setState(() {});
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('移出失败，请稍后重试')));
    }
  }

  List<_TimelineItem> _mergedItems() {
    final vaultEntries = VaultController.instance.entries;
    final items = <_TimelineItem>[
      if (!_vaultOnly) ..._mainMemos.map(_MainItem.new),
      ...vaultEntries.map(_VaultItem.new),
    ];
    items.sort((a, b) => b.time.compareTo(a.time));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _mergedItems();
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私空间'),
        actions: [
          IconButton(
            icon: Icon(
              _vaultOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
            ),
            tooltip: _vaultOnly ? '显示全部' : '仅看隐私',
            onPressed: () => setState(() => _vaultOnly = !_vaultOnly),
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('还没有条目'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final item = items[i];
                return switch (item) {
                  _VaultItem(:final entry) => VaultEntryCard(
                    entry: entry,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VaultEditorPage(existing: entry),
                        ),
                      );
                      setState(() {});
                    },
                    onLongPress: () => _moveOut(entry),
                  ),
                  _MainItem(:final memo) => ListTile(
                    title: Text(
                      memo.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text('（普通日记，长按移入隐私空间）'),
                    onLongPress: () => _moveIn(memo),
                  ),
                };
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const VaultEditorPage()));
          setState(() {});
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
