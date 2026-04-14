import 'package:flutter/material.dart';

import '../../../shared/constants/app_constants.dart';

/// 通用柱状图，月度/年度统计共用
///
/// [labels]：X 轴标签列表
/// [values]：对应的数值列表（与 labels 等长）
/// [highlightIndex]：高亮柱（当月/当年），为 null 则不高亮
/// [barColor]：普通柱颜色
/// [highlightColor]：高亮柱颜色
class BarChartWidget extends StatelessWidget {
  final List<String> labels;
  final List<int> values;
  final int? highlightIndex;
  final Color barColor;
  final Color highlightColor;
  final double height;

  const BarChartWidget({
    super.key,
    required this.labels,
    required this.values,
    this.highlightIndex,
    this.barColor = AppColors.primary,
    this.highlightColor = AppColors.primaryDark,
    this.height = 160,
  });

  @override
  Widget build(BuildContext context) {
    assert(labels.length == values.length);
    final maxVal = values.fold(0, (prev, v) => v > prev ? v : prev);

    return SizedBox(
      height: height + 32, // 32 = 标签区高度
      child: CustomPaint(
        painter: _BarChartPainter(
          labels: labels,
          values: values,
          maxVal: maxVal,
          highlightIndex: highlightIndex,
          barColor: barColor,
          highlightColor: highlightColor,
          chartHeight: height,
          labelStyle: TextStyle(
            fontSize: labels.length > 12 ? 9 : 10,
            color: Colors.grey[500],
          ),
          valueStyle: const TextStyle(fontSize: 8, color: Colors.grey),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<String> labels;
  final List<int> values;
  final int maxVal;
  final int? highlightIndex;
  final Color barColor;
  final Color highlightColor;
  final double chartHeight;
  final TextStyle labelStyle;
  final TextStyle valueStyle;

  _BarChartPainter({
    required this.labels,
    required this.values,
    required this.maxVal,
    required this.highlightIndex,
    required this.barColor,
    required this.highlightColor,
    required this.chartHeight,
    required this.labelStyle,
    required this.valueStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty) return;

    final count = labels.length;
    final totalWidth = size.width;
    final colWidth = totalWidth / count;
    final barWidth = (colWidth * 0.55).clamp(4.0, 24.0);

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      final val = values[i];
      final barHeight =
          maxVal == 0 ? 0.0 : (val / maxVal) * chartHeight;
      final isHighlight = i == highlightIndex;

      final left = colWidth * i + (colWidth - barWidth) / 2;
      final top = chartHeight - barHeight;

      // 绘制柱体（圆角矩形）
      paint.color = isHighlight ? highlightColor : barColor;
      if (barHeight > 0) {
        final rRect = RRect.fromLTRBR(
          left,
          top,
          left + barWidth,
          chartHeight,
          const Radius.circular(3),
        );
        canvas.drawRRect(rRect, paint);
      }

      // 柱顶数值标签（仅有值时显示）
      if (val > 0) {
        final valLabel = val >= 10000
            ? '${(val / 10000).toStringAsFixed(1)}w'
            : val >= 1000
                ? '${(val / 1000).toStringAsFixed(1)}k'
                : '$val';
        _drawText(
          canvas,
          valLabel,
          valueStyle.copyWith(
            color: isHighlight ? highlightColor : Colors.grey[500],
          ),
          Offset(left + barWidth / 2, top - 2),
          maxWidth: colWidth,
          align: TextAlign.center,
          baseline: true,
        );
      }

      // X 轴标签
      _drawText(
        canvas,
        labels[i],
        labelStyle.copyWith(
          color: isHighlight ? highlightColor : Colors.grey[500],
          fontWeight:
              isHighlight ? FontWeight.w600 : FontWeight.normal,
        ),
        Offset(colWidth * i + colWidth / 2, chartHeight + 4),
        maxWidth: colWidth,
        align: TextAlign.center,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset position, {
    double maxWidth = 40,
    TextAlign align = TextAlign.left,
    bool baseline = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    final dx = position.dx - tp.width / 2;
    final dy = baseline ? position.dy - tp.height : position.dy;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.values != values ||
      old.highlightIndex != highlightIndex ||
      old.maxVal != maxVal;
}
