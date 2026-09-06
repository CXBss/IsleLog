import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/database/thread_membership_policy.dart';
import '../../data/models/memo_entry.dart';
import '../../data/models/thread_entry.dart';
import '../../shared/constants/app_constants.dart';
import '../memo_detail/memo_detail_page.dart';

/// 事件串详情：按日记时间升序展示完整事件过程。
class ThreadDetailPage extends StatefulWidget {
  final int threadId;
  const ThreadDetailPage({super.key, required this.threadId});

  @override
  State<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends State<ThreadDetailPage> {
  ThreadEntry? _thread;
  List<MemoEntry> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final thread = await DatabaseService.getThreadById(widget.threadId);
    final members = <MemoEntry>[];
    if (thread != null) {
      for (final id in thread.memberLocalIds) {
        final memo = await DatabaseService.getMemoById(id);
        if (memo != null && !memo.isDeleted) members.add(memo);
      }
      members.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    if (mounted)
      setState(() {
        _thread = thread;
        _members = members;
        _loading = false;
      });
  }

  Future<void> _edit({
    required String label,
    required String initial,
    required ValueChanged<String> onSave,
    bool allowEmpty = false,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null && (allowEmpty || value.isNotEmpty)) onSave(value);
  }

  Future<void> _save() async {
    final thread = _thread;
    if (thread == null) return;
    thread.syncStatus = SyncStatus.pending;
    await DatabaseService.saveThread(thread);
    await _load();
  }

  Future<void> _toggleSummaryLock() async {
    final thread = _thread;
    if (thread == null) return;
    thread.summaryLocked = !thread.summaryLocked;
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final thread = _thread;
    if (thread == null)
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('事件串不存在')),
      );
    final resolved = thread.status == ThreadStatus.resolved;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(thread.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑标题',
            onPressed: () => _edit(
              label: '事件串标题',
              initial: thread.title,
              onSave: (value) {
                thread.title = value;
                _save();
              },
            ),
          ),
          IconButton(
            icon: Icon(resolved ? Icons.replay : Icons.check_circle_outline),
            tooltip: resolved ? '重新打开' : '标记完结',
            onPressed: () {
              thread.status = resolved
                  ? ThreadStatus.active
                  : ThreadStatus.resolved;
              _save();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除事件串',
            onPressed: () async {
              await DatabaseService.softDeleteThread(thread.id);
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _edit(
                      label: '简介',
                      initial: thread.summary,
                      allowEmpty: true,
                      onSave: (value) {
                        thread.summary = value;
                        thread.summaryIsManual = true;
                        // 手动改写后自动锁定，否则当晚就被批次覆盖
                        thread.summaryLocked = true;
                        _save();
                      },
                    ),
                    child: Text(
                      thread.summary.isEmpty ? '点击添加一句话简介' : thread.summary,
                      style: TextStyle(
                        color: thread.summary.isEmpty
                            ? Colors.grey
                            : AppColors.textBody(context),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    thread.summaryLocked ? Icons.lock : Icons.lock_open_outlined,
                    size: 18,
                    color: thread.summaryLocked
                        ? AppColors.primary
                        : AppColors.textSecondary(context),
                  ),
                  tooltip: thread.summaryLocked ? '已锁定，点击解锁' : '锁定简介，AI 不再改写',
                  onPressed: _toggleSummaryLock,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '${_members.length} 篇${resolved ? ' · 已完结' : ''}',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
            ),
          ),
          if (_members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('还没有日记', style: TextStyle(color: Colors.grey)),
              ),
            ),
          for (var index = 0; index < _members.length; index++)
            _MemberCard(
              index: index,
              memo: _members[index],
              onOpen: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MemoDetailPage(memo: _members[index]),
                ),
              ).then((_) => _load()),
              onRemove: () {
                thread.memberLocalIds = toggleThreadMember(
                  thread.memberLocalIds,
                  _members[index].id,
                  selected: false,
                );
                _save();
              },
            ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  final int index;
  final MemoEntry memo;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  const _MemberCard({
    required this.index,
    required this.memo,
    required this.onOpen,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.surface(context),
      borderRadius: BorderRadius.circular(AppDimens.cardRadius),
    ),
    child: ListTile(
      onTap: onOpen,
      title: Text(
        memo.content.replaceAll('\n', ' '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${index + 1} · ${memo.createdAt.year}-${memo.createdAt.month.toString().padLeft(2, '0')}-${memo.createdAt.day.toString().padLeft(2, '0')}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        tooltip: '移出事件串',
        onPressed: onRemove,
      ),
    ),
  );
}
