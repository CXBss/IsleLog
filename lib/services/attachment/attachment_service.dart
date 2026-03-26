import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/attachment_info.dart';
import '../api/memos_api_service.dart';
import '../settings/settings_service.dart';

/// 附件上传与本地存储服务
///
/// ## 在线模式
/// [uploadToServer]：直接上传到 Memos 服务器，返回带 remoteUrl 的 [AttachmentInfo]。
///
/// ## 离线模式
/// [saveLocally]：将文件复制到应用私有目录，返回带 localPath 的 [AttachmentInfo]。
/// 待联网后由 [SyncService] 批量调用 [uploadPendingAttachment] 补传。
class AttachmentService {
  AttachmentService._();

  static const _uuid = Uuid();

  // ── 在线上传 ──────────────────────────────────────────────────

  /// 上传文件到 Memos 服务器
  ///
  /// [file]：本地文件
  /// [filename]：展示用文件名（默认取 file.path 的 basename）
  ///
  /// 返回携带 [AttachmentInfo.remoteUrl] 的附件信息。
  static Future<AttachmentInfo> uploadToServer(
    File file, {
    String? filename,
  }) async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      throw Exception('服务器未配置，无法上传');
    }

    final api = MemosApiService(baseUrl: url, token: token);
    final fname = filename ?? p.basename(file.path);
    final mime = _guessMime(file.path);
    final size = await file.length();

    debugPrint('[Attachment] 上传文件 $fname (${size}B) mime=$mime');
    final data = await api.uploadAttachment(file: file, filename: fname);

    final resName = data['name'] as String; // "attachments/xxx"
    // v0.25 返回 externalLink 作为访问 URL；否则手动拼接并 encode 文件名
    final externalLink = data['externalLink'] as String? ?? '';
    final remoteUrl = externalLink.isNotEmpty
        ? externalLink
        : '$url/file/$resName/${Uri.encodeComponent(fname)}';

    debugPrint('[Attachment] 上传成功 resName=$resName url=$remoteUrl');
    return AttachmentInfo(
      localId: _uuid.v4(),
      filename: fname,
      mimeType: mime,
      sizeBytes: size,
      remoteResName: resName,
      remoteUrl: remoteUrl,
    );
  }

  // ── 离线存储 ──────────────────────────────────────────────────

  /// 将文件复制到应用私有目录（离线模式）
  ///
  /// 文件重命名为 `{uuid}.{ext}` 避免名称冲突。
  /// 返回携带 [AttachmentInfo.localPath] 的附件信息（remoteUrl 为 null）。
  static Future<AttachmentInfo> saveLocally(File file, {String? filename}) async {
    final fname = filename ?? p.basename(file.path);
    final ext = p.extension(file.path);
    final id = _uuid.v4();
    final mime = _guessMime(file.path);
    final size = await file.length();

    final dir = await _attachmentsDir();
    final destPath = p.join(dir.path, '$id$ext');
    await file.copy(destPath);

    debugPrint('[Attachment] 本地存储 $fname → $destPath');
    return AttachmentInfo(
      localId: id,
      filename: fname,
      mimeType: mime,
      sizeBytes: size,
      localPath: destPath,
    );
  }

  // ── 离线补传 ──────────────────────────────────────────────────

  /// 将离线存储的附件上传到服务器，返回更新后的 [AttachmentInfo]
  ///
  /// 若本地文件不存在，标记 uploadFailed=true 并返回，不抛异常。
  static Future<AttachmentInfo> uploadPendingAttachment(
    AttachmentInfo attachment,
    String baseUrl,
    String token,
  ) async {
    if (attachment.localPath == null) return attachment;

    final file = File(attachment.localPath!);
    if (!file.existsSync()) {
      debugPrint('[Attachment] 离线文件不存在，跳过：${attachment.localPath}');
      return attachment.copyWith(uploadFailed: true);
    }

    try {
      final api = MemosApiService(baseUrl: baseUrl, token: token);
      final data = await api.uploadAttachment(
        file: file,
        filename: attachment.filename,
      );
      final resName = data['name'] as String;
      final externalLink = data['externalLink'] as String? ?? '';
      final remoteUrl = externalLink.isNotEmpty
          ? externalLink
          : '$baseUrl/file/$resName/${Uri.encodeComponent(attachment.filename)}';

      debugPrint('[Attachment] 离线补传成功 resName=$resName');
      return attachment.copyWith(
        remoteResName: resName,
        remoteUrl: remoteUrl,
        clearLocalPath: true, // 上传成功后不再需要本地副本引用
      );
    } catch (e) {
      debugPrint('[Attachment] 离线补传失败：$e');
      return attachment.copyWith(uploadFailed: true);
    }
  }

  // ── 删除远端资源 ──────────────────────────────────────────────

  /// 删除远端 Memos 资源（静默失败）
  static Future<void> deleteRemote(String resName) async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || token == null) return;

    try {
      final api = MemosApiService(baseUrl: url, token: token);
      await api.deleteAttachment(resName);
      debugPrint('[Attachment] 远端附件已删除：$resName');
    } catch (e) {
      debugPrint('[Attachment] 远端资源删除失败（静默）：$e');
    }
  }

  /// 删除本地缓存文件（静默失败）
  static Future<void> deleteLocal(String localPath) async {
    try {
      final file = File(localPath);
      if (file.existsSync()) await file.delete();
      debugPrint('[Attachment] 本地文件已删除：$localPath');
    } catch (e) {
      debugPrint('[Attachment] 本地文件删除失败（静默）：$e');
    }
  }

  // ── 工具方法 ──────────────────────────────────────────────────

  static Future<Directory> _attachmentsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'attachments'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static String _guessMime(String path) =>
      lookupMimeType(path) ?? 'application/octet-stream';
}
