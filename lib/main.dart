import 'package:flutter/material.dart';

import 'config.dart';
import 'shell/home_shell.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = ThemeController();
  await themeController.load();
  runApp(DulochatApp(themeController: themeController));
}

class DulochatApp extends StatelessWidget {
  final ThemeController themeController;
  const DulochatApp({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeController.mode,
        home: HomeShell(themeController: themeController),
      ),
    );
  }
}
