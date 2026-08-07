import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/features/memo_editor/ai/tag_insertion.dart';

void main() {
  group('insertSelectedTags', () {
    test('只追加不存在的已选标签', () {
      expect(
        insertSelectedTags('今天修复同步 #工作', ['工作', 'IsleLog']),
        '今天修复同步 #工作\n\n#IsleLog',
      );
    });

    test('空正文插入标签且去重', () {
      expect(insertSelectedTags('', ['生活', '生活']), '#生活');
    });

    test('全部已存在时正文不变', () {
      expect(insertSelectedTags('记录 #生活 #工作', ['生活', '工作']), '记录 #生活 #工作');
    });

    test('保留原有尾部空行并追加标签', () {
      expect(insertSelectedTags('今天去爬山\n\n', ['户外']), '今天去爬山\n\n#户外');
    });

    test('多个新标签以空格分隔追加', () {
      expect(insertSelectedTags('正文', ['生活', '户外']), '正文\n\n#生活 #户外');
    });
  });
}
