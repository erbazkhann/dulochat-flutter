import 'package:flutter/material.dart';

import '../core/session.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import 'common.dart';
import 'user_profile.dart';

/// Find people on Dulochat.
class SearchScreen extends StatefulWidget {
  final Session session;
  const SearchScreen({super.key, required this.session});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_r);
  }

  void _r() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(_r);
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.dulo;
    final q = _q.text.trim().toLowerCase().replaceFirst('@', '');
    final ids = s.users.keys.where((u) => s.hidden[u] == null && (q.isEmpty || s.nameOf(u).toLowerCase().contains(q))).toList()
      ..sort((a, b) {
        final oa = s.isOnline(a) ? 0 : 1, ob = s.isOnline(b) ? 0 : 1;
        if (oa != ob) return oa - ob;
        return s.nameOf(a).toLowerCase().compareTo(s.nameOf(b).toLowerCase());
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: DuloTextField(controller: _q, hint: 'Search people by username', prefixIcon: Icons.search_rounded, onChanged: (_) => setState(() {})),
          ),
          Expanded(
            child: ids.isEmpty
                ? const EmptyState(icon: Icons.search_off_rounded, title: 'No one found', message: 'Try another name.')
                : ListView.builder(
                    itemCount: ids.length,
                    itemBuilder: (ctx, i) {
                      final u = ids[i];
                      return ListTile(
                        leading: userAvatar(s, u),
                        title: NameWithTick(name: s.nameOf(u) + (u == s.uid ? ' (you)' : ''), official: s.isOfficial(u), verified: s.isVerified(u), style: TextStyle(color: cc.ink, fontWeight: FontWeight.w700, fontSize: 15.5)),
                        subtitle: s.isOnline(u) ? Text('online', style: TextStyle(color: cc.accent, fontSize: 12.5)) : null,
                        onTap: () => openProfile(context, s, u),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
