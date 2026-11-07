import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import 'chats_screen.dart';
import 'common.dart';

/// Someone else's (or your own) public profile.
class UserProfileScreen extends StatefulWidget {
  final Session session;
  final String uid;
  const UserProfileScreen({super.key, required this.session, required this.uid});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? _p;
  String _err = '';
  bool _busy = false;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await s.api.get('/api/user?uid=${widget.uid}');
      if (mounted) setState(() => _p = r);
    } catch (e) {
      if (mounted) setState(() => _err = e is ApiError && e.code == 'not-found' ? 'This account was not found.' : 'Could not load this profile.');
    }
  }

  Future<void> _follow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await s.api.post('/api/thoughts/follow', <String, dynamic>{'uid': widget.uid});
      if (mounted && _p != null) {
        setState(() => _p!['iFollow'] = r['following'] ?? !(_p!['iFollow'] == true));
        _load();
      }
    } catch (_) {
      if (mounted) toast(context, 'Could not do that. Try again.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.dulo;
    final p = _p;
    final me = widget.uid == s.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _err.isNotEmpty
          ? EmptyState(icon: Icons.person_off_outlined, title: 'Profile', message: _err)
          : p == null
              ? loadingBox()
              : p['unknown'] == true
                  ? const EmptyState(icon: Icons.person_off_outlined, title: 'Unknown User', message: 'This profile is not available.')
                  : ListView(
                      padding: const EdgeInsets.all(18),
                      children: <Widget>[
                        Center(child: userAvatar(s, widget.uid, size: 104, showOnline: false)),
                        const SizedBox(height: 14),
                        Center(
                          child: NameWithTick(
                            name: (p['fullName'] ?? '').toString().isNotEmpty ? p['fullName'].toString() : (p['username'] ?? '').toString(),
                            official: p['official'] == true,
                            verified: p['verified'] == true,
                            style: TextStyle(color: cc.ink, fontSize: 24, fontWeight: FontWeight.w900),
                          ),
                        ),
                        Center(child: Text('@${p['username'] ?? ''}', style: TextStyle(color: cc.muted, fontSize: 14.5))),
                        if ((p['bio'] ?? '').toString().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 14),
                          Text(p['bio'].toString(), textAlign: TextAlign.center, style: TextStyle(color: cc.ink, fontSize: 15, height: 1.4)),
                        ],
                        if ((p['link'] ?? '').toString().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          Center(child: Text(p['link'].toString(), style: TextStyle(color: cc.accent, fontWeight: FontWeight.w600))),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            _stat(cc, p['followers'], 'Followers'),
                            _stat(cc, p['following'], 'Following'),
                            _stat(cc, p['friendCount'], 'Friends'),
                          ],
                        ),
                        const SizedBox(height: 22),
                        if (!me) ...<Widget>[
                          DuloButton(
                            label: 'Message',
                            icon: Icons.chat_bubble_outline_rounded,
                            onPressed: () {
                              Navigator.pop(context);
                              openDm(context, s, widget.uid, (p['username'] ?? '').toString());
                            },
                          ),
                          const SizedBox(height: 10),
                          DuloButton(label: p['iFollow'] == true ? 'Following' : 'Follow', outlined: true, busy: _busy, onPressed: _follow),
                        ],
                        const SizedBox(height: 18),
                        if ((p['country'] ?? '').toString().isNotEmpty) DuloTile(icon: Icons.public_rounded, title: (p['country']).toString(), subtitle: (p['region'] ?? '').toString().isEmpty ? null : p['region'].toString()),
                      ],
                    ),
    );
  }

  Widget _stat(DuloColors cc, dynamic n, String label) => Column(
        children: <Widget>[
          Text('${n ?? 0}', style: TextStyle(color: cc.ink, fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: cc.muted, fontSize: 12.5)),
        ],
      );
}

void openProfile(BuildContext context, Session s, String uid) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UserProfileScreen(session: s, uid: uid)));
}
