import 'dart:typed_data';

/// 隐私空间日记条目（不是 Isar collection，只存在于解密后的内存中）。
class VaultEntry {
  final String id;
  String content;
  final DateTime createdAt;
  DateTime updatedAt;
  List<String> tags;
  List<String> attachmentIds;
  String? memosName;
  final String? movedFromMemosName;

  /// 地址文本（与主库 MemoEntry.location 同义）
  String? location;

  /// 经纬度，与 location 配套，用于点击跳转地图
  double? latitude;
  double? longitude;

  /// 天气信息 JSON（与主库 MemoEntry.weatherJson 同格式）
  String? weatherJson;

  /// 心情标识（与主库 MemoEntry.mood 同义）
  String? mood;

  VaultEntry({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.tags,
    required this.attachmentIds,
    this.memosName,
    this.movedFromMemosName,
    this.location,
    this.latitude,
    this.longitude,
    this.weatherJson,
    this.mood,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'tags': tags,
    'attachmentIds': attachmentIds,
    'memosName': memosName,
    'movedFromMemosName': movedFromMemosName,
    'location': location,
    'latitude': latitude,
    'longitude': longitude,
    'weatherJson': weatherJson,
    'mood': mood,
  };

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
    id: json['id'] as String,
    content: json['content'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    tags: (json['tags'] as List).cast<String>(),
    attachmentIds: (json['attachmentIds'] as List).cast<String>(),
    memosName: json['memosName'] as String?,
    movedFromMemosName: json['movedFromMemosName'] as String?,
    // 这几个键是后加的，早期 vault 文件里没有——缺失一律读成 null
    location: json['location'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    weatherJson: json['weatherJson'] as String?,
    mood: json['mood'] as String?,
  );
}

/// 加密 body 的顶层结构。
///
/// 版本号和 revision 放在这里（密文内），不放明文文件头——
/// 明文头的固定字节会成为"这是个 vault 文件"的可识别特征。
class VaultBody {
  final int version;
  int revision;
  List<VaultEntry> entries;

  VaultBody({
    required this.version,
    required this.revision,
    required this.entries,
  });

  Map<String, dynamic> toJson() => {
    'v': version,
    'revision': revision,
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  /// 顶层字段取默认值兜底；条目字段严格解析（条目损坏时由调用方视为
  /// "这个文件打不开"，而不是带病运行）。
  factory VaultBody.fromJson(Map<String, dynamic> json) => VaultBody(
    version: json['v'] as int? ?? 1,
    revision: json['revision'] as int? ?? 0,
    entries: ((json['entries'] as List?) ?? const [])
        .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 隐私空间附件的原始字节 + 元数据。
///
/// 不复用主库的 [AttachmentInfo]——那个类围绕"本地路径 + 远端 URL"设计，
/// vault 附件只有加密前的原始字节，没有独立的本地文件路径。
class VaultAttachment {
  final String id;
  final String mimeType;
  final Uint8List bytes;

  const VaultAttachment({
    required this.id,
    required this.mimeType,
    required this.bytes,
  });
}
