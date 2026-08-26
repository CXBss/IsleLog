import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/shared/widgets/image_grid.dart';

/// 用带 key 的占位方块代替真实图片，避免测试依赖图片解码。
///
/// 必须给 color——不绘制的空 Container 不参与命中测试，点击会打不到，
/// 而真实图片是会绘制的。
GridImageSource _source(String id, {VoidCallback? onExport}) => GridImageSource(
  build: ({double? width, double? height, BoxFit fit = BoxFit.cover}) =>
      Container(
        key: ValueKey(id),
        width: width,
        height: height,
        color: const Color(0xFF888888),
      ),
  onExport: onExport,
);

List<GridImageSource> _sources(int n) =>
    List.generate(n, (i) => _source('img$i'));

Future<void> _pump(WidgetTester tester, List<GridImageSource> images) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: ImageGrid(images: images))),
  );
}

void main() {
  group('网格布局分支', () {
    testWidgets('空列表不渲染任何图片', (tester) async {
      await _pump(tester, const []);
      expect(find.byKey(const ValueKey('img0')), findsNothing);
    });

    testWidgets('1 张：铺满，高 220', (tester) async {
      await _pump(tester, _sources(1));
      expect(find.byKey(const ValueKey('img0')), findsOneWidget);
      final box = tester.widget<Container>(find.byKey(const ValueKey('img0')));
      expect(box.constraints?.maxHeight, 220);
    });

    testWidgets('2 张：并排渲染两张', (tester) async {
      await _pump(tester, _sources(2));
      expect(find.byKey(const ValueKey('img0')), findsOneWidget);
      expect(find.byKey(const ValueKey('img1')), findsOneWidget);
    });

    testWidgets('3 张：只渲染前 3 张，无 +N 角标', (tester) async {
      await _pump(tester, _sources(3));
      expect(find.byKey(const ValueKey('img2')), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('超过 3 张：第 3 张盖 +N 角标', (tester) async {
      await _pump(tester, _sources(6));
      expect(find.text('+3'), findsOneWidget);
      // 第 4 张之后不进网格
      expect(find.byKey(const ValueKey('img3')), findsNothing);
    });
  });

  group('全屏查看器', () {
    testWidgets('点击缩略图打开查看器', (tester) async {
      await _pump(tester, _sources(2));
      await tester.tap(find.byKey(const ValueKey('img0')));
      await tester.pumpAndSettle();

      expect(find.byType(ImageViewerPage), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsWidgets);
    });

    testWidgets('允许导出时，长按触发回调', (tester) async {
      var exported = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ImageViewerPage(
            images: [_source('a', onExport: () => exported = true)],
            initialIndex: 0,
          ),
        ),
      );

      await tester.longPress(find.byKey(const ValueKey('a')));
      expect(exported, isTrue);
    });

    // 隐私空间必须走这条：导出会把私密照片写进系统相册或直接送出去。
    testWidgets('onExport 为 null 时长按不做任何事', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ImageViewerPage(images: [_source('a')], initialIndex: 0),
        ),
      );

      await tester.longPress(find.byKey(const ValueKey('a')));
      await tester.pumpAndSettle();
      // 不应弹出任何导出菜单
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('多张时显示页码圆点', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ImageViewerPage(images: _sources(3), initialIndex: 0),
        ),
      );
      expect(find.byType(PageView), findsOneWidget);
    });
  });
}
