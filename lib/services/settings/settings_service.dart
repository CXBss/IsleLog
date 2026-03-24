import 'package:shared_preferences/shared_preferences.dart';

/// 应用配置持久化（SharedPreferences）
///
/// 存储 Memos 服务器地址、Access Token 和上次同步时间。
class SettingsService {
  SettingsService._();

  static const _keyServerUrl = 'memos_server_url';
  static const _keyAccessToken = 'memos_access_token';
  static const _keyLastSyncTime = 'memos_last_sync_time';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  // ── Server URL ────────────────────────────────────────────────

  static Future<String?> get serverUrl async =>
      (await _prefs).getString(_keyServerUrl);

  static Future<void> setServerUrl(String url) async {
    // 去掉末尾斜杠，保持规范格式
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    await (await _prefs).setString(_keyServerUrl, normalized);
  }

  // ── Access Token ──────────────────────────────────────────────

  static Future<String?> get accessToken async =>
      (await _prefs).getString(_keyAccessToken);

  static Future<void> setAccessToken(String token) async =>
      (await _prefs).setString(_keyAccessToken, token.trim());

  // ── Last Sync Time ────────────────────────────────────────────

  static Future<DateTime?> get lastSyncTime async {
    final str = (await _prefs).getString(_keyLastSyncTime);
    return str == null ? null : DateTime.tryParse(str)?.toLocal();
  }

  static Future<void> setLastSyncTime(DateTime time) async =>
      (await _prefs).setString(
          _keyLastSyncTime, time.toUtc().toIso8601String());

  static Future<void> clearLastSyncTime() async =>
      (await _prefs).remove(_keyLastSyncTime);

  // ── Helpers ───────────────────────────────────────────────────

  /// 是否已配置服务器（有 URL 且有 Token）
  static Future<bool> get isConfigured async {
    final url = await serverUrl;
    final token = await accessToken;
    return (url?.isNotEmpty ?? false) && (token?.isNotEmpty ?? false);
  }
}
