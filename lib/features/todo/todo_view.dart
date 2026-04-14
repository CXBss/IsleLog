import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../features/memo_detail/memo_detail_page.dart';
import '../../shared/constants/app_constants.dart';

/// 待办视图
///
/// 汇总所有含待办项的日记（todoStatus != none），按创建时间倒序排列。
/// 支持 全部 / 未完成 / 已完成 三档筛选；待办项可就地勾选（直接修改 content）。
class TodoView extends StatefulWidget {
  const TodoView({super.key});

  @override
  State<TodoView> createState() => _TodoViewState();
}

class _TodoViewState extends State<TodoView> {
  /// 当前筛选：null=全部，hasPending=未完成，allDone=已完成
  TodoStatus? _filter;

  List<MemoEntry> _memos = [];
  bool _loading = true;
  bool _scanning = false;

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
    super.dispose();
  }

  Future<void> _load() async {
    final result = await DatabaseService.getMemosWithTodo(filter: _filter);
    if (mounted) setState(() { _memos = result; _loading = false; });
  }

  Future<void> _watchDb() async {
    final stream = await DatabaseService.watchDbChanges();
    _dbSub = stream.listen((_) => _load());
  }

  /// 切换某条日记中指定行的待办勾选状态。
  Future<void> _toggleTodo(MemoEntry memo, int lineIndex) async {
    final lines = memo.content.split('\n');
    if (lineIndex >= lines.length) return;
    final line = lines[lineIndex];
    if (line.contains('- [ ]')) {
      lines[lineIndex] = line.replaceFirst('- [ ]', '- [x]');
    } else if (RegExp(r'- \[[xX]\]').hasMatch(line)) {
      lines[lineIndex] = line.replaceFirst(RegExp(r'- \[[xX]\]'), '- [ ]');
    } else {
      return;
    }
    memo.content = lines.join('\n');
    await DatabaseService.saveMemo(memo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('待办'),
        backgroundColor: AppColors.surface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          _scanning
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '重新扫描待办状态',
                  onPressed: () async {
                    setState(() => _scanning = true);
                    final count = await DatabaseService.rebuildTodoStatus();
                    if (mounted) {
                      setState(() => _scanning = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(count > 0
                              ? '扫描完成，更新了 $count 条'
                              : '扫描完成，状态均正确'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _FilterBar(
            current: _filter,
            onChanged: (v) {
              setState(() { _filter = v; _loading = true; });
              _load();
            },
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _memos.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _memos.length,
                  itemBuilder: (ctx, i) => _TodoCard(
                    memo: _memos[i],
                    onToggle: (lineIdx) => _toggleTodo(_memos[i], lineIdx),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MemoDetailPage(memo: _memos[i]),
                        ),
                      );
                      _load();
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_box_outline_blank,
              size: 56, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            _filter == TodoStatus.allDone
                ? '还没有已完成的待办'
                : _filter == TodoStatus.hasPending
                    ? '没有未完成的待办'
                    : '还没有待办事项',
            style: TextStyle(color: Colors.grey[500], fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            '在日记中用 - [ ] 添加待办项',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── 筛选栏 ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final TodoStatus? current;
  final ValueChanged<TodoStatus?> onChanged;

  const _FilterBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: AppColors.surface(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _Chip(label: '全部', selected: current == null,
              onTap: () => onChanged(null)),
          const SizedBox(width: 8),
          _Chip(label: '未完成', selected: current == TodoStatus.hasPending,
              onTap: () => onChanged(TodoStatus.hasPending)),
          const SizedBox(width: 8),
          _Chip(label: '已完成', selected: current == TodoStatus.allDone,
              onTap: () => onChanged(TodoStatus.allDone)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.primaryLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : AppColors.primaryDark,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ── 待办卡片 ──────────────────────────────────────────────────────────────

class _TodoCard extends StatelessWidget {
  final MemoEntry memo;
  final ValueChanged<int> onToggle;
  final VoidCallback onTap;

  const _TodoCard({
    required this.memo,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lines = memo.content.split('\n');
    final todoItems = <_TodoItem>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('- [ ]')) {
        todoItems.add(_TodoItem(
            lineIndex: i,
            text: line.replaceFirst(RegExp(r'^.*- \[ \]\s*'), ''),
            done: false));
      } else if (RegExp(r'- \[[xX]\]').hasMatch(line)) {
        todoItems.add(_TodoItem(
            lineIndex: i,
            text: line.replaceFirst(RegExp(r'^.*- \[[xX]\]\s*'), ''),
            done: true));
      }
    }

    final pendingCount = todoItems.where((t) => !t.done).length;
    final totalCount = todoItems.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 卡片头部
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Row(
                  children: [
                    Text(
                      _formatDate(memo.createdAt),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: pendingCount == 0
                            ? AppColors.primaryLight
                            : AppColors.primaryLighter,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        pendingCount == 0
                            ? '全部完成'
                            : '剩余 $pendingCount / $totalCount',
                        style: TextStyle(
                          fontSize: 11,
                          color: pendingCount == 0
                              ? AppColors.primaryDark
                              : AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 待办列表
              ...todoItems.map((item) => _buildTodoRow(context, item)),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodoRow(BuildContext context, _TodoItem item) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                value: item.done,
                onChanged: (_) => onToggle(item.lineIndex),
                activeColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  item.text.isEmpty ? '（空待办）' : item.text,
                  style: TextStyle(
                    fontSize: 14,
                    color: item.done
                        ? Colors.grey[400]
                        : AppColors.textPrimary(context),
                    decoration:
                        item.done ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.grey[400],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day) {
      return '今天 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (dt.year == now.year) {
      return '${dt.month}月${dt.day}日';
    }
    return '${dt.year}年${dt.month}月${dt.day}日';
  }
}

class _TodoItem {
  final int lineIndex;
  final String text;
  final bool done;
  const _TodoItem(
      {required this.lineIndex, required this.text, required this.done});
}
