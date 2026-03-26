import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/calendar/calendar_view.dart';
import '../../features/home/home_view.dart';
import '../../features/memo_editor/memo_editor_page.dart';
import '../constants/app_constants.dart';

/// 带底部导航栏和居中 FAB 的主骨架
///
/// 包含两个 Tab 页：主页（时间线）和日历。
/// 底部使用 [BottomAppBar] + [FloatingActionButton] 组合，FAB 居中嵌入导航栏缺口。
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  /// 当前选中 Tab 索引（0=主页，1=日历）
  int _currentIndex = 0;

  /// 日历视图当前选中的日期（FAB 新建时使用）
  DateTime _calendarSelectedDay = DateTime.now();

  /// 移动端平台判断（Android / iOS 需处理系统导航条 inset）
  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// 打开新建日记编辑器
  void _openEditor() {
    final initialDate = _currentIndex == 1 ? _calendarSelectedDay : null;
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
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
          label: AppStrings.navHome,
          selected: _currentIndex == 0,
          onTap: () {
            debugPrint('[MainScaffold] 切换到主页 Tab');
            setState(() => _currentIndex = 0);
          },
        ),
        // FAB 占位：避免两侧 NavItem 被压缩
        const SizedBox(width: AppDimens.fabPlaceholder),
        _NavItem(
          icon: Icons.calendar_month_outlined,
          activeIcon: Icons.calendar_month,
          label: AppStrings.navCalendar,
          selected: _currentIndex == 1,
          onTap: () {
            debugPrint('[MainScaffold] 切换到日历 Tab');
            setState(() => _currentIndex = 1);
          },
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
          const HomeView(),
          CalendarView(
            onSelectedDayChanged: (day) {
              _calendarSelectedDay = day;
            },
          ),
        ],
      ),

      // 居中嵌入式 FAB（绿色加号）
      floatingActionButton: FloatingActionButton(
        onPressed: _openEditor,
        backgroundColor: AppColors.primary,
        elevation: 4,
        shape: const CircleBorder(),
        tooltip: '新建日记',
        child: const Icon(Icons.add, size: 28, color: AppColors.surfaceWhite),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // 底部导航栏（带缺口容纳 FAB）
      // 移动端：padding:0 + SafeArea 处理系统导航条；桌面端：默认 padding
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
///
/// 选中时显示 [activeIcon] 和品牌绿色，未选中时显示 [icon] 和灰色。
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
    // 选中时使用品牌色，未选中时使用灰色
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
