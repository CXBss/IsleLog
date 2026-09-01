import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/shared/utils/media_duration.dart';

void main() {
  test('一小时以内用 mm:ss', () {
    expect(formatMediaDuration(const Duration(seconds: 7)), '00:07');
    expect(formatMediaDuration(const Duration(seconds: 65)), '01:05');
    expect(formatMediaDuration(const Duration(minutes: 59, seconds: 59)), '59:59');
  });

  // 长视频不能显示成 "61:05"，那是错的读数。
  test('超过一小时补上小时位', () {
    expect(formatMediaDuration(const Duration(seconds: 3725)), '1:02:05');
    expect(formatMediaDuration(const Duration(hours: 10)), '10:00:00');
  });

  test('零时长显示 00:00', () {
    expect(formatMediaDuration(Duration.zero), '00:00');
  });
}
