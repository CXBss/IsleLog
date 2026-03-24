import 'dart:async';

import 'package:flutter/material.dart';

import 'data/database/database_service.dart';
import 'services/settings/settings_service.dart';
import 'services/sync/sync_service.dart';
import 'shared/mock/mock_data.dart';
import 'shared/widgets/main_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.db;
  await DatabaseService.seedIfEmpty(mockMemos);

  // 已配置服务器时，启动后在后台自动全量同步
  final configured = await SettingsService.isConfigured;
  if (configured) unawaited(SyncService.syncAll());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memos Local',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4CAF50)),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1A1A1A),
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
        ),
        scaffoldBackgroundColor: const Color(0xFFF2F4F6),
      ),
      home: const MainScaffold(),
    );
  }
}
