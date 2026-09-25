/// 用户自配模型（本地 / 任意 OpenAI 兼容云端）的数据模型。
///
/// 配置在客户端编辑、保存在服务端：夜间事件串分析和日记助手在服务端后台运行，
/// 客户端不在线时也要知道用哪个模型。API Key 只上传不回读，服务端只返回末 4 位。
library;

import 'ai_models.dart';

/// 模型种类：本地模型在 NAS 内推理；云端模型会把内容发往外部服务商。
enum AiProfileKind {
  local,
  cloud;

  String get serverValue => this == AiProfileKind.local ? 'LOCAL' : 'CLOUD';

  static AiProfileKind fromServerValue(Object? value) => switch (value) {
    'LOCAL' => AiProfileKind.local,
    'CLOUD' => AiProfileKind.cloud,
    _ => throw const AiApiException('AI 返回的数据格式无效'),
  };
}

/// 模型连通状态。
class AiProfileStatus {
  final bool available;
  final String? message;

  const AiProfileStatus({required this.available, this.message});
}

/// 一条模型配置。
class AiModelProfile {
  /// 资源名 `aiProfiles/{id}`。
  final String name;
  final AiProfileKind kind;
  final String displayName;
  final String baseUrl;
  final bool hasApiKey;

  /// Key 末 4 位，如 `…a3f9`。
  final String apiKeyHint;

  /// 服务端密钥更换后旧 Key 解不开，需要重新填写。
  final bool keyUnreadable;
  final String model;
  final int contextLength;
  final int timeoutSeconds;
  final int maxConcurrency;
  final bool jsonMode;
  final double? priceIn;
  final double? priceOut;

  /// 列表接口附带的健康状态；新建/修改接口不带。
  final AiProfileStatus? status;

  const AiModelProfile({
    required this.name,
    required this.kind,
    required this.displayName,
    required this.baseUrl,
    required this.hasApiKey,
    required this.apiKeyHint,
    required this.keyUnreadable,
    required this.model,
    required this.contextLength,
    required this.timeoutSeconds,
    required this.maxConcurrency,
    required this.jsonMode,
    this.priceIn,
    this.priceOut,
    this.status,
  });

  bool get isCloud => kind == AiProfileKind.cloud;

  factory AiModelProfile.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final displayName = json['displayName'];
    final baseUrl = json['baseUrl'];
    final model = json['model'];
    final contextLength = json['contextLength'];
    if (name is! String ||
        displayName is! String ||
        baseUrl is! String ||
        model is! String ||
        contextLength is! int) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    final status = json['status'];
    return AiModelProfile(
      name: name,
      kind: AiProfileKind.fromServerValue(json['kind']),
      displayName: displayName,
      baseUrl: baseUrl,
      hasApiKey: json['hasApiKey'] == true,
      apiKeyHint: json['apiKeyHint'] as String? ?? '',
      keyUnreadable: json['keyUnreadable'] == true,
      model: model,
      contextLength: contextLength,
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 120,
      maxConcurrency: json['maxConcurrency'] as int? ?? 1,
      jsonMode: json['jsonMode'] == true,
      priceIn: (json['priceIn'] as num?)?.toDouble(),
      priceOut: (json['priceOut'] as num?)?.toDouble(),
      status: status is Map<String, dynamic>
          ? AiProfileStatus(
              available: status['available'] == true,
              message: status['message'] as String?,
            )
          : null,
    );
  }
}

/// 模型配置列表 + 全局设置。
class AiProfileSettings {
  final List<AiModelProfile> profiles;

  /// 当前全局模型的资源名；没有任何配置时为 null。
  final String? activeProfile;

  /// 敏感标签（不带 #）：带这些标签的日记不会交给云端模型。
  final List<String> sensitiveTags;

  const AiProfileSettings({
    required this.profiles,
    required this.activeProfile,
    required this.sensitiveTags,
  });

