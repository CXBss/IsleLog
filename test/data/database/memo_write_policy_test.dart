import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/database/memo_write_policy.dart';
import 'package:isle_log/data/models/attachment_info.dart';
import 'package:isle_log/data/models/memo_entry.dart';

void main() {
  test('preserves stored remote identity when a stale memo saves null', () {
    final stored = MemoEntry()
      ..id = 1
      ..memosName = 'memos/42';
    final incoming = MemoEntry()
      ..id = 1
      ..memosName = null;

    preserveRemoteIdentity(incoming, stored);

    expect(incoming.memosName, 'memos/42');
  });

  group('mergePreparedMemoForPush', () {
    test('stores uploaded attachment data for the current revision', () {
      final revision = DateTime(2026, 6, 8, 12);
      final prepared = MemoEntry()
        ..content = '![photo](/file/resources/7/photo.jpg)'
        ..updatedAt = revision
        ..attachments = [
          const AttachmentInfo(
            localId: 'photo-1',
            filename: 'photo.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 100,
            remoteResName: 'resources/7',
          ),
        ];
      final latest = MemoEntry()
        ..content = '![photo](file:///tmp/photo.jpg)'
        ..updatedAt = revision;

      final merged = mergePreparedMemoForPush(latest, prepared);

      expect(merged, isTrue);
      expect(latest.content, prepared.content);
      expect(latest.attachments.single.remoteResName, 'resources/7');
    });

    test('does not overwrite a newer local edit', () {
      final prepared = MemoEntry()
        ..content = 'A'
        ..updatedAt = DateTime(2026, 6, 8, 12);
      final latest = MemoEntry()
        ..content = 'AB'
        ..updatedAt = DateTime(2026, 6, 8, 12, 1);

      final merged = mergePreparedMemoForPush(latest, prepared);

      expect(merged, isFalse);
      expect(latest.content, 'AB');
    });
  });

  group('reconcileMemoPushSuccess', () {
    test('marks the latest memo synced when it did not change during push', () {
      final revision = DateTime(2026, 6, 8, 12);
      final submitted = MemoEntry()
        ..id = 1
        ..content = 'A'
        ..updatedAt = revision
        ..syncStatus = SyncStatus.pending;
      final latest = MemoEntry()
        ..id = 1
        ..content = 'A'
        ..updatedAt = revision
        ..syncStatus = SyncStatus.pending
        ..originalContent = 'old';
      final syncedAt = DateTime(2026, 6, 8, 12, 1);

      reconcileMemoPushSuccess(
        latest: latest,
        submitted: submitted,
        remoteName: 'memos/42',
        syncedAt: syncedAt,
      );

      expect(latest.memosName, 'memos/42');
      expect(latest.syncStatus, SyncStatus.synced);
      expect(latest.lastSyncAt, syncedAt);
      expect(latest.originalContent, isNull);
    });

    test('moodWeatherSynced 跟随本次推送的实际结果翻转', () {
      final revision = DateTime(2026, 6, 8, 12);
      MemoEntry make() => MemoEntry()
        ..id = 1
        ..content = 'A'
        ..updatedAt = revision
        ..syncStatus = SyncStatus.pending;

      // 推了真实心情 → 置为 true
      final setValue = make()..moodWeatherSynced = false;
      reconcileMemoPushSuccess(
        latest: setValue,
        submitted: make(),
        moodWeatherSynced: true,
      );
      expect(setValue.moodWeatherSynced, isTrue);

      // 推的是清空 → 置回 false
      final cleared = make()..moodWeatherSynced = true;
      reconcileMemoPushSuccess(
        latest: cleared,
        submitted: make(),
        moodWeatherSynced: false,
      );
      expect(cleared.moodWeatherSynced, isFalse);

      // 不传该参数 → 保持原值不动
      final untouched = make()..moodWeatherSynced = true;
      reconcileMemoPushSuccess(latest: untouched, submitted: make());
      expect(untouched.moodWeatherSynced, isTrue);
    });

    test(
      'stores uploaded attachment data when the local revision is unchanged',
      () {
        final revision = DateTime(2026, 6, 8, 12);
        final submitted = MemoEntry()
          ..id = 1
          ..content = 'A\n![photo](/file/resources/7/photo.jpg)'
          ..updatedAt = revision
          ..attachments = [
            const AttachmentInfo(
              localId: 'photo-1',
              filename: 'photo.jpg',
              mimeType: 'image/jpeg',
              sizeBytes: 100,
              remoteResName: 'resources/7',
              remoteUrl: '/file/resources/7/photo.jpg',
            ),
          ];
        final latest = MemoEntry()
          ..id = 1
          ..content = 'A\n![photo](file:///tmp/photo.jpg)'
          ..updatedAt = revision
          ..syncStatus = SyncStatus.pending
          ..attachments = [
            const AttachmentInfo(
              localId: 'photo-1',
              filename: 'photo.jpg',
              mimeType: 'image/jpeg',
              sizeBytes: 100,
              localPath: '/tmp/photo.jpg',
            ),
          ];

        reconcileMemoPushSuccess(
          latest: latest,
          submitted: submitted,
          remoteName: 'memos/42',
        );

        expect(latest.content, submitted.content);
        expect(latest.attachments.single.remoteResName, 'resources/7');
        expect(latest.syncStatus, SyncStatus.synced);
      },
    );

    test(
      'keeps a newer text edit pending and attaches the created remote id',
      () {
        final submitted = MemoEntry()
          ..id = 1
          ..content = 'A'
          ..updatedAt = DateTime(2026, 6, 8, 12)
          ..syncStatus = SyncStatus.pending;
        final latest = MemoEntry()
          ..id = 1
          ..content = 'AB'
          ..updatedAt = DateTime(2026, 6, 8, 12, 1)
          ..syncStatus = SyncStatus.pending;

        reconcileMemoPushSuccess(
          latest: latest,
          submitted: submitted,
          remoteName: 'memos/42',
        );

        expect(latest.memosName, 'memos/42');
        expect(latest.content, 'AB');
        expect(latest.syncStatus, SyncStatus.pending);
        expect(latest.originalContent, 'A');
      },
    );

    test('keeps an attachment added while push was in flight', () {
      final submitted = MemoEntry()
        ..id = 1
        ..content = 'A'
        ..updatedAt = DateTime(2026, 6, 8, 12)
        ..syncStatus = SyncStatus.pending;
      final latest = MemoEntry()
        ..id = 1
        ..content = 'A\n![photo](file:///tmp/photo.jpg)'
        ..updatedAt = DateTime(2026, 6, 8, 12, 1)
        ..syncStatus = SyncStatus.pending
        ..attachments = [
          const AttachmentInfo(
            localId: 'photo-1',
            filename: 'photo.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 100,
            localPath: '/tmp/photo.jpg',
          ),
        ];

      reconcileMemoPushSuccess(
        latest: latest,
        submitted: submitted,
        remoteName: 'memos/42',
      );

      expect(latest.memosName, 'memos/42');
      expect(latest.attachments.single.localId, 'photo-1');
      expect(latest.syncStatus, SyncStatus.pending);
      expect(latest.originalContent, 'A');
    });
  });
}
