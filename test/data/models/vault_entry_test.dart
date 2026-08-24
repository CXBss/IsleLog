import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/vault_entry.dart';

void main() {
  test('VaultEntry 序列化后能还原全部字段', () {
    final entry = VaultEntry(
      id: 'abc-123',
      content: '今天...',
      createdAt: DateTime.utc(2026, 8, 24, 10, 30),
      updatedAt: DateTime.utc(2026, 8, 24, 11, 0),
      tags: ['心情', '私密'],
      attachmentIds: ['att-1', 'att-2'],
      memosName: 'memos/999',
      movedFromMemosName: 'memos/42',
    );

    final restored = VaultEntry.fromJson(entry.toJson());

    expect(restored.id, entry.id);
    expect(restored.content, entry.content);
    expect(restored.createdAt, entry.createdAt);
    expect(restored.updatedAt, entry.updatedAt);
    expect(restored.tags, entry.tags);
    expect(restored.attachmentIds, entry.attachmentIds);
    expect(restored.memosName, entry.memosName);
    expect(restored.movedFromMemosName, entry.movedFromMemosName);
  });

  test('memosName 和 movedFromMemosName 允许为 null 并正确还原', () {
    final entry = VaultEntry(
      id: 'abc-124',
      content: 'x',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      tags: const [],
      attachmentIds: const [],
    );

    final restored = VaultEntry.fromJson(entry.toJson());

    expect(restored.memosName, isNull);
    expect(restored.movedFromMemosName, isNull);
  });

  test('VaultBody 序列化后还原版本号、revision 和条目', () {
    final body = VaultBody(
      version: 1,
      revision: 17,
      entries: [
        VaultEntry(
          id: 'e1',
          content: 'x',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          tags: const [],
          attachmentIds: const [],
        ),
      ],
    );

    final restored = VaultBody.fromJson(body.toJson());

    expect(restored.version, 1);
    expect(restored.revision, 17);
    expect(restored.entries.single.id, 'e1');
  });

  test('VaultBody.fromJson 对缺失字段取默认值，不抛异常', () {
    final restored = VaultBody.fromJson(<String, dynamic>{});

    expect(restored.version, 1);
    expect(restored.revision, 0);
    expect(restored.entries, isEmpty);
  });
}
