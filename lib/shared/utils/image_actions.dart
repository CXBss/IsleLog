import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/attachment_info.dart';
import '../../services/settings/settings_service.dart';

bool get _isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// 获取附件的图片字节数据（优先本地，否则从远端下载）
Future<Uint8List?> getImageBytes(AttachmentInfo att, {String? baseUrl}) async {
  if (att.localPath != null && File(att.localPath!).existsSync()) {
    return File(att.localPath!).readAsBytes();
  }
  final base = baseUrl ?? await SettingsService.serverUrl ?? '';
  final url = att.fullUrl(base);
  if (url == null || url.isEmpty) return null;
  final token = await SettingsService.accessToken;
  final dio = Dio();
  final resp = await dio.get<List<int>>(
    url,
    options: Options(
      responseType: ResponseType.bytes,
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
    ),
  );
  return Uint8List.fromList(resp.data!);
}

/// 在全屏图片查看器中长按时弹出操作菜单
///
/// 桌面端：复制 + 保存（文件管理器）
/// 移动端：分享 + 保存（相册）
void showImageActions(BuildContext context, AttachmentInfo att, {String? baseUrl}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isDesktop)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyImage(context, att, baseUrl: baseUrl);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('分享'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareImage(context, att, baseUrl: baseUrl);
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('保存'),
              onTap: () {
                Navigator.pop(ctx);
                _saveImage(context, att, baseUrl: baseUrl);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// 桌面端：复制图片到剪贴板
Future<void> _copyImage(BuildContext context, AttachmentInfo att, {String? baseUrl}) async {
  try {
    final bytes = await getImageBytes(att, baseUrl: baseUrl);
    if (bytes == null) throw Exception('无法获取图片数据');
    await Pasteboard.writeImage(bytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('复制失败：$e')),
      );
    }
  }
}

/// 移动端：分享图片
Future<void> _shareImage(BuildContext context, AttachmentInfo att, {String? baseUrl}) async {
  try {
    final bytes = await getImageBytes(att, baseUrl: baseUrl);
    if (bytes == null) throw Exception('无法获取图片数据');

    // 写入临时文件后分享
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/${att.filename}');
    await tempFile.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(tempFile.path)]));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：$e')),
      );
    }
  }
}

/// 保存图片：移动端保存到相册，桌面端弹出文件选择器
Future<void> _saveImage(BuildContext context, AttachmentInfo att, {String? baseUrl}) async {
  try {
    if (_isDesktop) {
      await _saveImageDesktop(context, att, baseUrl: baseUrl);
    } else {
      await _saveImageMobile(context, att, baseUrl: baseUrl);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }
}

/// 桌面端：弹出文件管理器选择保存位置
Future<void> _saveImageDesktop(BuildContext context, AttachmentInfo att, {String? baseUrl}) async {
  final bytes = await getImageBytes(att, baseUrl: baseUrl);
  if (bytes == null) throw Exception('无法获取图片数据');

  final result = await FilePicker.platform.saveFile(
    dialogTitle: '保存图片',
    fileName: att.filename,
  );
  if (result == null) return;

  final file = File(result);
  await file.writeAsBytes(bytes);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存')),
    );
  }
}

/// 移动端：保存到系统相册
Future<void> _saveImageMobile(BuildContext context, AttachmentInfo att, {String? baseUrl}) async {
  final hasAccess = await Gal.hasAccess(toAlbum: false);
  if (!hasAccess) {
    final granted = await Gal.requestAccess(toAlbum: false);
    if (!granted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无相册写入权限')),
        );
      }
      return;
    }
  }

  if (att.localPath != null && File(att.localPath!).existsSync()) {
    await Gal.putImage(att.localPath!);
  } else {
    final bytes = await getImageBytes(att, baseUrl: baseUrl);
    if (bytes == null) throw Exception('无法获取图片数据');
    await Gal.putImageBytes(bytes, name: att.filename);
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存到相册')),
    );
  }
}
