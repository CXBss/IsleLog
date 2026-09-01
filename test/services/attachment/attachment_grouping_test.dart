import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/attachment_info.dart';
import 'package:isle_log/services/attachment/attachment_grouping.dart';

AttachmentInfo _a(String id, String mime) =>
    AttachmentInfo(localId: id, filename: id, mimeType: mime, sizeBytes: 1);

final _all = [
  _a('img', 'image/png'),
  _a('aud', 'audio/aac'),
  _a('vid', 'video/mp4'),
  _a('pdf', 'application/pdf'),
];

void main() {
  test('按渲染方式分成图片/音频/视频/文件四组', () {
    final g = groupAttachments(_all, videoPlayback: true);

    expect(g.images.map((a) => a.localId), ['img']);
    expect(g.audios.map((a) => a.localId), ['aud']);
    expect(g.videos.map((a) => a.localId), ['vid']);
    expect(g.files.map((a) => a.localId), ['pdf']);
  });

  // Linux/Web 没有 media_kit 库，视频必须留在文件列表里，
  // 否则附件会直接从界面上消失。
  test('不支持播放时视频归入文件组', () {
    final g = groupAttachments(_all, videoPlayback: false);

    expect(g.videos, isEmpty);
    expect(g.files.map((a) => a.localId), ['vid', 'pdf']);
  });

  test('保持原有顺序', () {
    final g = groupAttachments([
      _a('v1', 'video/mp4'),
      _a('v2', 'video/quicktime'),
    ], videoPlayback: true);

    expect(g.videos.map((a) => a.localId), ['v1', 'v2']);
  });

  test('空列表得到四个空组', () {
    final g = groupAttachments(const [], videoPlayback: true);

    expect(g.images, isEmpty);
    expect(g.audios, isEmpty);
    expect(g.videos, isEmpty);
    expect(g.files, isEmpty);
  });
}
