import 'package:flutter/foundation.dart';

/// 应用内视频播放依赖 media_kit 的预编译库，pubspec 只引了这四个平台的
/// `media_kit_libs_*_video`。其余平台（Linux / Web）创建 Player 会失败，
/// 视频仍按普通文件处理——点开走系统播放器。
bool videoPlaybackSupportedOn(TargetPlatform platform) => const {
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.macOS,
  TargetPlatform.windows,
}.contains(platform);

/// 当前运行平台是否支持应用内播放。
bool get videoPlaybackSupported =>
    !kIsWeb && videoPlaybackSupportedOn(defaultTargetPlatform);
