import 'package:flutter/material.dart';

import 'config.dart';
import 'core/session.dart';
import 'shell/home_shell.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'ui/auth_screen.dart';
import 'ui/common.dart';
import 'ui/e2ee_ui.dart';
import 'widgets/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = ThemeController();
  await themeController.load();
  final session = Session();
  session.e2ee.ui = AppE2eeUi(session.e2ee);
  runApp(DulochatApp(themeController: themeController, session: session));
  session.boot();
}

class DulochatApp extends StatelessWidget {
  final ThemeController themeController;
  final Session session;
  const DulochatApp({super.key, required this.themeController, required this.session});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        title: AppConfig.appName,
        navigatorKey: navKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeController.mode,
        home: _Root(session: session, themeController: themeController),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  final Session session;
  final ThemeController themeController;
  const _Root({required this.session, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        if (session.booting) {
          return const Scaffold(body: Center(child: DuloLogo(size: 84)));
        }
        if (session.signedIn) {
          return HomeShell(key: ValueKey<String>(session.uid), session: session, themeController: themeController);
        }
        return AuthScreen(key: ValueKey<String?>(session.failMessage), session: session);
      },
    );
  }
}
