import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/vault_entry.dart';
import 'package:isle_log/features/vault/widgets/vault_entry_card.dart';

void main() {
  testWidgets('展示 vault 条目的正文摘要和锁标记', (tester) async {
    final entry = VaultEntry(
      id: 'e1',
      content: '这是一条隐私日记',
      createdAt: DateTime(2026, 8, 24, 9, 0),
      updatedAt: DateTime(2026, 8, 24, 9, 0),
      tags: const [],
      attachmentIds: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultEntryCard(entry: entry, onTap: () {}),
        ),
      ),
    );

    expect(find.textContaining('这是一条隐私日记'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });
}
