import '../../data/models/attachment_info.dart';

/// 附件按渲染方式分好的四组，顺序与原列表一致。
class GroupedAttachments {
  final List<AttachmentInfo> images;
  final List<AttachmentInfo> audios;
  final List<AttachmentInfo> videos;

  /// 其余附件，渲染成文件 Chip。
  final List<AttachmentInfo> files;

  const GroupedAttachments({
    required this.images,
    required this.audios,
    required this.videos,
    required this.files,
  });
}

/// 把 [attachments] 分组。
///
/// [videoPlayback] 为 false（没有 media_kit 库的平台）时视频归入 [files]，
/// 走系统播放器打开——分不出组就等于附件从界面上消失了。
GroupedAttachments groupAttachments(
  List<AttachmentInfo> attachments, {
  required bool videoPlayback,
}) {
  final images = <AttachmentInfo>[];
  final audios = <AttachmentInfo>[];
  final videos = <AttachmentInfo>[];
  final files = <AttachmentInfo>[];

  for (final a in attachments) {
    if (a.isImage) {
      images.add(a);
    } else if (a.isAudio) {
      audios.add(a);
    } else if (a.isVideo && videoPlayback) {
      videos.add(a);
    } else {
      files.add(a);
    }
  }

  return GroupedAttachments(
    images: images,
    audios: audios,
    videos: videos,
    files: files,
  );
}
