import 'package:flutter/foundation.dart';

import '../settings/settings_service.dart';
import 'ai_api_client.dart';
import 'ai_models.dart';

/// AI 能力检测与网关解析。
///
/// 缓存按服务器地址存储：只有明确 404（标准 Memos 服务端）才缓存 `false`；
/// 超时和断网不会把已有 `true` 覆盖为 `false`。
class AiService {
  /// 测试注入的网关；为 null 时从 [SettingsService] 创建真实客户端。
  final AiGateway? _gateway;

  AiService({AiGateway? gateway}) : _gateway = gateway;

  Future<AiGateway> _resolveGateway() async {
    final injected = _gateway;
    if (injected != null) return injected;
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      throw const AiApiException('尚未配置服务器');
    }
    return AiApiClient(baseUrl: url, token: token);
  }

  /// 探测当前服务器是否支持 AI 编辑辅助接口。
  ///
  /// 成功缓存 `true`，明确 404 缓存 `false`；网络错误不覆盖已有缓存。
  Future<bool> isCapabilityAvailable() async {
    final url = await SettingsService.serverUrl;
    if (url == null || url.isEmpty) return false;
    final cached = await SettingsService.aiCapabilityFor(url);

    final AiGateway gateway;
    try {
      gateway = await _resolveGateway();
    } on AiApiException catch (e) {
      debugPrint('[AI] 能力探测跳过：${e.message}');
      return cached ?? false;
    }

    try {
      await gateway.listProviders();
      await SettingsService.setAiCapability(url, true);
      return true;
    } on AiApiException catch (e) {
      if (e.statusCode == 404) {
        await SettingsService.setAiCapability(url, false);
        return false;
      }
      if (cached != null) return cached;
      return false;
    }
  }

  /// 创建用于实际 AI 操作的网关。
  Future<AiGateway> createGateway() => _resolveGateway();
}
