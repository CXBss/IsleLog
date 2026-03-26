import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用配置持久化服务（SharedPreferences）
///
/// 存储以下配置项：
/// - [serverUrl]：Memos 服务器地址（自动去除末尾斜杠）
/// - [accessToken]：API 鉴权 Token
/// - [lastSyncTime]：上次成功同步的 UTC 时间
///
/// 所有方法均为静态方法，纯函数风格，无需实例化。
class SettingsService {
  SettingsService._();

  // SharedPreferences 键名常量
  static const _keyServerUrl = 'memos_server_url';
  static const _keyAccessToken = 'memos_access_token';
  static const _keyLastSyncTime = 'memos_last_sync_time';

  /// 获取 SharedPreferences 实例（每次调用都会从缓存中取，开销极低）
  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  // ── Server URL ────────────────────────────────────────────────

  /// 获取已保存的服务器地址（未设置时返回 null）
  static Future<String?> get serverUrl async =>
      (await _prefs).getString(_keyServerUrl);

  /// 保存服务器地址
  ///
  /// 自动去除末尾斜杠（如 "https://example.com/" → "https://example.com"），
  /// 保证拼接 API 路径时不出现双斜杠。
  static Future<void> setServerUrl(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    debugPrint('[Settings] setServerUrl: $normalized');
    await (await _prefs).setString(_keyServerUrl, normalized);
  }

  // ── Access Token ──────────────────────────────────────────────

  /// 获取已保存的 Access Token（未设置时返回 null）
  static Future<String?> get accessToken async =>
      (await _prefs).getString(_keyAccessToken);

  /// 保存 Access Token（自动去除首尾空白）
  static Future<void> setAccessToken(String token) async {
    debugPrint('[Settings] setAccessToken: [已隐藏]');
    await (await _prefs).setString(_keyAccessToken, token.trim());
  }

  // ── Last Sync Time ────────────────────────────────────────────

  /// 获取上次同步时间（已转为本地时间；未同步过时返回 null）
  static Future<DateTime?> get lastSyncTime async {
    final str = (await _prefs).getString(_keyLastSyncTime);
    if (str == null) return null;
    final time = DateTime.tryParse(str)?.toLocal();
    debugPrint('[Settings] lastSyncTime: $time');
    return time;
  }

  /// 保存上次同步时间（存储为 UTC ISO8601 字符串，读取时转回本地时区）
  static Future<void> setLastSyncTime(DateTime time) async {
    final utcStr = time.toUtc().toIso8601String();
    debugPrint('[Settings] setLastSyncTime: $utcStr');
    await (await _prefs).setString(_keyLastSyncTime, utcStr);
  }

  /// 清除上次同步时间（用于重置同步状态）
  static Future<void> clearLastSyncTime() async {
    debugPrint('[Settings] clearLastSyncTime');
    await (await _prefs).remove(_keyLastSyncTime);
  }

  // ── Draft ─────────────────────────────────────────────────────

  static const _keyDraftContent = 'draft_content';
  static const _keyDraftLocation = 'draft_location';

  static Future<String?> get draftContent async =>
      (await _prefs).getString(_keyDraftContent);

  static Future<String?> get draftLocation async =>
      (await _prefs).getString(_keyDraftLocation);

  static Future<void> saveDraft(String content, String location) async {
    final p = await _prefs;
    await p.setString(_keyDraftContent, content);
    await p.setString(_keyDraftLocation, location);
  }

  static Future<void> clearDraft() async {
    final p = await _prefs;
    await p.remove(_keyDraftContent);
    await p.remove(_keyDraftLocation);
  }

  // ── Helpers ───────────────────────────────────────────────────

  /// 是否已完整配置服务器（URL 和 Token 均非空才算已配置）
  ///
  /// 用于启动时判断是否需要自动同步，以及同步前的前置检查。
  static Future<bool> get isConfigured async {
    final url = await serverUrl;
    final token = await accessToken;
    final configured =
        (url?.isNotEmpty ?? false) && (token?.isNotEmpty ?? false);
    debugPrint('[Settings] isConfigured: $configured');
    return configured;
  }
}
