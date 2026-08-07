import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/services/sync/pending_memo_conflict_policy.dart';

void main() {
  group('decidePendingMemo', () {
    test('pushes local edit when remote still matches edit baseline', () {
      final local = MemoEntry()
        ..content = 'second edit'
        ..originalContent = 'first edit'
        ..syncStatus = SyncStatus.pending;

      final decision = decidePendingMemo(
        local,
        _remoteMemo(content: 'first edit'),
        archived: false,
      );

      expect(decision, PendingMemoDecision.pushLocal);
    });

    test('reports conflict when remote changed from edit baseline', () {
      final local = MemoEntry()
        ..content = 'local edit'
        ..originalContent = 'shared baseline'
        ..syncStatus = SyncStatus.pending;

      final decision = decidePendingMemo(
        local,
        _remoteMemo(content: 'remote edit'),
        archived: false,
      );

      expect(decision, PendingMemoDecision.conflict);
    });

    test('recognizes retry when remote already equals local edit', () {
      final local = MemoEntry()
        ..content = 'local edit'
        ..originalContent = 'shared baseline'
        ..syncStatus = SyncStatus.pending;

      final decision = decidePendingMemo(
        local,
        _remoteMemo(content: 'local edit'),
        archived: false,
      );

      expect(decision, PendingMemoDecision.alreadySynced);
    });

    test('stays conservative when no edit baseline is available', () {
      final local = MemoEntry()
        ..content = 'local edit'
        ..syncStatus = SyncStatus.pending;

      final decision = decidePendingMemo(
        local,
        _remoteMemo(content: 'remote content'),
        archived: false,
      );

      expect(decision, PendingMemoDecision.conflict);
    });
  });

  test('markMemoSynced clears edit and conflict snapshots', () {
    final memo = MemoEntry()
      ..syncStatus = SyncStatus.conflict
      ..originalContent = 'edit baseline'
      ..conflictRemoteContent = 'remote edit';
    final syncedAt = DateTime(2026, 6, 8, 12);

    markMemoSynced(memo, syncedAt: syncedAt);

    expect(memo.syncStatus, SyncStatus.synced);
    expect(memo.lastSyncAt, syncedAt);
    expect(memo.originalContent, isNull);
    expect(memo.conflictRemoteContent, isNull);
  });

  group('captureEditBaseline', () {
    test('captures current content when no unsynced baseline exists', () {
      final memo = MemoEntry()..content = 'remote baseline';

      captureEditBaseline(memo);

      expect(memo.originalContent, 'remote baseline');
    });

    test('preserves existing baseline across consecutive local edits', () {
      final memo = MemoEntry()
        ..content = 'first local edit'
        ..originalContent = 'remote baseline';

      captureEditBaseline(memo);

      expect(memo.originalContent, 'remote baseline');
    });
  });
}

Map<String, dynamic> _remoteMemo({required String content}) {
  return {
    'content': content,
    'pinned': false,
    'attachments': <Map<String, dynamic>>[],
  };
}
