import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/attachment_info.dart';
import 'package:isle_log/services/attachment/video_thumbnail.dart';
import 'package:isle_log/shared/widgets/video_attachment_card.dart';

/// 1x1 透明 PNG——Image.memory 需要真能解码的字节，否则会走 errorBuilder。
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const _attachment = AttachmentInfo(
  localId: 'v1',
  filename: 'clip.mp4',
  mimeType: 'video/mp4',
  sizeBytes: 1024,
);

Future<void> _pump(
  WidgetTester tester, {
  required VideoThumbnailLoader loader,
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: VideoAttachmentCard(
          attachment: _attachment,
          loader: loader,
          onTap: onTap ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('取帧完成前显示占位，不显示图片', (tester) async {
    await _pump(
      tester,
      loader: (_) => Future.delayed(
        const Duration(seconds: 1),
        () => const VideoThumbnail(),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // 让挂起的 Future 走完，避免测试结束时留下计时器
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('取到首帧后显示封面图', (tester) async {
    await _pump(
      tester,
      loader: (_) async => VideoThumbnail(frame: _png),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  // 截帧对某些编码会失败，这时不能留一块空白——用户得看得出这是个视频。
  testWidgets('取帧失败时回落成视频图标', (tester) async {
    await _pump(tester, loader: (_) async => const VideoThumbnail());
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
  });

  testWidgets('取帧抛异常时不崩，同样回落', (tester) async {
    await _pump(tester, loader: (_) async => throw Exception('boom'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
  });

  testWidgets('已知时长时右下角显示时长', (tester) async {
    await _pump(
      tester,
      loader: (_) async =>
          VideoThumbnail(frame: _png, duration: const Duration(seconds: 12)),
    );
    await tester.pumpAndSettle();

    expect(find.text('00:12'), findsOneWidget);
  });

  testWidgets('时长未知时不显示时长标签', (tester) async {
    await _pump(tester, loader: (_) async => VideoThumbnail(frame: _png));
    await tester.pumpAndSettle();

    expect(find.textContaining(':'), findsNothing);
  });

  testWidgets('点击触发 onTap', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      loader: (_) async => VideoThumbnail(frame: _png),
      onTap: () => tapped = true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(VideoAttachmentCard));
    expect(tapped, isTrue);
  });
}
