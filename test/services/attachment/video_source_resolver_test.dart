import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/attachment_info.dart';
import 'package:isle_log/services/attachment/video_source_resolver.dart';

AttachmentInfo _video({String? localPath, String? remoteUrl}) => AttachmentInfo(
  localId: 'v1',
  filename: 'clip.mp4',
  mimeType: 'video/mp4',
  sizeBytes: 100,
  localPath: localPath,
  remoteUrl: remoteUrl,
);

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('video_src_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String writeFile(String name) {
    final f = File('${tmp.path}/$name')..writeAsBytesSync([0, 1, 2]);
    return f.path;
  }

  test('本地文件存在时优先用本地路径', () {
    final path = writeFile('clip.mp4');
    final source = resolveVideoSource(
      _video(localPath: path, remoteUrl: '/o/r/9'),
      baseUrl: 'https://s.example.com',
      token: 'tk',
    );

    expect(source, isA<LocalVideoSource>());
    expect((source as LocalVideoSource).path, path);
  });

  // 附件上传后 localPath 会被置 null，但也可能文件被系统清理掉而路径还在，
  // 这时必须回落远端，不能因为字段非空就当本地可播。
  test('localPath 非空但文件已不存在时回落远端', () {
    final source = resolveVideoSource(
      _video(localPath: '${tmp.path}/gone.mp4', remoteUrl: '/o/r/9'),
      baseUrl: 'https://s.example.com',
      token: 'tk',
    );

    expect(source, isA<RemoteVideoSource>());
    expect((source as RemoteVideoSource).url, 'https://s.example.com/o/r/9');
  });

  test('远端源带 Authorization 头', () {
    final source =
        resolveVideoSource(
              _video(remoteUrl: '/o/r/9'),
              baseUrl: 'https://s.example.com',
              token: 'tk',
            )
            as RemoteVideoSource;

    expect(source.headers, {'Authorization': 'Bearer tk'});
  });

  test('无 token 时远端源不带请求头', () {
    final source =
        resolveVideoSource(
              _video(remoteUrl: '/o/r/9'),
              baseUrl: 'https://s.example.com',
              token: null,
            )
            as RemoteVideoSource;

    expect(source.headers, isEmpty);
  });

  test('remoteUrl 已是完整 URL 时不再拼 baseUrl', () {
    final source =
        resolveVideoSource(
              _video(remoteUrl: 'https://cdn.example.com/a.mp4'),
              baseUrl: 'https://s.example.com',
              token: null,
            )
            as RemoteVideoSource;

    expect(source.url, 'https://cdn.example.com/a.mp4');
  });

  test('既无本地文件也无远端地址时返回 null', () {
    expect(
      resolveVideoSource(_video(), baseUrl: 'https://s.example.com'),
      isNull,
    );
  });
}
