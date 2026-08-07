import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/home/widgets/memo_search_card.dart';

void main() {
  test('长文本展示首次命中附近的上下文', () {
    final text = '${'前置内容' * 60}目标关键词${'后置内容' * 60}';

    final excerpt = buildSearchExcerpt(text, '目标关键词');

    expect(excerpt, contains('目标关键词'));
    expect(excerpt, startsWith('…'));
    expect(excerpt, endsWith('…'));
    expect(excerpt.length, lessThanOrEqualTo(222));
  });

  test('短文本保持完整显示', () {
    const text = '这是一篇包含目标关键词的短日记。';

    expect(buildSearchExcerpt(text, '目标关键词'), text);
  });

  test('无关键词时从正文开头截取', () {
    final text = '内容' * 150;

    final excerpt = buildSearchExcerpt(text, '不存在');

    expect(excerpt, startsWith('内容'));
    expect(excerpt, endsWith('…'));
  });
}
