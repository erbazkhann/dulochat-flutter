import 'package:flutter/material.dart';

import '../config.dart';
import '../theme/colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/widgets.dart';
import 'server_check.dart';

/// Part 2: temporary Profile tab. Theme switch, server check and a preview of
/// the reusable widgets. The real profile comes in a later part.
class ProfileScreen extends StatelessWidget {
  final ThemeController themeController;
  const ProfileScreen({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _title(c, 'Theme'),
          AnimatedBuilder(
            animation: themeController,
            builder: (context, _) => SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
              ],
              selected: {themeController.mode},
              onSelectionChanged: (s) => themeController.set(s.first),
            ),
          ),
          const SizedBox(height: 22),
          _title(c, 'Connection'),
          const ServerCheckCard(),
          const SizedBox(height: 22),
          _title(c, 'Design preview'),
          Row(
            children: [
              const DuloAvatar(name: 'Arbaz', size: 48, online: true),
              const SizedBox(width: 10),
              const DuloAvatar(name: 'Dulo', size: 48),
              const SizedBox(width: 10),
              const DuloAvatar(name: 'Zoya', size: 48),
              const SizedBox(width: 10),
              DuloAvatar(name: AppConfig.appName, size: 48),
            ],
          ),
          const SizedBox(height: 14),
          const DuloTextField(label: 'Username', hint: 'Type here', prefixIcon: Icons.person_outline),
          const SizedBox(height: 12),
          const DuloTextField(label: 'Password', hint: 'Password', password: true, prefixIcon: Icons.lock_outline),
          const SizedBox(height: 14),
          const DuloButton(label: 'Primary button', onPressed: _noop),
          const SizedBox(height: 10),
          const DuloButton(label: 'Outlined button', outlined: true, onPressed: _noop),
          const SizedBox(height: 10),
          const DuloButton(label: 'Danger button', danger: true, onPressed: _noop),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
            child: const Column(
              children: [
                ChatBubble(text: 'Hi! Dulochat app ka design ready ho raha hai', time: '2:55 PM'),
                ChatBubble(text: 'Wah, mast lag raha hai', time: '2:56 PM', mine: true, seen: true),
                ChatBubble(text: 'Next part mein login aayega', time: '2:56 PM'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _noop() {}

  Widget _title(DuloColors c, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(t, style: TextStyle(color: c.muted, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
      );
}
