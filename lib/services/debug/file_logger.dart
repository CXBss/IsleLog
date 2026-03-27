import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 文件日志（仅 debug 模式生效）
///
/// 用于无法通过 logcat 看日志的设备（如部分荣耀机型）。
/// 日志写到应用文档目录的 isle_log.txt，可通过设置页导出。
class FileLogger {
  FileLogger._();

  static const _filename = 'isle_log.txt';
  static const _maxLines = 2000; // 超过后截断旧行

  static File? _file;
  static int _lineCount = 0;

  static Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/$_filename');
    return _file!;
  }

  /// 写一条日志（仅 debug 模式）
  static Future<void> log(String message) async {
    if (!kDebugMode) return;
    final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:mm:ss.mmm
    final line = '[$ts] $message\n';
    debugPrint(message); // 同时走 debugPrint
    try {
      final file = await _getFile();
      await file.writeAsString(line, mode: FileMode.append);
      _lineCount++;
      // 超过限制时重写（保留后半部分）
      if (_lineCount > _maxLines) {
        final lines = await file.readAsLines();
        final trimmed = lines.skip(lines.length ~/ 2).join('\n');
        await file.writeAsString(trimmed);
        _lineCount = lines.length ~/ 2;
      }
    } catch (_) {}
  }

  /// 读取全部日志内容
  static Future<String> read() async {
    try {
      final file = await _getFile();
      if (await file.exists()) return await file.readAsString();
    } catch (_) {}
    return '';
  }

  /// 清空日志文件
  static Future<void> clear() async {
    try {
      final file = await _getFile();
      await file.writeAsString('');
      _lineCount = 0;
    } catch (_) {}
  }

  /// 返回日志文件路径（用于 adb pull）
  static Future<String> get filePath async => (await _getFile()).path;
}
