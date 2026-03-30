import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database/database_service.dart';
import '../../data/models/attachment_info.dart';
import '../../data/models/memo_entry.dart';
import '../../data/models/tag_stat.dart';
import '../../services/attachment/attachment_service.dart';
import '../../services/location/location_service.dart';
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

  /// 新建模式时指定初始日期（日历视图选中某天后新建使用）
  final DateTime? initialDate;

  const MemoEditorPage({super.key, this.editingMemo, this.initialDate});

  @override
  State<MemoEditorPage> createState() => _MemoEditorPageState();
}

class _MemoEditorPageState extends State<MemoEditorPage> {
  late final TextEditingController _contentCtrl;
  late final TextEditingController _locationCtrl;
  late final FocusNode _contentFocus;

  /// 是否正在保存（控制保存按钮 loading 状态）
  bool _saving = false;

  /// 是否正在上传附件
  bool _uploading = false;

  /// 是否正在获取位置
  bool _locating = false;

  /// 录音器
  final AudioRecorder _recorder = AudioRecorder();

  /// 是否正在录音
  bool _recording = false;

  /// 录音时长（秒）
  int _recordSeconds = 0;
  Timer? _recordTimer;

  /// 当前位置信息（含经纬度，用于点击跳转地图）
  LocationInfo? _locationInfo;

  /// 本次编辑的附件列表（保存时写入 MemoEntry）
  final List<AttachmentInfo> _pendingAttachments = [];

  /// 编辑模式下被移除的旧附件（仅保存成功后才真正删除远端资源）
  final List<AttachmentInfo> _removedAttachments = [];

  /// 是否为编辑模式（影响标题文字）
  bool get _isEditing => widget.editingMemo != null;

  /// 当前选定的日记时间（新建时默认为 initialDate 日期+当前时间，编辑时为原始时间）
  late DateTime _selectedDateTime;

  // ── 标签提示 ──────────────────────────────────────────────────

  /// 当前正在输入的 # 前缀（null = 不显示提示）
  String? _tagPrefix;

  /// 所有可用标签（从本地缓存加载）
  List<TagStat> _allTags = [];

  /// 当前过滤后的候选标签
  List<TagStat> get _tagSuggestions {
    if (_tagPrefix == null) return [];
    final prefix = _tagPrefix!.toLowerCase();
    if (prefix.isEmpty) return _allTags;
    return _allTags
        .where((t) => t.name.toLowerCase().startsWith(prefix))
        .toList();
  }

  /// 内容输入框的 GlobalKey，用于定位浮层位置
  final GlobalKey _contentFieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    debugPrint('[MemoEditor] 初始化，模式=${_isEditing ? "编辑" : "新建"}，'
        'id=${widget.editingMemo?.id}');

    _contentCtrl =
        TextEditingController(text: widget.editingMemo?.content ?? '');
    _locationCtrl =
        TextEditingController(text: widget.editingMemo?.location ?? '');
    _contentFocus = FocusNode(
      onKeyEvent: _isDesktop ? _onKeyEvent : null,
    );

    // 编辑模式用原始时间，新建模式用 initialDate 日期+当前时间
    if (widget.editingMemo != null) {
      _selectedDateTime = widget.editingMemo!.createdAt;
    } else {
      final now = DateTime.now();
      final base = widget.initialDate ?? now;
      _selectedDateTime = DateTime(base.year, base.month, base.day,
          now.hour, now.minute, now.second);
    }

    if (widget.editingMemo != null) {
      _pendingAttachments.addAll(widget.editingMemo!.attachments);
      // 编辑模式：若已有经纬度则恢复 LocationInfo（支持点击跳转）
      final m = widget.editingMemo!;
      if (m.latitude != null && m.longitude != null) {
        _locationInfo = LocationInfo(
          latitude: m.latitude!,
          longitude: m.longitude!,
          address: m.location,
        );
      }
    }

