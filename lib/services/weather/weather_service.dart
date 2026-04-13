import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/weather_info.dart';
import '../settings/settings_service.dart';

/// 天气服务
///
/// 优先和风天气（qweatherKey），失败或未配置则回退高德（amapKey）。
/// 缓存 key：城市标识符，30 分钟内不重复请求。
class WeatherService {
  WeatherService._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  static final Map<String, (WeatherInfo, DateTime)> _cache = {};
  static const _cacheDuration = Duration(minutes: 30);

  // ── 公开接口 ──────────────────────────────────────────────────────

  /// 通过 WGS84 坐标获取天气，优先和风，失败回退高德
  static Future<WeatherInfo?> fetchWeatherByCoords({
    required double latitude,
    required double longitude,
  }) async {
    final qkey = await SettingsService.qweatherKey;
    if (qkey != null && qkey.isNotEmpty) {
      final info = await _qweatherByCoords(latitude, longitude, qkey);
      if (info != null) return info;
      debugPrint('[WeatherService] 和风坐标获取失败，回退高德');
    }

    final amapKey = await SettingsService.amapKey;
    if (amapKey != null && amapKey.isNotEmpty) {
      return _amapByCoords(latitude, longitude, amapKey);
    }

    debugPrint('[WeatherService] 未配置任何天气 API Key');
    return null;
  }

  /// 通过城市名获取天气，优先和风，失败回退高德
  static Future<WeatherInfo?> fetchWeatherByCity(String cityName) async {
    final qkey = await SettingsService.qweatherKey;
    if (qkey != null && qkey.isNotEmpty) {
      final info = await _qweatherByCity(cityName, qkey);
      if (info != null) return info;
      debugPrint('[WeatherService] 和风城市获取失败，回退高德');
    }

    final amapKey = await SettingsService.amapKey;
    if (amapKey != null && amapKey.isNotEmpty) {
      return _amapByCity(cityName, amapKey);
    }

    debugPrint('[WeatherService] 未配置任何天气 API Key');
    return null;
  }

  // ── 和风天气 ──────────────────────────────────────────────────────

