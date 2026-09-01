import 'dart:io';

import '../../data/models/attachment_info.dart';

/// 视频附件的播放源。
///
/// 取源规则与 [AudioPlayerWidget] 一致：本地文件在就用本地，否则走远端流。
/// 抽出来是因为卡片首帧和全屏播放页都要解析同一个附件，逻辑不该抄两遍。
sealed class VideoPlaybackSource {
  const VideoPlaybackSource();
}

/// 本地文件，播放器直接按路径打开。
class LocalVideoSource extends VideoPlaybackSource {
  final String path;

  const LocalVideoSource(this.path);
}

/// 远端流。[headers] 携带 Bearer token——自建服务端的附件接口要求鉴权。
class RemoteVideoSource extends VideoPlaybackSource {
  final String url;
  final Map<String, String> headers;

  const RemoteVideoSource(this.url, {this.headers = const {}});
}

/// 解析 [attachment] 的可播放源，无本地文件也无远端地址时返回 null。
VideoPlaybackSource? resolveVideoSource(
  AttachmentInfo attachment, {
  required String baseUrl,
  String? token,
}) {
  final localPath = attachment.localPath;
  // 字段非空不等于文件还在：上传后会被置 null，也可能被系统清理临时目录。
  if (localPath != null && File(localPath).existsSync()) {
    return LocalVideoSource(localPath);
  }

  final url = attachment.fullUrl(baseUrl);
  if (url == null || url.isEmpty) return null;

  return RemoteVideoSource(
    url,
    headers: token != null ? {'Authorization': 'Bearer $token'} : const {},
  );
}
