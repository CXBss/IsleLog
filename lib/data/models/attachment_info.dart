import 'dart:convert';

/// 附件信息（不是 Isar collection，序列化为 JSON 字符串存入 MemoEntry.attachmentsJson）
class AttachmentInfo {
  /// 本地唯一标识（UUID），生命周期内不变
  final String localId;

  /// 远端资源名，如 "resources/123"；未上传时为 null
  final String? remoteResName;

  /// 本地文件绝对路径；远端上传成功后置 null
  final String? localPath;

  /// 远端访问 URL；未上传时为 null
  final String? remoteUrl;

  /// 原始文件名，如 "photo.jpg"
  final String filename;

  /// MIME 类型，如 "image/jpeg"、"audio/mpeg"
  final String mimeType;

  /// 文件大小（字节）
  final int sizeBytes;

  /// 离线附件上传失败标记（不中断整体同步流程）
  final bool uploadFailed;

  const AttachmentInfo({
    required this.localId,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    this.remoteResName,
    this.localPath,
    this.remoteUrl,
    this.uploadFailed = false,
  });

  // ── 类型判断 ──────────────────────────────────────────────────

  bool get isImage => mimeType.startsWith('image/');
  bool get isAudio => mimeType.startsWith('audio/');

  /// 附件在正文中的 Markdown 引用（图片用 ![]()，其他用 []()）
  String get markdownLink {
    final url = remoteUrl ?? (localPath != null ? 'file://$localPath' : '');
    return isImage ? '![$filename]($url)' : '[$filename]($url)';
  }

  // ── 序列化 ────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'localId': localId,
        if (remoteResName != null) 'remoteResName': remoteResName,
        if (localPath != null) 'localPath': localPath,
        if (remoteUrl != null) 'remoteUrl': remoteUrl,
        'filename': filename,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        if (uploadFailed) 'uploadFailed': uploadFailed,
      };

  factory AttachmentInfo.fromJson(Map<String, dynamic> j) => AttachmentInfo(
        localId: j['localId'] as String,
        remoteResName: j['remoteResName'] as String?,
        localPath: j['localPath'] as String?,
        remoteUrl: j['remoteUrl'] as String?,
        filename: j['filename'] as String,
        mimeType: j['mimeType'] as String,
        sizeBytes: j['sizeBytes'] as int,
        uploadFailed: j['uploadFailed'] as bool? ?? false,
      );

  String toJsonString() => jsonEncode(toJson());

  static AttachmentInfo fromJsonString(String s) =>
      AttachmentInfo.fromJson(jsonDecode(s) as Map<String, dynamic>);

  /// 用 [clearLocalPath]/[clearRemoteResName] 显式传 true 可将对应字段置 null
  AttachmentInfo copyWith({
    String? remoteResName,
    String? localPath,
    String? remoteUrl,
    bool? uploadFailed,
    bool clearLocalPath = false,
    bool clearRemoteResName = false,
  }) =>
      AttachmentInfo(
        localId: localId,
        filename: filename,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        remoteResName: clearRemoteResName ? null : (remoteResName ?? this.remoteResName),
        localPath: clearLocalPath ? null : (localPath ?? this.localPath),
        remoteUrl: remoteUrl ?? this.remoteUrl,
        uploadFailed: uploadFailed ?? this.uploadFailed,
      );
}