    // 新建模式下恢复草稿；移动端自动获取位置（草稿无位置时）
    if (!_isEditing) {
      _loadDraft().then((_) {
        if (_isMobile && _locationCtrl.text.trim().isEmpty) {
          _autoGetLocation();
        }
      });
    }

    _contentCtrl.addListener(_onContentChanged);

    DatabaseService.getCachedTagStats().then((tags) {
      if (mounted) setState(() => _allTags = tags);
    });

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
    _contentCtrl.removeListener(_onContentChanged);
    _contentCtrl.dispose();
    _locationCtrl.dispose();
    _contentFocus.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ── 日期时间选择 ───────────────────────────────────────────────

  String get _dateTimeLabel {
    final d = _selectedDateTime;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
        ' ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (time == null || !mounted) return;
    setState(() {
      _selectedDateTime = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  // ── 位置 ──────────────────────────────────────────────────────

  /// 静默自动获取位置（新建时后台调用，失败不提示）
  Future<void> _autoGetLocation() async {
    if (!_isMobile) return;
    try {
      final info = await LocationService.getLocation();
      if (mounted && _locationCtrl.text.trim().isEmpty) {
        setState(() {
          _locationInfo = info;
          _locationCtrl.text = info.displayText;
        });
      }
    } catch (e) {
      debugPrint('[MemoEditor] 自动获取位置失败（静默忽略）：$e');
    }
  }

  /// 手动点击位置图标获取位置（失败时提示用户）
  Future<void> _manualGetLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final info = await LocationService.getLocation();
      if (mounted) {
        setState(() {
          _locationInfo = info;
          _locationCtrl.text = info.displayText;
          _locating = false;
        });
      }
    } on LocationException catch (e) {
      debugPrint('[MemoEditor] 获取位置失败：$e');
      if (mounted) {
        setState(() => _locating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      debugPrint('[MemoEditor] 获取位置未知错误：$e');
      if (mounted) {
        setState(() => _locating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取位置失败：$e')),
        );
      }
    }
  }

  /// 点击地址文本跳转系统地图
  Future<void> _openLocationMap() async {
    if (_locationInfo == null) return;
    await openMapFromCoords(
      _locationInfo!.latitude,
      _locationInfo!.longitude,
      _locationInfo!.address,
    );
  }

  // ── 草稿 ──────────────────────────────────────────────────────

  Future<void> _loadDraft() async {
    final content = await SettingsService.draftContent;
    final location = await SettingsService.draftLocation;
    if (content != null && content.isNotEmpty && mounted) {
      _contentCtrl.text = content;
      _locationCtrl.text = location ?? '';
    }
  }

  Future<void> _saveDraftAndPop() async {
    final content = _contentCtrl.text;
    if (content.trim().isNotEmpty) {
      await SettingsService.saveDraft(content, _locationCtrl.text);
    } else {
      await SettingsService.clearDraft();
    }
    if (mounted) Navigator.pop(context);
  }

  // ── 标签提示逻辑 ──────────────────────────────────────────────

  void _onContentChanged() {
    final text = _contentCtrl.text;
    final cursor = _contentCtrl.selection.baseOffset;
    if (cursor <= 0) {
      _setTagPrefix(null);
      return;
    }

    // 取光标前的文本，找最后一个 # 的位置
    final before = text.substring(0, cursor);
    final hashIdx = before.lastIndexOf('#');
    if (hashIdx == -1) {
      _setTagPrefix(null);
      return;
    }

    final segment = before.substring(hashIdx + 1); // # 之后到光标的内容
    // 遇到空格/换行则关闭提示
    if (segment.contains(' ') || segment.contains('\n')) {
      _setTagPrefix(null);
      return;
    }

    _setTagPrefix(segment); // 可能是空字符串（刚输入 # 时）
  }

  void _setTagPrefix(String? prefix) {
    if (_tagPrefix == prefix) return;
    setState(() => _tagPrefix = prefix);
  }

  /// 点击候选标签：替换光标前的 #xxx 片段
  void _acceptTag(String tagName) {
    final text = _contentCtrl.text;
    final cursor = _contentCtrl.selection.baseOffset;
    final before = text.substring(0, cursor);
    final hashIdx = before.lastIndexOf('#');
    if (hashIdx == -1) return;

    final after = text.substring(cursor);
    final newText = '${text.substring(0, hashIdx)}#$tagName $after';
    final newCursor = hashIdx + tagName.length + 2; // # + name + 空格

    _contentCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    setState(() => _tagPrefix = null);
    _contentFocus.requestFocus();
  }

  // ── 附件选择与上传 ────────────────────────────────────────────

  // 仅 iOS / Android 支持摄像头
  static bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  static bool get _isDesktop => !_isMobile;

  /// 弹出附件类型选择菜单，然后选择并处理文件
  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<_AttachType>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拍照仅在移动端显示
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('图片'),
              onTap: () => Navigator.pop(context, _AttachType.image),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('其他文件'),
              onTap: () => Navigator.pop(context, _AttachType.file),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    // ── 拍照 ──────────────────────────────────────────────────────
    if (choice == _AttachType.camera) {
      await _takePhoto();
      return;
    }

    // ── 文件选择器 ─────────────────────────────────────────────────
    FileType fileType;
    switch (choice) {
      case _AttachType.image:
        fileType = FileType.image;
      case _AttachType.audio:
        fileType = FileType.audio;
      case _AttachType.camera: // 不会走到这里
        return;
      case _AttachType.file:
        fileType = FileType.any;
    }

    final result = await FilePicker.platform.pickFiles(
      type: fileType,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    if (picked.path == null) return;

    // 图片类型询问是否压缩
    bool compress = true;
    if (choice == _AttachType.image && mounted) {
      final useCompress = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('图片质量'),
          content: const Text('压缩后上传可节省流量，原图保留完整画质。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('原图'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('压缩'),
            ),
          ],
        ),
      );
      if (useCompress == null) return;
      compress = useCompress;
    }

    await _processFile(File(picked.path!), picked.name, compress: compress);
  }

