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

/// 判断 [snap] 是否就是 [ref] 指向的那一条。
///
/// 撞车守卫只在两边都有远端名时才成立：只有那时"对不上"才有意义。
/// 链接没有远端名说明它是在目标同步前创建的，此时 lid 是唯一权威标识。
bool _sameEntity(MemoLinkRef ref, LinkedEntitySnapshot snap) =>
    ref.remoteName == null || snap.remoteName == ref.remoteName;

/// 由两次查库的结果判定该打开谁、或报哪种失效。
///
/// 两段式：先找一个还活着的目标；都没有活的，再看有没有"目标确实被删了"的
/// 证据来决定说哪句话。
///
/// 归档条目照常打开——是用户主动点的，读得到才合理。
/// `missing` 只在**拿到实物且它是软删除**时才成立；其余一切找不到的情况
/// （没拉下来、撞车判否、链接只有 lid 而本机没有）一律 `notSynced`。
/// 把"我找不到"说成"它被删了"会吓到用户，而且多设备下前者常见得多。
LinkAction decideLinkAction({
  required MemoLinkRef ref,
  required LinkedEntitySnapshot? byRemoteName,
  required LinkedEntitySnapshot? byLocalId,
}) {
  // 第一段：任何一个活着的目标都可以打开，远端名优先
  if (byRemoteName != null && !byRemoteName.isDeleted) {
    return LinkAction.openByRemoteName;
  }
  final localIsSame = byLocalId != null && _sameEntity(ref, byLocalId);
  if (localIsSame && !byLocalId.isDeleted) {
    return LinkAction.openByLocalId;
  }

  // 第二段：没有活的，看是否见到了目标本身的"尸体"
  final sawDeletedTarget =
      (byRemoteName?.isDeleted ?? false) || (localIsSame && byLocalId.isDeleted);
  return sawDeletedTarget ? LinkAction.missing : LinkAction.notSynced;
}
