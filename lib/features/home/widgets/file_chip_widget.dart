import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/models/attachment_info.dart';
import '../../../services/settings/settings_service.dart';
import '../../../shared/constants/app_constants.dart';

/// 非图片/非音频附件的文件 Chip
///
/// 点击或长按：弹出菜单，可选"打开"或"保存"
class FileChipWidget extends StatefulWidget {
  final AttachmentInfo attachment;

  const FileChipWidget({super.key, required this.attachment});

  @override
  State<FileChipWidget> createState() => _FileChipWidgetState();
}

class _FileChipWidgetState extends State<FileChipWidget> {
  bool _downloading = false;
  double? _progress;

  AttachmentInfo get attachment => widget.attachment;

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  IconData get _icon {
    final mime = attachment.mimeType;
    if (mime.startsWith('video/')) return Icons.video_file_outlined;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mime.contains('zip') || mime.contains('compressed')) {
      return Icons.folder_zip_outlined;
    }
    if (mime.startsWith('text/')) return Icons.description_outlined;
    return Icons.attach_file;
  }

  void _showActions() {
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
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('打开'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openFile();
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('保存'),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开：下载到临时目录后用系统应用打开
  Future<void> _openFile() async {
    if (_downloading) return;
    setState(() { _downloading = true; _progress = null; });
    try {
      final bytes = await _getFileBytes();
      if (bytes == null) {
        _showError('无法获取文件');
        return;
      }
      final tempDir = await getTemporaryDirectory();
      await tempDir.create(recursive: true);
      final file = File('${tempDir.path}/${attachment.filename}');
      await file.writeAsBytes(bytes);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        _showError('无法打开：${result.message}');
      }
    } catch (e) {
      _showError('打开失败：$e');
    } finally {
      if (mounted) setState(() { _downloading = false; _progress = null; });
    }
  }

  /// 保存：桌面端弹文件管理器，移动端保存到系统 Downloads
  Future<void> _saveFile() async {
    if (_downloading) return;
    setState(() { _downloading = true; _progress = null; });
    try {
      final bytes = await _getFileBytes();
      if (bytes == null) {
        _showError('无法获取文件');
        return;
      }

      if (_isDesktop) {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: '保存文件',
          fileName: attachment.filename,
        );
        if (result == null) return;
        await File(result).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已保存')),
          );
        }
      } else {
        // 移动端：写入系统 Downloads 目录
        // Android: /storage/emulated/0/Download
        // iOS: 应用文档目录（可通过"文件" App 访问）
        final Directory saveDir;
        if (Platform.isAndroid) {
          saveDir = Directory('/storage/emulated/0/Download');
        } else {
          saveDir = await getApplicationDocumentsDirectory();
        }
        await saveDir.create(recursive: true);
        final file = File('${saveDir.path}/${attachment.filename}');
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已保存至 ${file.path}')),
          );
        }
      }
    } catch (e) {
      _showError('保存失败：$e');
    } finally {
      if (mounted) setState(() { _downloading = false; _progress = null; });
    }
  }

  Future<List<int>?> _getFileBytes() async {
    if (attachment.localPath != null && File(attachment.localPath!).existsSync()) {
      return File(attachment.localPath!).readAsBytes();
    }
    final baseUrl = await SettingsService.serverUrl ?? '';
    final url = attachment.fullUrl(baseUrl);
    if (url == null || url.isEmpty) return null;
    final token = await SettingsService.accessToken;
    final dio = Dio();
    final resp = await dio.get<List<int>>(
      url,
      onReceiveProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      },
      options: Options(
        responseType: ResponseType.bytes,
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      ),
    );
    return resp.data;
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showActions,
      onLongPress: _showActions,
      child: Container(
        margin: const EdgeInsets.only(top: 4, right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: _downloading ? AppColors.primaryLighter : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _downloading ? AppColors.primary : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 14,
                color: _downloading ? AppColors.primary : Colors.grey[600]),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                attachment.filename,
                style: TextStyle(
                  fontSize: 12,
                  color: _downloading ? AppColors.primaryDark : Colors.grey[700],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            if (_downloading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.primary,
                  value: _progress,
                ),
              )
            else
              Icon(Icons.more_horiz, size: 12, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }
}
