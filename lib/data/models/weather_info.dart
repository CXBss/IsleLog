import 'dart:convert';

import 'package:flutter/material.dart';

/// 天气信息（轻量值对象，序列化为 JSON 存入 MemoEntry.weatherJson）
///
/// 不做结构化解析，detail 直接存 API 返回的拼接字符串，换 API 也能展示。
class WeatherInfo {
  final String condition; // 天气状况，如"晴"/"阴"/"多云"（用于图标映射）
  final String detail;    // 展示字符串，如"阴，8°C，南风≤3级，湿度20%"

  const WeatherInfo({required this.condition, required this.detail});

  String toJsonString() => jsonEncode({'condition': condition, 'detail': detail});

  factory WeatherInfo.fromJsonString(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return WeatherInfo(
      condition: m['condition'] as String? ?? '',
      // 兼容旧结构化数据
      detail: m['detail'] as String? ?? _legacyDetail(m),
    );
  }

  static String _legacyDetail(Map<String, dynamic> m) {
    final parts = <String>[];
    if (m['condition'] != null) parts.add(m['condition'] as String);
    if (m['temp'] != null) parts.add('${m['temp']}°C');
    if (m['tempMax'] != null && m['temp'] == null) parts.add('${m['tempMax']}°C');
    if (m['windDir'] != null && m['windLevel'] != null) parts.add('${m['windDir']}风${m['windLevel']}级');
    return parts.join('，');
  }
}

/// 心情选项（Material 图标 + key + 中文标签 + 颜色）
class MoodOption {
  final String key;
  final IconData icon;
  final String label;
  final Color color;

  const MoodOption({required this.key, required this.icon, required this.label, required this.color});
}

/// 所有可用心情列表
const List<MoodOption> kMoodOptions = [
  MoodOption(key: 'happy',    icon: Icons.sentiment_satisfied_alt,   label: '开心', color: Color(0xFFFFA726)),
  MoodOption(key: 'excited',  icon: Icons.celebration_outlined,      label: '兴奋', color: Color(0xFFFF7043)),
  MoodOption(key: 'calm',     icon: Icons.self_improvement_outlined, label: '平静', color: Color(0xFF66BB6A)),
  MoodOption(key: 'tired',    icon: Icons.bedtime_outlined,          label: '疲惫', color: Color(0xFF8D6E63)),
  MoodOption(key: 'anxious',  icon: Icons.psychology_outlined,       label: '焦虑', color: Color(0xFFAB47BC)),
  MoodOption(key: 'sad',      icon: Icons.sentiment_dissatisfied_outlined, label: '难过', color: Color(0xFF42A5F5)),
  MoodOption(key: 'angry',    icon: Icons.whatshot_outlined,         label: '生气', color: Color(0xFFEF5350)),
  MoodOption(key: 'sick',     icon: Icons.sick_outlined,             label: '不适', color: Color(0xFF26A69A)),
  MoodOption(key: 'grateful', icon: Icons.favorite_outline,          label: '感恩', color: Color(0xFFEC407A)),
];

/// 根据 key 获取心情选项，找不到返回 null
MoodOption? moodByKey(String? key) {
  if (key == null) return null;
  try {
    return kMoodOptions.firstWhere((m) => m.key == key);
  } catch (_) {
    return null;
  }
}

// ── 服务端 int 枚举映射 ────────────────────────────────────────────
//
// mood / weather 在服务端存为 int，本地用字符串 key。
// 0 表示未设置，与服务端约定一致。

/// 本地 mood key → 服务端 int
const Map<String, int> kMoodToInt = {
  'happy':    1,
  'excited':  2,
  'calm':     3,
  'tired':    4,
  'anxious':  5,
  'sad':      6,
  'angry':    7,
  'sick':     8,
  'grateful': 9,
};

/// 服务端 int → 本地 mood key
const Map<int, String> kIntToMood = {
  1: 'happy',
  2: 'excited',
  3: 'calm',
  4: 'tired',
  5: 'anxious',
  6: 'sad',
  7: 'angry',
  8: 'sick',
  9: 'grateful',
};

/// 本地 WeatherInfo.condition（天气状况字符串）→ 服务端 int
///
/// 按高德/和风天气常见描述做模糊匹配。
int weatherConditionToInt(String? condition) {
  if (condition == null || condition.isEmpty) return 0;
  if (condition.contains('晴')) return 1;
  if (condition.contains('多云')) return 2;
  if (condition.contains('阴')) return 3;
  if (condition.contains('雨') && condition.contains('雪')) return 8;
  if (condition.contains('小雨') || condition.contains('毛毛雨')) return 4;
  if (condition.contains('中雨')) return 5;
  if (condition.contains('大雨') || condition.contains('暴雨') || condition.contains('雷')) return 6;
  if (condition.contains('雨')) return 4;
  if (condition.contains('雪')) return 7;
  if (condition.contains('雾') || condition.contains('霾') || condition.contains('沙')) return 9;
  return 0;
}

/// 服务端 int → 天气状况描述（用于从远端拉取时回填 condition）
const Map<int, String> kIntToWeatherCondition = {
  1: '晴',
  2: '多云',
  3: '阴',
  4: '小雨',
  5: '中雨',
  6: '大雨',
  7: '雪',
  8: '雨夹雪',
  9: '雾/霾',
};
