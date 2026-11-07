import 'package:flutter/material.dart';

import '../screens/profile_screen.dart';
import '../theme/theme_controller.dart';
import '../widgets/widgets.dart';

/// Main frame with the bottom navigation: Feed, Search, Chats, Profile.
/// Each tab keeps its state when you switch.
class HomeShell extends StatefulWidget {
  final ThemeController themeController;
  const HomeShell({super.key, required this.themeController});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  Widget _placeholder(String title, IconData icon, String msg) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EmptyState(icon: icon, title: '$title coming soon', message: msg),
      );

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _placeholder('Feed', Icons.home_rounded, 'Posts, Thoughts, Moments and Reels will show here.'),
      _placeholder('Search', Icons.search_rounded, 'Find people and rooms here.'),
      _placeholder('Chats', Icons.chat_bubble_rounded, 'Private chats, groups and the public room will show here.'),
      ProfileScreen(themeController: widget.themeController),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Feed'),
          NavigationDestination(icon: Icon(Icons.search_rounded), selectedIcon: Icon(Icons.search_rounded), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}
