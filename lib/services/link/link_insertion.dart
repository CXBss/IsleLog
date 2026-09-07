/// 在光标处插入文本的纯计算，供两个编辑器共用。
///
/// 抽出来是为了能单测：编辑器里的 TextEditingController 操作没法直接断言。
library;

/// 一次插入的结果：新正文与新光标位置。
class TextInsertion {
  final String text;
  final int cursor;

  const TextInsertion({required this.text, required this.cursor});
}

/// 在 [cursor] 处插入 [insert]，光标落到插入内容之后。
///
/// [cursor] 无效（负数或越界）时追加到末尾——这与编辑器里
/// `sel.isValid ? sel.baseOffset : text.length` 的既有约定一致。
/// 不做任何空格补齐，与 `_insertAtCursor` 的现有行为保持一致。
TextInsertion insertAtCursor({
  required String text,
  required int cursor,
  required String insert,
}) {
  final pos = (cursor < 0 || cursor > text.length) ? text.length : cursor;
  return TextInsertion(
    text: text.substring(0, pos) + insert + text.substring(pos),
    cursor: pos + insert.length,
  );
}
