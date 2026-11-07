import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/util.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import 'chat_screen.dart';
import 'common.dart';

void openDm(BuildContext context, Session s, String other, [String? name]) {
  final id = s.chatIdFor(other);
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ChatScreen(session: s, ctx: ChatCtx(kind: 'dm', base: 'dms/$id', otherUid: other, title: s.nameOf(other, name))),
  ));
}

void openGroupChat(BuildContext context, Session s, Map<String, dynamic> g) {
  final id = (g['id'] ?? '').toString();
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ChatScreen(session: s, ctx: ChatCtx(kind: 'group', base: 'groups/$id', gid: id, title: (g['name'] ?? 'Group').toString())),
  ));
}

void openPublic(BuildContext context, Session s) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ChatScreen(session: s, ctx: const ChatCtx(kind: 'public', base: 'public', title: 'Public room')),
  ));
}

class ChatsScreen extends StatefulWidget {
  final Session session;
  const ChatsScreen({super.key, required this.session});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _archived = false;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_r);
    s.loadGroups();
  }

  void _r() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(_r);
    _tabs.dispose();
    super.dispose();
  }

  Widget _tabLabel(String t, int n) => Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[Text(t), if (n > 0) ...<Widget>[const SizedBox(width: 6), CountBadge(n)]],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cc = context.dulo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: cc.accent,
          unselectedLabelColor: cc.muted,
          indicatorColor: cc.accent,
          dividerColor: cc.line,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          tabs: <Widget>[_tabLabel('Public', s.pubUnread), _tabLabel('Private', s.dmUnread), _tabLabel('Groups', s.groupUnread)],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (_, __) => _tabs.index == 1
            ? FloatingActionButton.extended(
                onPressed: () => _newChat(context),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('New chat'),
              )
            : const SizedBox.shrink(),
      ),
      body: TabBarView(controller: _tabs, children: <Widget>[_publicTab(cc), _privateTab(cc), _groupsTab(cc)]),
    );
  }

  // ---------- public ----------
  Widget _publicTab(DuloColors cc) {
    final online = s.presence.keys.toList()..sort((a, b) => s.nameOf(a).toLowerCase().compareTo(s.nameOf(b).toLowerCase()));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openPublic(context, s),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: <Color>[cc.accent, const Color(0xFF0B6FC2)]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: <Widget>[
                Container(width: 48, height: 48, decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle), child: const Icon(Icons.public_rounded, color: Colors.white)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Public room', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                      Text('Talk with everyone on Dulochat', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                if (s.pubUnread > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(s.pubUnread > 99 ? '99+' : '${s.pubUnread}', style: TextStyle(color: cc.accent, fontWeight: FontWeight.w800))),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text('ONLINE NOW (${online.length})', style: TextStyle(color: cc.muted, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        ),
        if (online.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('Nobody is online right now.', textAlign: TextAlign.center, style: TextStyle(color: cc.muted))),
        ...online.map((u) {
          final me = u == s.uid;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: userAvatar(s, u, fallbackName: (s.presence[u] is Map ? (s.presence[u] as Map)['name'] : null)?.toString()),
            title: NameWithTick(name: s.nameOf(u, (s.presence[u] is Map ? (s.presence[u] as Map)['name'] : null)?.toString()) + (me ? ' (you)' : ''), official: s.isOfficial(u), verified: s.isVerified(u), style: TextStyle(color: cc.ink, fontWeight: FontWeight.w700, fontSize: 15.5)),
            subtitle: Text(me ? 'This is you' : 'Tap to send a private message', style: TextStyle(color: cc.muted, fontSize: 12.5)),
            onTap: me ? null : () => openDm(context, s, u),
          );
        }),
      ],
    );
  }

  // ---------- private ----------
  Widget _privateTab(DuloColors cc) {
    if (!s.chatsLoaded) return loadingBox();
    var ids = s.userChats.keys.where((u) => u != s.uid && s.hidden[u] == null).toList();
    final arch = ids.where((u) => s.prefArchive[u] != null).toList();
    ids = ids.where((u) => _archived ? s.prefArchive[u] != null : s.prefArchive[u] == null).toList();
    int ts(String u) {
      final v = s.userChats[u];
      return v is Map && v['ts'] is num ? (v['ts'] as num).toInt() : 0;
    }

    ids.sort((a, b) {
      final pa = s.prefPin[a] != null ? 1 : 0, pb = s.prefPin[b] != null ? 1 : 0;
      if (pa != pb) return pb - pa;
      return ts(b) - ts(a);
    });
    final children = <Widget>[];
    if (_archived || arch.isNotEmpty) {
      children.add(ListTile(
        leading: Icon(_archived ? Icons.arrow_back_rounded : Icons.archive_outlined, color: cc.accent),
        title: Text(_archived ? 'Back to chats' : 'Archived chats (${arch.length})', style: TextStyle(color: cc.ink, fontWeight: FontWeight.w700)),
        onTap: () => setState(() => _archived = !_archived),
      ));
    }
    if (ids.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.all(40),
        child: EmptyState(icon: Icons.chat_bubble_outline_rounded, title: _archived ? 'No archived chats' : 'No private chats yet', message: _archived ? '' : 'Tap "New chat" to message someone.'),
      ));
    }
    for (final u in ids) {
      final c = s.userChats[u] is Map ? Map<String, dynamic>.from(s.userChats[u] as Map) : <String, dynamic>{};
      final un = c['unread'] is num ? (c['unread'] as num).toInt() : 0;
      final pinned = s.prefPin[u] != null;
      children.add(InkWell(
        onTap: () => openDm(context, s, u),
        onLongPress: () => _chatMenu(u),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              userAvatar(s, u, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    NameWithTick(name: s.nameOf(u), official: s.isOfficial(u), verified: s.isVerified(u), style: TextStyle(color: cc.ink, fontWeight: un > 0 ? FontWeight.w800 : FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text((c['last'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: un > 0 ? cc.ink : cc.muted, fontSize: 14, fontWeight: un > 0 ? FontWeight.w600 : FontWeight.w400)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (c['ts'] is num) Text(shortTimeOf((c['ts'] as num).toInt()), style: TextStyle(color: un > 0 ? cc.accent : cc.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    if (s.isMuted(u)) Icon(Icons.volume_off_rounded, size: 15, color: cc.muted),
                    if (pinned) Icon(Icons.push_pin_rounded, size: 15, color: cc.muted),
                    if (un > 0) CountBadge(un),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ));
    }
    children.add(const SizedBox(height: 80));
    return RefreshIndicator(
      onRefresh: () async {
        await s.loadGroups();
      },
      child: ListView(children: children),
    );
  }

  void _chatMenu(String u) {
    final pinned = s.prefPin[u] != null;
    final muted = s.isMuted(u);
    final arch = s.prefArchive[u] != null;
    Future<void> setPref(String k, dynamic v) async {
      try {
        await s.db.set('prefs/${s.uid}/$k/$u', v);
      } catch (_) {}
    }

    final hour = 3600000;
    final now = DateTime.now().millisecondsSinceEpoch;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(pinned ? 'Unpin chat' : 'Pin chat'),
              onTap: () {
                Navigator.pop(ctx);
                setPref('pin', pinned ? null : true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(arch ? 'Unarchive chat' : 'Archive chat'),
              onTap: () {
                Navigator.pop(ctx);
                setPref('archive', arch ? null : true);
              },
            ),
            if (muted)
              ListTile(
                leading: const Icon(Icons.volume_up_outlined),
                title: const Text('Unmute'),
                onTap: () {
                  Navigator.pop(ctx);
                  setPref('mute', null);
                },
              )
            else ...<Widget>[
              ListTile(
                leading: const Icon(Icons.volume_off_outlined),
                title: const Text('Mute for 1 hour'),
                onTap: () {
                  Navigator.pop(ctx);
                  setPref('mute', now + hour);
                },
              ),
              ListTile(
                leading: const Icon(Icons.volume_off_outlined),
                title: const Text('Mute for 8 hours'),
                onTap: () {
                  Navigator.pop(ctx);
                  setPref('mute', now + 8 * hour);
                },
              ),
              ListTile(
                leading: const Icon(Icons.volume_off_outlined),
                title: const Text('Mute forever'),
                onTap: () {
                  Navigator.pop(ctx);
                  setPref('mute', true);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _newChat(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PeoplePicker(session: s, onPick: (u) => openDm(context, s, u))));
  }

  // ---------- groups ----------
  Widget _groupsTab(DuloColors cc) {
    if (!s.groupsLoaded) return loadingBox();
    final items = <Widget>[];
    if (s.myGroups.isEmpty && s.pendingGroups.isEmpty) {
      items.add(const Padding(padding: EdgeInsets.all(40), child: EmptyState(icon: Icons.groups_2_outlined, title: 'No groups yet', message: 'Groups you join or create will show here.')));
    }
    for (final g in s.myGroups) {
      final id = (g['id'] ?? '').toString();
      final ug = s.userGroups[id] is Map ? Map<String, dynamic>.from(s.userGroups[id] as Map) : <String, dynamic>{};
      final un = ug['unread'] is num ? (ug['unread'] as num).toInt() : 0;
      final pic = g['pic'] is String ? g['pic'] as String : null;
      items.add(ListTile(
        leading: DuloAvatar(name: (g['name'] ?? 'G').toString(), size: 52, dataUrl: pic != null && pic.startsWith('data:') ? pic : null, imageUrl: pic != null && pic.startsWith('http') ? pic : null),
        title: Text('${g['name'] ?? ''}${g['privacy'] == 'private' ? ' (Private)' : ''}', style: TextStyle(color: cc.ink, fontWeight: FontWeight.w700, fontSize: 16)),
        subtitle: Text((ug['last'] ?? '${g['members'] ?? 0} members').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cc.muted)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (ug['ts'] is num) Text(shortTimeOf((ug['ts'] as num).toInt()), style: TextStyle(color: cc.muted, fontSize: 12)),
            const SizedBox(height: 4),
            CountBadge(un),
          ],
        ),
        onTap: () => openGroupChat(context, s, g),
      ));
    }
    for (final g in s.pendingGroups) {
      items.add(ListTile(
        leading: DuloAvatar(name: (g['name'] ?? 'G').toString(), size: 52),
        title: Text((g['name'] ?? '').toString(), style: TextStyle(color: cc.ink, fontWeight: FontWeight.w700)),
        subtitle: Text('Waiting for approval', style: TextStyle(color: cc.muted)),
      ));
    }
    return RefreshIndicator(onRefresh: s.loadGroups, child: ListView(children: items));
  }
}

/// Pick a person to start a private chat with.
class PeoplePicker extends StatefulWidget {
  final Session session;
  final void Function(String uid) onPick;
  const PeoplePicker({super.key, required this.session, required this.onPick});

  @override
  State<PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<PeoplePicker> {
  final _q = TextEditingController();
  Session get s => widget.session;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.dulo;
    final q = _q.text.trim().toLowerCase();
    final ids = s.users.keys.where((u) => u != s.uid && s.hidden[u] == null && s.nameOf(u).toLowerCase().contains(q)).toList()
      ..sort((a, b) {
        final oa = s.isOnline(a) ? 0 : 1, ob = s.isOnline(b) ? 0 : 1;
        if (oa != ob) return oa - ob;
        return s.nameOf(a).toLowerCase().compareTo(s.nameOf(b).toLowerCase());
      });
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: DuloTextField(controller: _q, hint: 'Search people', prefixIcon: Icons.search_rounded, onChanged: (_) => setState(() {})),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: ids.length,
              itemBuilder: (ctx, i) {
                final u = ids[i];
                return ListTile(
                  leading: userAvatar(s, u),
                  title: NameWithTick(name: s.nameOf(u), official: s.isOfficial(u), verified: s.isVerified(u), style: TextStyle(color: cc.ink, fontWeight: FontWeight.w700)),
                  subtitle: Text(s.isOnline(u) ? 'online' : '', style: TextStyle(color: cc.accent, fontSize: 12.5)),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onPick(u);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
