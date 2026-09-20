import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../data/database/database_service.dart';
import '../../data/models/tag_stat.dart';
import '../../data/models/weather_info.dart';
import '../../services/ai/ai_api_client.dart';
import '../../services/ai/ai_models.dart';
import '../../services/ai/ai_service.dart';
import '../../services/location/location_service.dart';
import '../../services/settings/settings_service.dart';
import '../../services/weather/weather_service.dart';
import '../../shared/constants/app_constants.dart';
import 'package:uuid/uuid.dart' show Uuid;

import '../../data/models/vault_entry.dart';
import '../../services/vault/vault_controller.dart';
import '../../shared/widgets/image_grid.dart';
import '../memo_editor/ai/ai_action_sheet.dart';
import '../memo_editor/ai/cloud_ai_consent_dialog.dart';
import '../memo_editor/ai/polish_preview_page.dart';
import '../memo_editor/ai/tag_insertion.dart';
import '../memo_editor/ai/tag_suggestions_sheet.dart';

/// 新建 / 编辑日记页面
///
/// - [editingMemo] 为 null → 新建模式，保存时创建新 [MemoEntry]
/// - [editingMemo] 不为 null → 编辑模式，保存时更新该条目
///
/// 保存成功后会在后台静默推送到远端（如已配置服务器），不阻塞 UI。
class VaultEditorPage extends StatefulWidget {
  /// 编辑模式时传入目标条目，新建模式不传
  final VaultEntry? existing;

  /// 新建模式时指定初始日期
  final DateTime? initialDate;

  /// 测试注入的 AI 网关；为 null 时由 [AiService] 从设置解析
  final AiGateway? aiGateway;

  /// 测试注入的 AI 能力开关；为 null 时按服务端状态判断
  final bool? aiCapabilityOverride;

  const VaultEditorPage({
    super.key,
    this.existing,
    this.initialDate,
    this.aiGateway,
    this.aiCapabilityOverride,
  });

  @override
  State<VaultEditorPage> createState() => _VaultEditorPageState();
}

