import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
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
/// [uploadToServer]：压缩（可选原图）后上传到 Memos 服务器，
/// 同时在本地保留备份，返回同时带 remoteUrl + localPath 的 [AttachmentInfo]。
///
/// ## 离线模式
/// [saveLocally]：将文件复制到应用私有目录，返回带 localPath 的 [AttachmentInfo]。
/// 待联网后由 [SyncService] 批量调用 [uploadPendingAttachment] 补传。
class AttachmentService {
  AttachmentService._();

  static const _uuid = Uuid();

  // ── 在线上传 ──────────────────────────────────────────────────

  /// 上传图片到 Memos 服务器
  ///
  /// [file]：原始图片文件
  /// [filename]：展示用文件名
  /// [compress]：true（默认）压缩后上传；false 使用原图
  ///
  /// 无论是否压缩，都会在本地保留一份备份（localPath）。
  /// 返回同时携带 [AttachmentInfo.remoteUrl] 和 [AttachmentInfo.localPath] 的附件信息。
  static Future<AttachmentInfo> uploadToServer(
    File file, {
    String? filename,
    bool compress = true,
  }) async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      throw Exception('服务器未配置，无法上传');
    }

    final fname = filename ?? p.basename(file.path);
    final mime = _guessMime(file.path);

    // ── 1. 先将文件复制/压缩到本地备份目录 ──
    final localPath = await _saveToLocal(file, fname, mime, compress: compress);
    final uploadFile = File(localPath);
    final size = await uploadFile.length();

    // ── 2. 上传到服务器 ──
    debugPrint('[Attachment] 上传文件 $fname (${size}B) mime=$mime compress=$compress');
    final api = MemosApiService(baseUrl: url, token: token);
    final data = await api.uploadAttachment(file: uploadFile, filename: fname);

    final resName = data['name'] as String;
    final externalLink = data['externalLink'] as String? ?? '';
    final remoteUrl = externalLink.isNotEmpty
        ? externalLink
        : '$url/file/$resName/${Uri.encodeComponent(fname)}';

    debugPrint('[Attachment] 上传成功 resName=$resName url=$remoteUrl localPath=$localPath');
    return AttachmentInfo(
      localId: _uuid.v4(),
      filename: fname,
      mimeType: mime,
      sizeBytes: size,
      remoteResName: resName,
      remoteUrl: remoteUrl,
      localPath: localPath, // 保留本地备份
    );
  }

  // ── 离线存储 ──────────────────────────────────────────────────

  /// 将文件保存到应用私有目录（离线模式）
  ///
  /// 图片会压缩后保存（compress=true），其他类型直接复制。
  /// 返回携带 [AttachmentInfo.localPath] 的附件信息（remoteUrl 为 null）。
  static Future<AttachmentInfo> saveLocally(
    File file, {
    String? filename,
    bool compress = true,
  }) async {
    final fname = filename ?? p.basename(file.path);
    final mime = _guessMime(file.path);

    final localPath = await _saveToLocal(file, fname, mime, compress: compress);
    final size = await File(localPath).length();

    debugPrint('[Attachment] 本地存储 $fname → $localPath');
    return AttachmentInfo(
      localId: p.basenameWithoutExtension(localPath), // UUID
      filename: fname,
      mimeType: mime,
      sizeBytes: size,
      localPath: localPath,
    );
  }

  // ── 离线补传 ──────────────────────────────────────────────────

  /// 将离线存储的附件上传到服务器，返回更新后的 [AttachmentInfo]
  ///
  /// 上传成功后保留 localPath（本地备份）。
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

      debugPrint('[Attachment] 离线补传成功 resName=$resName，保留本地备份');
      return attachment.copyWith(
        remoteResName: resName,
        remoteUrl: remoteUrl,
        // localPath 保留，不清除
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

  // ── 内部：保存到本地备份目录 ──────────────────────────────────

  /// 将文件复制或压缩到应用私有 attachments 目录，返回目标路径
  static Future<String> _saveToLocal(
    File file,
    String filename,
    String mime, {
    bool compress = true,
  }) async {
    final id = _uuid.v4();
    final ext = p.extension(filename).toLowerCase();
    final dir = await _attachmentsDir();
    final destPath = p.join(dir.path, '$id$ext');

    if (compress && _isCompressibleImage(mime) && _supportsCompress) {
      // 压缩图片：最长边 1920px，质量 85
      try {
        final result = await FlutterImageCompress.compressAndGetFile(
          file.absolute.path,
          destPath,
          quality: 85,
          minWidth: 1920,
          minHeight: 1920,
          keepExif: false,
        );
        if (result != null) {
          final orig = await file.length();
          final compressed = await File(result.path).length();
          debugPrint('[Attachment] 压缩完成 ${orig}B → ${compressed}B (${(compressed * 100 ~/ orig)}%)');
          return result.path;
        }
      } catch (e) {
        debugPrint('[Attachment] 压缩失败，使用原图：$e');
      }
    }

    await file.copy(destPath);
    return destPath;
  }

  /// 判断 MIME 类型是否支持压缩
  static bool _isCompressibleImage(String mime) =>
      mime == 'image/jpeg' ||
      mime == 'image/jpg' ||
      mime == 'image/png' ||
      mime == 'image/webp' ||
      mime == 'image/heic' ||
      mime == 'image/heif';

  /// flutter_image_compress 仅支持 Android / iOS
  static bool get _supportsCompress =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static Future<Directory> _attachmentsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'attachments'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static String _guessMime(String path) =>
      lookupMimeType(path) ?? 'application/octet-stream';
}
