import 'package:flutter/material.dart';

/// GitHub 风格热力图，展示过去 365 天每天的字数
///
/// 7 行（周一→周日）× 53 列，颜色深浅对应当天字数多少。
/// 点击某个格子可触发 [onDayTap] 回调（传入对应日期）。
class HeatmapWidget extends StatelessWidget {
  /// 日期 → 字数映射（只需包含有数据的日期）
  final Map<DateTime, int> dailyWords;

  /// 单格尺寸
  final double cellSize;

  /// 格间距
  final double gap;

  /// 点击某天回调
  final void Function(DateTime date)? onDayTap;

  const HeatmapWidget({
    super.key,
    required this.dailyWords,
    this.cellSize = 12,
    this.gap = 2.5,
    this.onDayTap,
  });

  // 热力图色阶（5 级，从空到深绿）
  static const _colors = [
    Color(0xFFEBEDF0), // 0 字
    Color(0xFFC6E48B), // 少
    Color(0xFF7BC96F), // 中低
    Color(0xFF239A3B), // 中高
    Color(0xFF196127), // 多
  ];

  Color _colorForCount(int words, int maxWords) {
    if (words == 0 || maxWords == 0) return _colors[0];
    final ratio = words / maxWords;
    if (ratio < 0.25) return _colors[1];
    if (ratio < 0.5) return _colors[2];
    if (ratio < 0.75) return _colors[3];
    return _colors[4];
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);

    // 往前数 364 天（含今天共 365 天）
    final startDay = todayNorm.subtract(const Duration(days: 364));

    // 从周一对齐：找到 startDay 所在周的周一
    final weekdayOffset = startDay.weekday - 1; // weekday: 1=Mon ... 7=Sun
    final gridStart = startDay.subtract(Duration(days: weekdayOffset));

    // 总格数 = 从 gridStart 到今天，补满整周
    final totalDays = todayNorm.difference(gridStart).inDays + 1;
    final totalCols = (totalDays / 7).ceil();

    final maxWords =
        dailyWords.values.fold(0, (prev, v) => v > prev ? v : prev);

    // 月份标签：记录每列第一天所在月份变化点
    final monthLabels = <int, String>{};
    for (int col = 0; col < totalCols; col++) {
      final firstDayOfCol = gridStart.add(Duration(days: col * 7));
      if (col == 0 || firstDayOfCol.day <= 7) {
        monthLabels[col] = _monthLabel(firstDayOfCol.month);
      }
    }

    final weekLabels = ['一', '三', '五', '日'];
    final weekLabelRows = [0, 2, 4, 6]; // 对应周一/三/五/日

    final cellStep = cellSize + gap;
    final labelWidth = 14.0;
    final gridWidth = totalCols * cellStep - gap;
    final gridHeight = 7 * cellStep - gap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 月份标签行
        Padding(
          padding: EdgeInsets.only(left: labelWidth + gap),
          child: SizedBox(
            width: gridWidth,
            height: 14,
            child: Stack(
              children: [
                for (final entry in monthLabels.entries)
                  Positioned(
                    left: entry.key * cellStep,
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // 格子区域（左侧星期标签 + 右侧热力格）
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 星期标签
            SizedBox(
              width: labelWidth,
              height: gridHeight,
              child: Stack(
                children: [
                  for (int i = 0; i < weekLabels.length; i++)
                    Positioned(
                      top: weekLabelRows[i] * cellStep,
                      child: Text(
                        weekLabels[i],
                        style: TextStyle(fontSize: 9, color: Colors.grey[400]),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: gap),
            // 热力格
            SizedBox(
              width: gridWidth,
              height: gridHeight,
              child: Stack(
                children: [
                  for (int col = 0; col < totalCols; col++)
                    for (int row = 0; row < 7; row++) _buildCell(
                      context,
                      col: col,
                      row: row,
                      gridStart: gridStart,
                      todayNorm: todayNorm,
                      startDay: startDay,
                      maxWords: maxWords,
                      cellStep: cellStep,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 图例
        Row(
          children: [
            SizedBox(width: labelWidth + gap),
            Text('少', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
            const SizedBox(width: 4),
            for (final c in _colors)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Container(
                  width: cellSize,
                  height: cellSize,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Text('多', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
          ],
        ),
      ],
    );
  }

  Widget _buildCell(
    BuildContext context, {
    required int col,
    required int row,
    required DateTime gridStart,
    required DateTime todayNorm,
    required DateTime startDay,
    required int maxWords,
    required double cellStep,
  }) {
    final date = gridStart.add(Duration(days: col * 7 + row));
    // 超出范围的格子（gridStart 到 startDay 之前，或今天之后）
    final inRange = !date.isBefore(startDay) && !date.isAfter(todayNorm);
    final words = inRange ? (dailyWords[date] ?? 0) : 0;
    final color = inRange ? _colorForCount(words, maxWords) : Colors.transparent;

    return Positioned(
      left: col * cellStep,
      top: row * cellStep,
      child: GestureDetector(
        onTap: inRange && onDayTap != null ? () => onDayTap!(date) : null,
        child: Tooltip(
          message: inRange
              ? '${date.month}/${date.day}  $words 字'
              : '',
          child: Container(
            width: cellSize,
            height: cellSize,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  static String _monthLabel(int month) {
    const labels = [
      '1月', '2月', '3月', '4月', '5月', '6月',
      '7月', '8月', '9月', '10月', '11月', '12月',
    ];
    return labels[month - 1];
  }
}
