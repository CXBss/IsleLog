import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/services/ai/markdown_protection.dart';

void main() {
  group('MarkdownProtection.validate', () {
    test('标签、链接或待办变化时拒绝应用', () {
      const original = '记录 #工作\n\n- [ ] 提交 [文档](https://example.com)';
      const revised = '记录 #生活\n\n- [x] 提交 [文档](https://evil.example)';
      final result = MarkdownProtection.validate(original, revised);
      expect(result.isValid, isFalse);
      expect(result.message, contains('受保护'));
    });

    test('普通措辞和空白变化允许', () {
      const original = '今天天气不错，适合散步。';
      const revised = '今天天气不错，  很适合散步！';
      final result = MarkdownProtection.validate(original, revised);
      expect(result.isValid, isTrue);
    });

    test('日期变化拒绝', () {
      const original = '完成于 2026-07-31';
      const revised = '完成于 2026-08-01';
      final result = MarkdownProtection.validate(original, revised);
      expect(result.isValid, isFalse);
    });

    test('数值变化拒绝', () {
      const original = '共花费 128 元';
      const revised = '共花费 129 元';
      final result = MarkdownProtection.validate(original, revised);
      expect(result.isValid, isFalse);
    });

    test('围栏代码变化拒绝', () {
      const original = '代码：\n```dart\nfinal x = 1;\n```\n结束';
      const revised = '代码：\n```dart\nfinal x = 2;\n```\n结束';
      final result = MarkdownProtection.validate(original, revised);
      expect(result.isValid, isFalse);
    });

    test('链接 URL 变化拒绝', () {
      const original = '参考 [文档](https://example.com)';
      const revised = '参考 [文档](https://evil.example)';
      final result = MarkdownProtection.validate(original, revised);
      expect(result.isValid, isFalse);
    });

    test('有序列表序号变化允许', () {
      const original = '1. 第一项\n2. 第二项';
      const revised = '1. 第一项\n1. 第二项';
      final result = MarkdownProtection.validate(original, revised);
      expect(result.isValid, isTrue);
    });
  });

  group('MarkdownProtection.splitParagraphs', () {
    test('保留空行分隔符', () {
      final paragraphs = MarkdownProtection.splitParagraphs('第一段。\n\n第二段。');
      expect(paragraphs, hasLength(2));
      expect(paragraphs[0].text, '第一段。');
      expect(paragraphs[0].separator, '\n\n');
      expect(paragraphs[1].text, '第二段。');
      expect(paragraphs[1].separator, '');
    });

    test('跳过围栏代码内部的空行', () {
      const text = '开头\n\n```\ncode\n\nstill code\n```\n\n结尾';
      final paragraphs = MarkdownProtection.splitParagraphs(text);
      expect(paragraphs, hasLength(3));
      expect(paragraphs[0].text, '开头');
      expect(paragraphs[1].text, '```\ncode\n\nstill code\n```');
      expect(paragraphs[2].text, '结尾');
    });

    test('空原文返回一个空段落', () {
      final paragraphs = MarkdownProtection.splitParagraphs('');
      expect(paragraphs, hasLength(1));
      expect(paragraphs.single.text, '');
    });
  });
}
