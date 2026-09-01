import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/attachment_info.dart';

AttachmentInfo _info(String mime) => AttachmentInfo(
  localId: 'a1',
  filename: 'f',
  mimeType: mime,
  sizeBytes: 1,
);

void main() {
  group('isVideo', () {
    test('video/* 判定为视频', () {
      expect(_info('video/mp4').isVideo, isTrue);
      expect(_info('video/quicktime').isVideo, isTrue);
    });

    test('图片、音频、普通文件不是视频', () {
      expect(_info('image/png').isVideo, isFalse);
      expect(_info('audio/aac').isVideo, isFalse);
      expect(_info('application/pdf').isVideo, isFalse);
    });

    // 三个渲染点用 isImage/isAudio/isVideo 分流，剩下的才落到文件 Chip，
    // 三者必须互斥，否则同一个附件会被渲染两次。
    test('与 isImage / isAudio 互斥', () {
      final video = _info('video/mp4');
      expect(video.isImage, isFalse);
      expect(video.isAudio, isFalse);
    });
  });
}
