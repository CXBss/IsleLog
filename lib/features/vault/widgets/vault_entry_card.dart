import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../data/models/vault_entry.dart';
import '../../../services/vault/vault_controller.dart';
import '../../../shared/constants/app_constants.dart';
import '../vault_audio_source.dart';

class VaultEntryCard extends StatelessWidget {
  final VaultEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const VaultEntryCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.onLongPress,
  });

  /// 与主页时间线卡片保持一致的截断口径（memo_timeline_card.dart 的 _kMaxLines）。
  ///
  /// 旧实现除了 maxLines 还额外做了 substring(0, 80) 的字符数硬砍，中文 80 字
  /// 只有两三句话，列表里几乎看不出这条写的是什么。字符数限制已去掉，
  /// 只保留行数截断，看全文点进详情/编辑页。
  static const int _kMaxLines = 6;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface(context),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: onTap,
            onLongPress: onLongPress,
            leading: const Icon(
              Icons.lock,
              size: 18,
              color: AppColors.primaryDark,
            ),
            title: Text(
              entry.content,
              maxLines: _kMaxLines,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(_formatTime(entry.createdAt)),
          ),
          if (entry.attachmentIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  if (_imageIds.isNotEmpty) Expanded(child: _buildThumbnails()),
                  ..._audioIds.map(_buildAudioButton),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<String> get _imageIds => entry.attachmentIds
      .where(
        (id) =>
            VaultController.instance
                .attachmentMimeType(id)
                ?.startsWith('image/') ??
            false,
      )
      .toList();

  List<String> get _audioIds => entry.attachmentIds
      .where(
        (id) =>
            VaultController.instance
                .attachmentMimeType(id)
                ?.startsWith('audio/') ??
            false,
      )
      .toList();

  Widget _buildThumbnails() {
    final imageIds = _imageIds;
    if (imageIds.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: imageIds.map((id) {
          final bytes = VaultController.instance.attachmentBytes(id);
          if (bytes == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Image.memory(
              bytes,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAudioButton(String id) {
    final bytes = VaultController.instance.attachmentBytes(id);
    final mime = VaultController.instance.attachmentMimeType(id);
    if (bytes == null) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.play_circle_outline),
      tooltip: '播放录音',
      onPressed: () {
        final player = AudioPlayer();
        player.setAudioSource(
          VaultByteAudioSource(bytes, mimeType: mime ?? 'audio/aac'),
        );
        player.play();
        // 播放器生命周期跟随一次播放，结束后释放。
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            player.dispose();
          }
        });
      },
    );
  }

  String _formatTime(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
