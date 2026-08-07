/// AI 编辑辅助的数据模型。
///
/// 与服务端 `service/ai` 的 JSON 契约一一对应，所有 `fromJson`
/// 在字段缺失或类型错误时抛出 [AiApiException]（"AI 返回的数据格式无效"）。
library;

/// AI 模型提供者。
enum AiProvider {
  /// 私有本地模型（llama.cpp 部署的 Qwen 等）。
  local,

  /// 云端 DeepSeek。
  deepSeek;

  /// 服务端 ProviderName 大写字符串。
  String get serverValue => switch (this) {
    AiProvider.local => 'LOCAL',
    AiProvider.deepSeek => 'DEEPSEEK',
  };

  static AiProvider fromServerValue(String value) => switch (value) {
    'LOCAL' => AiProvider.local,
    'DEEPSEEK' => AiProvider.deepSeek,
    _ => throw const AiApiException('AI 返回的数据格式无效'),
  };
}

/// 润色模式（与服务端 [PolishMode] 对应）。
enum PolishMode {
  /// 只修正病句和错别字。
  light,

  /// 保留原意，改善表达。
  medium,

  /// 允许较大结构和措辞调整。
  deep,

  /// 只调整空白与 Markdown 格式，不改文字。
  formatOnly;

  /// 服务端润色模式字符串。
  String get serverValue => switch (this) {
    PolishMode.light => 'LIGHT',
    PolishMode.medium => 'MEDIUM',
    PolishMode.deep => 'DEEP',
    PolishMode.formatOnly => 'FORMAT_ONLY',
  };
}

/// 已有标签及使用次数，供模型优先选择。
class AiExistingTag {
  final String name;
  final int count;

  const AiExistingTag({required this.name, required this.count});

  Map<String, dynamic> toJson() => {'name': name, 'count': count};
}

/// 一个标签建议。
class AiTagSuggestion {
  final String name;
  final bool isNew;
  final double confidence;
  final String reason;

  const AiTagSuggestion({
    required this.name,
    required this.isNew,
    required this.confidence,
    required this.reason,
  });

  factory AiTagSuggestion.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final isNew = json['isNew'];
    final confidence = json['confidence'];
    final reason = json['reason'];
    if (name is! String ||
        isNew is! bool ||
        confidence is! num ||
        reason is! String) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return AiTagSuggestion(
      name: name,
      isNew: isNew,
      confidence: confidence.toDouble(),
      reason: reason,
    );
  }
}

/// 一个润色输出片段及其来源段落索引。
class AiPolishSegment {
  final List<int> sourceIndexes;
  final String originalText;
  final String revisedText;
  final String reason;

  const AiPolishSegment({
    required this.sourceIndexes,
    required this.originalText,
    required this.revisedText,
    required this.reason,
  });

  factory AiPolishSegment.fromJson(Map<String, dynamic> json) {
    final sourceIndexes = json['sourceIndexes'];
    final originalText = json['originalText'];
    final revisedText = json['revisedText'];
    final reason = json['reason'];
    if (sourceIndexes is! List ||
        sourceIndexes.any((e) => e is! int) ||
        originalText is! String ||
        revisedText is! String ||
        reason is! String) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return AiPolishSegment(
      sourceIndexes: List<int>.from(sourceIndexes),
      originalText: originalText,
      revisedText: revisedText,
      reason: reason,
    );
  }
}

/// 模型提供者状态。
class AiProviderStatus {
  final AiProvider name;
  final bool enabled;
  final bool available;
  final String model;
  final int contextLength;
  final String? message;

  const AiProviderStatus({
    required this.name,
    required this.enabled,
    required this.available,
    required this.model,
    required this.contextLength,
    this.message,
  });

  factory AiProviderStatus.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final enabled = json['enabled'];
    final available = json['available'];
    final model = json['model'];
    final contextLength = json['contextLength'];
    final message = json['message'];
    if (name is! String ||
        enabled is! bool ||
        available is! bool ||
        model is! String ||
        contextLength is! int ||
        (message != null && message is! String)) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return AiProviderStatus(
      name: AiProvider.fromServerValue(name),
      enabled: enabled,
      available: available,
      model: model,
      contextLength: contextLength,
      message: message as String?,
    );
  }
}

/// AI 请求异常，message 来自服务端中文错误。
class AiApiException implements Exception {
  final String message;
  final int? statusCode;

  const AiApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// 用户主动取消 AI 请求。
class AiRequestCancelled implements Exception {
  const AiRequestCancelled();

  @override
  String toString() => 'AI 请求已取消';
}
