import 'dart:typed_data';

import '../../data/models/attachment_info.dart';

/// 视频封面：首帧图片字节 + 总时长，任一项取不到就是 null。
///
/// 刻意不含 media_kit 类型——UI 层只依赖这个纯数据结构，取帧实现
/// （[VideoThumbnailService]）才碰播放器。
class VideoThumbnail {
  /// JPEG 字节；截帧失败为 null，此时卡片回落成视频图标。
  final Uint8List? frame;

  final Duration? duration;

  const VideoThumbnail({this.frame, this.duration});
}

/// 取封面的方式。生产实现是 [VideoThumbnailService.load]。
typedef VideoThumbnailLoader =
    Future<VideoThumbnail> Function(AttachmentInfo attachment);
