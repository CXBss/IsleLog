import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../data/models/attachment_info.dart';
import '../../../services/attachment/audio_manager.dart';
import '../../../services/settings/settings_service.dart';
import '../../../shared/constants/app_constants.dart';

/// 音频附件播放控件
///
/// 自管理 [AudioPlayer] 生命周期，通过 [AudioManager] 确保全局唯一播放。
/// 支持本地文件（file://）和远端 HTTP URL。
class AudioPlayerWidget extends StatefulWidget {
  final AttachmentInfo attachment;

  const AudioPlayerWidget({super.key, required this.attachment});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late final AudioPlayer _player;
  bool _loading = true;
  bool _error = false;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final localPath = widget.attachment.localPath;
      final baseUrl = await SettingsService.serverUrl ?? '';
      final url = widget.attachment.fullUrl(baseUrl);

      if (url != null && url.isNotEmpty) {
        await _player.setUrl(url);
      } else if (localPath != null) {
        await _player.setFilePath(localPath);
      } else {
        setState(() => _error = true);
        return;
      }
      if (mounted) {
        setState(() {
          _duration = _player.duration ?? Duration.zero;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[AudioPlayer] 初始化失败：$e');
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  @override
  void dispose() {
    AudioManager.release(_player);
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await AudioManager.requestPlay(_player);
      await _player.play();
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return _buildErrorTile();
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryLighter,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 音乐图标
          Icon(Icons.music_note, size: 18, color: AppColors.primaryDark),
          const SizedBox(width: 6),

          // 文件名 + 进度条
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.attachment.filename,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                _loading
                    ? const LinearProgressIndicator(
                        minHeight: 2, color: AppColors.primary)
                    : StreamBuilder<Duration>(
                        stream: _player.positionStream,
                        builder: (ctx, snap) {
                          final pos = snap.data ?? Duration.zero;
                          final total = _duration.inMilliseconds > 0
                              ? _duration.inMilliseconds.toDouble()
                              : 1.0;
                          return SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12),
                              activeTrackColor: AppColors.primary,
                              inactiveTrackColor: AppColors.timelineBar,
                              thumbColor: AppColors.primary,
                            ),
                            child: Slider(
                              value: pos.inMilliseconds
                                  .toDouble()
                                  .clamp(0, total),
                              min: 0,
                              max: total,
                              onChanged: (v) => _player.seek(
                                  Duration(milliseconds: v.toInt())),
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),

          const SizedBox(width: 4),

          // 时长显示
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (ctx, snap) {
              final pos = snap.data ?? Duration.zero;
              return Text(
                '${_formatDuration(pos)} / ${_formatDuration(_duration)}',
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              );
            },
          ),

          const SizedBox(width: 4),

          // 播放/暂停按钮
          StreamBuilder<bool>(
            stream: _player.playingStream,
            builder: (ctx, snap) {
              final playing = snap.data ?? false;
              return IconButton(
                icon: Icon(
                  playing ? Icons.pause_circle : Icons.play_circle,
                  color: AppColors.primary,
                  size: 28,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _loading ? null : _togglePlay,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildErrorTile() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.music_off, size: 16, color: Colors.grey[400]),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.attachment.filename,
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('无法播放', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ],
      ),
    );
  }
}