  /// 和风：WGS84 坐标直接查询（和风接受 WGS84，无需转换）
  static Future<WeatherInfo?> _qweatherByCoords(
      double lat, double lng, String key) async {
    final cacheKey = 'qw_${lat.toStringAsFixed(2)}_${lng.toStringAsFixed(2)}';
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.$2) < _cacheDuration) {
      return cached.$1;
    }
    try {
      final resp = await _dio.get(
        'https://devapi.qweather.com/v7/weather/now',
        queryParameters: {
          'location': '${lng.toStringAsFixed(4)},${lat.toStringAsFixed(4)}',
          'key': key,
          'lang': 'zh',
        },
      );
      final info = _parseQweather(resp.data);
      if (info != null) _cache[cacheKey] = (info, DateTime.now());
      return info;
    } catch (e) {
      debugPrint('[WeatherService] 和风坐标查询失败: $e');
      return null;
    }
  }

  /// 和风：城市名 → GeoAPI 获取 locationId → 天气
  static Future<WeatherInfo?> _qweatherByCity(String cityName, String key) async {
    final cacheKey = 'qw_city_$cityName';
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.$2) < _cacheDuration) {
      return cached.$1;
    }
    try {
      final geoResp = await _dio.get(
        'https://geoapi.qweather.com/v2/city/lookup',
        queryParameters: {'location': cityName, 'key': key, 'lang': 'zh'},
      );
      final geoData = geoResp.data as Map<String, dynamic>;
      if (geoData['code'] != '200') return null;
      final locations = geoData['location'] as List<dynamic>;
      if (locations.isEmpty) return null;

      final loc = locations[0] as Map<String, dynamic>;
      final locationId = loc['id'] as String? ?? '';
      final city = loc['name'] as String? ?? cityName;
      if (locationId.isEmpty) return null;

      final resp = await _dio.get(
        'https://devapi.qweather.com/v7/weather/now',
        queryParameters: {'location': locationId, 'key': key, 'lang': 'zh'},
      );
      final info = _parseQweather(resp.data, city: city);
      if (info != null) _cache[cacheKey] = (info, DateTime.now());
      return info;
    } catch (e) {
      debugPrint('[WeatherService] 和风城市查询失败: $e');
      return null;
    }
  }

  /// 解析和风 now 响应
  static WeatherInfo? _parseQweather(dynamic data, {String city = ''}) {
    try {
      final m = data as Map<String, dynamic>;
      if (m['code'] != '200') return null;
      final now = m['now'] as Map<String, dynamic>;
      final condition = now['text'] as String? ?? '';
      final temp = now['temp'] as String? ?? '';
      final feelsLike = now['feelsLike'] as String? ?? '';
      final windDir = now['windDir'] as String? ?? '';
      final windScale = now['windScale'] as String? ?? '';
      final humidity = now['humidity'] as String? ?? '';

      final detail = [
        if (city.isNotEmpty) city,
        condition,
        if (temp.isNotEmpty) '$temp°C',
        if (feelsLike.isNotEmpty && feelsLike != temp) '体感$feelsLike°C',
        if (windDir.isNotEmpty && windScale.isNotEmpty) '$windDir$windScale级',
        if (humidity.isNotEmpty) '湿度$humidity%',
      ].join('，');

      return WeatherInfo(condition: condition, detail: detail);
    } catch (e) {
      debugPrint('[WeatherService] 和风解析失败: $e');
      return null;
    }
  }

  // ── 高德天气 ──────────────────────────────────────────────────────

  /// 高德：坐标 → 逆地理得 adcode → 天气
  static Future<WeatherInfo?> _amapByCoords(
      double lat, double lng, String amapKey) async {
    try {
      final gcj = _wgs84ToGcj02(lat, lng);
      final regeoResp = await _dio.get(
        'https://restapi.amap.com/v3/geocode/regeo',
        queryParameters: {
          'location': '${gcj.$2.toStringAsFixed(6)},${gcj.$1.toStringAsFixed(6)}',
          'key': amapKey,
          'extensions': 'base',
        },
      );
      final regeoData = regeoResp.data as Map<String, dynamic>;
      if (regeoData['status'] != '1') return null;

      final adInfo = (regeoData['regeocode'] as Map<String, dynamic>?)?['addressComponent']
          as Map<String, dynamic>?;
      final adcode = adInfo?['adcode'] as String? ?? '';
      final city = adInfo?['city'] is String
          ? adInfo!['city'] as String
          : adInfo?['province'] as String? ?? '';
      if (adcode.isEmpty) return null;

      return _amapByAdcode(adcode, city, amapKey);
    } catch (e) {
      debugPrint('[WeatherService] 高德坐标查询失败: $e');
      return null;
    }
  }

  /// 高德：城市名 → 地理编码得 adcode → 天气
  static Future<WeatherInfo?> _amapByCity(String cityName, String amapKey) async {
    try {
      final geoResp = await _dio.get(
        'https://restapi.amap.com/v3/geocode/geo',
        queryParameters: {'address': cityName, 'key': amapKey},
      );
      final geoData = geoResp.data as Map<String, dynamic>;
      if (geoData['status'] != '1') return null;

      final geocodes = geoData['geocodes'] as List<dynamic>;
      if (geocodes.isEmpty) return null;

      final geo = geocodes[0] as Map<String, dynamic>;
      final adcode = geo['adcode'] as String? ?? '';
      final city = geo['city'] is String
          ? geo['city'] as String
          : geo['province'] as String? ?? cityName;
      if (adcode.isEmpty) return null;

      return _amapByAdcode(adcode, city, amapKey);
    } catch (e) {
      debugPrint('[WeatherService] 高德城市查询失败: $e');
      return null;
    }
  }

  /// 高德：adcode → 天气（带缓存）
  static Future<WeatherInfo?> _amapByAdcode(
      String adcode, String cityName, String amapKey) async {
    final cacheKey = 'amap_$adcode';
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.$2) < _cacheDuration) {
      return cached.$1;
    }
    try {
      final resp = await _dio.get(
        'https://restapi.amap.com/v3/weather/weatherInfo',
        queryParameters: {'city': adcode, 'extensions': 'base', 'key': amapKey},
      );
      final data = resp.data as Map<String, dynamic>;
      if (data['status'] != '1') return null;

      final lives = data['lives'] as List<dynamic>;
      if (lives.isEmpty) return null;

      final live = lives[0] as Map<String, dynamic>;
      final condition = live['weather'] as String? ?? '';
      final temp = live['temperature'] as String? ?? '';
      final windDir = live['winddirection'] as String? ?? '';
      final windPower = live['windpower'] as String? ?? '';
      final humidity = live['humidity'] as String? ?? '';
      final city = live['city'] as String? ?? cityName;

      final detail = [
        if (city.isNotEmpty) city,
        condition,
        if (temp.isNotEmpty) '$temp°C',
        if (windDir.isNotEmpty && windPower.isNotEmpty) '${windDir}风$windPower级',
        if (humidity.isNotEmpty) '湿度$humidity%',
      ].join('，');

      final info = WeatherInfo(condition: condition, detail: detail);
      _cache[cacheKey] = (info, DateTime.now());
      debugPrint('[WeatherService] 高德天气: $detail');
      return info;
    } catch (e) {
      debugPrint('[WeatherService] 高德 adcode 查询失败: $e');
      return null;
    }
  }

  // ── WGS84 → GCJ-02 ───────────────────────────────────────────────

  static (double lat, double lng) _wgs84ToGcj02(double lat, double lng) {
    if (!_inChina(lat, lng)) return (lat, lng);
    const a = 6378245.0;
    const ee = 0.00669342162296594323;
    double dLat = _transformLat(lng - 105.0, lat - 35.0);
    double dLng = _transformLng(lng - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * pi;
    double magic = sin(radLat);
    magic = 1 - ee * magic * magic;
    final sqrtMagic = sqrt(magic);
    dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi);
    dLng = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * pi);
    return (lat + dLat, lng + dLng);
  }

  static bool _inChina(double lat, double lng) =>
      lng >= 72.004 && lng <= 137.8347 && lat >= 0.8293 && lat <= 55.8271;

  static double _transformLat(double x, double y) {
    double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }
}
