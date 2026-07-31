import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/main.dart';

void main() {
  testWidgets('应用启动后展示主界面', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byTooltip('新建日记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
