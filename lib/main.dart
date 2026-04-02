import 'dart:async';

import 'package:flutter/material.dart';

import 'data/database/database_service.dart';
import 'services/settings/settings_service.dart';
import 'services/sync/sync_service.dart';
import 'shared/constants/app_constants.dart';
import 'shared/mock/mock_data.dart';
import 'shared/widgets/main_scaffold.dart';

/// 全局主题模式控制器，可在应用任意位置修改以实时切换主题
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

/// 应用入口
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('[App] 初始化数据库...');
  await DatabaseService.db;
  debugPrint('[App] 数据库初始化完成');

  debugPrint('[App] 检查并写入 Mock 数据...');
  await DatabaseService.seedIfEmpty(mockMemos);
  debugPrint('[App] Mock 数据检查完成');

  // 读取持久化的主题模式
  themeModeNotifier.value = await SettingsService.themeMode;

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
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF2F4F6),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardColor: colorScheme.surface,
      bottomAppBarTheme: BottomAppBarThemeData(color: colorScheme.surface),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white12 : Colors.black12,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (_, mode, __) => MaterialApp(
        title: 'IsleLog',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: const MainScaffold(),
      ),
    );
  }
}
