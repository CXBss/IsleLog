import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 全局音频播放管理器
///
/// 保证同一时刻只有一个音频在播放。
/// 各 [AudioPlayerWidget] 在开始播放前调用 [requestPlay]，
/// Manager 会暂停当前正在播放的其他实例。
class AudioManager {
  AudioManager._();

  /// 当前正在（或最近）播放的 player
  static AudioPlayer? _active;

  /// 请求独占播放权
  ///
  /// 若有其他 player 正在播放则先暂停，然后将 [player] 设为活跃实例。
  static Future<void> requestPlay(AudioPlayer player) async {
    if (_active != null && _active != player) {
      try {
        await _active!.pause();
        debugPrint('[AudioManager] 暂停上一个播放器');
      } catch (_) {}
    }
    _active = player;
  }

  /// 释放活跃 player 引用（player dispose 时调用）
  static void release(AudioPlayer player) {
    if (_active == player) _active = null;
  }
}
