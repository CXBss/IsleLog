import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 隐私空间编辑器是从主库编辑器整份复制再改造而来的。
///
/// 这组测试把「不落盘、不写主库、不推服务器」这条边界钉在源码层面：
/// 一旦有人（包括从主库同步新功能时）把这些调用带回来，测试立刻失败。
///
/// 只检查源码而不检查运行时行为，是因为这些出口分散在 2000+ 行的
/// 多条分支里，靠 widget test 覆盖不全；而「源码里根本没有这个符号」
/// 是个更强也更容易验证的保证。
void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/features/vault/vault_editor_page.dart',
    ).readAsStringSync();
  });

  /// 去掉注释后再匹配，避免文档里提到的名字造成误报。
  String stripComments(String code) => code
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  void expectAbsent(String symbol, String why) {
    expect(
      stripComments(source).contains(symbol),
      isFalse,
      reason: '隐私空间编辑器不得调用 $symbol：$why',
    );
  }

  group('明文落盘出口', () {
    test('不写 SharedPreferences 草稿', () {
      expectAbsent('SettingsService.saveDraft', '会把正文明文写进 SharedPreferences');
      expectAbsent('SettingsService.clearDraft', '草稿路径整体不该存在');
    });

    test('不经 AttachmentService 存取附件', () {
      expectAbsent('AttachmentService', '它会把附件明文写进应用目录，并在联网时上传到服务器');
    });
  });

  group('明文写库/出网出口', () {
    test('不写主库 Isar', () {
      expectAbsent('DatabaseService.saveMemo', 'vault 条目必须加密后写 idx.bin，不能进主库');
    });

    test('不触发主库同步推送', () {
      expectAbsent('SyncService', 'vault 有自己的加密推送通道');
    });

    test('不写编辑基线快照', () {
      expectAbsent(
        'captureEditBaseline',
        '它把正文快照存进 MemoEntry.originalContent，属于主库明文字段',
      );
    });
  });

  group('已移除的主库专有功能', () {
    test('不含事件串', () {
      expectAbsent('_pickThreads', 'vault 条目没有主库 id，无法参与事件串');
      expectAbsent('ThreadPickerSheet', '同上');
    });

    test('不含版本历史', () {
      expectAbsent('RevisionHistoryPage', 'vault 条目没有 memosName');
    });
  });

  group('刻意保留的能力', () {
    // 这些经核实不会留下明文痕迹：AI 走自建服务端且两端都只记字符数不记正文，
    // 天气/地理只发坐标。保留它们是为了让编辑体验与普通空间一致。
    test('保留 AI 辅助', () {
      expect(source.contains('AiService'), isTrue);
    });

    test('保留位置与天气', () {
      expect(source.contains('LocationService'), isTrue);
      expect(source.contains('WeatherService'), isTrue);
    });
  });

  group('AI 只走本地模型', () {
    // 全局模型可能是云端模型；隐私空间的内容绝不能随全局设置被送上云。
    test('每个 AI 请求都带 vault 标记', () {
      final code = stripComments(source);
      final calls = RegExp(
        r'gateway\.(suggestTags|polish)\(',
      ).allMatches(code).length;
      final marked = RegExp(r'vault: true').allMatches(code).length;
      expect(calls, greaterThan(0));
      expect(
        marked,
        greaterThanOrEqualTo(calls),
        reason: '隐私空间的每个 AI 请求都必须带 vault: true，服务端据此只用本地模型',
      );
    });

    test('不出现云端模型与逐次授权', () {
      expectAbsent('AiProvider.deepSeek', '隐私空间不允许选择云端模型');
      expectAbsent('cloudConsent', '隐私空间不存在云端授权');
    });
  });
}
