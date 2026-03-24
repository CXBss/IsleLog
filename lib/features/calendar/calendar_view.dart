import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../home/widgets/memo_timeline_card.dart';

/// 日历视图（月视图 + 农历 + 有记录日期高亮 + 点击联动列表）
class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  Stream<List<MemoEntry>>? _stream;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  Future<void> _initStream() async {
    final stream = await DatabaseService.watchAllMemos();
    if (mounted) setState(() => _stream = stream);
  }

  String _lunarLabel(DateTime date) {
    try {
      final solar = Solar.fromDate(date);
      final lunar = solar.getLunar();
      return lunar.getDay() == 1
          ? '${lunar.getMonthInChinese()}月'
          : lunar.getDayInChinese();
    } catch (_) {
      return '';
    }
  }

  void _prevMonth() => setState(() {
        _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
      });

  void _nextMonth() => setState(() {
        _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
      });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MemoEntry>>(
      stream: _stream,
      builder: (ctx, snap) {
        final allMemos = snap.data ?? [];

        List<MemoEntry> eventsForDay(DateTime day) =>
            allMemos.where((m) => isSameDay(m.createdAt, day)).toList();

        final selectedMemos = eventsForDay(_selectedDay)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return Scaffold(
          backgroundColor: const Color(0xFFF2F4F6),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 1,
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _prevMonth,
                  tooltip: '上月',
                ),
                Text(
                  '${_focusedDay.year}年 ${_focusedDay.month}月',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _nextMonth,
                  tooltip: '下月',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => setState(() {
                  _focusedDay = DateTime.now();
                  _selectedDay = DateTime.now();
                }),
                child: const Text('今日', style: TextStyle(color: Color(0xFF4CAF50))),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () {},
                tooltip: '分享月历',
              ),
            ],
          ),
          body: Column(
            children: [
              // ── 日历主体 ──────────────────────────────────────
              Container(
                color: Colors.white,
                child: TableCalendar<MemoEntry>(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  eventLoader: eventsForDay,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  headerVisible: false,
                  rowHeight: 58,
                  calendarStyle: const CalendarStyle(
                    outsideDaysVisible: false,
                    markerSize: 0,
                  ),
                  calendarBuilders: CalendarBuilders(
                    // ── 中文星期行 ──
                    dowBuilder: (ctx, day) {
                      const labels = ['一', '二', '三', '四', '五', '六', '日'];
                      final isWeekend = day.weekday >= 6;
                      return Center(
                        child: Text(
                          labels[day.weekday - 1],
                          style: TextStyle(
                            fontSize: 13,
                            color: isWeekend ? Colors.red[300] : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                    defaultBuilder: (ctx, day, _) => _DayCell(
                      day: day,
                      lunarLabel: _lunarLabel(day),
                      hasEvents: eventsForDay(day).isNotEmpty,
                    ),
                    selectedBuilder: (ctx, day, _) => _DayCell(
                      day: day,
                      lunarLabel: _lunarLabel(day),
                      hasEvents: eventsForDay(day).isNotEmpty,
                      isSelected: true,
                    ),
                    todayBuilder: (ctx, day, _) => _DayCell(
                      day: day,
                      lunarLabel: _lunarLabel(day),
                      hasEvents: eventsForDay(day).isNotEmpty,
                      isToday: true,
                    ),
                  ),
                  onDaySelected: (selected, focused) => setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  }),
                  onPageChanged: (focused) =>
                      setState(() => _focusedDay = focused),
                ),
              ),

              const Divider(height: 1, thickness: 1),

              // ── 选中日期的日记列表 ──────────────────────────
              Expanded(
                child: !snap.hasData
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF4CAF50)),
                      )
                    : selectedMemos.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_calendar_outlined,
                                    size: 48, color: Colors.grey[300]),
                                const SizedBox(height: 12),
                                Text(
                                  '这天没有记录',
                                  style: TextStyle(
                                      color: Colors.grey[400], fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(12, 12, 12, 96),
                            itemCount: selectedMemos.length,
                            itemBuilder: (ctx, i) => MemoTimelineCard(
                              memo: selectedMemos[i],
                              isLast: i == selectedMemos.length - 1,
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 日历单元格
class _DayCell extends StatelessWidget {
  final DateTime day;
  final String lunarLabel;
  final bool hasEvents;
  final bool isSelected;
  final bool isToday;

  const _DayCell({
    required this.day,
    required this.lunarLabel,
    required this.hasEvents,
    this.isSelected = false,
    this.isToday = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color dayColor;
    Color lunarColor;

    if (isSelected) {
      bg = const Color(0xFF4CAF50);
      dayColor = Colors.white;
      lunarColor = Colors.white70;
    } else if (isToday) {
      bg = const Color(0xFFE8F5E9);
      dayColor = const Color(0xFF2E7D32);
      lunarColor = const Color(0xFF4CAF50);
    } else if (hasEvents) {
      bg = const Color(0xFFF1F8E9);
      dayColor = Colors.black87;
      lunarColor = Colors.grey[500]!;
    } else {
      bg = Colors.transparent;
      dayColor = Colors.black87;
      lunarColor = Colors.grey[400]!;
    }

    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: isToday && !isSelected
            ? Border.all(color: const Color(0xFF4CAF50), width: 1.5)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 15,
              fontWeight:
                  isSelected || isToday ? FontWeight.bold : FontWeight.normal,
              color: dayColor,
            ),
          ),
          if (lunarLabel.isNotEmpty)
            Text(lunarLabel,
                style: TextStyle(fontSize: 9, color: lunarColor)),
          if (hasEvents && !isSelected) ...[
            const SizedBox(height: 2),
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
