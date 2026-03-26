import 'dart:async';

import 'package:flutter/material.dart';

import 'data/database/database_service.dart';
import 'services/settings/settings_service.dart';
import 'services/sync/sync_service.dart';
import 'shared/constants/app_constants.dart';
import 'shared/mock/mock_data.dart';
import 'shared/widgets/main_scaffold.dart';

/// 应用入口
///
/// 启动流程：
/// 1. 初始化 Isar 本地数据库
/// 2. 若数据库为空则写入 Mock 演示数据
/// 3. 若已配置服务器，在后台启动全量同步
/// 4. 启动 Flutter UI
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('[App] 初始化数据库...');
  await DatabaseService.db;
  debugPrint('[App] 数据库初始化完成');

  debugPrint('[App] 检查并写入 Mock 数据...');
  await DatabaseService.seedIfEmpty(mockMemos);
  debugPrint('[App] Mock 数据检查完成');

  // 已配置服务器时，启动后在后台自动全量同步（fire-and-forget，不阻塞启动）
  final configured = await SettingsService.isConfigured;
  if (configured) {
    debugPrint('[App] 检测到服务器配置，启动后台同步...');
    unawaited(SyncService.syncAll());
  } else {
    debugPrint('[App] 未配置服务器，跳过启动同步');
  }

  debugPrint('[App] 启动 Flutter UI');
  runApp(const MyApp());
}

/// 根应用 Widget
///
/// 配置全局 Material3 主题（绿色主题），并以 [MainScaffold] 作为根页面。
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IsleLog',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // 以品牌绿为种子色自动派生完整 ColorScheme
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surfaceWhite,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
        ),
        scaffoldBackgroundColor: AppColors.scaffoldBg,
      ),
      home: const MainScaffold(),
    );
  }
}
