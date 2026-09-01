import 'package:flutter/material.dart';

import '../../data/models/attachment_info.dart';
import '../../services/attachment/video_thumbnail.dart';
import '../../services/attachment/video_thumbnail_service.dart';
import '../utils/media_duration.dart';

/// 视频封面：首帧 + 播放角标（可选时长），铺满父容器。
///
/// 只画一张图，不持有播放器——时间线上可能同时出现多个视频，
/// 真正的解码留给全屏播放页。
class VideoThumbnailView extends StatefulWidget {
  final AttachmentInfo attachment;

  final VideoThumbnailLoader loader;

  /// 播放角标直径。编辑器里的 64px 缩略图要调小。
  final double badgeSize;

  final bool showDuration;

  const VideoThumbnailView({
    super.key,
    required this.attachment,
    this.loader = VideoThumbnailService.load,
    this.badgeSize = 44,
    this.showDuration = true,
  });

  @override
  State<VideoThumbnailView> createState() => _VideoThumbnailViewState();
}

class _VideoThumbnailViewState extends State<VideoThumbnailView> {
  VideoThumbnail? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VideoThumbnailView old) {
    super.didUpdateWidget(old);
    if (old.attachment.localId != widget.attachment.localId) {
      _thumb = null;
      _load();
    }
  }

  Future<void> _load() async {
    final localId = widget.attachment.localId;
    VideoThumbnail result;
    try {
      result = await widget.loader(widget.attachment);
    } catch (e) {
      // 取帧失败只影响封面，卡片照样能点开播放。
      debugPrint('[VideoThumb] 取封面失败：$e');
      result = const VideoThumbnail();
    }
    if (!mounted || widget.attachment.localId != localId) return;
    setState(() => _thumb = result);
  }

  @override
  Widget build(BuildContext context) {
    final duration = _thumb?.duration;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildCover(),
        Center(child: _PlayBadge(size: widget.badgeSize)),
        if (duration != null && widget.showDuration)
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                formatMediaDuration(duration),
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCover() {
    final frame = _thumb?.frame;
    if (frame != null) {
      return Image.memory(
        frame,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallbackCover(),
      );
    }
    // 加载中与取帧失败共用同一块底：没有闪烁，也不会出现空白方块。
    return _thumb == null
        ? const ColoredBox(color: Color(0xFF1F1F1F))
        : _fallbackCover();
  }

  Widget _fallbackCover() => ColoredBox(
    color: const Color(0xFF1F1F1F),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.movie_outlined, size: 28, color: Colors.white38),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            widget.attachment.filename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ),
      ],
    ),
  );
}

/// 视频附件卡片：16:9 封面，点击交给 [onTap]（通常是打开全屏播放页）。
class VideoAttachmentCard extends StatelessWidget {
  final AttachmentInfo attachment;

  final VoidCallback onTap;

  final VideoThumbnailLoader loader;

  const VideoAttachmentCard({
    super.key,
    required this.attachment,
    required this.onTap,
    this.loader = VideoThumbnailService.load,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: VideoThumbnailView(attachment: attachment, loader: loader),
          ),
        ),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  final double size;

  const _PlayBadge({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: Colors.black45,
      shape: BoxShape.circle,
    ),
    child: Icon(Icons.play_arrow, size: size * 0.64, color: Colors.white),
  );
}
