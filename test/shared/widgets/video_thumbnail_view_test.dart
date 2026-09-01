import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/attachment_info.dart';
import 'package:isle_log/services/attachment/video_thumbnail.dart';
import 'package:isle_log/shared/widgets/video_attachment_card.dart';

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
  bool showDuration = true,
  double badgeSize = 44,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 64,
          height: 64,
          child: VideoThumbnailView(
            attachment: _attachment,
            loader: loader,
            showDuration: showDuration,
            badgeSize: badgeSize,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('渲染封面与播放角标', (tester) async {
    await _pump(tester, loader: (_) async => VideoThumbnail(frame: _png));

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  // 编辑器里的缩略图只有 64px，塞不下时长标签。
  testWidgets('showDuration 为 false 时不显示时长', (tester) async {
    await _pump(
      tester,
      showDuration: false,
      loader: (_) async =>
          VideoThumbnail(frame: _png, duration: const Duration(seconds: 12)),
    );

    expect(find.text('00:12'), findsNothing);
  });

  testWidgets('badgeSize 决定播放角标尺寸', (tester) async {
    await _pump(
      tester,
      badgeSize: 20,
      loader: (_) async => VideoThumbnail(frame: _png),
    );

    final badge = tester.getSize(
      find.ancestor(
        of: find.byIcon(Icons.play_arrow),
        matching: find.byType(Container),
      ).first,
    );
    expect(badge.width, 20);
  });
}
