import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/attachment/video_playback_support.dart';

void main() {
  // 只有这四个平台在 pubspec 里带了 media_kit_libs_*_video，
  // 其余平台没有预编译库，创建 Player 会直接崩，必须走文件 Chip 老路径。
  test('打包了 media_kit 库的平台支持播放', () {
    expect(videoPlaybackSupportedOn(TargetPlatform.android), isTrue);
    expect(videoPlaybackSupportedOn(TargetPlatform.iOS), isTrue);
    expect(videoPlaybackSupportedOn(TargetPlatform.macOS), isTrue);
    expect(videoPlaybackSupportedOn(TargetPlatform.windows), isTrue);
  });

  test('未打包的平台不支持播放', () {
    expect(videoPlaybackSupportedOn(TargetPlatform.linux), isFalse);
    expect(videoPlaybackSupportedOn(TargetPlatform.fuchsia), isFalse);
  });
}
