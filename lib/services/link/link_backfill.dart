import 'memo_link.dart';

/// 查询某个本地 id 对应实体的远端资源名；查不到返回 null。
typedef RemoteNameLookup = String? Function(LinkKind kind, int localId);

/// 匹配 markdown 链接目标位置上的内链 URI。
///
/// 必须锚定在 `]( ` 与 `)` 之间：正文里别处出现的同名串（尤其是链接的**显示文字**里
/// 粘进来的地址）不能被改写，否则会动到用户看得见的文字。
final RegExp _linkUri = RegExp(r'(?<=\]\()islelog://[^\s)]+(?=\s*\))');


/// 找出正文里所有「只有本地 id、缺远端名」的 [kind] 类目标的本地 id。
///
/// 供推送排序判断依赖关系用。
Set<int> bareLinkTargets(String content, LinkKind kind) {
  final ids = <int>{};
  for (final match in _linkUri.allMatches(content)) {
    final ref = MemoLink.parse(match.group(0)!);
    if (ref == null) continue;
    if (ref.kind != kind) continue;
    if (ref.remoteName != null) continue;
    final lid = ref.localId;
    if (lid != null) ids.add(lid);
  }
  return ids;
}

/// 把正文里缺远端名的内链补全。
///
/// 只改 URI，不碰链接的显示文字。只补「缺远端名且有 lid」的链接，因此天然幂等——
/// 补完的链接下次不再匹配。查不到远端名就原样保留，等目标同步后的下一次推送再补。
String backfillLinks(String content, RemoteNameLookup lookup) {
  if (!content.contains('${MemoLink.scheme}://')) return content;

  return content.replaceAllMapped(_linkUri, (match) {
    final href = match.group(0)!;
    final ref = MemoLink.parse(href);
    // 不是合法内链（未知 host、两个标识都缺）→ 原样
    if (ref == null) return href;
    // 已经有远端名 → 原样
    if (ref.remoteName != null) return href;

    final lid = ref.localId;
    if (lid == null) return href;

    final remoteName = lookup(ref.kind, lid);
    if (remoteName == null || remoteName.isEmpty) return href;

    return MemoLink.build(
      kind: ref.kind,
      remoteName: remoteName,
      localId: lid,
    );
  });
}
