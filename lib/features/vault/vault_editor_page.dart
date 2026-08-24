import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart' show Uuid;

import '../../data/models/vault_entry.dart';
import '../../services/vault/vault_controller.dart';

class VaultEditorPage extends StatefulWidget {
  final VaultEntry? existing;

  const VaultEditorPage({super.key, this.existing});

  @override
  State<VaultEditorPage> createState() => _VaultEditorPageState();
}

class _VaultEditorPageState extends State<VaultEditorPage>
    with WidgetsBindingObserver {
  late final TextEditingController _controller;
  bool _saving = false;

  /// 待保存的附件（由图片/录音捕获填充）。
  final List<VaultAttachment> _pendingAttachments = [];
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;

  /// 新建条目在首次写入（可能是自动保存）时定下的 id / 创建时间，
  /// 后续所有写入都复用，避免重复建条目。
  String? _workingId;
  DateTime? _workingCreatedAt;

  @override
  void initState() {
    super.initState();
    // 有意不读取/写入 SettingsService 的草稿字段——这是隐私空间编辑器
    // 与 MemoEditorPage 的核心区别，绝不能让内容明文落进 SharedPreferences。
    _controller = TextEditingController(text: widget.existing?.content ?? '');
    VaultController.instance.isUnlockedListenable.addListener(_onLockChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  /// 进后台立刻加密保存当前内容。
  ///
  /// 只靠"锁定时清空输入框"会造成另一种数据丢失：正在写的一段话，切出去
  /// 超过 60 秒回来就没了。这里的保存发生在 60 秒锁定**之前**，密钥还在，
  /// 所以之后的锁定是无损的。
  ///
  /// 不能改成"锁定那一刻抢救保存"——lock() 是先清密钥再广播，那时已经写不进去了。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused) return;
    if (!VaultController.instance.isUnlocked) return;
    if (_controller.text.trim().isEmpty && _pendingAttachments.isEmpty) return;
    unawaited(_persist());
  }

  /// 后台超时锁定时，清空输入框并退出。
  ///
  /// 不做这件事的后果：编辑器仍持有明文，且此时点保存会走到已经没有主密钥的
  /// 存储层（VaultStorage._requireKey() 会抛 StateError）。
  void _onLockChanged() {
    if (!VaultController.instance.isUnlocked && mounted) {
      _controller.clear();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    WidgetsBinding.instance.removeObserver(this);
    VaultController.instance.isUnlockedListenable.removeListener(_onLockChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _persistPendingAttachments() async {
    for (final a in _pendingAttachments) {
      await VaultController.instance.addAttachment(a);
    }
  }

  List<String> _mergedAttachmentIds() => {
    ...?widget.existing?.attachmentIds,
    ..._pendingAttachments.map((a) => a.id),
  }.toList();

  /// 实际写入 vault。被手动保存和进后台自动保存共用。
  ///
  /// [_workingId] 保证两条路径写的是同一个条目——否则"自动保存一次、
  /// 回来再点保存一次"会产生两条重复日记。
  Future<void> _persist() async {
    await _persistPendingAttachments();
    final now = DateTime.now();
    final existing = widget.existing;
    final entry = existing != null
        ? (existing
              ..content = _controller.text
              ..attachmentIds = _mergedAttachmentIds())
        : VaultEntry(
            id: _workingId ??= const Uuid().v4(),
            content: _controller.text,
            createdAt: _workingCreatedAt ??= now,
            updatedAt: now,
            tags: const [],
            attachmentIds: _mergedAttachmentIds(),
          );
    await VaultController.instance.saveEntry(entry);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (photo == null) return;
    final bytes = await File(photo.path).readAsBytes();
    // image_picker 会先在应用缓存/临时目录落一份明文副本，读入内存后立即删除，
    // 否则这份明文会一直留在缓存里。
    try {
      await File(photo.path).delete();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _pendingAttachments.add(
        VaultAttachment(
          id: const Uuid().v4(),
          mimeType: 'image/jpeg',
          bytes: bytes,
        ),
      );
    });
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() => _recording = false);
      if (path == null) return;
      final file = File(path);
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();
      // 录音包必须先落盘（record 包限制），读入内存后文件与所在临时目录都要删。
      await file.delete();
      final parent = file.parent;
      try {
        if (await parent.exists()) await parent.delete(recursive: true);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _pendingAttachments.add(
          VaultAttachment(
            id: const Uuid().v4(),
            mimeType: 'audio/aac',
            bytes: bytes,
          ),
        );
      });
    } else {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return;
      final tmpDir = await Directory.systemTemp.createTemp('vault_rec_');
      final path = '${tmpDir.path}/rec.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (mounted) setState(() => _recording = true);
    }
  }

  Future<void> _save() async {
    if (!VaultController.instance.isUnlocked) {
      // 保存过程中刚好被后台超时锁掉：直接退出，不尝试写入。
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (_controller.text.trim().isEmpty && _pendingAttachments.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    await _persist();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    await VaultController.instance.deleteEntry(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '新建隐私日记' : '编辑'),
        actions: [
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: '添加图片',
            onPressed: _saving ? null : _pickImage,
          ),
          IconButton(
            icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none),
            tooltip: _recording ? '停止录音' : '录音',
            onPressed: _toggleRecording,
          ),
          if (widget.existing != null)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          autofocus: widget.existing == null,
          // 隐私内容不进系统输入法的学习词库和联想候选
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: '写点什么…',
          ),
        ),
      ),
    );
  }
}
