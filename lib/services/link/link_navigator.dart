import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../data/database/database_service.dart';
import '../../features/articles/article_editor_page.dart';
import '../../features/memo_detail/memo_detail_page.dart';
import 'link_resolver.dart';
import 'memo_link.dart';

/// 点击正文里的链接之后的落地处理。
///
/// 内链走本地查库 + 页面跳转，其它 URL 交给系统浏览器。
class LinkNavigator {
  LinkNavigator._();

  static Future<void> openHref(BuildContext context, String? href) async {
    if (href == null || href.isEmpty) return;

    final ref = MemoLink.parse(href);

    // await 之前先取出，避免跨异步边界用 context。
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (ref == null) {
      // 普通外链。用 launchUrlString 而非 Uri，理由同 location_service：
      // 绕过 Uri 对汉字的自动 percent-encode。
      //
      // 这里用 try/catch 而不是 canLaunchUrlString 前置判断：Android 11+ 的
      // 包可见性限制会让 canLaunch 对实际能打开的链接也返回 false，前置判断会误杀。
      try {
        final ok = await launchUrlString(
          href,
          mode: LaunchMode.externalApplication,
        );
        // iOS/macOS 插件失败时是返回 false 而不是抛异常，只 catch 会漏掉它们。
        if (!ok) _toast(messenger, '无法打开链接');
      } catch (_) {
        _toast(messenger, '无法打开链接');
      }
      return;
    }

    switch (ref.kind) {
      case LinkKind.memo:
        await _openMemo(navigator, messenger, ref);
      case LinkKind.article:
        await _openArticle(navigator, messenger, ref);
    }
  }

  static Future<void> _openMemo(
    NavigatorState navigator,
    ScaffoldMessengerState messenger,
    MemoLinkRef ref,
  ) async {
    final byName = ref.remoteName == null
        ? null
        : await DatabaseService.getMemoByMemosName(ref.remoteName!);
    final byId = ref.localId == null
        ? null
        : await DatabaseService.getMemoById(ref.localId!);

    final action = decideLinkAction(
      ref: ref,
      byRemoteName: byName == null
          ? null
          : LinkedEntitySnapshot(
              remoteName: byName.memosName,
              isDeleted: byName.isDeleted,
            ),
      byLocalId: byId == null
          ? null
          : LinkedEntitySnapshot(
              remoteName: byId.memosName,
              isDeleted: byId.isDeleted,
            ),
    );

    switch (action) {
      case LinkAction.openByRemoteName:
        await navigator.push(
          MaterialPageRoute(builder: (_) => MemoDetailPage(memo: byName!)),
        );
      case LinkAction.openByLocalId:
        await navigator.push(
          MaterialPageRoute(builder: (_) => MemoDetailPage(memo: byId!)),
        );
      case LinkAction.notSynced:
        _toast(messenger, '这条日记还没同步到本设备');
      case LinkAction.missing:
        _toast(messenger, '链接的条目已不存在或已被删除');
    }
  }

  static Future<void> _openArticle(
    NavigatorState navigator,
    ScaffoldMessengerState messenger,
    MemoLinkRef ref,
  ) async {
    final byName = ref.remoteName == null
        ? null
        : await DatabaseService.getArticleByArticleName(ref.remoteName!);
    final byId = ref.localId == null
        ? null
        : await DatabaseService.getArticleById(ref.localId!);

    final action = decideLinkAction(
      ref: ref,
      byRemoteName: byName == null
          ? null
          : LinkedEntitySnapshot(
              remoteName: byName.articleName,
              isDeleted: byName.isDeleted,
            ),
      byLocalId: byId == null
          ? null
          : LinkedEntitySnapshot(
              remoteName: byId.articleName,
              isDeleted: byId.isDeleted,
            ),
    );

    switch (action) {
      case LinkAction.openByRemoteName:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) =>
                ArticleEditorPage(editingArticle: byName!, openInPreview: true),
          ),
        );
      case LinkAction.openByLocalId:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) =>
                ArticleEditorPage(editingArticle: byId!, openInPreview: true),
          ),
        );
      case LinkAction.notSynced:
        _toast(messenger, '这篇文章还没同步到本设备');
      case LinkAction.missing:
        _toast(messenger, '链接的条目已不存在或已被删除');
    }
  }

  static void _toast(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
