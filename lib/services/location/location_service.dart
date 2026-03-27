import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../settings/settings_service.dart';

/// 地理位置信息（经纬度 + 地址名称）
///
/// 内部存储 WGS84 坐标（GPS 原始坐标），跳转地图时自动转换为 GCJ-02。
class LocationInfo {
  final double latitude;
  final double longitude;

  /// 逆地理编码后的地址（如"广东省深圳市南山区"），获取失败时为 null
  final String? address;

  const LocationInfo({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  /// 显示文本：有地址则显示地址，否则显示坐标
  String get displayText =>
      address ?? '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  /// 系统地图跳转 URI（geo: 协议）
  ///
  /// 高德/百度等国内地图使用 GCJ-02 坐标，需先将 WGS84 转换。
  /// label 直接使用汉字，不做 percent-encode（避免地图 App 显示转义符）。
  String get geoUri {
    final gcj = _wgs84ToGcj02(latitude, longitude);
    final label = address ?? '位置';
    return 'geo:${gcj.lat},${gcj.lng}?q=${gcj.lat},${gcj.lng}($label)';
  }
}

// ── WGS84 → GCJ-02 坐标转换 ────────────────────────────────────────

/// 简单的经纬度记录
class _LatLng {
  final double lat;
  final double lng;
  const _LatLng(this.lat, this.lng);
}

/// WGS84（GPS）→ GCJ-02（国测局/高德）坐标转换
///
/// 算法来源：开源社区广泛验证的偏移修正公式。
/// 在中国大陆境内误差 < 5m，境外直接返回原坐标。
_LatLng _wgs84ToGcj02(double lat, double lng) {
  // 境外不偏移（GCJ-02 仅适用于中国大陆）
  if (!_inChina(lat, lng)) return _LatLng(lat, lng);

  const a = 6378245.0; // 克拉索夫斯基椭球长半轴
  const ee = 0.00669342162296594323; // 偏心率平方

  double dLat = _transformLat(lng - 105.0, lat - 35.0);
  double dLng = _transformLng(lng - 105.0, lat - 35.0);

  final radLat = lat / 180.0 * pi;
  double magic = sin(radLat);
  magic = 1 - ee * magic * magic;
  final sqrtMagic = sqrt(magic);

  dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi);
  dLng = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * pi);

  return _LatLng(lat + dLat, lng + dLng);
}

bool _inChina(double lat, double lng) =>
    lng >= 72.004 && lng <= 137.8347 && lat >= 0.8293 && lat <= 55.8271;

double _transformLat(double x, double y) {
  double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y +
      0.1 * x * y + 0.2 * sqrt(x.abs());
  ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
  ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
  ret += (160.0 * sin(y / 12.0 * pi) + 320 * sin(y * pi / 30.0)) * 2.0 / 3.0;
  return ret;
}

double _transformLng(double x, double y) {
  double ret = 300.0 + x + 2.0 * y + 0.1 * x * x +
      0.1 * x * y + 0.1 * sqrt(x.abs());
  ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
  ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
  ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0;
  return ret;
}

// ── LocationService ─────────────────────────────────────────────────

/// 地理位置服务
///
/// - [getLocation]：请求权限并获取当前位置
/// - [reverseGeocode]：高德逆地理编码（经纬度 → 地址）
class LocationService {

  /// 获取当前位置（含逆地理编码）
  ///
  /// 返回 [LocationInfo]，address 字段可能为 null（逆地理编码失败时）。
  /// 抛出 [LocationException] 表示无法获取位置。
  static Future<LocationInfo> getLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException('设备位置服务未开启，请在系统设置中开启');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationException('位置权限被拒绝');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException('位置权限被永久拒绝，请在系统设置中手动开启');
    }

    debugPrint('[Location] 开始获取位置...');
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      debugPrint('[Location] GPS 定位成功：${pos.latitude}, ${pos.longitude}');
    } catch (e) {
      // 超时或失败时降级到最后已知位置（通常来自网络/基站，速度极快）
      debugPrint('[Location] GPS 超时，尝试最后已知位置：$e');
      pos = await Geolocator.getLastKnownPosition();
      if (pos == null) {
        throw LocationException('GPS 超时且无缓存位置：$e');
      }
      debugPrint('[Location] 使用最后已知位置：${pos.latitude}, ${pos.longitude}');
    }

    // 高德使用 GCJ-02，逆地理编码前先转换坐标
    final gcj = _wgs84ToGcj02(pos.latitude, pos.longitude);
    final key = await SettingsService.amapKey;
    final address = key != null && key.isNotEmpty
        ? await reverseGeocode(gcj.lat, gcj.lng, key)
        : null;
    return LocationInfo(
      latitude: pos.latitude,
      longitude: pos.longitude,
      address: address,
    );
  }

  /// 高德逆地理编码：GCJ-02 经纬度 → 地址字符串
  ///
  /// 传入坐标须已转换为 GCJ-02。失败时返回 null。
  static Future<String?> reverseGeocode(double lat, double lng, String key) async {
    try {
      final dio = Dio();
      final res = await dio.get(
        'https://restapi.amap.com/v3/geocode/regeo',
        queryParameters: {
          'key': key,
          'location': '$lng,$lat',
          'radius': 100,
          'extensions': 'base',
          'output': 'json',
        },
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );

      final data = res.data;
      if (data is! Map || data['status'] != '1') return null;

      final regeo = data['regeocode'] as Map?;
      if (regeo == null) return null;

      // formatted_address 是高德返回的完整地址，如"江苏省苏州市相城区..."
      final formatted = regeo['formatted_address'] as String?;
      if (formatted != null && formatted.isNotEmpty) {
        debugPrint('[Location] 逆地理编码成功：$formatted');
        return formatted;
      }

      return null;
    } catch (e) {
      debugPrint('[Location] 逆地理编码失败：$e');
      return null;
    }
  }
}

/// 根据经纬度跳转系统地图
///
/// 坐标自动从 WGS84 转换为 GCJ-02，label 直接传汉字不编码。
/// 使用 [launchUrlString] 绕过 [Uri] 对汉字的自动 percent-encode。
Future<void> openMapFromCoords(double? lat, double? lng, String? label) async {
  if (lat == null || lng == null) return;
  final gcj = _wgs84ToGcj02(lat, lng);
  final name = label ?? '位置';
  // 直接拼接原始字符串，不经过 Uri.parse / Uri()，汉字保持原样
  final uriString =
      'geo:${gcj.lat},${gcj.lng}?q=${gcj.lat},${gcj.lng}($name)';
  debugPrint('[Location] 跳转地图 URI：$uriString');
  if (await canLaunchUrlString(uriString)) {
    await launchUrlString(uriString, mode: LaunchMode.externalApplication);
  } else {
    debugPrint('[Location] 无法打开地图 URI：$uriString');
  }
}

/// 位置获取异常
class LocationException implements Exception {
  final String message;
  const LocationException(this.message);

  @override
  String toString() => message;
}
