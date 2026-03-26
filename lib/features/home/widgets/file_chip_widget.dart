import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../../data/models/attachment_info.dart';
import '../../../shared/constants/app_constants.dart';

/// 非图片/非音频附件的文件 Chip
///
/// 显示文件图标 + 文件名，点击后：
/// - 有本地路径：用系统应用打开
/// - 只有远端 URL：暂时提示（后续可扩展下载逻辑）
class FileChipWidget extends StatelessWidget {
  final AttachmentInfo attachment;

  const FileChipWidget({super.key, required this.attachment});

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

  Future<void> _open(BuildContext context) async {
    if (attachment.localPath != null) {
      final result = await OpenFilex.open(attachment.localPath!);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开文件：${result.message}')),
        );
      }
    } else if (attachment.remoteUrl != null) {
      // 远端文件：提示暂不支持直接打开（可后续扩展下载）
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('远端文件暂不支持直接打开，请先同步下载')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        margin: const EdgeInsets.only(top: 4, right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                attachment.filename,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.open_in_new, size: 12, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
