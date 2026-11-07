import 'package:flutter/material.dart';

import '../core/session.dart';
import '../theme/colors.dart';
import '../theme/theme_controller.dart';
import '../ui/chats_screen.dart';
import '../ui/common.dart';
import '../ui/profile_tab.dart';
import '../ui/search_screen.dart';
import '../widgets/widgets.dart';

/// Main frame with the bottom navigation: Home, Search, Chats, Profile.
class HomeShell extends StatefulWidget {
  final Session session;
  final ThemeController themeController;
  const HomeShell({super.key, required this.session, required this.themeController});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 2;
  bool _phraseShown = false;
  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.addListener(_r);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePhrase());
  }

  void _r() {
    if (mounted) setState(() {});
    _maybePhrase();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    s.db.setVisible(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.removeListener(_r);
    super.dispose();
  }

  Future<void> _maybePhrase() async {
    final ph = s.pendingPhrase;
    if (ph == null || _phraseShown || !mounted) return;
    _phraseShown = true;
    s.pendingPhrase = null;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PhraseDialog(phrase: ph, name: s.me),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatBadge = s.dmUnread + s.groupUnread + s.pubUnread;
    final pages = <Widget>[
      Scaffold(
        appBar: AppBar(title: const Text('Dulochat')),
        body: const EmptyState(icon: Icons.auto_awesome_rounded, title: 'Thoughts are on the way', message: 'The Thoughts feed, Moments and Reels come in the next update. Chats work now.'),
      ),
      SearchScreen(session: s),
      ChatsScreen(session: s),
      ProfileTab(session: s, themeController: widget.themeController),
    ];
    Widget badge(IconData icon, int n) => Badge(isLabelVisible: n > 0, label: Text(n > 99 ? '99+' : '$n'), child: Icon(icon));
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: <NavigationDestination>[
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Search'),
          NavigationDestination(icon: badge(Icons.chat_bubble_outline_rounded, chatBadge), selectedIcon: badge(Icons.chat_bubble_rounded, chatBadge), label: 'Chats'),
          const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}

class _PhraseDialog extends StatefulWidget {
  final String phrase;
  final String name;
  const _PhraseDialog({required this.phrase, required this.name});
  @override
  State<_PhraseDialog> createState() => _PhraseDialogState();
}

class _PhraseDialogState extends State<_PhraseDialog> {
  bool _ok = false;

  @override
  Widget build(BuildContext context) {
    final cc = context.dulo;
    final words = widget.phrase.split(' ');
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('Welcome, ${widget.name}!'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Your recovery password', style: TextStyle(color: cc.ink, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                'Write these 12 words on paper, in this order. If you ever forget your password, these 12 words get you back into your account. Never share them with anyone. Dulochat will never ask for them.',
                style: TextStyle(color: cc.muted, height: 1.35, fontSize: 13.5),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (var i = 0; i < words.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: cc.soft, borderRadius: BorderRadius.circular(10), border: Border.all(color: cc.line)),
                      child: Text('${i + 1}. ${words[i]}', style: TextStyle(color: cc.ink, fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                ],
              ),
              CheckboxListTile(
                value: _ok,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => setState(() => _ok = v == true),
                title: const Text('I have written down my 12 words', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => copyText(context, widget.phrase, 'Words copied'), child: const Text('Copy words')),
          TextButton(onPressed: _ok ? () => Navigator.pop(context) : null, child: const Text('Continue')),
        ],
      ),
    );
  }
}
