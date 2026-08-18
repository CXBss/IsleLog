import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/database/thread_membership_policy.dart';
import '../../data/models/memo_entry.dart';
import '../../data/models/thread_entry.dart';
import '../../shared/constants/app_constants.dart';

/// 为已有日记选择可多归属的事件串。
Future<bool?> showThreadPickerSheet(
  BuildContext context, {
  required int memoLocalId,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ThreadPickerSheet(memoLocalId: memoLocalId),
);

class _ThreadPickerSheet extends StatefulWidget {
  final int memoLocalId;
  const _ThreadPickerSheet({required this.memoLocalId});
  @override
  State<_ThreadPickerSheet> createState() => _ThreadPickerSheetState();
}

class _ThreadPickerSheetState extends State<_ThreadPickerSheet> {
  List<ThreadEntry> _threads = [];
  final _selected = <int>{};
  bool _changed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final threads = await DatabaseService.getAllThreads();
    if (mounted)
      setState(() {
        _threads = threads;
        _selected
          ..clear()
          ..addAll(
            threads
                .where(
                  (thread) =>
                      thread.memberLocalIds.contains(widget.memoLocalId),
                )
                .map((thread) => thread.id),
          );
      });
  }

  Future<void> _toggle(ThreadEntry thread, bool selected) async {
    thread
      ..memberLocalIds = toggleThreadMember(
        thread.memberLocalIds,
        widget.memoLocalId,
        selected: selected,
      )
      ..syncStatus = SyncStatus.pending;
    await DatabaseService.saveThread(thread);
    _changed = true;
    await _load();
  }

  Future<void> _newThread() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建事件串'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：工位蛐蛐'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    final thread = ThreadEntry()..title = title;
    thread.memberLocalIds = [widget.memoLocalId];
    await DatabaseService.saveThread(thread);
    _changed = true;
    await _load();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(width: 16),
              const Text(
                '归入事件串',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _newThread,
                icon: const Icon(Icons.add),
                label: const Text('新建'),
              ),
            ],
          ),
          const Divider(),
          if (_threads.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('还没有事件串，点击右上角新建'),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final thread in _threads)
                    CheckboxListTile(
                      value: _selected.contains(thread.id),
                      activeColor: AppColors.primary,
                      title: Text(thread.title),
                      subtitle: Text('${thread.memberLocalIds.length} 篇'),
                      onChanged: (value) => _toggle(thread, value ?? false),
                    ),
                ],
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, _changed),
            child: const Text('完成'),
          ),
        ],
      ),
    ),
  );
}

/// 创建事件串并通过全文搜索一次选择多篇历史日记。
Future<bool?> showThreadCreateSheet(BuildContext context) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ThreadCreateSheet(),
    );

class _ThreadCreateSheet extends StatefulWidget {
  const _ThreadCreateSheet();
  @override
  State<_ThreadCreateSheet> createState() => _ThreadCreateSheetState();
}

class _ThreadCreateSheetState extends State<_ThreadCreateSheet> {
  final _title = TextEditingController(), _search = TextEditingController();
  final _picked = <int>{};
  List<MemoEntry> _results = [];
  @override
  void dispose() {
    _title.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final query = _search.text.trim();
    final results = query.isEmpty
        ? <MemoEntry>[]
        : await DatabaseService.searchMemos(query);
    if (mounted) setState(() => _results = results);
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) return;
    final thread = ThreadEntry()..title = _title.text.trim();
    thread.memberLocalIds = _picked.toList();
    await DatabaseService.saveThread(thread);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '事件串标题',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                labelText: '搜索要加入的日记',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _runSearch,
                ),
              ),
            ),
          ),
          if (_picked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('已选 ${_picked.length} 篇'),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final memo in _results)
                  CheckboxListTile(
                    value: _picked.contains(memo.id),
                    activeColor: AppColors.primary,
                    title: Text(
                      memo.content.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${memo.createdAt.year}-${memo.createdAt.month}-${memo.createdAt.day}',
                    ),
                    onChanged: (value) => setState(() {
                      if (value ?? false) {
                        _picked.add(memo.id);
                      } else {
                        _picked.remove(memo.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(onPressed: _create, child: const Text('创建')),
            ],
          ),
        ],
      ),
    ),
  );
}
