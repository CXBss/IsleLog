import 'memo_link.dart';

/// 查库结果里跳转判定需要用到的那两个字段。
///
/// 用快照而不是直接吃 MemoEntry / ArticleEntry，是为了让判定逻辑保持纯粹、
/// 同时服务日记和文章两种实体。
class LinkedEntitySnapshot {
  final String? remoteName;
  final bool isDeleted;

  const LinkedEntitySnapshot({this.remoteName, this.isDeleted = false});
}

/// 点击一条内链之后该做什么。
enum LinkAction {
  /// 打开按远端名查到的那条
  openByRemoteName,

  /// 打开按本地 id 查到的那条
  openByLocalId,

  /// 目标从未同步到本设备
  notSynced,

  /// 目标已不存在或已被删除
  missing,
}

/// 由两次查库的结果判定该打开谁、或报哪种失效。
///
/// 归档条目照常打开——是用户主动点的，读得到才合理；软删除则按失效处理。
LinkAction decideLinkAction({
  required MemoLinkRef ref,
  required LinkedEntitySnapshot? byRemoteName,
  required LinkedEntitySnapshot? byLocalId,
}) {
  // 优先用远端名查到的结果
  if (byRemoteName != null && !byRemoteName.isDeleted) {
    return LinkAction.openByRemoteName;
  }

  // 次选是本地 id
  if (byLocalId != null) {
    if (byLocalId.isDeleted) {
      // 找到了但已删除，说明目标已不存在
      return LinkAction.missing;
    }

    // 本地 id 在别的设备上指向完全不同的条目。若命中的条目自己有远端名、
    // 却和链接里的对不上，说明这不是同一条。
    final sameEntity =
        byLocalId.remoteName == null || byLocalId.remoteName == ref.remoteName;
    if (sameEntity) return LinkAction.openByLocalId;

    // 本地 id 撞车，它指向了另一条条目
    return LinkAction.missing;
  }

  // 两边都没查到：区分是"从未同步"还是"已不存在"
  // 链接本身就没有远端名，说明目标当初就没同步过，换设备自然找不到。
  if (ref.remoteName == null) return LinkAction.notSynced;

  return LinkAction.missing;
}
