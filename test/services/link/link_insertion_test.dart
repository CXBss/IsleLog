import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/link/link_insertion.dart';

void main() {
  test('在光标处插入，光标落到插入内容之后', () {
    final result = insertAtCursor(text: '前后', cursor: 1, insert: '中');

    expect(result.text, '前中后');
    expect(result.cursor, 2);
  });

  test('光标在开头', () {
    final result = insertAtCursor(text: 'abc', cursor: 0, insert: 'X');

    expect(result.text, 'Xabc');
    expect(result.cursor, 1);
  });

  test('光标在末尾', () {
    final result = insertAtCursor(text: 'abc', cursor: 3, insert: 'X');

    expect(result.text, 'abcX');
    expect(result.cursor, 4);
  });

  test('光标无效（-1）时追加到末尾', () {
    final result = insertAtCursor(text: 'abc', cursor: -1, insert: 'X');

    expect(result.text, 'abcX');
    expect(result.cursor, 4);
  });

  test('光标越界时追加到末尾', () {
    final result = insertAtCursor(text: 'abc', cursor: 99, insert: 'X');

    expect(result.text, 'abcX');
    expect(result.cursor, 4);
  });

  test('空正文', () {
    final result = insertAtCursor(text: '', cursor: 0, insert: 'X');

    expect(result.text, 'X');
    expect(result.cursor, 1);
  });

  test('不额外补空格', () {
    final result = insertAtCursor(
      text: '跟那天一样',
      cursor: 1,
      insert: '[03-12 暴雨](islelog://memo?lid=1)',
    );

    expect(result.text, '跟[03-12 暴雨](islelog://memo?lid=1)那天一样');
  });
}
