import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/database/thread_membership_policy.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/data/models/thread_entry.dart';

ThreadEntry _local(SyncStatus status, DateTime updatedAt) =>
    ThreadEntry()
      ..syncStatus = status
      ..updatedAt = updatedAt;

void main() {
  group('decideThreadPull', () {
    final remote = DateTime(2026, 8, 2);

    test('本地不存在时新增', () {
      expect(
        decideThreadPull(local: null, remoteUpdatedAt: remote),
        ThreadPullAction.insert,
      );
    });

    test('本地已同步时覆盖为远端版本', () {
      expect(
        decideThreadPull(
          local: _local(SyncStatus.synced, DateTime(2026, 8, 1)),
          remoteUpdatedAt: remote,
        ),
        ThreadPullAction.overwrite,
      );
    });

    test('本地已同步且远端更旧时仍以远端为准', () {
      // synced 表示本地无未推送改动，远端即真相，时间先后不影响判定
      expect(
        decideThreadPull(
          local: _local(SyncStatus.synced, DateTime(2026, 8, 3)),
          remoteUpdatedAt: remote,
        ),
        ThreadPullAction.overwrite,
      );
    });

    test('待同步且远端更新更晚时标记冲突', () {
      expect(
        decideThreadPull(
          local: _local(SyncStatus.pending, DateTime(2026, 8, 1)),
          remoteUpdatedAt: remote,
        ),
        ThreadPullAction.markConflict,
      );
    });

    test('待同步且本地改动更新时跳过，等待推送', () {
      expect(
        decideThreadPull(
          local: _local(SyncStatus.pending, DateTime(2026, 8, 3)),
          remoteUpdatedAt: remote,
        ),
        ThreadPullAction.skip,
      );
    });

    test('时间戳相同的待同步条目不判为冲突', () {
      expect(
        decideThreadPull(
          local: _local(SyncStatus.pending, remote),
          remoteUpdatedAt: remote,
        ),
        ThreadPullAction.skip,
      );
    });

    test('已处于冲突的条目不再被远端覆盖', () {
      expect(
        decideThreadPull(
          local: _local(SyncStatus.conflict, DateTime(2026, 8, 1)),
          remoteUpdatedAt: remote,
        ),
        ThreadPullAction.skip,
      );
    });
  });

  group('toggleThreadMember', () {
    test('加入成员', () {
      expect(toggleThreadMember([1, 2], 3, selected: true), [1, 2, 3]);
    });

    test('移除成员', () {
      expect(toggleThreadMember([1, 2, 3], 2, selected: false), [1, 3]);
    });

    test('重复加入不产生重复项', () {
      expect(toggleThreadMember([1, 2], 2, selected: true), [1, 2]);
    });

    test('移除不存在的成员无副作用', () {
      expect(toggleThreadMember([1, 2], 9, selected: false), [1, 2]);
    });

    test('不修改传入的列表', () {
      final original = [1, 2];
      toggleThreadMember(original, 3, selected: true);
      expect(original, [1, 2]);
    });

    // Isar 反序列化 List<int> 得到的正是 Int64List（定长），
    // 早先的实现直接 add/remove 会抛异常，且在异步回调中被静默吞掉，
    // 表现为勾选框点了没反应。
    test('接受定长的 Int64List 输入而不抛异常', () {
      final fixedLength = Int64List.fromList([1, 2]);

      expect(toggleThreadMember(fixedLength, 3, selected: true), [1, 2, 3]);
      expect(toggleThreadMember(fixedLength, 1, selected: false), [2]);
    });
  });

  group('resolveThreadMemberNames', () {
    test('成员全部已同步时解析完整', () {
      final result = resolveThreadMemberNames(
        [1, 2],
        {1: 'memos/1001', 2: 'memos/1002'},
      );

      expect(result.memoNames, ['memos/1001', 'memos/1002']);
      expect(result.complete, isTrue);
    });

    test('成员尚未推送时保留待推送状态', () {
      final result = resolveThreadMemberNames([1, 2], {1: 'memos/1001', 2: null});

      expect(result.memoNames, ['memos/1001']);
      expect(result.complete, isFalse);
    });

    test('空字符串资源名视为未解析', () {
      final result = resolveThreadMemberNames([1], {1: ''});

      expect(result.memoNames, isEmpty);
      expect(result.complete, isFalse);
    });

    test('本地 id 在映射表中缺失时视为未解析', () {
      final result = resolveThreadMemberNames([1, 99], {1: 'memos/1001'});

      expect(result.memoNames, ['memos/1001']);
      expect(result.complete, isFalse);
    });

    test('空成员列表视为解析完整', () {
      final result = resolveThreadMemberNames([], {});

      expect(result.memoNames, isEmpty);
      expect(result.complete, isTrue);
    });
  });

  group('mapRemoteMembersToLocalIds', () {
    test('已知远端成员映射为本地 id 并保持顺序', () {
      expect(
        mapRemoteMembersToLocalIds(
          ['memos/1001', 'memos/1002'],
          {'memos/1001': 8, 'memos/1002': 3},
        ),
        [8, 3],
      );
    });

    test('本地缺失的成员被丢弃，留待后续同步补齐', () {
      expect(
        mapRemoteMembersToLocalIds(['memos/1', 'memos/2'], {'memos/1': 8}),
        [8],
      );
    });

    test('空列表返回空结果', () {
      expect(mapRemoteMembersToLocalIds([], {'memos/1': 8}), isEmpty);
    });
  });
}
