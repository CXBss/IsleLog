import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/link/link_resolver.dart';
import 'package:isle_log/services/link/memo_link.dart';

const _synced = MemoLinkRef(
  kind: LinkKind.memo,
  remoteName: 'memos/123',
  localId: 45,
);
const _unsynced = MemoLinkRef(kind: LinkKind.memo, localId: 45);

void main() {
  test('按远端名查到就打开它', () {
    expect(
      decideLinkAction(
        ref: _synced,
        byRemoteName: const LinkedEntitySnapshot(remoteName: 'memos/123'),
        byLocalId: null,
      ),
      LinkAction.openByRemoteName,
    );
  });

  test('远端名查不到时用本地 id 兜底', () {
    expect(
      decideLinkAction(
        ref: _synced,
        byRemoteName: null,
        byLocalId: const LinkedEntitySnapshot(remoteName: 'memos/123'),
      ),
      LinkAction.openByLocalId,
    );
  });

  test('本地 id 命中的条目还没同步过，视为同一条', () {
    expect(
      decideLinkAction(
        ref: _unsynced,
        byRemoteName: null,
        byLocalId: const LinkedEntitySnapshot(remoteName: null),
      ),
      LinkAction.openByLocalId,
    );
  });

  test('本地 id 撞到了远端名不一致的条目，判定为失效', () {
    // 换设备后 Isar 自增 id 会撞车，没有这一步会跳到完全无关的日记
    expect(
      decideLinkAction(
        ref: _synced,
        byRemoteName: null,
        byLocalId: const LinkedEntitySnapshot(remoteName: 'memos/999'),
      ),
      LinkAction.missing,
    );
  });

  test('远端名命中但条目已软删除，判定为失效', () {
    expect(
      decideLinkAction(
        ref: _synced,
        byRemoteName: const LinkedEntitySnapshot(
          remoteName: 'memos/123',
          isDeleted: true,
        ),
        byLocalId: null,
      ),
      LinkAction.missing,
    );
  });

  test('本地 id 命中但条目已软删除，判定为失效', () {
    expect(
      decideLinkAction(
        ref: _unsynced,
        byRemoteName: null,
        byLocalId: const LinkedEntitySnapshot(
          remoteName: null,
          isDeleted: true,
        ),
      ),
      LinkAction.missing,
    );
  });

  test('链接没有远端名且本地也查不到，说明目标没同步到本设备', () {
    expect(
      decideLinkAction(ref: _unsynced, byRemoteName: null, byLocalId: null),
      LinkAction.notSynced,
    );
  });

  test('链接有远端名但两边都查不到，说明条目已不存在', () {
    expect(
      decideLinkAction(ref: _synced, byRemoteName: null, byLocalId: null),
      LinkAction.missing,
    );
  });

  test('链接无远端名、目标此后已同步，仍按 lid 打开', () {
    // spec 第 3 节：离线创建内链（仅有 lid），目标后来同步获得 remoteName，
    // 但 lid 兜底仍然在本机有效，不应判为失效。
    expect(
      decideLinkAction(
        ref: _unsynced,
        byRemoteName: null,
        byLocalId: const LinkedEntitySnapshot(remoteName: 'memos/500'),
      ),
      LinkAction.openByLocalId,
    );
  });

  test('本地 id 命中但已软删除、且链接有远端名，同样判失效', () {
    expect(
      decideLinkAction(
        ref: _synced,
        byRemoteName: null,
        byLocalId: const LinkedEntitySnapshot(
          remoteName: 'memos/123',
          isDeleted: true,
        ),
      ),
      LinkAction.missing,
    );
  });

  test('远端名命中的那条已删除、而 lid 命中的那条存活时，以存活的为准', () {
    // 底层数据不一致时的兜底行为：同一远端名同时存在一条已删和一条存活。
    expect(
      decideLinkAction(
        ref: _synced,
        byRemoteName: const LinkedEntitySnapshot(
          remoteName: 'memos/123',
          isDeleted: true,
        ),
        byLocalId: const LinkedEntitySnapshot(remoteName: 'memos/123'),
      ),
      LinkAction.openByLocalId,
    );
  });
}
