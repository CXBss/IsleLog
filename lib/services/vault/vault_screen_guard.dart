import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 进入隐私空间时启用截屏防护，离开时关闭。
///
/// Android：FLAG_SECURE，同时屏蔽截屏和最近任务缩略图。
/// iOS：在 willResignActive 时给窗口盖一层不透明视图。
/// 桌面端无等价机制，静默跳过。
class VaultScreenGuard {
  VaultScreenGuard._();

  static const _channel = MethodChannel('islelog/screen_guard');

  static bool get _supported => Platform.isAndroid || Platform.isIOS;

  static Future<void> enable() => _invoke('enable');
  static Future<void> disable() => _invoke('disable');

  static Future<void> _invoke(String method) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (e) {
      debugPrint('[ScreenGuard] $method 失败：$e');
    }
  }
}
