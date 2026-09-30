import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/services/agent/agent_models.dart';

AgentChange _change(String op, Map<String, dynamic> payload) =>
    AgentChange.fromJson({
      'name': 'agentChanges/1',
      'seq': 1,
      'op': op,
      'status': 'PROPOSED',
      'payload': payload,
    });

void main() {
  final memos = [
    {'id': 1, 'include': true, 'snippet': 'a'},
    {'id': 2, 'include': false, 'snippet': 'b'},
  ];

  test('第二批写入改动的说明', () {
    expect(
      _change('memo.retag', {
        'from': '大语言模型',
        'to': '大模型',
        'memos': memos,
      }).description,
      '把 1 篇日记里的 #大语言模型 改成 #大模型',
    );
    expect(
      _change('memo.retag', {
        'from': '临时',
        'to': '',
        'memos': memos,
      }).description,
      '去掉 1 篇日记里的 #临时',
    );
    expect(
      _change('memo.set_meta', {'label': '置顶', 'memos': memos}).description,
      '把 1 篇日记置顶',
    );
    expect(
      _change('article.move', {'folder': '旧文', 'memos': memos}).description,
      '把 1 篇文章移到「旧文」',
    );
    expect(
      _change('folder.update', {'current': '草稿', 'title': '草稿箱'}).description,
      '文件夹「草稿」 改名为「草稿箱」',
    );
    expect(
      _change('thread.update', {
        'current': '装修',
        'status': 'RESOLVED',
      }).description,
      '事件串「装修」 标为已结束',
    );
    expect(
      _change('suggestion.review', {
        'decision': 'accept',
        'memos': memos,
      }).description,
      '接受 1 条事件串建议',
    );
  });

  test('会改正文或元数据的改动列出勾选的日记，供应用前检查本机未同步修改', () {
    for (final op in ['memo.retag', 'memo.set_meta', 'memo.add_tags']) {
      expect(_change(op, {'memos': memos}).touchedMemos, [
        'memos/1',
      ], reason: op);
    }
    expect(_change('article.move', {'memos': memos}).touchedMemos, isEmpty);
  });
}