  AiModelProfile? get active {
    for (final p in profiles) {
      if (p.name == activeProfile) return p;
    }
    return null;
  }

  factory AiProfileSettings.fromJson(Map<String, dynamic> json) {
    final profiles = json['profiles'];
    final tags = json['sensitiveTags'];
    if (profiles is! List || tags is! List) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return AiProfileSettings(
      profiles: profiles
          .map(
            (e) => e is Map<String, dynamic>
                ? AiModelProfile.fromJson(e)
                : throw const AiApiException('AI 返回的数据格式无效'),
          )
          .toList(),
      activeProfile: json['activeProfile'] as String?,
      sensitiveTags: tags.whereType<String>().toList(),
    );
  }
}

/// 新建或修改配置时提交的内容。修改时 [apiKey] 为 null 表示保持原 Key。
class AiProfileDraft {
  final AiProfileKind kind;
  final String displayName;
  final String baseUrl;
  final String? apiKey;
  final String model;
  final int contextLength;
  final int? timeoutSeconds;
  final int? maxConcurrency;
  final double? priceIn;
  final double? priceOut;

  const AiProfileDraft({
    required this.kind,
    required this.displayName,
    required this.baseUrl,
    this.apiKey,
    required this.model,
    required this.contextLength,
    this.timeoutSeconds,
    this.maxConcurrency,
    this.priceIn,
    this.priceOut,
  });

  Map<String, dynamic> toJson() => {
    'kind': kind.serverValue,
    'displayName': displayName,
    'baseUrl': baseUrl,
    if (apiKey != null) 'apiKey': apiKey,
    'model': model,
    'contextLength': contextLength,
    if (timeoutSeconds != null) 'timeoutSeconds': timeoutSeconds,
    if (maxConcurrency != null) 'maxConcurrency': maxConcurrency,
    if (priceIn != null) 'priceIn': priceIn,
    if (priceOut != null) 'priceOut': priceOut,
  };
}

/// 测试连接的结果。
class AiProfileTestResult {
  final bool ok;
  final int latencyMs;
  final bool jsonMode;
  final String? message;

  const AiProfileTestResult({
    required this.ok,
    required this.latencyMs,
    required this.jsonMode,
    this.message,
  });

  factory AiProfileTestResult.fromJson(Map<String, dynamic> json) =>
      AiProfileTestResult(
        ok: json['ok'] == true,
        latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 0,
        jsonMode: json['jsonMode'] == true,
        message: json['message'] as String?,
      );
}

/// 预设服务商：只用来自动填表单，所有字段都可以改。
class AiProviderPreset {
  final String label;
  final String baseUrl;

  /// 常见模型及其上下文长度，用来在选中模型时自动填上下文长度。
  final Map<String, int> contextLengths;

  const AiProviderPreset({
    required this.label,
    required this.baseUrl,
    this.contextLengths = const {},
  });

  static const custom = AiProviderPreset(label: '自定义', baseUrl: '');

  static const all = <AiProviderPreset>[
    AiProviderPreset(
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      contextLengths: {'deepseek-chat': 65536, 'deepseek-reasoner': 65536},
    ),
    AiProviderPreset(
      label: '阿里百炼',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      contextLengths: {
        'qwen-max': 32768,
        'qwen-plus': 131072,
        'qwen-turbo': 1000000,
      },
    ),
    AiProviderPreset(
      label: 'Kimi',
      baseUrl: 'https://api.moonshot.cn/v1',
      contextLengths: {
        'moonshot-v1-8k': 8192,
        'moonshot-v1-32k': 32768,
        'moonshot-v1-128k': 131072,
      },
    ),
    AiProviderPreset(
      label: '智谱',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      contextLengths: {'glm-4-plus': 131072, 'glm-4-air': 131072},
    ),
    AiProviderPreset(
      label: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
    ),
    AiProviderPreset(label: 'OpenAI', baseUrl: 'https://api.openai.com/v1'),
    custom,
  ];
}
