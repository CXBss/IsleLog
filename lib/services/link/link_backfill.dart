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

/// 判断一条待推送条目的正文是否可以安全回写。
///
/// 只有**从未同步过**的条目才安全：它的正文一定是在本机写的，里面的 lid 也就一定
/// 指向本机的条目。已同步条目的正文可能是从别台设备拉来的，其中的 lid 属于那台
/// 设备的 id 空间，在本机解析会命中一条同号但毫不相干的条目。
bool canBackfillLinks({required String? remoteName}) => remoteName == null;

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

/// 把待推送列表排序，使「正文里带光杆链接的条目」排在它引用的条目之后。
///
/// 这样被引用者先拿到远端名，引用方推送时才补得上。与既有的
/// 「文件夹先于文章」「事件串最后推送」是同一个套路。
///
/// 只考虑同批次内、同类型的依赖：目标不在本批次（已同步或不存在）不构成依赖。
/// 成环时把剩余条目按原序输出，不死循环——受影响的链接下次编辑该条目时再补。
List<T> sortForLinkBackfill<T>(
  List<T> pending, {
  required LinkKind kind,
  required int Function(T) localIdOf,
  required String Function(T) contentOf,
}) {
  if (pending.length < 2) return List<T>.of(pending);

  final idsInBatch = pending.map(localIdOf).toSet();
  final deps = <int, Set<int>>{};
  for (final item in pending) {
    final self = localIdOf(item);
    deps[self] = bareLinkTargets(contentOf(item), kind)
        // 自引用不构成依赖，否则它永远等不到自己
        .where((id) => id != self && idsInBatch.contains(id))
        .toSet();
  }

  final sorted = <T>[];
  final emitted = <int>{};
  final remaining = List<T>.of(pending);

  while (remaining.isNotEmpty) {
    final ready = remaining
        .where((item) => deps[localIdOf(item)]!.every(emitted.contains))
        .toList();
    if (ready.isEmpty) {
      // 成环：剩下的按原序输出，保证函数一定终止
      sorted.addAll(remaining);
      break;
    }
    for (final item in ready) {
      sorted.add(item);
      emitted.add(localIdOf(item));
    }
    remaining.removeWhere((item) => emitted.contains(localIdOf(item)));
  }

  return sorted;
}
