import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/models/attachment_info.dart';
import '../settings/settings_service.dart';
import 'video_playback_support.dart';
import 'video_source_resolver.dart';
import 'video_thumbnail.dart';

/// 视频首帧封面的取帧与缓存。
///
/// 取一帧要开一个完整的解码器，代价不小，所以结果按 localId 缓存两级：
/// 内存（同一次会话内滚动列表不重复取）+ 磁盘（重启后仍能直接显示封面）。
class VideoThumbnailService {
  static final Map<String, VideoThumbnail> _memory = {};
  static final Map<String, Future<VideoThumbnail>> _inflight = {};

  /// 单个视频的取帧上限。远端流可能很慢，卡住不如回落成图标。
  static const _timeout = Duration(seconds: 12);

  /// 取 [attachment] 的封面，失败时返回空 [VideoThumbnail]（不抛异常）。
  static Future<VideoThumbnail> load(AttachmentInfo attachment) {
    if (!videoPlaybackSupported) return Future.value(const VideoThumbnail());

    final id = attachment.localId;
    final cached = _memory[id];
    if (cached != null) return Future.value(cached);

    // 同一个视频在列表和详情页可能同时请求，合并成一次取帧。
    return _inflight[id] ??= _load(
      attachment,
    ).whenComplete(() => _inflight.remove(id));
  }

  /// 清空缓存（附件被删除或替换时调用）。
  static Future<void> evict(String localId) async {
    _memory.remove(localId);
    final dir = await _cacheDir();
    for (final f in [_frameFile(dir, localId), _metaFile(dir, localId)]) {
      if (f.existsSync()) await f.delete();
    }
  }

  static Future<VideoThumbnail> _load(AttachmentInfo attachment) async {
    final id = attachment.localId;

    final fromDisk = await _readDisk(id);
    if (fromDisk != null) return _memory[id] = fromDisk;

    final baseUrl = await SettingsService.serverUrl ?? '';
    final token = await SettingsService.accessToken;
    final source = resolveVideoSource(
      attachment,
      baseUrl: baseUrl,
      token: token,
    );
    if (source == null) return const VideoThumbnail();

    final thumb = await _capture(source);
    // 空结果不写盘，也不长期驻留内存——下次可能就有网了。
    if (thumb.frame == null) return thumb;
    await _writeDisk(id, thumb);
    return _memory[id] = thumb;
  }

  static Future<VideoThumbnail> _capture(VideoPlaybackSource source) async {
    final player = Player();
    try {
      // screenshot 依赖已初始化的视频输出，必须先挂 controller。
      final controller = VideoController(player);
      await player.open(mediaForVideoSource(source), play: false);
      // 等第一帧解码出来，否则截到的是空画面。
      await player.stream.width
          .firstWhere((w) => w != null && w > 0)
          .timeout(_timeout);
      await controller.waitUntilFirstFrameRendered.timeout(_timeout);

      final frame = await player.screenshot().timeout(_timeout);
      final duration = player.state.duration;
      return VideoThumbnail(
        frame: frame,
        duration: duration > Duration.zero ? duration : null,
      );
    } catch (e) {
      debugPrint('[VideoThumbnail] 取帧失败：$e');
      return const VideoThumbnail();
    } finally {
      await player.dispose();
    }
  }

  // ── 磁盘缓存 ──────────────────────────────────────────────────

  static Future<Directory> _cacheDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'video_thumbs'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static File _frameFile(Directory dir, String id) =>
      File(p.join(dir.path, '$id.jpg'));

  static File _metaFile(Directory dir, String id) =>
      File(p.join(dir.path, '$id.json'));

  static Future<VideoThumbnail?> _readDisk(String id) async {
    try {
      final dir = await _cacheDir();
      final frameFile = _frameFile(dir, id);
      if (!frameFile.existsSync()) return null;

      Duration? duration;
      final metaFile = _metaFile(dir, id);
      if (metaFile.existsSync()) {
        final meta = jsonDecode(await metaFile.readAsString());
        final ms = (meta as Map)['durationMs'] as int?;
        if (ms != null) duration = Duration(milliseconds: ms);
      }
      return VideoThumbnail(
        frame: Uint8List.fromList(await frameFile.readAsBytes()),
        duration: duration,
      );
    } catch (e) {
      debugPrint('[VideoThumbnail] 读缓存失败：$e');
      return null;
    }
  }

  static Future<void> _writeDisk(String id, VideoThumbnail thumb) async {
    try {
      final dir = await _cacheDir();
      await _frameFile(dir, id).writeAsBytes(thumb.frame!);
      final ms = thumb.duration?.inMilliseconds;
      if (ms != null) {
        await _metaFile(dir, id).writeAsString(jsonEncode({'durationMs': ms}));
      }
    } catch (e) {
      debugPrint('[VideoThumbnail] 写缓存失败：$e');
    }
  }
}

/// 把播放源转成 media_kit 的 [Media]，远端流带上鉴权头。
Media mediaForVideoSource(VideoPlaybackSource source) => switch (source) {
  LocalVideoSource(:final path) => Media(path),
  RemoteVideoSource(:final url, :final headers) => Media(
    url,
    httpHeaders: headers.isEmpty ? null : headers,
  ),
};
