import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/api/memos_api_service.dart';

void main() {
  group('buildMemoUpdatePayload', () {
    test('未开启 syncMoodWeather 时不写 mood/weather，也不列入 updateMask', () {
      final payload = buildMemoUpdatePayload(content: '正文');

      expect(payload.body.containsKey('mood'), isFalse);
      expect(payload.body.containsKey('weather'), isFalse);
      expect(payload.body.containsKey('weatherDetail'), isFalse);
      expect(payload.mask, isNot(contains('mood')));
      expect(payload.mask, isNot(contains('weather')));
      expect(payload.mask, isNot(contains('weatherDetail')));
      // 基础字段始终更新
      expect(payload.mask, containsAll(['content', 'visibility', 'attachments']));
    });

    test('开启 syncMoodWeather 且有值时写入并列入 mask', () {
      final payload = buildMemoUpdatePayload(
        content: '正文',
        syncMoodWeather: true,
        mood: 3,
        weather: 1,
        weatherDetail: '晴，20°C',
      );

      expect(payload.body['mood'], 3);
      expect(payload.body['weather'], 1);
      expect(payload.body['weatherDetail'], '晴，20°C');
      expect(payload.mask, containsAll(['mood', 'weather', 'weatherDetail']));
    });

    test('开启 syncMoodWeather 但无值时显式写 0（用于清除远端旧值）', () {
      final payload = buildMemoUpdatePayload(
        content: '正文',
        syncMoodWeather: true,
      );

      expect(payload.body['mood'], 0);
      expect(payload.body['weather'], 0);
      expect(payload.body['weatherDetail'], '');
      expect(payload.mask, containsAll(['mood', 'weather', 'weatherDetail']));
    });

    test('location/state/createTime 仅在传入时进入 mask', () {
      final bare = buildMemoUpdatePayload(content: 'x');
      expect(bare.mask, isNot(contains('location')));
      expect(bare.mask, isNot(contains('state')));
      expect(bare.mask, isNot(contains('createTime')));

      final full = buildMemoUpdatePayload(
        content: 'x',
        latitude: 1,
        longitude: 2,
        state: 'ARCHIVED',
        createTime: DateTime.utc(2026, 1, 1),
      );
      expect(full.mask, containsAll(['location', 'state', 'createTime']));
    });
  });
}
