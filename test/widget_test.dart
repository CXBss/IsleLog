import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:isle_log/data/database/database_service.dart';
import 'package:isle_log/main.dart';

void main() {
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temporaryDirectory;

  setUpAll(() async {
    final packageConfigFile = File('.dart_tool/package_config.json').absolute;
    final packageConfig =
        jsonDecode(await packageConfigFile.readAsString())
            as Map<String, dynamic>;
    final packages = packageConfig['packages'] as List<dynamic>;
    final isarFlutterLibs = packages.cast<Map<String, dynamic>>().firstWhere(
      (package) => package['name'] == 'isar_flutter_libs',
    );
    final configuredRootUri = packageConfigFile.uri.resolve(
      isarFlutterLibs['rootUri'] as String,
    );
    final rootUri = configuredRootUri.path.endsWith('/')
        ? configuredRootUri
        : configuredRootUri.replace(path: '${configuredRootUri.path}/');
    final libraryFileName = Platform.isMacOS
        ? 'macos/libisar.dylib'
        : Platform.isLinux
        ? 'linux/libisar.so'
        : Platform.isWindows
        ? 'windows/isar.dll'
        : throw UnsupportedError('当前平台不支持 Isar 启动测试');
    final libraryPath = rootUri.resolve(libraryFileName).toFilePath();

    await Isar.initializeIsarCore(libraries: {Abi.current(): libraryPath});
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'isle_log_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return temporaryDirectory.path;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  testWidgets('应用启动后展示主界面', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      await DatabaseService.db;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(tester.takeException(), isNull);

    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('时间线'), findsOneWidget);
    expect(find.byTooltip('新建日记'), findsOneWidget);
  });
}
