import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../shared/constants/app_constants.dart';
import '../home/widgets/memo_timeline_card.dart';

/// 日历视图
///
/// ## 性能策略
///
/// 不再全量加载所有日记，改为按需分两层查询：
///
/// 1. **月度高亮层**：[DatabaseService.getDaysWithMemoInMonth] 只拉取当月有
///    记录的「天数」整数集合（非常轻量），驱动日历格子的圆点高亮。
///    翻月时重新查询新月份。
///
/// 2. **当日详情层**：[DatabaseService.getMemosByDate] 在点击某天时按需查询
///    当天的日记列表，不提前加载其他日期的数据。
///
/// 3. **DB 变更监听**：使用带 300ms debounce 的 [DatabaseService.watchDbChanges]，
///    批量同步时不会高频重刷；收到通知后只刷新当前月高亮和当日列表。
class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  /// 当前日历聚焦的月份
  DateTime _focusedDay = DateTime.now();

  /// 当前选中的日期
  DateTime _selectedDay = DateTime.now();

  // ── 数据状态 ──────────────────────────────────────────────────

  /// 当前月份有日记的「天数」集合（如 {7, 9, 10, 11}）
  Set<int> _daysWithMemo = {};

  /// 当前选中日期的日记列表
  List<MemoEntry> _selectedMemos = [];

  /// 月高亮数据是否加载中（控制日历区 loading）
  bool _monthLoading = true;

  /// 当日列表是否加载中（控制下方列表 loading）
  bool _dayLoading = true;

  // ── Stream 订阅 ───────────────────────────────────────────────

  StreamSubscription<void>? _dbSub;

  @override
  void initState() {
    super.initState();
    // 主动触发首次加载，不依赖 watchDbChanges 的 fireImmediately 信号
    _loadMonthData(_focusedDay.year, _focusedDay.month);
    _loadDayData(_selectedDay);
    _initDbWatch();
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    super.dispose();
  }

  // ── 初始化 & 监听 ─────────────────────────────────────────────

  /// 订阅 DB 变更流（带 debounce），仅监听后续写操作触发刷新。
  Future<void> _initDbWatch() async {
    debugPrint('[CalendarView] 初始化 DB 监听...');
    final stream = await DatabaseService.watchDbChanges();
    _dbSub = stream.listen((_) {
      debugPrint('[CalendarView] DB 变更，刷新月高亮和当日列表');
      _loadMonthData(_focusedDay.year, _focusedDay.month);
      _loadDayData(_selectedDay);
    });
  }

  /// 加载指定月份有日记的天数集合
  Future<void> _loadMonthData(int year, int month) async {
    debugPrint('[CalendarView] 加载月高亮 $year-$month');
    setState(() => _monthLoading = true);
    final days =
        await DatabaseService.getDaysWithMemoInMonth(year, month);
    if (mounted) {
      setState(() {
        _daysWithMemo = days;
        _monthLoading = false;
      });
    }
  }

  /// 加载指定日期的日记列表
  Future<void> _loadDayData(DateTime date) async {
    debugPrint('[CalendarView] 加载当日列表 ${date.toLocal()}');
    setState(() => _dayLoading = true);
    final memos = await DatabaseService.getMemosByDate(date);
    memos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (mounted) {
      setState(() {
        _selectedMemos = memos;
        _dayLoading = false;
      });
    }
  }

  // ── 月份导航 ──────────────────────────────────────────────────

  void _prevMonth() {
    final newDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
    debugPrint('[CalendarView] 切换到上月：${newDay.year}-${newDay.month}');
    setState(() => _focusedDay = newDay);
    _loadMonthData(newDay.year, newDay.month);
  }

  void _nextMonth() {
    final newDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
    debugPrint('[CalendarView] 切换到下月：${newDay.year}-${newDay.month}');
    setState(() => _focusedDay = newDay);
    _loadMonthData(newDay.year, newDay.month);
  }

  // ── 农历标签 ──────────────────────────────────────────────────

  /// 计算指定日期对应的农历标签
  ///
  /// 农历初一显示 "X月"（月份），其余显示 "初X"（日数）。
  /// 异常时返回空字符串，跳过渲染。
  String _lunarLabel(DateTime date) {
    try {
      final solar = Solar.fromDate(date);
      final lunar = solar.getLunar();
      return lunar.getDay() == 1
          ? '${lunar.getMonthInChinese()}月'
          : lunar.getDayInChinese();
    } catch (e) {
      debugPrint('[CalendarView] 农历计算失败 date=$date: $e');
      return '';
    }
  }

  // ── 构建 ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: null,
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          final availW = constraints.maxWidth;
          final availH = constraints.maxHeight;

          // 宽度 >= 720 时切换为横向布局（日历左 / 列表右）
          const wideBreakpoint = 720.0;
          final isWide = availW >= wideBreakpoint;

          if (isWide) {
            return _buildWideLayout(availW, availH);
          } else {
            return _buildNarrowLayout(availW, availH);
          }
        },
      ),
    );
  }

  // ── 布局 ──────────────────────────────────────────────────────

  /// 计算日历行高
  ///
  /// [calendarW]：日历可用宽度；[maxCalH]：日历允许的最大高度。
  double _calcRowHeight(double calendarW, double maxCalH) {
    // 每列宽度即为正方形格子的边长
    final byW = (calendarW / 7).floorToDouble();
    const dowHeight = 32.0;
    final byH = ((maxCalH - dowHeight) / 6).floorToDouble();
    return byW.clamp(0.0, byH).clamp(44.0, 72.0);
  }

  /// 月份导航栏（月份切换 + 今日 + 分享）
  Widget _buildMonthHeader() {
    return Container(
      color: AppColors.surfaceWhite,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _prevMonth,
            tooltip: AppStrings.calendarPrevMonth,
          ),
          Expanded(
            child: Text(
              '${_focusedDay.year}年 ${_focusedDay.month}月',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _nextMonth,
            tooltip: AppStrings.calendarNextMonth,
          ),
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              final monthChanged = now.year != _focusedDay.year ||
                  now.month != _focusedDay.month;
              setState(() {
                _focusedDay = now;
                _selectedDay = now;
              });
              if (monthChanged) _loadMonthData(now.year, now.month);
              _loadDayData(now);
            },
            child: const Text(AppStrings.calendarToday,
                style: TextStyle(color: AppColors.primary)),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {},
            tooltip: AppStrings.calendarShare,
          ),
        ],
      ),
    );
  }

  /// 构建日历 TableCalendar widget
  Widget _buildCalendar(double rowHeight) {
    return AnimatedOpacity(
      opacity: _monthLoading ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: TableCalendar<void>(
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        eventLoader: (day) =>
            _daysWithMemo.contains(day.day) ? [null] : [],
        startingDayOfWeek: StartingDayOfWeek.monday,
        headerVisible: false,
        rowHeight: rowHeight,
        calendarStyle: const CalendarStyle(
          outsideDaysVisible: false,
          markerSize: 0,
        ),
        calendarBuilders: CalendarBuilders(
          dowBuilder: (ctx, day) {
            const labels = ['一', '二', '三', '四', '五', '六', '日'];
            final isWeekend = day.weekday >= 6;
            return Center(
              child: Text(
                labels[day.weekday - 1],
                style: TextStyle(
                  fontSize: 13,
                  color:
                      isWeekend ? Colors.red[300] : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          },
          defaultBuilder: (ctx, day, _) => _DayCell(
            day: day,
            lunarLabel: _lunarLabel(day),
            hasEvents: _daysWithMemo.contains(day.day),
            cellHeight: rowHeight,
          ),
          selectedBuilder: (ctx, day, _) => _DayCell(
            day: day,
            lunarLabel: _lunarLabel(day),
            hasEvents: _daysWithMemo.contains(day.day),
            isSelected: true,
            cellHeight: rowHeight,
          ),
          todayBuilder: (ctx, day, _) => _DayCell(
            day: day,
            lunarLabel: _lunarLabel(day),
            hasEvents: _daysWithMemo.contains(day.day),
            isToday: true,
            cellHeight: rowHeight,
          ),
        ),
        onDaySelected: (selected, focused) {
          debugPrint('[CalendarView] 选中日期：$selected');
          setState(() {
            _selectedDay = selected;
            _focusedDay = focused;
          });
          _loadDayData(selected);
        },
        onPageChanged: (focused) {
          debugPrint(
              '[CalendarView] 翻页到：${focused.year}-${focused.month}');
          setState(() => _focusedDay = focused);
          _loadMonthData(focused.year, focused.month);
        },
      ),
    );
  }

  /// 竖向布局（窄屏）：日历在上，列表在下
  Widget _buildNarrowLayout(double availW, double availH) {
    const calendarMaxWidth = 560.0;
    final calendarW = availW.clamp(0.0, calendarMaxWidth);
    // 正方形格子：行高 = 列宽
    final rowHeight = (calendarW / 7).floorToDouble().clamp(44.0, 72.0);
    const dowHeight = 32.0;
    final calendarH = dowHeight + rowHeight * 6;

    return Column(
      children: [
        _buildMonthHeader(),
        SizedBox(
          height: calendarH,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: calendarMaxWidth),
              child: _buildCalendar(rowHeight),
            ),
          ),
        ),
        const Divider(height: 1, thickness: 1),
        Expanded(child: _buildDayList(availW)),
      ],
    );
  }

  /// 横向布局（宽屏 >= 720px）：左侧日历，右侧列表，竖向分割线分隔
  Widget _buildWideLayout(double availW, double availH) {
    final calendarW = (availW * 0.42).clamp(300.0, 420.0);
    final rowHeight = _calcRowHeight(calendarW, availH * 0.88);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 左侧：日历（含月份导航）──────────────────────────
        SizedBox(
          width: calendarW,
          child: Column(
            children: [
              _buildMonthHeader(),
              _buildCalendar(rowHeight),
            ],
          ),
        ),

        // ── 竖向分割线 ──────────────────────────────────────
        const VerticalDivider(width: 1, thickness: 1),

        // ── 右侧：当日日记列表 ──────────────────────────────
        Expanded(child: _buildDayList(availW - calendarW - 1)),
      ],
    );
  }

  /// 构建当日日记列表区域
  Widget _buildDayList(double availWidth) {
    if (_dayLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_selectedMemos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_calendar_outlined,
                size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              AppStrings.calendarEmpty,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ],
        ),
      );
    }
    // 列表与日历保持相同最大宽度并居中
    final hPad = availWidth > 600 ? 24.0 : 12.0;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomPad = 84.0 + bottomInset;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(hPad, 12, hPad, bottomPad),
          itemCount: _selectedMemos.length,
          itemBuilder: (ctx, i) => MemoTimelineCard(
            memo: _selectedMemos[i],
            isLast: i == _selectedMemos.length - 1,
            showTime: true,
          ),
        ),
      ),
    );
  }
}

