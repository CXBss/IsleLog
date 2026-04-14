import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/calendar/calendar_view.dart';
import '../../features/home/home_view.dart';
import '../../features/memo_editor/memo_editor_page.dart';
import '../../features/on_this_day/on_this_day_page.dart';
import '../../features/todo/todo_view.dart';
import '../constants/app_constants.dart';

/// 带底部导航栏和居中 FAB 的主骨架
///
/// 4 个 Tab：待办 | 主页 | [FAB] | 日历 | 往年今日
/// 底部使用 [BottomAppBar] + [FloatingActionButton] 组合，FAB 居中嵌入导航栏缺口。
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  /// 当前选中 Tab 索引
  /// 0=待办  1=主页  2=日历  3=往年今日
  /// FAB 仅在主页(1)和日历(2)时显示
  int _currentIndex = 1; // 默认打开主页

  /// 日历视图当前选中的日期（FAB 新建时使用）
  DateTime _calendarSelectedDay = DateTime.now();

  /// 移动端平台判断（Android / iOS 需处理系统导航条 inset）
  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// FAB 仅在主页（1）和日历（2）时显示
  bool get _showFab => _currentIndex == 1 || _currentIndex == 2;

  /// 打开新建日记编辑器
  void _openEditor() {
    final initialDate = _currentIndex == 2 ? _calendarSelectedDay : null;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoEditorPage(initialDate: initialDate),
      ),
    );
  }

  Widget _buildNavRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _NavItem(
          icon: Icons.check_box_outline_blank,
          activeIcon: Icons.check_box,
          label: AppStrings.navTodo,
          selected: _currentIndex == 0,
          onTap: () => setState(() => _currentIndex = 0),
        ),
        _NavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
          label: AppStrings.navHome,
          selected: _currentIndex == 1,
          onTap: () => setState(() => _currentIndex = 1),
        ),
        // FAB 占位
        const SizedBox(width: AppDimens.fabPlaceholder),
        _NavItem(
          icon: Icons.calendar_month_outlined,
          activeIcon: Icons.calendar_month,
          label: AppStrings.navCalendar,
          selected: _currentIndex == 2,
          onTap: () => setState(() => _currentIndex = 2),
        ),
        _NavItem(
          icon: Icons.history_edu_outlined,
          activeIcon: Icons.history_edu,
          label: AppStrings.navOnThisDay,
          selected: _currentIndex == 3,
          onTap: () => setState(() => _currentIndex = 3),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack 保持各 Tab 页面状态，切换时不销毁
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const TodoView(),
          const HomeView(),
          CalendarView(
            onSelectedDayChanged: (day) {
              _calendarSelectedDay = day;
            },
          ),
          const OnThisDayPage(),
        ],
      ),

      // 居中嵌入式 FAB（仅主页/日历显示）
      floatingActionButton: _showFab
          ? FloatingActionButton(
              heroTag: 'fab_main_new_memo',
              onPressed: _openEditor,
              backgroundColor: AppColors.primary,
              elevation: 4,
              shape: const CircleBorder(),
              tooltip: '新建日记',
              child: const Icon(Icons.add, size: 28, color: Colors.white),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // 底部导航栏（带缺口容纳 FAB）
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        elevation: 8,
        height: 48,
        padding: EdgeInsets.zero,
        child: _isMobile
            ? SafeArea(
                top: false,
                child: SizedBox(
                  height: AppDimens.bottomBarHeight,
                  child: _buildNavRow(),
                ),
              )
            : SizedBox(
                height: AppDimens.bottomBarHeight,
                child: _buildNavRow(),
              ),
      ),
    );
  }
}

/// 底部导航栏单个条目
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : Colors.grey[500]!;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
