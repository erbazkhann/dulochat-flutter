import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../theme/colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/widgets.dart';
import 'common.dart';
import 'security_screen.dart';
import 'user_profile.dart';

/// "Profile" tab: your account card, quick settings and logout.
class ProfileTab extends StatefulWidget {
  final Session session;
  final ThemeController themeController;
  const ProfileTab({super.key, required this.session, required this.themeController});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map<String, dynamic>? _me;
  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_r);
    _load();
  }

  void _r() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(_r);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await s.api.get('/api/me');
      if (mounted) setState(() => _me = r);
    } catch (_) {}
  }

  Future<void> _logout() async {
    final ok = await confirmDialog(context, 'Log out?', 'You will need your password to log in again. Keep your chat key safe so you can read your private chats later.', yes: 'Log out', danger: true);
    if (ok) await s.logout();
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.dulo;
    final me = _me;
    final full = (me?['fullName'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: <Widget>[
            SectionCard(
              children: <Widget>[
                InkWell(
                  onTap: () => openProfile(context, s, s.uid),
                  child: Row(
                    children: <Widget>[
                      userAvatar(s, s.uid, size: 68, showOnline: false),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(full.isNotEmpty ? full : s.me, style: TextStyle(color: cc.ink, fontSize: 20, fontWeight: FontWeight.w900)),
                            Text('@${s.me}', style: TextStyle(color: cc.muted)),
                            if ((me?['bio'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(me!['bio'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cc.ink, fontSize: 13.5))),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: cc.muted),
                    ],
                  ),
                ),
              ],
            ),
            SectionCard(
              title: 'Appearance',
              children: <Widget>[
                AnimatedBuilder(
                  animation: widget.themeController,
                  builder: (context, _) => SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const <ButtonSegment<ThemeMode>>[
                        ButtonSegment<ThemeMode>(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                        ButtonSegment<ThemeMode>(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                        ButtonSegment<ThemeMode>(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                      ],
                      selected: <ThemeMode>{widget.themeController.mode},
                      onSelectionChanged: (v) => widget.themeController.set(v.first),
                    ),
                  ),
                ),
              ],
            ),
            SectionCard(
              title: 'Security',
              children: <Widget>[
                DuloTile(
                  icon: Icons.key_rounded,
                  title: 'Chat key',
                  subtitle: 'View or copy your chat backup key',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SecurityScreen(session: s))),
                ),
              ],
            ),
            SectionCard(
              title: 'Connection',
              children: <Widget>[
                DuloTile(
                  icon: s.online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  title: s.online ? 'Connected to server' : 'Connecting...',
                  subtitle: s.online ? 'Realtime updates are on' : 'Check that your server and ngrok are running',
                ),
              ],
            ),
            const SizedBox(height: 4),
            DuloButton(label: 'Log out', outlined: true, danger: true, icon: Icons.logout_rounded, onPressed: _logout),
          ],
        ),
      ),
    );
  }
}

String friendlyApiError(Object e) {
  if (e is ApiError) {
    if (e.code == 'network') return 'No connection.';
    if (e.code == 'too-many-requests') return 'Too many attempts. Wait a minute.';
    return 'Something went wrong (${e.code}).';
  }
  return 'Something went wrong.';
}
