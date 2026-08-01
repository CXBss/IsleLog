import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/features/memo_editor/ai/polish_result_controller.dart';
import 'package:isle_log/services/ai/ai_models.dart';

void main() {
  group('PolishResultController', () {
    test('只组合用户接受的润色片段', () {
      const original = '第一段。\n\n第二段。';
      final controller = PolishResultController(original, const [
        AiPolishSegment(
          sourceIndexes: [0],
          originalText: '第一段。',
          revisedText: '第一段已润色。',
          reason: '通顺',
        ),
        AiPolishSegment(
          sourceIndexes: [1],
          originalText: '第二段。',
          revisedText: '第二段已润色。',
          reason: '简洁',
        ),
      ]);
      expect(controller.buildText(), original);
      controller.setAccepted(0, true);
      expect(controller.buildText(), '第一段已润色。\n\n第二段。');
    });

    test('全部拒绝时逐字返回原文', () {
      const original = '第一段。\n\n第二段。';
      final controller = PolishResultController(original, const [
        AiPolishSegment(
          sourceIndexes: [0],
          originalText: '第一段。',
          revisedText: '第一段已润色。',
          reason: '通顺',
        ),
        AiPolishSegment(
          sourceIndexes: [1],
          originalText: '第二段。',
          revisedText: '第二段已润色。',
          reason: '简洁',
        ),
      ]);
      expect(controller.buildText(), original);
    });

    test('全部接受时返回全部修订', () {
      const original = '第一段。\n\n第二段。';
      final controller = PolishResultController(original, const [
        AiPolishSegment(
          sourceIndexes: [0],
          originalText: '第一段。',
          revisedText: '第一段已润色。',
          reason: '通顺',
        ),
        AiPolishSegment(
          sourceIndexes: [1],
          originalText: '第二段。',
          revisedText: '第二段已润色。',
          reason: '简洁',
        ),
      ]);
      controller.setAccepted(0, true);
      controller.setAccepted(1, true);
      expect(controller.buildText(), '第一段已润色。\n\n第二段已润色。');
    });

    test('跨段片段只替换对应段落', () {
      const original = '一段\n\n二段\n\n三段';
      final controller = PolishResultController(original, const [
        AiPolishSegment(
          sourceIndexes: [0],
          originalText: '一段',
          revisedText: '一段。',
          reason: '通顺',
        ),
        AiPolishSegment(
          sourceIndexes: [1, 2],
          originalText: '二段\n\n三段',
          revisedText: '二三合并。',
          reason: '简洁',
        ),
      ]);
      controller.setAccepted(1, true);
      expect(controller.buildText(), '一段\n\n二三合并。');
    });

    test('修订改变受保护内容时抛 StateError', () {
      const original = '记录 #工作';
      final controller = PolishResultController(original, const [
        AiPolishSegment(
          sourceIndexes: [0],
          originalText: '记录 #工作',
          revisedText: '记录 #生活',
          reason: 'x',
        ),
      ]);
      controller.setAccepted(0, true);
      expect(controller.buildText, throwsStateError);
    });

    test('构造时校验来源索引不完整', () {
      expect(
        () => PolishResultController('一段\n\n二段', const [
          AiPolishSegment(
            sourceIndexes: [1],
            originalText: '二段',
            revisedText: '二段。',
            reason: '通顺',
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('构造时校验来源索引越界', () {
      expect(
        () => PolishResultController('一段', const [
          AiPolishSegment(
            sourceIndexes: [5],
            originalText: '一段',
            revisedText: '一段。',
            reason: '通顺',
          ),
        ]),
        throwsArgumentError,
      );
    });
  });
}
