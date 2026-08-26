import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/models/vault_entry.dart';
import '../../services/vault/vault_controller.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/widgets/image_grid.dart';
import 'vault_audio_source.dart';
import 'vault_editor_page.dart';

/// 隐私日记详情页（只读）。
///
/// 补上此前的空档：列表卡片只有截断正文 + 缩略图，编辑页只有全文输入框、
/// 完全不渲染已有附件——没有任何一个页面能同时看到全文和附件。
///
/// 交互与主库的 MemoDetailPage 一致：列表点进详情，详情点「编辑」才进编辑态。
class VaultDetailPage extends StatefulWidget {
  final VaultEntry entry;

  const VaultDetailPage({super.key, required this.entry});

  @override
  State<VaultDetailPage> createState() => _VaultDetailPageState();
}

class _VaultDetailPageState extends State<VaultDetailPage> {
  late VaultEntry _entry = widget.entry;
  AudioPlayer? _player;

  @override
  void initState() {
    super.initState();
    // 锁定时立刻退出：这个页面上摊着解密后的正文和附件。
    VaultController.instance.isUnlockedListenable.addListener(_onLockChanged);
  }

  void _onLockChanged() {
    if (!VaultController.instance.isUnlocked && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    VaultController.instance.isUnlockedListenable.removeListener(
      _onLockChanged,
    );
    _player?.dispose();
    super.dispose();
  }

  List<String> _idsWithMime(String prefix) => _entry.attachmentIds
      .where(
        (id) =>
            VaultController.instance
                .attachmentMimeType(id)
                ?.startsWith(prefix) ??
            false,
      )
      .toList();

  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VaultEditorPage(existing: _entry)),
    );
    if (!mounted) return;
    // 编辑页可能改了正文或删了这条；回来后从内存里取最新状态。
    final latest = VaultController.instance.entries
        .where((e) => e.id == _entry.id)
        .firstOrNull;
    if (latest == null) {
      Navigator.of(context).pop(); // 已被删除
      return;
    }
    setState(() => _entry = latest);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私日记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: _openEditor,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildMeta(),
          const SizedBox(height: 12),
          if (_entry.content.trim().isEmpty)
            Text(
              '（无正文）',
              style: TextStyle(color: AppColors.textSecondary(context)),
            )
          else
            MarkdownBody(data: _entry.content, selectable: true),
          if (_entry.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildTags(),
          ],
          ..._buildAttachments(),
        ],
      ),
    );
  }

  Widget _buildMeta() {
    return Row(
      children: [
        const Icon(Icons.lock, size: 16, color: AppColors.primaryDark),
        const SizedBox(width: 6),
        Text(
          _formatTime(_entry.createdAt),
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildTags() {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: _entry.tags
          .map(
            (t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '#$t',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  List<Widget> _buildAttachments() {
    final images = _idsWithMime('image/');
    final audios = _idsWithMime('audio/');
    if (images.isEmpty && audios.isEmpty) return const [];

    return [
      const SizedBox(height: 20),
      Text(
        '附件',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary(context),
        ),
      ),
      const SizedBox(height: 8),
      // 复用主库详情页那套网格 + 全屏查看器（翻页、双指缩放），
      // 只是取图换成内存字节——落盘就违背隐私空间的意义。
      //
      // onExport 一律为 null：全屏查看器的长按导出会把私密照片保存进系统相册
      // 或直接分享出去，两者都会击穿隐私空间，这里必须禁掉。
      ImageGrid(
        images: [
          for (final id in images)
            if (VaultController.instance.attachmentBytes(id) case final bytes?)
              GridImageSource(
                build:
                    ({
                      double? width,
                      double? height,
                      BoxFit fit = BoxFit.cover,
                    }) => Image.memory(
                      bytes,
                      width: width,
                      height: height,
                      fit: fit,
                    ),
                onExport: null,
              ),
        ],
      ),
      ...audios.map(_buildAudioTile),
    ];
  }

  Widget _buildAudioTile(String id) {
    final bytes = VaultController.instance.attachmentBytes(id);
    final mime = VaultController.instance.attachmentMimeType(id);
    if (bytes == null) return const SizedBox.shrink();
    return Card(
      color: AppColors.surface(context),
      child: ListTile(
        leading: const Icon(Icons.play_circle_outline),
        title: const Text('录音'),
        onTap: () async {
          await _player?.dispose();
          final player = AudioPlayer();
          _player = player;
          await player.setAudioSource(
            VaultByteAudioSource(bytes, mimeType: mime ?? 'audio/aac'),
          );
          await player.play();
        },
      ),
    );
  }

  String _formatTime(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