class _VaultEditorPageState extends State<VaultEditorPage>
    with WidgetsBindingObserver {
  late final TextEditingController _contentCtrl;
  late final TextEditingController _locationCtrl;
  late final FocusNode _contentFocus;

  /// 是否正在保存（控制保存按钮 loading 状态）
  bool _saving = false;

  /// 是否正在上传附件
  bool _uploading = false;

  /// 录音器
  final AudioRecorder _recorder = AudioRecorder();

  /// 是否正在录音
  bool _recording = false;

  /// 录音时长（秒）
  int _recordSeconds = 0;
  Timer? _recordTimer;

  /// 当前位置信息（含经纬度，用于点击跳转地图）
  LocationInfo? _locationInfo;

  /// 当前天气信息（null 表示未设置）
  WeatherInfo? _weatherInfo;

  /// 位置数据版本号，用于丢弃自动获取过程中已经过期的结果
  int _locationRevision = 0;

  /// 天气数据版本号，用于丢弃自动获取过程中已经过期的结果
  int _weatherRevision = 0;

  /// 当前心情（null 表示未设置）
  String? _mood;

  /// 本次编辑的附件列表（保存时写入 MemoEntry）
  final List<VaultAttachment> _pendingAttachments = [];

  /// 编辑模式下被移除的旧附件 id（保存成功后才从 vault 附件包里删）
  final Set<String> _removedAttachmentIds = {};

  /// 新建条目在首次写入（含进后台自动保存）时定下的 id 与创建时间，
  /// 后续所有写入复用，避免自动保存后再手动保存产生两条。
  /// 防止粘贴快捷键重入
  bool _pasteBusy = false;

  String? _workingId;
  DateTime? _workingCreatedAt;

  bool get _isEditing => widget.existing != null;

  bool get _hasLocation =>
      _locationInfo != null || _locationCtrl.text.trim().isNotEmpty;

  String get _locationDisplayText {
    final name = _locationCtrl.text.trim();
    if (name.isNotEmpty) return name;
    return _locationInfo?.displayText ?? '';
  }

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

  // ── AI 编辑辅助 ───────────────────────────────────────────────

  /// 服务端 Provider 状态（为空表示尚未加载或加载失败）
  List<AiProviderStatus> _aiStatuses = [];

  /// 是否显示 AI 入口：服务端至少有一个 `enabled=true` 的 Provider，
  /// 不等同于当前健康检查的 `available`（暂时离线仍保留入口和重试能力）
  bool _aiAvailable = false;

  /// 是否正在 AI 请求（期间禁用入口，避免并发）
  bool _aiRequesting = false;

  /// 当前请求的取消令牌
  CancelToken? _aiCancelToken;

  @override
  void initState() {
    super.initState();
    // 锁定时清空并退出：编辑器持有解密后的明文。
    VaultController.instance.isUnlockedListenable.addListener(_onLockChanged);
    WidgetsBinding.instance.addObserver(this);

    final existing = widget.existing;
    _contentCtrl = TextEditingController(text: existing?.content ?? '');
    if (existing != null) {
      _contentCtrl.selection = const TextSelection.collapsed(offset: 0);
    }
    _locationCtrl = TextEditingController(text: existing?.location ?? '');
    _contentFocus = FocusNode(onKeyEvent: _isDesktop ? _onKeyEvent : null);

    if (existing != null) {
      _selectedDateTime = existing.createdAt;
      if (existing.latitude != null && existing.longitude != null) {
        _locationInfo = LocationInfo(
          latitude: existing.latitude!,
          longitude: existing.longitude!,
          address: existing.location,
        );
      }
      if (existing.weatherJson != null) {
        try {
          _weatherInfo = WeatherInfo.fromJsonString(existing.weatherJson!);
        } catch (_) {}
      }
      _mood = existing.mood;
      // 已有附件按 id 从 vault 附件包里取字节，回填成可编辑（可删除）的列表
      for (final id in existing.attachmentIds) {
        final bytes = VaultController.instance.attachmentBytes(id);
        if (bytes == null) continue;
        _pendingAttachments.add(
          VaultAttachment(
            id: id,
            mimeType:
                VaultController.instance.attachmentMimeType(id) ??
                'application/octet-stream',
            bytes: bytes,
          ),
        );
      }
    } else {
      final now = DateTime.now();
      final base = widget.initialDate ?? now;
      _selectedDateTime = DateTime(
        base.year,
        base.month,
        base.day,
        now.hour,
        now.minute,
        now.second,
      );
    }

    // 不恢复草稿：草稿走 SettingsService，会把正文明文写进 SharedPreferences。
    // 隐私空间靠「进后台立即加密保存」代替，见 didChangeAppLifecycleState。
    if (_isMobile) _autoFetchOnEntry();

    // 标签候选取主库已有标签，只用于输入补全，不会把 vault 标签写回主库
    DatabaseService.getCachedTagStats().then((tags) {
      if (mounted) setState(() => _allTags = tags);
    });
    _loadAiStatuses();
    _contentCtrl.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VaultController.instance.isUnlockedListenable.removeListener(
      _onLockChanged,
    );
    // 页面关闭时取消仍在进行的 AI 请求，避免云端请求继续产生费用
    _aiCancelToken?.cancel();
    _contentCtrl.removeListener(_onContentChanged);
    _contentCtrl.dispose();
    _locationCtrl.dispose();
    _contentFocus.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isCtrlOrCmd =
        HardwareKeyboard.instance.isMetaPressed ||
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

  String get _recordLabel {
    final m = _recordSeconds ~/ 60;
    final s = _recordSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  // ── 位置 ──────────────────────────────────────────────────────

  /// 进入编辑页后自动获取：经纬度 → 位置名称 → 天气（均静默，失败不打扰）
  Future<void> _autoFetchOnEntry() async {
    // 1. 自动获取经纬度（纯 GPS，离线可用）
    if (_locationInfo == null && _locationCtrl.text.trim().isEmpty) {
      final revision = _locationRevision;
      try {
        final (lat, lng) = await LocationService.getCoordinates();
        if (mounted &&
            revision == _locationRevision &&
            _locationInfo == null &&
            _locationCtrl.text.trim().isEmpty) {
          setState(() {
            _locationInfo = LocationInfo(latitude: lat, longitude: lng);
          });
        }
      } catch (e) {
        debugPrint('[MemoEditor] 自动获取经纬度失败（静默忽略）：$e');
      }
    }

    final located = _locationInfo;

    // 2. 有经纬度但没名称 → 尝试反查名称（需要网络，失败静默）
    if (located != null && _locationCtrl.text.trim().isEmpty) {
      final revision = _locationRevision;
      final address = await LocationService.reverseGeocode(
        located.latitude,
        located.longitude,
      );
      final current = _locationInfo;
      if (mounted &&
          revision == _locationRevision &&
          address != null &&
          address.isNotEmpty &&
          current != null &&
          current.latitude == located.latitude &&
          current.longitude == located.longitude &&
          _locationCtrl.text.trim().isEmpty) {
        setState(() {
          _locationInfo = LocationInfo(
            latitude: located.latitude,
            longitude: located.longitude,
            address: address,
          );
          _locationCtrl.text = address;
        });
      }
    }

    // 3. 天气为空 → 按坐标自动获取（有坐标即可，不依赖名称）
    if (_weatherInfo == null && _locationInfo != null) {
      final weatherRevision = _weatherRevision;
      final locationRevision = _locationRevision;
      final locatedForWeather = _locationInfo!;
      try {
        final info = await WeatherService.fetchWeatherByCoords(
          latitude: locatedForWeather.latitude,
          longitude: locatedForWeather.longitude,
        );
        final current = _locationInfo;
        if (mounted &&
            info != null &&
            weatherRevision == _weatherRevision &&
            locationRevision == _locationRevision &&
            _weatherInfo == null &&
            current != null &&
            current.latitude == locatedForWeather.latitude &&
            current.longitude == locatedForWeather.longitude) {
          setState(() => _weatherInfo = info);
        }
      } catch (e) {
        debugPrint('[MemoEditor] 自动获取天气失败（静默忽略）：$e');
      }
    }
  }

  /// 点击位置图标：弹出位置设置窗口（自动获取经纬度 / 反查名称）
  Future<void> _openLocationSheet() async {
    final result = await showModalBottomSheet<_LocationSheetResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _LocationSheet(
        latitude: _locationInfo?.latitude,
        longitude: _locationInfo?.longitude,
        name: _locationCtrl.text,
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _locationRevision++;
      if (result.clearAll) {
        _locationInfo = null;
        _locationCtrl.clear();
        return;
      }

      if (result.coordinatesChanged) {
        final currentName = _locationCtrl.text.trim();
        _locationInfo = LocationInfo(
          latitude: result.latitude!,
          longitude: result.longitude!,
          address: currentName.isEmpty ? null : currentName,
        );
      }

      if (result.nameChanged) {
        final name = result.name!.trim();
        _locationCtrl.text = name;
        final current = _locationInfo;
        if (current != null) {
          _locationInfo = LocationInfo(
            latitude: current.latitude,
            longitude: current.longitude,
            address: name,
          );
        }
      }
    });
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

  // ── 天气 ──────────────────────────────────────────────────────

  /// 点击天气按钮：弹出天气设置窗口（自动/城市/手动选择/描述）
  Future<void> _openWeatherSheet() async {
    final result = await showModalBottomSheet<_WeatherSheetResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _WeatherSheet(
        current: _weatherInfo,
        location: _locationInfo,
        canAutoLocate: _isMobile,
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _weatherRevision++;
      if (result.clearAll) {
        _weatherInfo = null;
        return;
      }

      final currentCondition = _weatherInfo?.condition ?? '';
      final currentDetail = _weatherInfo?.detail ?? '';
      final condition = result.conditionChanged
          ? result.condition ?? ''
          : currentCondition;
      final detail = result.detailChanged ? result.detail ?? '' : currentDetail;
      if (condition.isEmpty && detail.isEmpty) {
        _weatherInfo = null;
      } else if (result.conditionChanged || result.detailChanged) {
        _weatherInfo = WeatherInfo(condition: condition, detail: detail);
      }
    });
  }

  // ── 心情 ──────────────────────────────────────────────────────

  Future<void> _pickMood() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _MoodPickerSheet(selectedKey: _mood),
    );
    if (result != null && mounted) {
      // 空字符串表示清除；相同 key 表示取消选中；否则设置新心情
      setState(
        () => _mood = (result.isEmpty || result == _mood) ? null : result,
      );
    }
  }

  // ── 草稿 ──────────────────────────────────────────────────────

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法访问相机：$e')));
      }
      return;
    }
    if (photo == null) return; // 用户取消

    final filename = photo.name.isNotEmpty
        ? photo.name
        : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _processFile(File(photo.path), filename, compress: true);
  }

  /// 处理选中的文件：在线上传 or 离线存储
  ///
  /// 优先尝试在线上传；若服务器未配置或网络不通，自动降级到本地存储，
  /// 把选中的文件读成内存字节挂进待保存列表。
  ///
  /// 与主库编辑器的关键区别：不调用 AttachmentService——它会把附件明文写进
  /// 应用目录、并在联网时上传到服务器。隐私空间的附件只以字节形式存在于内存，
  /// 保存时随 vault 一起加密；[file] 若是选择器产生的临时副本，读完立即删除。
  Future<void> _processFile(
    File file,
    String filename, {
    bool compress = true,
    bool deleteSource = true,
  }) async {
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      if (deleteSource) {
        // image_picker / file_picker 会先在缓存目录落一份明文副本，
        // 读进内存后必须立刻删掉，否则明文一直留在缓存里。
        try {
          await file.delete();
        } catch (_) {}
      }
      setState(() {
        _pendingAttachments.add(
          VaultAttachment(
            id: const Uuid().v4(),
            mimeType: _guessMime(filename),
            bytes: bytes,
          ),
        );
      });
    } catch (e) {
      debugPrint('[VaultEditor] 附件处理失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('附件处理失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _guessMime(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'm4a' || 'aac' => 'audio/aac',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      _ => 'application/octet-stream',
    };
  }

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
  /// 移除一个附件。
  ///
  /// 本次新加的直接从内存列表拿掉；已存在于 vault 附件包里的先记账，
  /// 等保存成功再真正删——否则用户取消编辑就白删了。
  void _removeAttachment(VaultAttachment att) {
    setState(() {
      _pendingAttachments.removeWhere((a) => a.id == att.id);
      if (widget.existing?.attachmentIds.contains(att.id) ?? false) {
        _removedAttachmentIds.add(att.id);
      }
    });
  }

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无麦克风权限')));
      }
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(
      dir.path,
      'rec_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    setState(() {
      _recording = true;
      _recordSeconds = 0;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    setState(() {
      _recording = false;
      _recordSeconds = 0;
    });
    if (path == null) return;
    final file = File(path);
    if (!file.existsSync()) return;

    // record 包只能录到文件，读进内存后连同临时目录一起删掉。
    await _processFile(file, p.basename(path), compress: false);
    final parent = file.parent;
    try {
      if (await parent.exists()) await parent.delete(recursive: true);
    } catch (_) {}
  }

  void _wrapSelection(String prefix, String suffix) {
    final ctrl = _contentCtrl;
    final sel = ctrl.selection;
    final text = ctrl.text;
    if (!sel.isValid) {
      // 无有效光标，直接追加到末尾
      final insert = '$prefix$suffix';
      ctrl.value = TextEditingValue(
        text: text + insert,
        selection: TextSelection.collapsed(offset: text.length + prefix.length),
      );
    } else if (sel.isCollapsed) {
      // 无选中，插入占位符并将光标置于中间
      final pos = sel.baseOffset;
      final newText =
          text.substring(0, pos) + prefix + suffix + text.substring(pos);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: pos + prefix.length),
      );
    } else {
      // 有选中，包裹选中文字
      final selected = sel.textInside(text);
      final newText = text.replaceRange(
        sel.start,
        sel.end,
        '$prefix$selected$suffix',
      );
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: sel.start + prefix.length + selected.length + suffix.length,
        ),
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
    final newText =
        text.substring(0, lineStart) + prefix + text.substring(lineStart);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + prefix.length),
    );
    _contentFocus.requestFocus();
  }

  /// 在当前行行首插入 `- [ ] `
  void _insertTodo() => _insertLinePrefix('- [ ] ');

  // ── AI 编辑辅助 ───────────────────────────────────────────────

  Future<AiGateway> _resolveAiGateway() async {
    final injected = widget.aiGateway;
    if (injected != null) return injected;
    return AiService().createGateway();
  }

  /// 加载服务端 Provider 状态，决定是否显示 AI 入口。
  Future<void> _loadAiStatuses() async {
    final override = widget.aiCapabilityOverride;
    if (override != null) {
      setState(() => _aiAvailable = override);
      return;
    }
    try {
      final gateway = await _resolveAiGateway();
      final statuses = await gateway.listProviders();
      if (mounted) {
        setState(() {
          _aiStatuses = statuses;
          _aiAvailable = statuses.any(
            (s) => s.enabled && s.name != AiProvider.localEmbedding,
          );
        });
      }
    } catch (e) {
      // NAS 不可达：回退到已成功的能力缓存，避免隐藏入口
      final url = await SettingsService.serverUrl;
      final cached = url == null
          ? null
          : await SettingsService.aiCapabilityFor(url);
      if (mounted) setState(() => _aiAvailable = cached ?? false);
      debugPrint('[MemoEditor] AI 能力探测失败，回退缓存=$cached：$e');
    }
  }

  Future<void> _showAiActions() async {
    if (_aiRequesting) return;
    // 状态为空（探测失败或离线）时重新探测一次，网络恢复后无需重开编辑器
    if (widget.aiCapabilityOverride == null && _aiStatuses.isEmpty) {
      await _loadAiStatuses();
      if (!mounted) return;
    }
    if (widget.aiCapabilityOverride != true &&
        !_aiStatuses.any(
            (s) => s.enabled && s.name != AiProvider.localEmbedding,
          )) {
      _showAiSnack('AI 模型服务暂时不可用，请稍后再试');
      return;
    }
    final selection = await showAiActionSheet(context, providers: _aiStatuses);
    if (selection == null || !mounted) return;
    await _runAiAction(selection);
  }

  Future<void> _runAiAction(AiActionSelection selection) async {
    final AiGateway gateway;
    try {
      gateway = await _resolveAiGateway();
    } on AiApiException catch (e) {
      _showAiSnack(e.message);
      return;
    }

    final isDeepSeek = selection.provider == AiProvider.deepSeek;
    final content = _contentCtrl.text;
    final selectionRange = _contentCtrl.selection;
    final hasSelection =
        selectionRange.isValid &&
        selectionRange.isNormalized &&
        selectionRange.start != selectionRange.end;
    final targetStart = hasSelection ? selectionRange.start : 0;
    final targetEnd = hasSelection ? selectionRange.end : content.length;
    final target = content.substring(targetStart, targetEnd);

    // DeepSeek 每次操作单独确认，不持久化
    if (isDeepSeek) {
      if (!mounted) return;
      var model = 'DeepSeek';
      for (final s in _aiStatuses) {
        if (s.name == AiProvider.deepSeek && s.model.isNotEmpty) {
          model = s.model;
          break;
        }
      }
      final consent = await showCloudAiConsentDialog(
        context: context,
        model: model,
        recordCount: 1,
        characterCount: target.length,
        contentModeLabel: '原文',
        includedMetadata: const ['标签', '正文'],
      );
      if (!consent || !mounted) return;
    }

    final cancelToken = CancelToken();
    _aiCancelToken = cancelToken;
    setState(() => _aiRequesting = true);

    try {
      if (selection.type == AiActionType.suggestTags) {
        final existingTags = _allTags
            .map((t) => AiExistingTag(name: t.name, count: t.count))
            .toList();
        final suggestions = await _requestSuggestTags(
          gateway: gateway,
          target: target,
          existingTags: existingTags,
          isDeepSeek: isDeepSeek,
          cancelToken: cancelToken,
        );
        if (suggestions == null || !mounted) return;
        // 请求已结束：先收起进度条，再进行用户交互
        setState(() => _aiRequesting = false);
        if (_targetChanged(target, targetStart, targetEnd)) {
          _showAiSnack('正文已变化，请重新请求');
          return;
        }
        final selected = await showTagSuggestionsSheet(
          context: context,
          existingTags: existingTags.map((t) => t.name).toList(),
          suggestions: suggestions,
        );
        if (selected == null || !mounted) return;
        final updated = insertSelectedTags(target, selected);
        _replaceTarget(updated, targetStart, targetEnd, target);
      } else {
        final segments = await _requestPolish(
          gateway: gateway,
          selection: selection,
          target: target,
          isDeepSeek: isDeepSeek,
          cancelToken: cancelToken,
        );
        if (segments == null || !mounted) return;
        // 请求已结束：先收起进度条，再进行用户交互
        setState(() => _aiRequesting = false);
        // 深度润色的结构变化确认与 DeepSeek 隐私确认分别执行
        if (selection.type == AiActionType.polishDeep) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('深度润色'),
              content: const Text('深度润色可能调整段落结构和措辞，请在预览中逐段核对后再应用。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('继续'),
                ),
              ],
            ),
          );
          if (confirmed != true || !mounted) return;
        }
        if (_targetChanged(target, targetStart, targetEnd)) {
          _showAiSnack('正文已变化，请重新请求');
          return;
        }
        final result = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PolishPreviewPage(original: target, segments: segments),
          ),
        );
        if (result == null || !mounted) return;
        _replaceTarget(result, targetStart, targetEnd, target);
      }
    } finally {
      _aiCancelToken = null;
      if (mounted) setState(() => _aiRequesting = false);
    }
  }

  /// 请求标签建议；取消或失败返回 null。
  Future<List<AiTagSuggestion>?> _requestSuggestTags({
    required AiGateway gateway,
    required String target,
    required List<AiExistingTag> existingTags,
    required bool isDeepSeek,
    required CancelToken cancelToken,
  }) async {
    try {
      return await gateway.suggestTags(
        content: target,
        existingTags: existingTags,
        provider: isDeepSeek ? AiProvider.deepSeek : AiProvider.local,
        cloudConsent: isDeepSeek,
        cancelToken: cancelToken,
      );
    } on AiRequestCancelled {
      return null;
    } on AiApiException catch (e) {
      if (mounted) _showAiSnack(e.message);
      return null;
    }
  }

  /// 请求润色片段；取消或失败返回 null。
  Future<List<AiPolishSegment>?> _requestPolish({
    required AiGateway gateway,
    required AiActionSelection selection,
    required String target,
    required bool isDeepSeek,
    required CancelToken cancelToken,
  }) async {
    final mode = switch (selection.type) {
      AiActionType.polishLight => PolishMode.light,
      AiActionType.polishMedium => PolishMode.medium,
      AiActionType.polishDeep => PolishMode.deep,
      AiActionType.polishFormatOnly => PolishMode.formatOnly,
      AiActionType.suggestTags => PolishMode.light,
    };
    try {
      return await gateway.polish(
        content: target,
        mode: mode,
        provider: isDeepSeek ? AiProvider.deepSeek : AiProvider.local,
        cloudConsent: isDeepSeek,
        cancelToken: cancelToken,
      );
    } on AiRequestCancelled {
      return null;
    } on AiApiException catch (e) {
      if (mounted) _showAiSnack(e.message);
      return null;
    }
  }

  /// 校验当前正文的目标区域是否仍等于请求时的快照。
  bool _targetChanged(String snapshot, int start, int end) {
    final current = _contentCtrl.text;
    if (current.length < end) return true;
    return current.substring(start, end) != snapshot;
  }

  /// 用 [replacement] 替换目标区域（不保存、不同步）。
  void _replaceTarget(String replacement, int start, int end, String expected) {
    final current = _contentCtrl.text;
    if (current.length < end || current.substring(start, end) != expected) {
      _showAiSnack('正文已变化，请重新请求');
      return;
    }
    final updated = current.replaceRange(start, end, replacement);
    _contentCtrl.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  void _showAiSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 编辑器内选择事件串。取消勾选不会移除已有归属，避免误操作。
  /// 后台超时锁定时清空输入并退出。
  ///
  /// 不做这件事的话，编辑器会继续持有明文，且此时点保存会走到已经没有主密钥的
  /// 存储层（VaultStorage._requireKey() 抛 StateError）。
  void _onLockChanged() {
    if (!VaultController.instance.isUnlocked && mounted) {
      _contentCtrl.clear();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// 进后台立即加密保存。
  ///
  /// 发生在 60 秒锁定**之前**，密钥还在，所以之后的锁定是无损的。
  /// 不能改成"锁定那一刻抢救保存"——lock() 先清密钥再广播，那时已写不进去。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused) return;
    if (!VaultController.instance.isUnlocked) return;
    if (_contentCtrl.text.trim().isEmpty && _pendingAttachments.isEmpty) return;
    unawaited(_persist());
  }

  /// 实际写入 vault。手动保存与进后台自动保存共用。
  Future<void> _persist() async {
    // 先把本次新加的附件字节存进 vault 附件包
    for (final att in _pendingAttachments) {
      await VaultController.instance.addAttachment(att);
    }

    final keptExisting = (widget.existing?.attachmentIds ?? const <String>[])
        .where((id) => !_removedAttachmentIds.contains(id));
    final attachmentIds = <String>{
      ...keptExisting,
      ..._pendingAttachments.map((a) => a.id),
    }.toList();

    final now = DateTime.now();
    final locationText = _locationCtrl.text.trim();
    final existing = widget.existing;
    final entry = existing != null
        ? (existing
            ..content = _contentCtrl.text
            ..attachmentIds = attachmentIds
            ..location = locationText.isEmpty ? null : locationText
            ..latitude = _locationInfo?.latitude
            ..longitude = _locationInfo?.longitude
            ..weatherJson = _weatherInfo?.toJsonString()
            ..mood = _mood)
        : VaultEntry(
            id: _workingId ??= const Uuid().v4(),
            content: _contentCtrl.text,
            createdAt: _workingCreatedAt ??= _selectedDateTime,
            updatedAt: now,
            tags: const [],
            attachmentIds: attachmentIds,
            location: locationText.isEmpty ? null : locationText,
            latitude: _locationInfo?.latitude,
            longitude: _locationInfo?.longitude,
            weatherJson: _weatherInfo?.toJsonString(),
            mood: _mood,
          );
    await VaultController.instance.saveEntry(entry);

    // 保存成功后才真正丢弃被移除的附件，取消编辑不会误删
    for (final id in _removedAttachmentIds) {
      await VaultController.instance.storage.removeAttachment(id);
    }
    _removedAttachmentIds.clear();
  }

  Future<void> _save() async {
    if (!VaultController.instance.isUnlocked) {
      // 保存途中刚好被后台超时锁掉：直接退出，不尝试写入。
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    final content = _contentCtrl.text.trim();
    if (content.isEmpty && _pendingAttachments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.editorEmptyWarning)),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _persist();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[VaultEditor] 保存失败：$e');
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
      bottomNavigationBar: _aiRequesting
          ? _AiRequestProgressBar(
              onCancel: () {
                _aiCancelToken?.cancel();
                // 请求可能在后台继续挂起，立即收起进度条
                if (mounted) setState(() => _aiRequesting = false);
              },
            )
          : null,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        // 关闭按钮（取消编辑，直接返回）
        leading: IconButton(
          icon: const Icon(Icons.close),
          // 不走草稿保存：草稿会把正文明文写进 SharedPreferences。
          // 未保存内容由「进后台自动加密保存」兜底。
          onPressed: () => Navigator.pop(context),
          tooltip: AppStrings.cancel,
        ),
        title: Text(
          _isEditing ? AppStrings.editorEditTitle : AppStrings.editorNewTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          if (_aiAvailable)
            IconButton(
              key: const Key('memo-editor-ai-action'),
              icon: const Icon(Icons.auto_awesome_outlined),
              tooltip: 'AI 助手',
              onPressed: _aiRequesting ? null : _showAiActions,
            ),
        ],
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
                            final pos = sel.isValid
                                ? sel.baseOffset
                                : ctrl.text.length;
                            final newText =
                                ctrl.text.substring(0, pos) +
                                '# ' +
                                ctrl.text.substring(pos);
                            ctrl.value = TextEditingValue(
                              text: newText,
                              selection: TextSelection.collapsed(
                                offset: pos + 1,
                              ),
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
                            final pos = sel.isValid
                                ? sel.baseOffset
                                : ctrl.text.length;
                            final newText =
                                ctrl.text.substring(0, pos) +
                                ts +
                                ctrl.text.substring(pos);
                            ctrl.value = TextEditingValue(
                              text: newText,
                              selection: TextSelection.collapsed(
                                offset: pos + ts.length,
                              ),
                            );
                            _contentFocus.requestFocus();
                          },
                        ),
                        _FmtButton(
                          icon: Icons.format_bold,
                          tooltip: '加粗',
                          onTap: () => _wrapSelection('**', '**'),
                        ),
                        _FmtButton(
                          icon: Icons.format_italic,
                          tooltip: '斜体',
                          onTap: () => _wrapSelection('*', '*'),
                        ),
                        _FmtButton(
                          icon: Icons.code,
                          tooltip: '代码',
                          onTap: () => _wrapSelection('`', '`'),
                        ),
                        _FmtButton(
                          icon: Icons.format_list_numbered,
                          tooltip: '有序列表',
                          onTap: _insertOrderedList,
                        ),
                        _FmtButton(
                          icon: Icons.format_list_bulleted,
                          tooltip: '无序列表',
                          onTap: _insertUnorderedList,
                        ),
                        _FmtButton(
                          icon: Icons.check_box_outline_blank,
                          tooltip: 'Todo',
                          onTap: _insertTodo,
                        ),
                        const SizedBox(width: 8),
                        // 日期时间
                        GestureDetector(
                          onTap: _pickDateTime,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.access_time_outlined,
                                size: 15,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _dateTimeLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.stop_circle_outlined,
                                        size: 20,
                                        color: Colors.red,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _recordLabel,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.red,
                                          fontFeatures: [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.mic_outlined),
                                color: Colors.grey[600],
                                iconSize: 22,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                tooltip: '录音',
                                onPressed: _uploading ? null : _toggleRecording,
                              ),
                        if (_isMobile)
                          IconButton(
                            icon: const Icon(Icons.camera_alt_outlined),
                            color: Colors.grey[600],
                            iconSize: 22,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            tooltip: '拍照',
                            onPressed: _uploading ? null : _takePhoto,
                          ),
                        _uploading
                            ? const SizedBox(
                                width: 36,
                                height: 36,
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.attach_file),
                                color: Colors.grey[600],
                                iconSize: 22,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                tooltip: '添加附件',
                                onPressed: _pickAttachment,
                              ),
                        // 位置图标
                        IconButton(
                          key: const Key('memo-editor-location-action'),
                          icon: Icon(
                            _hasLocation
                                ? Icons.location_on
                                : Icons.location_on_outlined,
                          ),
                          color: _hasLocation
                              ? AppColors.primary
                              : Colors.grey[600],
                          iconSize: 22,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          tooltip: '位置',
                          onPressed: _openLocationSheet,
                        ),
                        // 天气按钮
                        _weatherInfo != null
                            ? GestureDetector(
                                key: const Key('memo-editor-weather-action'),
                                onTap: _openWeatherSheet,
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _weatherInfo!.condition.isEmpty
                                        ? '天气'
                                        : _weatherInfo!.condition,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              )
                            : IconButton(
                                key: const Key('memo-editor-weather-action'),
                                icon: const Icon(Icons.wb_sunny_outlined),
                                color: Colors.grey[600],
                                iconSize: 22,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                tooltip: '获取天气',
                                onPressed: _openWeatherSheet,
                              ),
                        // 心情按钮
                        IconButton(
                          icon: Icon(
                            moodByKey(_mood)?.icon ??
                                Icons.emoji_emotions_outlined,
                          ),
                          color: moodByKey(_mood)?.color ?? Colors.grey[600],
                          iconSize: 22,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          tooltip: '选择心情',
                          onPressed: _pickMood,
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
                                        child: Text(
                                          _locationDisplayText,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.primary,
                                            decoration:
                                                TextDecoration.underline,
                                            decorationColor: AppColors.primary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () => setState(() {
                                          _locationRevision++;
                                          _locationInfo = null;
                                          _locationCtrl.clear();
                                        }),
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : SizedBox(
                                  height: 24,
                                  child: TextField(
                                    controller: _locationCtrl,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                    decoration: InputDecoration(
                                      hintText: _isMobile
                                          ? '位置'
                                          : AppStrings.editorLocationHint,
                                      hintStyle: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[400],
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onChanged: (_) {
                                      setState(() => _locationRevision++);
                                    },
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
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            : TextButton(
                                onPressed: _save,
                                style: TextButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  AppStrings.save,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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
/// 待保存附件横条：缩略图 + 右上角删除角标。
///
/// 与主库版本的区别：渲染的是内存字节（[VaultAttachment.bytes]），
/// 不读本地文件也不拉远端 URL——隐私空间的附件不落盘。
class _AttachmentBar extends StatelessWidget {
  final List<VaultAttachment> attachments;
  final ValueChanged<VaultAttachment> onRemove;

  const _AttachmentBar({required this.attachments, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) =>
            _AttachThumb(attachment: attachments[i], onRemove: onRemove),
      ),
    );
  }
}

class _AttachThumb extends StatelessWidget {
  final VaultAttachment attachment;
  final ValueChanged<VaultAttachment> onRemove;

  const _AttachThumb({required this.attachment, required this.onRemove});

  bool get _isImage => attachment.mimeType.startsWith('image/');
  bool get _isAudio => attachment.mimeType.startsWith('audio/');

  void _preview(BuildContext context) {
    if (!_isImage) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) => ImageViewerPage(
          images: [
            GridImageSource(
              build:
                  ({
                    double? width,
                    double? height,
                    BoxFit fit = BoxFit.cover,
                  }) => Image.memory(
                    attachment.bytes,
                    width: width,
                    height: height,
                    fit: fit,
                  ),
              // 隐私空间禁用导出：保存到相册等于把私密照片写进公共图库
              onExport: null,
            ),
          ],
          initialIndex: 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _preview(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 64,
              height: 64,
              child: _isImage
                  ? Image.memory(attachment.bytes, fit: BoxFit.cover)
                  : ColoredBox(
                      color: AppColors.primaryLight,
                      child: Icon(
                        _isAudio ? Icons.mic : Icons.insert_drive_file_outlined,
                        color: AppColors.primaryDark,
                      ),
                    ),
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => onRemove(attachment),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

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
        color: AppColors.surface(context),
        border: Border(left: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: suggestions.isEmpty
          ? Center(
              child: Text(
                '暂无标签',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
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
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '#${tag.name}',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.onPrimarySoft(context),
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${tag.count}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
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

// ── 位置设置底部弹窗 ────────────────────────────────────────────────

/// 位置设置结果：仅覆盖明确修改过的字段，清除操作单独标记
class _LocationSheetResult {
  final double? latitude;
  final double? longitude;
  final String? name;
  final bool coordinatesChanged;
  final bool nameChanged;
  final bool clearAll;

  const _LocationSheetResult({
    this.latitude,
    this.longitude,
    this.name,
    this.coordinatesChanged = false,
    this.nameChanged = false,
    this.clearAll = false,
  });
}

class _LocationSheet extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  final String name;

  const _LocationSheet({this.latitude, this.longitude, this.name = ''});

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  late final TextEditingController _coordsCtrl;
  late final TextEditingController _nameCtrl;

  /// 是否正在自动获取经纬度
  bool _gettingCoords = false;

  /// 是否正在反查位置名称
  bool _gettingName = false;

  /// 用户或自动操作是否实际修改过对应字段
  bool _coordinatesChanged = false;
  bool _nameChanged = false;

  /// 输入版本号，确保后发的手动输入不会被较早的异步结果覆盖
  int _coordinatesInputRevision = 0;
  int _nameInputRevision = 0;

  /// 弹窗内的错误提示（避免被底部弹窗遮挡的 SnackBar）
  String? _message;

  void _showMessage(String message) {
    if (mounted) setState(() => _message = message);
  }

  @override
  void initState() {
    super.initState();
    // 经纬度显示格式：经度, 纬度
    final lng = widget.longitude;
    final lat = widget.latitude;
    _coordsCtrl = TextEditingController(
      text: (lat == null || lng == null)
          ? ''
          : '${lng.toStringAsFixed(5)}, ${lat.toStringAsFixed(5)}',
    );
    _nameCtrl = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _coordsCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  /// 解析"经度, 纬度"文本框 → (纬度, 经度)，格式错误返回 null
  (double?, double?) _parseCoords(String text) {
    final parts = text
        .replaceAll('，', ',')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length != 2) return (null, null);
    final lng = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lat == null || lng == null) return (null, null);
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return (null, null);
    }
    return (lat, lng);
  }

  /// 自动获取经纬度（GPS，离线可用）
  Future<void> _autoGetCoords() async {
    if (_gettingCoords) return;
    final revision = _coordinatesInputRevision;
    setState(() {
      _gettingCoords = true;
      _message = null;
    });
    try {
      final (lat, lng) = await LocationService.getCoordinates();
      if (mounted && revision == _coordinatesInputRevision) {
        setState(() {
          _coordsCtrl.text =
              '${lng.toStringAsFixed(5)}, ${lat.toStringAsFixed(5)}';
          _coordinatesChanged = true;
          _coordinatesInputRevision++;
          _gettingCoords = false;
        });
      } else if (mounted) {
        setState(() => _gettingCoords = false);
      }
    } on LocationException catch (e) {
      if (mounted) {
        setState(() => _gettingCoords = false);
        _showMessage(e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _gettingCoords = false);
        _showMessage('获取经纬度失败：$e');
      }
    }
  }

  /// 用当前经纬度反查位置名称（需网络）
  Future<void> _autoGetName() async {
    if (_gettingName) return;
    final (lat, lng) = _parseCoords(_coordsCtrl.text);
    if (lat == null || lng == null) {
      _showMessage('请先获取或填写有效的经纬度');
      return;
    }
    final revision = _nameInputRevision;
    setState(() {
      _gettingName = true;
      _message = null;
    });
    try {
      final address = await LocationService.reverseGeocode(lat, lng);
      if (mounted && revision == _nameInputRevision) {
        if (address != null && address.isNotEmpty) {
          setState(() {
            _gettingName = false;
            _nameCtrl.text = address;
            _nameChanged = true;
            _nameInputRevision++;
          });
        } else {
          setState(() => _gettingName = false);
          _showMessage('获取位置名称失败，请检查网络后重试');
        }
      } else if (mounted) {
        setState(() => _gettingName = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _gettingName = false);
        _showMessage('获取位置名称失败：$e');
      }
    }
  }

  void _confirm() {
    final (lat, lng) = _parseCoords(_coordsCtrl.text);
    final coordsEmpty = _coordsCtrl.text.trim().isEmpty;
    if (_coordinatesChanged && coordsEmpty) {
      _showMessage('经纬度不能为空；如需删除位置，请点击“清除”');
      return;
    }
    if (_coordinatesChanged && (lat == null || lng == null)) {
      _showMessage('经纬度格式或范围错误，应为“经度, 纬度”，如 113.93, 22.54');
      return;
    }
    final name = _nameCtrl.text.trim();
    if (_nameChanged && name.isEmpty && widget.name.trim().isNotEmpty) {
      _showMessage('位置名称不能为空；如需删除位置，请点击“清除”');
      return;
    }
    Navigator.pop(
      context,
      _LocationSheetResult(
        latitude: _coordinatesChanged ? lat : null,
        longitude: _coordinatesChanged ? lng : null,
        name: _nameChanged ? name : null,
        coordinatesChanged: _coordinatesChanged,
        nameChanged: _nameChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  '位置设置',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),

              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(
                  _message!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const Key('location-coordinates-field'),
                controller: _coordsCtrl,
                decoration: const InputDecoration(
                  labelText: '经纬度',
                  hintText: '经度, 纬度，如 113.93, 22.54',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.text,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,，\s]')),
                ],
                onChanged: (_) {
                  _coordinatesChanged = true;
                  _coordinatesInputRevision++;
                },
              ),

              const SizedBox(height: 16),
              // 自动获取经纬度
              FilledButton.tonalIcon(
                onPressed: _gettingCoords ? null : _autoGetCoords,
                icon: _gettingCoords
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, size: 20),
                label: Text(_gettingCoords ? '定位中...' : '自动获取经纬度'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('location-name-field'),
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '位置名称',
                  hintText: '暂无，可点击上方"获取位置名称"补充',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) {
                  _nameChanged = true;
                  _nameInputRevision++;
                },
              ),
              const SizedBox(height: 8),
              // 获取位置名称
              FilledButton.tonalIcon(
                onPressed: _gettingName ? null : _autoGetName,
                icon: _gettingName
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.place_outlined, size: 20),
                label: Text(_gettingName ? '查询中...' : '获取位置名称'),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        const _LocationSheetResult(clearAll: true),
                      );
                    },
                    child: const Text(
                      '清除',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _confirm, child: const Text('确定')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 天气设置底部弹窗 ────────────────────────────────────────────────

/// 天气设置结果：仅覆盖明确修改过的字段，清除操作单独标记
class _WeatherSheetResult {
  final String? condition;
  final String? detail;
  final bool conditionChanged;
  final bool detailChanged;
  final bool clearAll;

  const _WeatherSheetResult({
    this.condition,
    this.detail,
    this.conditionChanged = false,
    this.detailChanged = false,
    this.clearAll = false,
  });
}

class _WeatherSheet extends StatefulWidget {
  final WeatherInfo? current;
  final LocationInfo? location;
  final bool canAutoLocate;

  const _WeatherSheet({
    this.current,
    this.location,
    required this.canAutoLocate,
  });

  @override
  State<_WeatherSheet> createState() => _WeatherSheetState();
}

class _WeatherSheetState extends State<_WeatherSheet> {
  /// 当前选中的天气状况（如"晴"），null 表示未选择
  String? _condition;

  late final TextEditingController _detailCtrl;
  late final TextEditingController _cityCtrl;
  List<String> _favCities = [];

  /// 是否正在自动获取
  bool _fetchingAuto = false;

  /// 是否正在按城市获取
  bool _fetchingCity = false;

  /// 用户或自动操作是否实际修改过对应字段
  bool _conditionChanged = false;
  bool _detailChanged = false;

  /// 输入版本号，确保较早的异步结果不会覆盖后发的手动输入
  int _conditionInputRevision = 0;
  int _detailInputRevision = 0;

  bool get _fetching => _fetchingAuto || _fetchingCity;

  /// 弹窗内的错误提示（避免被底部弹窗遮挡的 SnackBar）
  String? _message;

  void _showMessage(String message) {
    if (mounted) setState(() => _message = message);
  }

  @override
  void initState() {
    super.initState();
    _condition = widget.current?.condition;
    _detailCtrl = TextEditingController(text: widget.current?.detail ?? '');
    _cityCtrl = TextEditingController();
    SettingsService.favoriteCities.then((cities) {
      if (mounted) setState(() => _favCities = cities);
    });
  }

  @override
  void dispose() {
    _detailCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  /// 自动获取天气：优先用当前定位，没有则先 GPS 定位（移动端）
  Future<void> _autoFetch() async {
    if (_fetching) return;
    final conditionRevision = _conditionInputRevision;
    final detailRevision = _detailInputRevision;
    setState(() {
      _fetchingAuto = true;
      _message = null;
    });
    try {
      var located = widget.location;
      if (located == null && widget.canAutoLocate) {
        try {
          final (lat, lng) = await LocationService.getCoordinates();
          located = LocationInfo(latitude: lat, longitude: lng);
        } catch (_) {}
      }
      WeatherInfo? info;
      if (located != null) {
        info = await WeatherService.fetchWeatherByCoords(
          latitude: located.latitude,
          longitude: located.longitude,
        );
      }
      if (mounted) {
        if (info != null) {
          final fetched = info;
          setState(() {
            _fetchingAuto = false;
            if (conditionRevision == _conditionInputRevision) {
              _condition = fetched.condition;
              _conditionChanged = true;
              _conditionInputRevision++;
            }
            if (detailRevision == _detailInputRevision) {
              _detailCtrl.text = fetched.detail;
              _detailChanged = true;
              _detailInputRevision++;
            }
          });
        } else {
          setState(() => _fetchingAuto = false);
          _showMessage('获取天气失败，请检查网络或 API Key');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _fetchingAuto = false);
        _showMessage('获取天气失败：$e');
      }
    }
  }

  /// 按城市名获取天气，成功后回填选择与描述
  Future<void> _fetchByCity() async {
    final city = _cityCtrl.text.trim();
    if (city.isEmpty || _fetching) return;
    final conditionRevision = _conditionInputRevision;
    final detailRevision = _detailInputRevision;
    setState(() {
      _fetchingCity = true;
      _message = null;
    });
    try {
      final info = await WeatherService.fetchWeatherByCity(city);
      if (mounted) {
        if (info != null) {
          setState(() {
            _fetchingCity = false;
            if (conditionRevision == _conditionInputRevision) {
              _condition = info.condition;
              _conditionChanged = true;
              _conditionInputRevision++;
            }
            if (detailRevision == _detailInputRevision) {
              _detailCtrl.text = info.detail;
              _detailChanged = true;
              _detailInputRevision++;
            }
          });
        } else {
          setState(() => _fetchingCity = false);
          _showMessage('未找到"$city"的天气，请检查城市名或 API Key');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _fetchingCity = false);
        _showMessage('获取天气失败：$e');
      }
    }
  }

  void _confirm() {
    Navigator.pop(
      context,
      _WeatherSheetResult(
        condition: _conditionChanged ? _condition : null,
        detail: _detailChanged ? _detailCtrl.text.trim() : null,
        conditionChanged: _conditionChanged,
        detailChanged: _detailChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                '天气设置',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            // 自动获取（按位置）
            FilledButton.tonalIcon(
              onPressed: _fetching ? null : _autoFetch,
              icon: _fetchingAuto
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wb_sunny_outlined, size: 20),
              label: Text(_fetchingAuto ? '获取中...' : '自动获取（按位置）'),
            ),
            const SizedBox(height: 8),
            // 按城市获取
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityCtrl,
                    decoration: const InputDecoration(
                      hintText: '输入城市名，如：深圳',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _fetchByCity(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _fetching ? null : _fetchByCity,
                  child: _fetchingCity
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('按城市获取'),
                ),
              ],
            ),
            if (_favCities.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _favCities
                    .map(
                      (city) => GestureDetector(
                        onTap: () {
                          _cityCtrl.text = city;
                          _fetchByCity();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft(context),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            city,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.onPrimarySoft(context),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(
                _message!,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
            const SizedBox(height: 16),
            const Text('手动选择天气', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            // 手动选择天气：横向滚动单选，不换行
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    <String>{
                      if (_condition != null && _condition!.isNotEmpty)
                        _condition!,
                      ...kIntToWeatherCondition.values,
                    }.map((condition) {
                      final selected = _condition == condition;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _condition = selected ? null : condition;
                            _conditionChanged = true;
                            _conditionInputRevision++;
                          }),
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primarySoft(context)
                                  : AppColors.codeSurface(context),
                              borderRadius: BorderRadius.circular(16),
                              border: selected
                                  ? Border.all(
                                      color: AppColors.primary,
                                      width: 1.5,
                                    )
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              condition,
                              style: TextStyle(
                                fontSize: 13,
                                color: selected
                                    ? AppColors.onPrimarySoft(context)
                                    : Colors.grey[700],
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('weather-detail-field'),
              controller: _detailCtrl,
              decoration: const InputDecoration(
                labelText: '天气描述',
                hintText: '如：晴，25°C，微风',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) {
                _detailChanged = true;
                _detailInputRevision++;
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      const _WeatherSheetResult(clearAll: true),
                    );
                  },
                  child: const Text('清除', style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _confirm, child: const Text('确定')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 心情选择底部弹窗 ────────────────────────────────────────────────

class _MoodPickerSheet extends StatelessWidget {
  final String? selectedKey;

  const _MoodPickerSheet({this.selectedKey});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '选择心情',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (selectedKey != null)
                  TextButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: const Text(
                      '清除',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kMoodOptions.map((opt) {
                final selected = opt.key == selectedKey;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, opt.key),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primarySoft(context)
                          : AppColors.codeSurface(context),
                      borderRadius: BorderRadius.circular(18),
                      border: selected
                          ? Border.all(color: AppColors.primary, width: 1.5)
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          opt.icon,
                          size: 18,
                          color: selected
                              ? opt.color
                              : opt.color.withAlpha(180),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          opt.label,
                          style: TextStyle(
                            fontSize: 13,
                            color: selected
                                ? AppColors.onPrimarySoft(context)
                                : Colors.grey[700],
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// AI 请求期间页面底部的非模态进度条。
///
/// 不拦截编辑器交互，请求期间正文仍可编辑；提供取消按钮。
class _AiRequestProgressBar extends StatelessWidget {
  final VoidCallback onCancel;

  const _AiRequestProgressBar({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface(context),
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(minHeight: 2.5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('AI 处理中...', style: TextStyle(fontSize: 13)),
                  ),
                  TextButton(onPressed: onCancel, child: const Text('取消')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
