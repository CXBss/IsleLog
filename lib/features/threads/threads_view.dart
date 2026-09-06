import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/database/database_service.dart';
import '../../data/database/thread_membership_policy.dart';
import '../../data/models/thread_entry.dart';
import '../../data/models/thread_suggestion_entry.dart';
import '../../services/api/memos_api_service.dart';
import '../../services/settings/settings_service.dart';
import '../../shared/constants/app_constants.dart';
import 'thread_detail_page.dart';
import 'thread_picker_sheet.dart';
import 'widgets/suggestion_banner.dart';
import 'widgets/thread_ai_status_line.dart';
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

  List<ThreadSuggestionEntry> _suggestions = [];
  List<SuggestionItem> _suggestionItems = [];
  ThreadAiStatusData? _aiStatus;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSuggestions();
    _loadAiStatus();
    _watch();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _watch() async {
    _subscription = (await DatabaseService.watchDbChanges()).listen((_) {
      if (mounted) {
        _load();
        _loadSuggestions();
      }
    });
  }

  Future<void> _loadSuggestions() async {
    final suggestions = await DatabaseService.getPendingSuggestions();
    final resolutions = <SuggestionResolution>[];
    for (final suggestion in suggestions) {
      final memo = await DatabaseService.getMemoById(suggestion.memoLocalId);
      final thread = await DatabaseService.getThreadById(
        suggestion.threadLocalId,
      );
      resolutions.add(
        SuggestionResolution(suggestion: suggestion, memo: memo, thread: thread),
      );
    }
    // kept 与 resolved 严格按下标一一对应，见 buildAlignedSuggestions 注释：
    // 一旦其中一条被跳过（memo/thread 已不存在或被软删除），后续下标必须
    // 同步偏移，否则横幅上点的「加入/忽略」会作用到错误的建议上。
    final aligned = buildAlignedSuggestions(resolutions);
    final items = <SuggestionItem>[
      for (var i = 0; i < aligned.kept.length; i++)
        SuggestionItem(
          suggestionLocalKey: '${aligned.kept[i].id}',
          memoSnippet: aligned.resolved[i].$1.content.replaceAll('\n', ' '),
          threadTitle: aligned.resolved[i].$2.title,
          reason: aligned.kept[i].reason,
        ),
    ];
    if (mounted) {
      setState(() {
        _suggestions = aligned.kept;
        _suggestionItems = items;
      });
    }
  }

  /// 接受建议：本地把日记加进事件串，并把建议标为已接受。
  ///
  /// 成员写入走客户端既有的推送链路，服务端不代写，避免两个写入方互相覆盖。
  Future<void> _acceptSuggestion(int index) async {
    await DatabaseService.applySuggestionDecision(
      _suggestions[index],
      accepted: true,
    );
    await _loadSuggestions();
    await _load();
  }

  Future<void> _dismissSuggestion(int index) async {
    await DatabaseService.applySuggestionDecision(
      _suggestions[index],
      accepted: false,
    );
    await _loadSuggestions();
  }

  Future<void> _loadAiStatus() async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) return;
    try {
      final data = await MemosApiService(
        baseUrl: url,
        token: token,
      ).getThreadAiStatus();
      if (!mounted) return;
      setState(() {
        _aiStatus = ThreadAiStatusData(
          enabled: data['enabled'] == true,
          providerAvailable: data['providerAvailable'] == true,
          pendingMemos: (data['pendingMemos'] as num?)?.toInt() ?? 0,
          dirtyThreads: (data['dirtyThreads'] as num?)?.toInt() ?? 0,
        );
      });
    } catch (_) {
      // 离线或服务端不支持时静默跳过，状态行不显示
    }
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
              if (_aiStatus != null) ThreadAiStatusLine(data: _aiStatus!),
              SuggestionBanner(
                items: _suggestionItems,
                onAccept: _acceptSuggestion,
                onDismiss: _dismissSuggestion,
              ),
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
        color: AppColors.textSecondary(context),
      ),
    ),
  );
}
