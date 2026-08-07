import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/attachment_info.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/features/home/memo_list_equality.dart';

void main() {
  test('detects a remote identity change without an updatedAt change', () {
    final updatedAt = DateTime(2026, 6, 8, 12);
    final stale = MemoEntry()
      ..id = 1
      ..updatedAt = updatedAt;
    final refreshed = MemoEntry()
      ..id = 1
      ..updatedAt = updatedAt
      ..memosName = 'memos/42';

    expect(memoListsMatchForDisplay([stale], [refreshed]), isFalse);
  });

  test('detects sync state and attachment changes', () {
    final updatedAt = DateTime(2026, 6, 8, 12);
    final stale = MemoEntry()
      ..id = 1
      ..updatedAt = updatedAt
      ..syncStatus = SyncStatus.pending;
    final refreshed = MemoEntry()
      ..id = 1
      ..updatedAt = updatedAt
      ..syncStatus = SyncStatus.synced
      ..attachments = [
        const AttachmentInfo(
          localId: 'photo-1',
          filename: 'photo.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: 100,
          remoteResName: 'resources/7',
        ),
      ];

    expect(memoListsMatchForDisplay([stale], [refreshed]), isFalse);
  });

  test('matches equivalent memo snapshots', () {
    final createdAt = DateTime(2026, 6, 8, 11);
    final updatedAt = DateTime(2026, 6, 8, 12);
    final first = MemoEntry()
      ..id = 1
      ..memosName = 'memos/42'
      ..content = 'A'
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncStatus = SyncStatus.synced;
    final second = MemoEntry()
      ..id = 1
      ..memosName = 'memos/42'
      ..content = 'A'
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncStatus = SyncStatus.synced;

    expect(memoListsMatchForDisplay([first], [second]), isTrue);
  });
}
