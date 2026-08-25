import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../shared/constants/app_constants.dart';

/// 隐私空间内的月历。
///
/// 与主页日历的区别：数据不查数据库，而是由父页面把已合并好的
/// 「有记录的日号」传进来——vault 条目只存在于内存，没法走 Isar 查询。
class VaultCalendarView extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime? selectedDay;

  /// 当前月份中有记录的日号集合（主库 ∪ vault，已按 scope 过滤）
  final Set<int> daysWithEntries;

  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  const VaultCalendarView({
    super.key,
    required this.focusedMonth,
    required this.selectedDay,
    required this.daysWithEntries,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  bool _hasEntry(DateTime day) =>
      day.year == focusedMonth.year &&
      day.month == focusedMonth.month &&
      daysWithEntries.contains(day.day);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface(context),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TableCalendar<void>(
        firstDay: DateTime(2000),
        lastDay: DateTime(2100),
        focusedDay: focusedMonth,
        currentDay: DateTime.now(),
        selectedDayPredicate: (day) =>
            selectedDay != null && isSameDay(day, selectedDay),
        startingDayOfWeek: StartingDayOfWeek.monday,
        availableGestures: AvailableGestures.horizontalSwipe,
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          todayDecoration: BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          todayTextStyle: const TextStyle(color: AppColors.primaryDark),
          selectedDecoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        ),
        onPageChanged: onMonthChanged,
        onDaySelected: (selected, focused) => onDaySelected(selected),
        calendarBuilders: CalendarBuilders(
          // 有记录的日期在下方点一个小圆点，和主页日历的观感一致
          markerBuilder: (context, day, _) {
            if (!_hasEntry(day)) return null;
            return Positioned(
              bottom: 4,
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