/// 日历单元格
///
/// 根据状态（选中 / 今天 / 有事件 / 普通）显示不同背景色和文字颜色。
/// 有事件时在日期数字下方绘制一个绿色小圆点。
class _DayCell extends StatelessWidget {
  final DateTime day;
  final String lunarLabel;
  final bool hasEvents;
  final bool isSelected;
  final bool isToday;

  /// 格子行高，用于自适应字号（由父层传入）
  final double cellHeight;

  const _DayCell({
    required this.day,
    required this.lunarLabel,
    required this.hasEvents,
    required this.cellHeight,
    this.isSelected = false,
    this.isToday = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color dayColor;
    Color lunarColor;

    if (isSelected) {
      bg = AppColors.primary;
      dayColor = Colors.white;
      lunarColor = Colors.white70;
    } else if (isToday) {
      bg = AppColors.primaryLight;
      dayColor = AppColors.primaryDark;
      lunarColor = AppColors.primary;
    } else if (hasEvents) {
      bg = AppColors.primaryLighter;
      dayColor = Colors.black87;
      lunarColor = Colors.grey[500]!;
    } else {
      bg = Colors.transparent;
      dayColor = Colors.black87;
      lunarColor = Colors.grey[400]!;
    }

    // 根据行高自适应字号，保持格子内内容比例协调
    // cellHeight 范围 48~72，dayFontSize 范围 13~17
    final dayFontSize = (cellHeight * 0.25).clamp(13.0, 17.0);
    final lunarFontSize = (cellHeight * 0.14).clamp(8.0, 11.0);
    final margin = cellHeight < 56 ? 2.0 : 3.0;

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
      margin: EdgeInsets.all(margin),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: isToday && !isSelected
            ? Border.all(color: AppColors.primary, width: 1.5)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${day.day}',
            style: TextStyle(
              fontSize: dayFontSize,
              fontWeight:
                  isSelected || isToday ? FontWeight.bold : FontWeight.normal,
              color: dayColor,
            ),
          ),
          if (lunarLabel.isNotEmpty)
            Text(lunarLabel,
                style: TextStyle(fontSize: lunarFontSize, color: lunarColor)),
          if (hasEvents && !isSelected) ...[
            SizedBox(height: cellHeight < 56 ? 1.0 : 2.0),
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    ),
    );
  }
}
