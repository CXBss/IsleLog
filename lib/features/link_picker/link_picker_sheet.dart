import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/link/link_query.dart';
import '../../services/link/link_search.dart';
import '../../services/link/link_target.dart';
import '../../services/link/memo_link.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/widgets/highlighted_text.dart';

/// 弹出内链选择器，返回用户选中的目标；用户取消时返回 null。
///
/// [search] 仅供测试注入，生产代码不要传。
Future<LinkTarget?> showLinkPickerSheet(
  BuildContext context, {
  LinkSearchFn? search,
  int? excludeMemoId,
  int? excludeArticleId,
}) => showModalBottomSheet<LinkTarget>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _LinkPickerSheet(
    search:
        search ??
        (query, kind) => searchLinkTargets(
          query,
          kind,
          excludeMemoId: excludeMemoId,
          excludeArticleId: excludeArticleId,
        ),
  ),
);

class _LinkPickerSheet extends StatefulWidget {
  final LinkSearchFn search;
  const _LinkPickerSheet({required this.search});

  @override
  State<_LinkPickerSheet> createState() => _LinkPickerSheetState();
}

class _LinkPickerSheetState extends State<_LinkPickerSheet> {
  final TextEditingController _queryCtrl = TextEditingController();

  /// null 表示"全部"。
  LinkKind? _kindFilter;

  List<LinkTarget> _results = [];
  bool _loading = true;
  Timer? _debounce;

  /// 每次查询自增，用于丢弃过期的异步结果。
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _runSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  /// 输入变化时防抖，避免每敲一个字都全表扫描一遍。
  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  Future<void> _runSearch() async {
    final seq = ++_requestSeq;
    setState(() => _loading = true);
    final query = parseLinkQuery(_queryCtrl.text);
    final results = await widget.search(query, _kindFilter);
    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  void _setFilter(LinkKind? kind) {
    setState(() => _kindFilter = kind);
    _runSearch();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    // 日期选择器打开期间 sheet 可能已被关闭，此时再 setState 会抛异常。
    if (!mounted) return;
    final text =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}'
        '-${picked.day.toString().padLeft(2, '0')}';
    _queryCtrl.text = text;
    await _runSearch();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    // 键盘弹起时可用高度会缩水，sheet 必须跟着缩，
    // 否则顶部的搜索框会被推出屏幕。
    final available = (media.size.height - media.padding.top - bottomInset)
        .clamp(0.0, double.infinity);
    final preferred = media.size.height * 0.75;
    final sheetHeight = preferred <= available ? preferred : available;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: sheetHeight,
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '插入链接',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            _buildSearchField(),
            _buildFilterChips(),
            const Divider(height: 1),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: TextField(
      controller: _queryCtrl,
      autofocus: false,
      textInputAction: TextInputAction.search,
      onChanged: _onQueryChanged,
      onSubmitted: (_) {
        _debounce?.cancel();
        _runSearch();
      },
      decoration: InputDecoration(
        isDense: true,
        hintText: '搜索日期或关键字，如 3-12 / 暴雨',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          tooltip: '选择日期',
          onPressed: _pickDate,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );

  Widget _buildFilterChips() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        _chip('全部', null),
        const SizedBox(width: 8),
        _chip('日记', LinkKind.memo),
        const SizedBox(width: 8),
        _chip('文章', LinkKind.article),
      ],
    ),
  );

  Widget _chip(String label, LinkKind? kind) => ChoiceChip(
    label: Text(label),
    selected: _kindFilter == kind,
    onSelected: (_) => _setFilter(kind),
  );

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的日记或文章',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      );
    }
    final keyword = parseLinkQuery(_queryCtrl.text).keyword;
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 48),
      itemBuilder: (_, index) => _buildRow(_results[index], keyword),
    );
  }

  Widget _buildRow(LinkTarget target, String keyword) {
    final isMemo = target.kind == LinkKind.memo;
    return ListTile(
      dense: true,
      leading: Icon(
        isMemo ? Icons.article_outlined : Icons.description_outlined,
        size: 20,
        color: AppColors.primary,
      ),
      title: HighlightedText(
        text: target.label,
        query: keyword,
        maxLines: 1,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        target.preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
      ),
      trailing: target.isSynced
          ? null
          : Text(
              '未同步',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
      onTap: () => Navigator.pop(context, target),
    );
  }
}
