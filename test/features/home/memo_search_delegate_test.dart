import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/home/home_view.dart';

void main() {
  // Android 上 enableSuggestions/autocorrect 为 false 会给输入框打上
  // TYPE_TEXT_FLAG_NO_SUGGESTIONS，中文输入法据此退化成英文/密码式键盘，
  // 搜索框根本打不出中文。
  testWidgets('搜索框保持系统默认键盘（不禁用联想与自动更正）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () =>
                  showSearch(context: ctx, delegate: MemoSearchDelegate()),
              child: const Text('搜索'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enableSuggestions, isTrue);
    expect(field.autocorrect, isTrue);
  });
}
