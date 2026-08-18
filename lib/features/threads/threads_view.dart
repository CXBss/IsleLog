import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/database/database_service.dart';
import '../../data/models/thread_entry.dart';
import '../../shared/constants/app_constants.dart';
import 'thread_detail_page.dart';
import 'thread_picker_sheet.dart';
import 'widgets/thread_card.dart';

/// 事件串 Tab，分进行中与已完结两组。
class ThreadsView extends StatefulWidget {
  const ThreadsView({super.key});
  @override
  State<ThreadsView> createState() => _ThreadsViewState();
}

class _ThreadsViewState extends State<ThreadsView> {
  List<(ThreadEntry, ThreadCardData)> _active = [], _resolved = [];
  bool _loading = true;
  StreamSubscription<void>? _subscription;
  @override
  void initState() {
    super.initState();
    _load();
    _watch();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _watch() async {
    _subscription = (await DatabaseService.watchDbChanges()).listen((_) {
      if (mounted) _load();
    });
  }

  Future<ThreadCardData> _data(ThreadEntry thread) async {
    final dates = <DateTime>[];
    for (final id in thread.memberLocalIds) {
      final memo = await DatabaseService.getMemoById(id);
      if (memo != null && !memo.isDeleted) dates.add(memo.createdAt);
    }
    dates.sort();
    return ThreadCardData(
      title: thread.title,
      summary: thread.summary,
      memberCount: dates.length,
      startedAt: dates.isEmpty ? null : dates.first,
      lastAt: dates.isEmpty ? null : dates.last,
    );
  }

  Future<void> _load() async {
    final active = <(ThreadEntry, ThreadCardData)>[],
        resolved = <(ThreadEntry, ThreadCardData)>[];
    for (final thread in await DatabaseService.getAllThreads()) {
      final item = (thread, await _data(thread));
      (thread.status == ThreadStatus.resolved ? resolved : active).add(item);
    }
    if (mounted)
      setState(() {
        _active = active;
        _resolved = resolved;
        _loading = false;
      });
  }

  void _open(ThreadEntry thread) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ThreadDetailPage(threadId: thread.id)),
  ).then((_) => _load());
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.scaffoldBg(context),
    appBar: AppBar(
      title: const Text(AppStrings.navThreads),
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: '新建事件串',
          onPressed: () async {
            if (await showThreadCreateSheet(context) == true) _load();
          },
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _active.isEmpty && _resolved.isEmpty
        ? const Center(
            child: Text(
              '还没有事件串\n点击右上角新建并关联历史日记',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          )
        : ListView(
            children: [
              if (_active.isNotEmpty)
                _Header(label: '进行中', count: _active.length),
              ..._active.map(
                (item) =>
                    ThreadCard(data: item.$2, onTap: () => _open(item.$1)),
              ),
              if (_resolved.isNotEmpty)
                _Header(label: '已完结', count: _resolved.length),
              ..._resolved.map(
                (item) =>
                    ThreadCard(data: item.$2, onTap: () => _open(item.$1)),
              ),
            ],
          ),
  );
}

class _Header extends StatelessWidget {
  final String label;
  final int count;
  const _Header({required this.label, required this.count});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      '$label · $count',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
        color: Colors.grey[600],
      ),
    ),
  );
}
