import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../services/settings/settings_service.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/constants/app_constants.dart';

/// 新建 / 编辑日记页面
///
/// - [editingMemo] 为 null → 新建模式，保存时创建新 [MemoEntry]
/// - [editingMemo] 不为 null → 编辑模式，保存时更新该条目
///
/// 保存成功后会在后台静默推送到远端（如已配置服务器），不阻塞 UI。
class MemoEditorPage extends StatefulWidget {
  /// 编辑模式时传入目标日记，新建模式不传
  final MemoEntry? editingMemo;

  const MemoEditorPage({super.key, this.editingMemo});

  @override
  State<MemoEditorPage> createState() => _MemoEditorPageState();
}

class _MemoEditorPageState extends State<MemoEditorPage> {
  late final TextEditingController _contentCtrl;
  late final TextEditingController _locationCtrl;
  late final FocusNode _contentFocus;

  /// 是否正在保存（控制保存按钮 loading 状态）
  bool _saving = false;

  /// 是否为编辑模式（影响标题文字）
  bool get _isEditing => widget.editingMemo != null;

  @override
  void initState() {
    super.initState();
    debugPrint('[MemoEditor] 初始化，模式=${_isEditing ? "编辑" : "新建"}，'
        'id=${widget.editingMemo?.id}');

    // 初始化输入控制器（编辑模式预填已有内容）
    _contentCtrl =
        TextEditingController(text: widget.editingMemo?.content ?? '');
    _locationCtrl =
        TextEditingController(text: widget.editingMemo?.location ?? '');
    _contentFocus = FocusNode();

    // macOS 上需延迟请求焦点，避免页面过渡动画期间首次点击失效；
    // 其他平台直接在下一帧请求，减少响应延迟
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final delay = defaultTargetPlatform == TargetPlatform.macOS
          ? const Duration(milliseconds: 300)
          : Duration.zero;
      Future.delayed(delay, () {
        if (mounted) {
          _contentFocus.requestFocus();
          debugPrint('[MemoEditor] 已请求正文焦点');
        }
      });
    });
  }

  @override
  void dispose() {
    debugPrint('[MemoEditor] 释放资源');
    _contentCtrl.dispose();
    _locationCtrl.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  /// 保存日记
  ///
  /// 流程：
  /// 1. 校验正文不为空
  /// 2. 写入本地 DB（新建或更新）
  /// 3. 如已配置服务器，在后台推送到远端
  /// 4. 返回上一页（携带 true 表示有变更）
  Future<void> _save() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      debugPrint('[MemoEditor] 保存失败：内容为空');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.editorEmptyWarning)),
      );
      return;
    }

    debugPrint('[MemoEditor] 开始保存，内容长度=${content.length}');
    setState(() => _saving = true);
    try {
      // 新建模式使用全新 MemoEntry，编辑模式复用已有对象
      final memo = widget.editingMemo ?? MemoEntry();
      memo.content = content;
      memo.location = _locationCtrl.text.trim().isEmpty
          ? null
          : _locationCtrl.text.trim();

      await DatabaseService.saveMemo(memo);
      debugPrint('[MemoEditor] 本地保存成功，memo.id=${memo.id}');

      // 后台静默推送到远端（fire-and-forget，不阻塞 UI 返回）
      final configured = await SettingsService.isConfigured;
      if (configured) {
        debugPrint('[MemoEditor] 服务器已配置，启动后台推送...');
        unawaited(SyncService.pushPendingBackground());
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[MemoEditor] 保存失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.editorSaveFailed}$e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 1,
        // 关闭按钮（取消编辑，直接返回）
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            debugPrint('[MemoEditor] 取消编辑，返回上一页');
            Navigator.pop(context);
          },
          tooltip: AppStrings.cancel,
        ),
        title: Text(
          _isEditing ? AppStrings.editorEditTitle : AppStrings.editorNewTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          // 保存中显示 loading，否则显示保存文字按钮
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text(
                    AppStrings.save,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
        ],
      ),
      // resizeToAvoidBottomInset=true（默认）让 Scaffold 在键盘弹起时自动收缩，
      // 底部工具栏随之上移，始终保持可见
      body: Column(
        children: [
          // ── 正文输入区（Markdown 格式提示）──────────────────────
          Expanded(
            child: SingleChildScrollView(
              // keyboardDismissBehavior：下拉正文区时收起键盘，符合 Android 习惯
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _contentCtrl,
                focusNode: _contentFocus,
                maxLines: null,
                autofocus: false,
                style: const TextStyle(fontSize: 16, height: 1.7),
                decoration: const InputDecoration(
                  hintText: AppStrings.editorContentHint,
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Color(0xFFBDBDBD)),
                ),
              ),
            ),
          ),

          const Divider(height: 1),

          // ── 底部工具栏：位置输入 ─────────────────────────────────
          // SafeArea top:false 只处理底部 inset（系统导航条），
          // 键盘高度由 Scaffold.resizeToAvoidBottomInset 自动处理
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 20, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _locationCtrl,
                      style:
                          TextStyle(fontSize: 14, color: Colors.grey[700]),
                      decoration: const InputDecoration(
                        hintText: AppStrings.editorLocationHint,
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
