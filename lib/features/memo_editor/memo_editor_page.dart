import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../services/settings/settings_service.dart';
import '../../services/sync/sync_service.dart';

/// 新建 / 编辑日记页面
class MemoEditorPage extends StatefulWidget {
  /// 传入已有 memo 时为编辑模式，否则为新建模式
  final MemoEntry? editingMemo;

  const MemoEditorPage({super.key, this.editingMemo});

  @override
  State<MemoEditorPage> createState() => _MemoEditorPageState();
}

class _MemoEditorPageState extends State<MemoEditorPage> {
  late final TextEditingController _contentCtrl;
  late final TextEditingController _locationCtrl;
  late final FocusNode _contentFocus;
  bool _saving = false;

  bool get _isEditing => widget.editingMemo != null;

  @override
  void initState() {
    super.initState();
    _contentCtrl = TextEditingController(text: widget.editingMemo?.content ?? '');
    _locationCtrl = TextEditingController(text: widget.editingMemo?.location ?? '');
    _contentFocus = FocusNode();
    // 等页面过渡动画完成后再请求焦点，避免 macOS 上首次点击失效
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _contentFocus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _locationCtrl.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('内容不能为空')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final memo = widget.editingMemo ?? MemoEntry();
      memo.content = content;
      memo.location = _locationCtrl.text.trim().isEmpty
          ? null
          : _locationCtrl.text.trim();
      await DatabaseService.saveMemo(memo);

      // 后台静默推送到远端（fire-and-forget，不阻塞 UI）
      final configured = await SettingsService.isConfigured;
      if (configured) unawaited(SyncService.pushPendingBackground());

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
          tooltip: '取消',
        ),
        title: Text(
          _isEditing ? '编辑日记' : '新建日记',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text(
                    '保存',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                ),
        ],
      ),
      body: Column(
        children: [
          // ── 正文输入区 ───────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _contentCtrl,
                focusNode: _contentFocus,
                maxLines: null,
                autofocus: false,
                style: const TextStyle(fontSize: 16, height: 1.7),
                decoration: const InputDecoration(
                  hintText: '写点什么...\n\n支持 Markdown 格式和 #标签',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Color(0xFFBDBDBD)),
                ),
              ),
            ),
          ),

          const Divider(height: 1),

          // ── 底部工具栏（位置输入） ───────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 20, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _locationCtrl,
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      decoration: const InputDecoration(
                        hintText: '添加位置（可选）',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
