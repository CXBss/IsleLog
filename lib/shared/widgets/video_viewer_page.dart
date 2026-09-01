import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/models/attachment_info.dart';
import '../../services/attachment/video_source_resolver.dart';
import '../../services/attachment/video_thumbnail_service.dart';
import '../../services/settings/settings_service.dart';

/// 全屏视频播放页。
///
/// 播放器只在这里创建——列表和详情页只放封面卡片，避免多个解码器同时存在。
class VideoViewerPage extends StatefulWidget {
  final AttachmentInfo attachment;

  const VideoViewerPage({super.key, required this.attachment});

  /// 打开播放页。淡入过渡，与图片查看器保持一致。
  static Future<void> open(BuildContext context, AttachmentInfo attachment) {
    return Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => VideoViewerPage(attachment: attachment),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<VideoViewerPage> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final baseUrl = await SettingsService.serverUrl ?? '';
      final token = await SettingsService.accessToken;
      final source = resolveVideoSource(
        widget.attachment,
        baseUrl: baseUrl,
        token: token,
      );
      if (source == null) {
        if (mounted) setState(() => _error = '找不到可播放的视频文件');
        return;
      }
      await _player.open(mediaForVideoSource(source));
    } catch (e) {
      debugPrint('[VideoViewer] 播放失败：$e');
      if (mounted) setState(() => _error = '无法播放：$e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.videocam_off_outlined,
                          color: Colors.white54,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  )
                : Video(controller: _controller, fit: BoxFit.contain),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
