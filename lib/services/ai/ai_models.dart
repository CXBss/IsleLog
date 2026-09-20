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
  deepSeek,

  /// 本地 embedding 模型，只用于 [AiProviderStatus] 状态展示（记忆检索是否
  /// 可用），从不作为 `suggestTags`/`polish`/记忆检索问答的 `provider` 取值。
  localEmbedding;

  /// 服务端 ProviderName 大写字符串。
  String get serverValue => switch (this) {
    AiProvider.local => 'LOCAL',
    AiProvider.deepSeek => 'DEEPSEEK',
    AiProvider.localEmbedding => 'LOCAL_EMBEDDING',
  };

  static AiProvider fromServerValue(String value) => switch (value) {
    'LOCAL' => AiProvider.local,
    'DEEPSEEK' => AiProvider.deepSeek,
    'LOCAL_EMBEDDING' => AiProvider.localEmbedding,
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

  /// 这一段改写导致标签/链接/待办标记/日期/数值/代码块等受保护元素发生了变化。
  /// 服务端不会因此拒绝结果，只是标记出来——由用户在预览里自己判断要不要接受
  /// 这一段，不是错误状态。
  final bool protectedElementsChanged;

  const AiPolishSegment({
    required this.sourceIndexes,
    required this.originalText,
    required this.revisedText,
    required this.reason,
    this.protectedElementsChanged = false,
  });

  factory AiPolishSegment.fromJson(Map<String, dynamic> json) {
    final sourceIndexes = json['sourceIndexes'];
    final originalText = json['originalText'];
    final revisedText = json['revisedText'];
    final reason = json['reason'];
    final protectedElementsChanged = json['protectedElementsChanged'];
    if (sourceIndexes is! List ||
        sourceIndexes.any((e) => e is! int) ||
        originalText is! String ||
        revisedText is! String ||
        reason is! String ||
        (protectedElementsChanged != null && protectedElementsChanged is! bool)) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return AiPolishSegment(
      sourceIndexes: List<int>.from(sourceIndexes),
      originalText: originalText,
      revisedText: revisedText,
      reason: reason,
      protectedElementsChanged: protectedElementsChanged as bool? ?? false,
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

/// 记忆检索问答/相关记忆共用的一条来源日记。
class MemorySource {
  final String memo;
  final DateTime displayTime;
  final String snippet;
  final double similarity;

  const MemorySource({
    required this.memo,
    required this.displayTime,
    required this.snippet,
    required this.similarity,
  });

  factory MemorySource.fromJson(Map<String, dynamic> json) {
    final memo = json['memo'];
    final displayTime = json['displayTime'];
    final snippet = json['snippet'];
    final similarity = json['similarity'];
    if (memo is! String ||
        displayTime is! String ||
        snippet is! String ||
        similarity is! num) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    final parsedTime = DateTime.tryParse(displayTime);
    if (parsedTime == null) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return MemorySource(
      memo: memo,
      displayTime: parsedTime.toLocal(),
      snippet: snippet,
      similarity: similarity.toDouble(),
    );
  }
}

/// 自然语言记忆检索问答的结果。
///
/// [insufficientEvidence] 为 true 时 [answer]/[sources] 均为空——这是正常的
/// "没找到相关日记"结果，不是请求失败，调用方不应把它当错误处理。
class MemorySearchResult {
  final String answer;
  final bool insufficientEvidence;
  final List<MemorySource> sources;
  final bool indexIncomplete;

  const MemorySearchResult({
    required this.answer,
    required this.insufficientEvidence,
    required this.sources,
    required this.indexIncomplete,
  });

  factory MemorySearchResult.fromJson(Map<String, dynamic> json) {
    final answer = json['answer'];
    final insufficientEvidence = json['insufficientEvidence'];
    final sourcesRaw = json['sources'];
    final indexIncomplete = json['indexIncomplete'];
    if (answer is! String ||
        insufficientEvidence is! bool ||
        sourcesRaw is! List ||
        indexIncomplete is! bool) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return MemorySearchResult(
      answer: answer,
      insufficientEvidence: insufficientEvidence,
      sources: sourcesRaw
          .map(
            (e) => e is Map<String, dynamic>
                ? MemorySource.fromJson(e)
                : throw const AiApiException('AI 返回的数据格式无效'),
          )
          .toList(),
      indexIncomplete: indexIncomplete,
    );
  }
}

/// "相关记忆"接口返回的一条结果，比 [MemorySource] 多一个 [matchReason]。
class RelatedMemory {
  final String memo;
  final DateTime displayTime;
  final String snippet;
  final double similarity;
  final String matchReason;

  const RelatedMemory({
    required this.memo,
    required this.displayTime,
    required this.snippet,
    required this.similarity,
    required this.matchReason,
  });

  factory RelatedMemory.fromJson(Map<String, dynamic> json) {
    final memo = json['memo'];
    final displayTime = json['displayTime'];
    final snippet = json['snippet'];
    final similarity = json['similarity'];
    final matchReason = json['matchReason'];
    if (memo is! String ||
        displayTime is! String ||
        snippet is! String ||
        similarity is! num ||
        matchReason is! String) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    final parsedTime = DateTime.tryParse(displayTime);
    if (parsedTime == null) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return RelatedMemory(
      memo: memo,
      displayTime: parsedTime.toLocal(),
      snippet: snippet,
      similarity: similarity.toDouble(),
      matchReason: matchReason,
    );
  }
}

/// "相关记忆"接口的完整响应。[pending] 为 true 表示目标日记自己还没建好
/// 索引，应展示"正在分析"而不是误判为没有相关记忆。
class RelatedMemoriesResult {
  final List<RelatedMemory> relatedMemos;
  final bool pending;

  const RelatedMemoriesResult({required this.relatedMemos, required this.pending});

  factory RelatedMemoriesResult.fromJson(Map<String, dynamic> json) {
    final relatedMemosRaw = json['relatedMemos'];
    final pending = json['pending'];
    if (relatedMemosRaw is! List || pending is! bool) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return RelatedMemoriesResult(
      relatedMemos: relatedMemosRaw
          .map(
            (e) => e is Map<String, dynamic>
                ? RelatedMemory.fromJson(e)
                : throw const AiApiException('AI 返回的数据格式无效'),
          )
          .toList(),
      pending: pending,
    );
  }
}

/// "往年今日"AI 对照的"现在"部分。[available] 为 false 时
/// [summary]/[sources] 均为空——近期没有素材，不应展示这部分内容。
class OnThisDayNow {
  final bool available;
  final String summary;
  final List<String> sources;

  const OnThisDayNow({
    required this.available,
    required this.summary,
    required this.sources,
  });

  factory OnThisDayNow.fromJson(Map<String, dynamic> json) {
    final available = json['available'];
    if (available is! bool) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    if (!available) {
      return const OnThisDayNow(available: false, summary: '', sources: []);
    }
    final summary = json['summary'];
    final sourcesRaw = json['sources'];
    if (summary is! String || sourcesRaw is! List) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return OnThisDayNow(
      available: true,
      summary: summary,
      sources: sourcesRaw
          .map(
            (e) => e is String
                ? e
                : throw const AiApiException('AI 返回的数据格式无效'),
          )
          .toList(),
    );
  }
}

/// "往年今日"AI 对照的完整结果。
class OnThisDayCompareResult {
  final String pastSummary;
  final OnThisDayNow now;

  const OnThisDayCompareResult({required this.pastSummary, required this.now});

  factory OnThisDayCompareResult.fromJson(Map<String, dynamic> json) {
    final past = json['past'];
    final nowRaw = json['now'];
    if (past is! Map<String, dynamic> ||
        past['summary'] is! String ||
        nowRaw is! Map<String, dynamic>) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return OnThisDayCompareResult(
      pastSummary: past['summary'] as String,
      now: OnThisDayNow.fromJson(nowRaw),
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
