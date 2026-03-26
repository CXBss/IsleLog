import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../home/widgets/memo_search_card.dart';
import '../home/widgets/memo_timeline_card.dart';

/// 归档日记列表页
class ArchiveView extends StatefulWidget {
  const ArchiveView({super.key});

  @override
  State<ArchiveView> createState() => _ArchiveViewState();
}

class _ArchiveViewState extends State<ArchiveView> {
  List<MemoEntry> _memos = [];
  bool _loading = true;
  StreamSubscription<void>? _dbSub;

  @override
  void initState() {
    super.initState();
    _load();
    _watchDb();
  }

  Future<void> _watchDb() async {
    final stream = await DatabaseService.watchDbChanges();
    _dbSub = stream.listen((_) => _load());
  }

  Future<void> _load() async {
    final memos = await DatabaseService.getArchivedMemos();
    if (mounted) setState(() { _memos = memos; _loading = false; });
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('归档'),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => showSearch(
              context: context,
              delegate: _ArchiveSearchDelegate(),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF2F4F6),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _memos.isEmpty
              ? const Center(
                  child: Text('暂无归档日记', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _memos.length,
                  itemBuilder: (ctx, i) => _ArchiveItem(
                    key: ValueKey(_memos[i].id),
                    memo: _memos[i],
                    isLast: i == _memos.length - 1,
                  ),
                ),
    );
  }
}

/// 归档列表条目：显示日期头 + 时间线卡片
class _ArchiveItem extends StatelessWidget {
  final MemoEntry memo;
  final bool isLast;

  const _ArchiveItem({super.key, required this.memo, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final d = memo.createdAt;
    final dateStr =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 0, 4),
          child: Text(
            dateStr,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
        ),
        MemoTimelineCard(memo: memo, isLast: isLast, showTime: true),
      ],
    );
  }
}

// ── 归档搜索 ───────────────────────────────────────────────────────

class _ArchiveSearchDelegate extends SearchDelegate<void> {
  @override
  String get searchFieldLabel => '搜索归档内容…';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) =>
      _ArchiveSearchResults(query: query);

  @override
  Widget buildSuggestions(BuildContext context) =>
      query.isEmpty ? const SizedBox() : _ArchiveSearchResults(query: query);
}

class _ArchiveSearchResults extends StatefulWidget {
  final String query;
  const _ArchiveSearchResults({required this.query});

  @override
  State<_ArchiveSearchResults> createState() => _ArchiveSearchResultsState();
}

class _ArchiveSearchResultsState extends State<_ArchiveSearchResults> {
  List<MemoEntry> _results = [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _doSearch(widget.query);
  }

  @override
  void didUpdateWidget(_ArchiveSearchResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _doSearch(widget.query);
  }

  Future<void> _doSearch(String q) async {
    if (q == _lastQuery) return;
    _lastQuery = q;
    setState(() => _loading = true);
    final results = await DatabaseService.searchArchivedMemos(q);
    if (mounted && _lastQuery == q) {
      setState(() { _results = results; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_results.isEmpty) {
      return Center(
        child: Text('没有找到"${widget.query}"',
            style: const TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _results.length,
      itemBuilder: (ctx, i) => MemoSearchCard(
        key: ValueKey(_results[i].id),
        memo: _results[i],
        query: widget.query,
      ),
    );
  }
}