  /// 调用系统相机拍照，拍完自动压缩并上传
  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    XFile? photo;
    try {
      photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85, // 系统层面先压一次（0-100）
        maxWidth: 2048,
        maxHeight: 2048,
      );
    } catch (e) {
      debugPrint('[MemoEditor] 拍照失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法访问相机：$e')),
        );
      }
      return;
    }
    if (photo == null) return; // 用户取消

    final filename = photo.name.isNotEmpty
        ? photo.name
        : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';

    // compress: true → AttachmentService 再做一次 flutter_image_compress 压缩
    await _processFile(File(photo.path), filename, compress: true);
  }

  /// 处理选中的文件：在线上传 or 离线存储
  ///
  /// 优先尝试在线上传；若服务器未配置或网络不通，自动降级到本地存储，
  /// 待下次联网同步时由 [SyncService] 补传。
  Future<void> _processFile(File file, String filename, {bool compress = true}) async {
    setState(() => _uploading = true);
    try {
      final configured = await SettingsService.isConfigured;
      AttachmentInfo info;

      if (configured) {
        try {
          info = await AttachmentService.uploadToServer(file, filename: filename, compress: compress);
          debugPrint('[MemoEditor] 在线上传成功：${info.filename}');
        } catch (e) {
          // 网络不通时降级到本地存储，等待联网后同步
          debugPrint('[MemoEditor] 在线上传失败，降级本地存储：$e');
          info = await AttachmentService.saveLocally(file, filename: filename, compress: compress);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('网络不可用，附件已本地保存，联网后自动上传')),
            );
          }
        }
      } else {
        info = await AttachmentService.saveLocally(file, filename: filename, compress: compress);
      }

      setState(() => _pendingAttachments.add(info));
      debugPrint('[MemoEditor] 附件已处理：${info.filename}');
    } catch (e) {
      debugPrint('[MemoEditor] 附件处理失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('附件处理失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 桌面端拦截 Ctrl/Cmd+V：若剪贴板有图片则作为附件添加，否则执行普通文本粘贴
  bool _pasteBusy = false;
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (!isCtrlOrCmd || event.logicalKey != LogicalKeyboardKey.keyV) {
      return KeyEventResult.ignored;
    }
    if (_pasteBusy) return KeyEventResult.handled;
    _pasteBusy = true;
    // 消费按键事件，异步判断剪贴板内容
    _handlePasteImage().then((handled) {
      _pasteBusy = false;
      if (!handled) {
        // 剪贴板没有图片，手动执行文本粘贴
        _pasteText();
      }
    });
    return KeyEventResult.handled;
  }

  /// 手动从剪贴板读取文本并插入到光标位置
  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final text = _contentCtrl.text;
    final sel = _contentCtrl.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final newText = text.replaceRange(start, end, data.text!);
    _contentCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + data.text!.length),
    );
  }

  /// 桌面端粘贴：优先检查剪贴板图片，其次检查剪贴板文件
  Future<bool> _handlePasteImage() async {
    if (!_isDesktop) return false;
    try {
      // 1. 尝试读取剪贴板图片
      final bytes = await Pasteboard.image;
      if (bytes != null && bytes.isNotEmpty) {
        final filename = 'paste_${DateTime.now().millisecondsSinceEpoch}.png';
        final tempDir = await getTemporaryDirectory();
        await tempDir.create(recursive: true);
        final tempFile = File('${tempDir.path}/$filename');
        await tempFile.writeAsBytes(bytes);
        await _processFile(tempFile, filename, compress: true);
        return true;
      }

      // 2. 尝试读取剪贴板文件
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        for (final path in files) {
          final file = File(path);
          if (file.existsSync()) {
            final filename = p.basename(path);
            final isImage = _isImageFile(filename);
            await _processFile(file, filename, compress: isImage);
          }
        }
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('[MemoEditor] 粘贴失败：$e');
      return false;
    }
  }

  static bool _isImageFile(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'}.contains(ext);
  }

  /// 移除一个附件（延迟删除：保存成功后才真正删远端，取消编辑则不删）
  void _removeAttachment(AttachmentInfo att) {
    setState(() => _pendingAttachments.remove(att));
    _removedAttachments.add(att);
  }

  /// 保存日记
  ///
  /// 流程：
  // ── 录音 ──────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无麦克风权限')),
        );
      }
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a');
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    setState(() { _recording = true; _recordSeconds = 0; });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    setState(() { _recording = false; _recordSeconds = 0; });
    if (path == null) return;
    final file = File(path);
    if (!file.existsSync()) return;

    setState(() => _uploading = true);
    try {
      final configured = await SettingsService.isConfigured;
      final filename = p.basename(path);
      AttachmentInfo att;
      if (configured) {
        try {
          att = await AttachmentService.uploadToServer(file, filename: filename, compress: false);
        } catch (e) {
          debugPrint('[MemoEditor] 录音上传失败，降级本地存储：$e');
          att = await AttachmentService.saveLocally(file, filename: filename, compress: false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('网络不可用，录音已本地保存，联网后自动上传')),
            );
          }
        }
      } else {
        att = await AttachmentService.saveLocally(file, filename: filename, compress: false);
      }
      if (mounted) setState(() => _pendingAttachments.add(att));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('录音保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String get _recordLabel {
    final m = _recordSeconds ~/ 60;
    final s = _recordSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 用指定前后缀包裹当前选中文字（或在光标处插入占位）
  void _wrapSelection(String prefix, String suffix) {
    final ctrl = _contentCtrl;
    final sel = ctrl.selection;
    final text = ctrl.text;
    if (!sel.isValid) {
      // 无有效光标，直接追加到末尾
      final insert = '$prefix$suffix';
      ctrl.value = TextEditingValue(
        text: text + insert,
        selection: TextSelection.collapsed(
            offset: text.length + prefix.length),
      );
    } else if (sel.isCollapsed) {
      // 无选中，插入占位符并将光标置于中间
      final pos = sel.baseOffset;
      final newText = text.substring(0, pos) + prefix + suffix + text.substring(pos);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: pos + prefix.length),
      );
    } else {
      // 有选中，包裹选中文字
      final selected = sel.textInside(text);
      final newText = text.replaceRange(sel.start, sel.end, '$prefix$selected$suffix');
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + prefix.length + selected.length + suffix.length),
      );
    }
    _contentFocus.requestFocus();
  }

  /// 在当前行行首插入 `1. `（有序列表）
  void _insertOrderedList() => _insertLinePrefix('1. ');

  /// 在当前行行首插入 `- `（无序列表）
  void _insertUnorderedList() => _insertLinePrefix('- ');

  /// 在当前行行首插入指定前缀
  void _insertLinePrefix(String prefix) {
    final ctrl = _contentCtrl;
    final text = ctrl.text;
    final sel = ctrl.selection;
    final pos = sel.isValid ? sel.baseOffset : text.length;
    final lineStart = text.lastIndexOf('\n', pos - 1) + 1;
    final newText = text.substring(0, lineStart) + prefix + text.substring(lineStart);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + prefix.length),
    );
    _contentFocus.requestFocus();
  }

  /// 在当前行行首插入 `- [ ] `
  void _insertTodo() => _insertLinePrefix('- [ ] ');

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
      memo.latitude = _locationInfo?.latitude;
      memo.longitude = _locationInfo?.longitude;
      memo.attachments = _pendingAttachments;
      memo.createdAt = _selectedDateTime;
      // 编辑模式必须重置为 pending，否则同步引擎查不到该条目
      memo.syncStatus = SyncStatus.pending;

      await DatabaseService.saveMemo(memo);
      debugPrint('[MemoEditor] 本地保存成功，memo.id=${memo.id}');

      // 保存成功后才删除被移除的附件（避免用户取消编辑时误删）
      for (final att in _removedAttachments) {
        if (att.remoteResName != null) AttachmentService.deleteRemote(att.remoteResName!);
        if (att.localPath != null) AttachmentService.deleteLocal(att.localPath!);
      }

      // 保存成功后清除草稿
      if (!_isEditing) await SettingsService.clearDraft();

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
            if (_isEditing) {
              Navigator.pop(context);
            } else {
              _saveDraftAndPop();
            }
          },
          tooltip: AppStrings.cancel,
        ),
        title: Text(
          _isEditing ? AppStrings.editorEditTitle : AppStrings.editorNewTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: const [],
      ),
      body: CallbackShortcuts(
        bindings: {
          SingleActivator(
            LogicalKeyboardKey.enter,
            meta: defaultTargetPlatform == TargetPlatform.macOS,
            control: defaultTargetPlatform != TargetPlatform.macOS,
          ): _save,
        },
        child: Column(
        children: [
          // ── 正文输入区 + 右侧标签面板 ────────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 正文输入
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      key: _contentFieldKey,
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
                // 右侧标签面板（输入 # 时出现）
                if (_tagPrefix != null)
                  _TagSuggestionPanel(
                    suggestions: _tagSuggestions,
                    onSelect: _acceptTag,
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── 附件预览条（有附件时展示）────────────────────────────
          if (_pendingAttachments.isNotEmpty)
            _AttachmentBar(
              attachments: _pendingAttachments,
              onRemove: _removeAttachment,
            ),

          // ── 底部工具栏（两行）────────────────────────────────────
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 第一行：# · 时间戳 · B · I · ` · 有序列表 · 无序列表 · -[]
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Row(
                    children: [
                      _FmtButton(
                        label: '#',
                        tooltip: '标题',
                        onTap: () {
                          final ctrl = _contentCtrl;
                          final sel = ctrl.selection;
                          final pos = sel.isValid ? sel.baseOffset : ctrl.text.length;
                          final newText = ctrl.text.substring(0, pos) + '# ' + ctrl.text.substring(pos);
                          ctrl.value = TextEditingValue(
                            text: newText,
                            selection: TextSelection.collapsed(offset: pos + 1),
                          );
                          _contentFocus.requestFocus();
                        },
                      ),
                      _FmtButton(
                        icon: Icons.access_time,
                        tooltip: '插入时间戳',
                        onTap: () {
                          final now = DateTime.now();
                          final ts =
                              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
                              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
                          final ctrl = _contentCtrl;
                          final sel = ctrl.selection;
                          final pos = sel.isValid ? sel.baseOffset : ctrl.text.length;
                          final newText = ctrl.text.substring(0, pos) + ts + ctrl.text.substring(pos);
                          ctrl.value = TextEditingValue(
                            text: newText,
                            selection: TextSelection.collapsed(offset: pos + ts.length),
                          );
                          _contentFocus.requestFocus();
                        },
                      ),
                      _FmtButton(icon: Icons.format_bold, tooltip: '加粗', onTap: () => _wrapSelection('**', '**')),
                      _FmtButton(icon: Icons.format_italic, tooltip: '斜体', onTap: () => _wrapSelection('*', '*')),
                      _FmtButton(icon: Icons.code, tooltip: '代码', onTap: () => _wrapSelection('`', '`')),
                      _FmtButton(icon: Icons.format_list_numbered, tooltip: '有序列表', onTap: _insertOrderedList),
                      _FmtButton(icon: Icons.format_list_bulleted, tooltip: '无序列表', onTap: _insertUnorderedList),
                      _FmtButton(icon: Icons.check_box_outline_blank, tooltip: 'Todo', onTap: _insertTodo),
                      const SizedBox(width: 8),
                      // 日期时间
                      GestureDetector(
                        onTap: _pickDateTime,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.access_time_outlined, size: 15, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(_dateTimeLabel, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),

                // ── 第二行：录音 · 拍照 · 附件 · 位置 · 保存 ──────
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                  child: Row(
                    children: [
                      // 录音按钮
                      _recording
                          ? GestureDetector(
                              onTap: _toggleRecording,
                              child: Container(
                                height: 36,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.stop_circle_outlined, size: 20, color: Colors.red),
                                    const SizedBox(width: 4),
                                    Text(_recordLabel, style: const TextStyle(fontSize: 13, color: Colors.red, fontFeatures: [FontFeature.tabularFigures()])),
                                  ],
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.mic_outlined),
                              color: Colors.grey[600],
                              iconSize: 22,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              tooltip: '录音',
                              onPressed: _uploading ? null : _toggleRecording,
                            ),
                      if (_isMobile)
                        IconButton(
                          icon: const Icon(Icons.camera_alt_outlined),
                          color: Colors.grey[600],
                          iconSize: 22,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          tooltip: '拍照',
                          onPressed: _uploading ? null : _takePhoto,
                        ),
                      _uploading
                          ? const SizedBox(
                              width: 36, height: 36,
                              child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                            )
                          : IconButton(
                              icon: const Icon(Icons.attach_file),
                              color: Colors.grey[600],
                              iconSize: 22,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              tooltip: '添加附件',
                              onPressed: _pickAttachment,
                            ),
                      // 位置图标
                      _isMobile && _locating
                          ? const SizedBox(width: 36, height: 36,
                              child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                          : IconButton(
                              icon: Icon(_locationInfo != null ? Icons.location_on : Icons.location_on_outlined),
                              color: _locationInfo != null ? AppColors.primary : Colors.grey[600],
                              iconSize: 22,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              tooltip: '位置',
                              onPressed: _isMobile ? _manualGetLocation : null,
                            ),
                      // 位置文本
                      Expanded(
                        child: _locationInfo != null
                            ? GestureDetector(
                                onTap: _openLocationMap,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(_locationCtrl.text,
                                        style: const TextStyle(fontSize: 12, color: AppColors.primary, decoration: TextDecoration.underline, decorationColor: AppColors.primary),
                                        overflow: TextOverflow.ellipsis),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => setState(() { _locationInfo = null; _locationCtrl.clear(); }),
                                      child: Icon(Icons.close, size: 14, color: Colors.grey[400]),
                                    ),
                                  ],
                                ),
                              )
                            : SizedBox(
                                height: 24,
                                child: TextField(
                                  controller: _locationCtrl,
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  decoration: InputDecoration(
                                    hintText: _isMobile ? '位置' : AppStrings.editorLocationHint,
                                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                                    border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 4),
                      // 保存按钮
                      _saving
                          ? const SizedBox(
                              width: 36,
                              height: 36,
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary),
                              ),
                            )
                          : TextButton(
                              onPressed: _save,
                              style: TextButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(AppStrings.save,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold)),
                            ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ── 附件类型枚举 ───────────────────────────────────────────────────

enum _AttachType { camera, image, audio, file }

// ── 附件预览条 ─────────────────────────────────────────────────────

/// 编辑器中已添加附件的横向预览条
///
/// 图片显示缩略图，音频/文件显示图标+文件名，每项右上角有删除按钮。
class _AttachmentBar extends StatelessWidget {
  final List<AttachmentInfo> attachments;
  final ValueChanged<AttachmentInfo> onRemove;

  const _AttachmentBar({
    required this.attachments,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) =>
            _AttachThumb(attachment: attachments[i], onRemove: onRemove),
      ),
    );
  }
}

class _AttachThumb extends StatefulWidget {
  final AttachmentInfo attachment;
  final ValueChanged<AttachmentInfo> onRemove;

  const _AttachThumb({required this.attachment, required this.onRemove});

  @override
  State<_AttachThumb> createState() => _AttachThumbState();
}

class _AttachThumbState extends State<_AttachThumb> {
  String _baseUrl = '';

  @override
  void initState() {
    super.initState();
    SettingsService.serverUrl.then((v) {
      if (mounted) setState(() => _baseUrl = v ?? '');
    });
  }

  AttachmentInfo get attachment => widget.attachment;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _buildThumbContent(),
          ),
        ),
        // 删除按钮
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => widget.onRemove(attachment),
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThumbContent() {
    if (attachment.isImage) {
      final path = attachment.localPath;
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) {
          return Image.file(file, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _iconFallback());
        }
      }
      final url = attachment.fullUrl(_baseUrl);
      if (url != null && url.isNotEmpty) {
        return Image.network(url, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _iconFallback());
      }
      return _iconFallback();
    }

    return _iconFallback();
  }

  Widget _iconFallback() {
    IconData icon;
    if (attachment.isAudio) {
      icon = Icons.music_note;
    } else if (attachment.mimeType == 'application/pdf') {
      icon = Icons.picture_as_pdf_outlined;
    } else if (attachment.isImage) {
      icon = Icons.image_outlined;
    } else {
      icon = Icons.insert_drive_file_outlined;
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: Colors.grey[500]),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              attachment.filename,
              style: TextStyle(fontSize: 8, color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 右侧标签候选面板 ───────────────────────────────────────────────

/// 输入 # 后在编辑区右侧弹出的竖向标签列表
///
/// 显示全部标签（[suggestions] 为空时显示"暂无标签"），
/// 随 [_tagPrefix] 实时过滤，点击后插入到正文。
class _TagSuggestionPanel extends StatelessWidget {
  final List<TagStat> suggestions;
  final ValueChanged<String> onSelect;

  const _TagSuggestionPanel({
    required this.suggestions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        border: Border(
          left: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
      ),
      child: suggestions.isEmpty
          ? Center(
              child: Text('暂无标签',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400])),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: suggestions.length,
              itemBuilder: (ctx, i) {
                final tag = suggestions[i];
                return InkWell(
                  onTap: () => onSelect(tag.name),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '#${tag.name}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${tag.count}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// 工具栏格式化按钮，支持图标或文字标签
class _FmtButton extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final String tooltip;
  final VoidCallback onTap;

  const _FmtButton({
    this.icon,
    this.label,
    required this.tooltip,
    required this.onTap,
  }) : assert(icon != null || label != null);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 22, color: Colors.grey[600])
                : Text(
                    label!,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                      height: 1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
