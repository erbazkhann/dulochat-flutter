import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/db.dart';
import '../core/session.dart';
import '../core/util.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import 'common.dart';

/// Which conversation a chat screen shows.
class ChatCtx {
  final String kind; // public | dm | group
  final String base; // path in the database
  final String? otherUid;
  final String? gid;
  final String title;
  const ChatCtx({required this.kind, required this.base, this.otherUid, this.gid, required this.title});

  String get key => kind == 'public' ? 'public' : (kind == 'dm' ? otherUid! : gid!);
  String get room => kind == 'public' ? 'public' : (kind == 'dm' ? base.split('/').last : gid!);
}

const Map<String, String> kReacts = <String, String>{
  'like': '\u{1F44D}',
  'love': '❤️',
  'haha': '\u{1F602}',
  'wow': '\u{1F62E}',
  'sad': '\u{1F622}',
  'fire': '\u{1F525}',
};

String previewOf(Map<String, dynamic> m) {
  final t = m['type'];
  if (t == 'thought') return 'Thought';
  if (t == 'poll') return 'Poll: ${((m['poll'] is Map ? (m['poll'] as Map)['q'] : '') ?? '').toString().characters.take(50)}';
  if (t == 'image' && m['once'] == true) return 'Photo (view once)';
  if (t == 'image' && m['album'] != null) return 'Album (${m['album'].toString().split(',').length} photos)';
  if (t == 'image') return 'Photo';
  if (t == 'gif') return 'GIF';
  if (t == 'voice') return 'Voice message';
  if (t == 'video') return 'Video';
  if (t == 'file') return 'File: ${(m['name'] ?? '').toString().characters.take(40)}';
  if (t == 'sticker') return 'Sticker';
  if (t == 'call') return 'Call';
  return (m['text'] ?? '').toString().characters.take(60).toString();
}

class ChatScreen extends StatefulWidget {
  final Session session;
  final ChatCtx ctx;
  const ChatScreen({super.key, required this.session, required this.ctx});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  Session get s => widget.session;
  ChatCtx get c => widget.ctx;

  final List<DbSub> _subs = <DbSub>[];
  List<Map<String, dynamic>> _msgs = <Map<String, dynamic>>[];
  bool _live = false;
  String _problem = '';
  int _otherRead = 0;
  Map<String, dynamic> _typing = <String, dynamic>{};
  Map<String, dynamic>? _pin;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Map<String, dynamic>? _reply;
  Map<String, dynamic>? _editing;
  bool _typingOn = false;
  Timer? _typingTimer;
  int _readSent = 0;
  int _limit = 150;
  String _status = '';
  bool _locked = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.setOpenChat(c.key);
    s.addListener(_onSession);
    _prepare();
  }

  Future<void> _prepare() async {
    if (c.kind != 'public') {
      final ok = await s.e2ee.gate();
      if (!mounted) return;
      if (!ok || s.e2ee.state != 'ready') {
        setState(() {
          _locked = true;
          _ready = true;
        });
        return;
      }
      if (c.kind == 'group') {
        try {
          await s.e2ee.groupReady(c.gid!, force: true);
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _locked = false;
      _ready = true;
    });
    _attach();
  }

  void _attach() {
    for (final x in _subs) {
      s.db.cancel(x);
    }
    _subs.clear();
    _subs.add(s.db.listen('${c.base}/messages', (v) {
      final arr = <Map<String, dynamic>>[];
      if (v is Map) {
        v.forEach((k, x) {
          if (x is Map && x['ts'] is num && x['type'] is String) {
            final m = Map<String, dynamic>.from(x);
            m['k'] = k.toString();
            m['ts'] = (x['ts'] as num).toInt();
            arr.add(m);
          }
        });
      }
      arr.sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
      if (!mounted) return;
      setState(() {
        _msgs = arr;
        _live = true;
        _problem = '';
      });
      _markRead();
    }, onError: (code) {
      if (!mounted) return;
      setState(() {
        _problem = 'denied';
        _live = true;
      });
    }, orderBy: 'ts', limitToLast: _limit));
    _subs.add(s.db.listen('typing/${c.room}', (v) {
      if (mounted) setState(() => _typing = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{});
    }, onError: (_) {}));
    if (c.kind != 'public') {
      _subs.add(s.db.listen('${c.base}/pin', (v) {
        if (mounted) setState(() => _pin = v is Map ? Map<String, dynamic>.from(v) : null);
      }, onError: (_) {}));
    }
    if (c.kind == 'dm') {
      _subs.add(s.db.listen('${c.base}/reads/${c.otherUid}', (v) {
        if (mounted) setState(() => _otherRead = v is num ? v.toInt() : 0);
      }, onError: (_) {}));
    }
  }

  void _onSession() {
    // clear unread while this chat is open
    if (c.kind == 'dm') {
      final u = s.userChats[c.otherUid];
      if (u is Map && u['unread'] is num && (u['unread'] as num) > 0) {
        s.db.set('userChats/${s.uid}/${c.otherUid}/unread', 0).catchError((Object e) {});
      }
    } else if (c.kind == 'group') {
      final u = s.userGroups[c.gid];
      if (u is Map && u['unread'] is num && (u['unread'] as num) > 0) {
        s.db.set('userGroups/${s.uid}/${c.gid}/unread', 0).catchError((Object e) {});
      }
    }
    if (mounted) setState(() {});
  }

  void _markRead() {
    if (c.kind != 'dm') return;
    var last = 0;
    for (var i = _msgs.length - 1; i >= 0; i--) {
      if (_msgs[i]['uid'] != s.uid) {
        last = _msgs[i]['ts'] as int;
        break;
      }
    }
    if (last == 0 || last <= _readSent) return;
    _readSent = last;
    s.db.set('${c.base}/reads/${s.uid}', svTimestamp()).catchError((Object e) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    s.db.setVisible(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) _markRead();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.removeListener(_onSession);
    s.setOpenChat('');
    for (final x in _subs) {
      s.db.cancel(x);
    }
    _stopTyping();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------- typing ----------
  void _pingTyping() {
    if (_input.text.trim().isEmpty) {
      _stopTyping();
      return;
    }
    final p = 'typing/${c.room}/${s.uid}';
    if (!_typingOn) {
      s.db.onDisconnectRemove(p);
      s.db.set(p, s.me).catchError((Object e) {});
      _typingOn = true;
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    if (_typingOn) {
      s.db.remove('typing/${c.room}/${s.uid}').catchError((Object e) {});
      s.db.onDisconnectCancel('typing/${c.room}/${s.uid}');
    }
    _typingOn = false;
  }

  // ---------- sending ----------
  String _errText(Object e) {
    final code = e is ApiError ? e.code : e.toString();
    if (code == 'slow-down') return 'You are sending too fast. Wait a few seconds.';
    if (code == 'spam') return 'That looks like spam, so it was not sent.';
    if (code == 'peer-no-e2e') return 'This user has not turned on secure chat yet. Ask them to open Dulochat once, then try again.';
    if (code == 'e2e-not-ready') return 'Secure chat is not ready yet. Finish the chat key setup first.';
    if (code == 'no-group-key') return 'Waiting for a group member to share the secure key. Try again in a moment.';
    if (code == 'rekey') return 'The group key was updated. Please send again.';
    if (code == 'dm-pending') return 'Waiting for the user to accept your chat request.';
    if (code == 'dm-accept-first') return 'Accept this chat request first, then you can reply.';
    if (code == 'dm-rejected') return 'This user did not accept your chat request.';
    if (code.toLowerCase().contains('permission')) return 'The server rejected that message.';
    if (code == 'network') return 'No connection. Message not sent.';
    return 'Message not sent. Try again.';
  }

  void _say(String t) {
    if (mounted) toast(context, t);
  }

  Future<void> _postMessage(Map<String, dynamic> fields) async {
    final msg = <String, dynamic>{'by': s.me, 'uid': s.uid, 'ts': DateTime.now().millisecondsSinceEpoch, 'type': fields['type']};
    for (final k in <String>['text', 'mid', 'dur', 'name', 'size', 'mime', 'url', 'reply', 'once', 'poll', 'fwd', 'men', 'album', 'tref']) {
      if (fields[k] != null) msg[k] = fields[k];
    }
    if (c.kind == 'public') {
      await s.db.push('public/messages', msg);
    } else if (c.kind == 'group') {
      await s.db.push('groups/${c.gid}/messages', msg);
    } else {
      final id = pushKey();
      final prev = previewOf(msg);
      final mine = 'userChats/${s.uid}/${c.otherUid}', theirs = 'userChats/${c.otherUid}/${s.uid}';
      await s.db.update(<String, dynamic>{
        '${c.base}/messages/$id': msg,
        '$mine/last': prev,
        '$mine/ts': msg['ts'],
        '$mine/unread': 0,
        '$theirs/last': prev,
        '$theirs/ts': msg['ts'],
        '$theirs/unread': svIncrement(1),
      });
    }
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    if (_editing != null) {
      await _saveEdit(t);
      return;
    }
    _stopTyping();
    final rp = _reply;
    final text = t.characters.take(1000).toString();
    setState(() {
      _input.clear();
      _reply = null;
    });
    try {
      await _postMessage(<String, dynamic>{'type': 'text', 'text': text, 'reply': rp});
      _toBottom();
    } catch (e) {
      if (mounted) {
        setState(() {
          _input.text = text;
          _reply = rp;
        });
      }
      _say(_errText(e));
    }
  }

  Future<void> _saveEdit(String t) async {
    final m = _editing!;
    setState(() {
      _editing = null;
      _input.clear();
    });
    if (t == (m['text'] ?? '').toString()) return;
    final upd = <String, dynamic>{};
    final p = '${c.base}/messages/${m['k']}';
    final txt = t.characters.take(1000).toString();
    upd['$p/text'] = txt;
    upd['$p/edited'] = DateTime.now().millisecondsSinceEpoch;
    if (c.kind == 'dm') {
      final uc = s.userChats[c.otherUid];
      if (uc is Map && uc['ts'] == m['ts']) {
        final short = txt.characters.take(60).toString();
        upd['userChats/${s.uid}/${c.otherUid}/last'] = short;
        upd['userChats/${c.otherUid}/${s.uid}/last'] = short;
      }
    }
    try {
      await s.db.update(upd);
    } catch (e) {
      _say('Could not edit the message. Try again.');
    }
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    if (m['uid'] != s.uid) return;
    final p = '${c.base}/messages/${m['k']}';
    final upd = <String, dynamic>{'$p/deleted': true};
    for (final f in <String>['text', 'mid', 'dur', 'reply', 'tref']) {
      upd['$p/$f'] = null;
    }
    if (c.kind == 'dm') {
      final uc = s.userChats[c.otherUid];
      if (uc is Map && uc['ts'] == m['ts']) {
        upd['userChats/${s.uid}/${c.otherUid}/last'] = 'Message deleted';
        upd['userChats/${c.otherUid}/${s.uid}/last'] = 'Message deleted';
      }
    }
    try {
      await s.db.update(upd);
    } catch (e) {
      _say('Could not delete the message. Try again.');
    }
  }

  Future<void> _react(Map<String, dynamic> m, String key) async {
    final cur = m['react'] is Map ? (m['react'] as Map)[s.uid] : null;
    HapticFeedback.selectionClick();
    try {
      await s.db.set('${c.base}/messages/${m['k']}/react/${s.uid}', cur == key ? null : key);
    } catch (e) {
      _say(_errText(e));
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  String _snip(Map<String, dynamic> m) {
    final t = previewOf(m);
    return t.characters.take(100).toString();
  }

  void _setReply(Map<String, dynamic> m) {
    setState(() {
      _editing = null;
      _reply = <String, dynamic>{'by': m['by'] ?? '', 'snip': _snip(m), 'k': m['k']};
    });
  }

  void _msgSheet(Map<String, dynamic> m) {
    if (m['deleted'] == true || m['type'] == 'call' || m['type'] == 'sys') return;
    final mine = m['uid'] == s.uid;
    final isText = m['type'] == 'text';
    final cc = context.dulo;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: cc.surface,
      builder: (ctx) {
        final cur = m['react'] is Map ? (m['react'] as Map)[s.uid] : null;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: kReacts.entries
                      .map((e) => GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                              _react(m, e.key);
                            },
                            child: Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: cur == e.key ? cc.accent.withAlpha(50) : cc.soft, shape: BoxShape.circle),
                              child: Text(e.value, style: const TextStyle(fontSize: 24)),
                            ),
                          ))
                      .toList(),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setReply(m);
                },
              ),
              if (isText)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copy'),
                  onTap: () {
                    Navigator.pop(ctx);
                    copyText(context, (m['text'] ?? '').toString());
                  },
                ),
              if (mine && isText && m['once'] != true)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _reply = null;
                      _editing = m;
                      _input.text = (m['text'] ?? '').toString();
                      _input.selection = TextSelection.collapsed(offset: _input.text.length);
                    });
                  },
                ),
              if (c.kind != 'public' && (c.kind == 'dm' || _isGroupAdmin()))
                ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: Text(_pin != null && _pin!['k'] == m['k'] ? 'Unpin message' : 'Pin message'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _togglePin(m);
                  },
                ),
              if (mine)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: cc.danger),
                  title: Text('Delete', style: TextStyle(color: cc.danger)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await confirmDialog(context, 'Delete message?', 'This message will be deleted for everyone.', yes: 'Delete', danger: true);
                    if (ok) _delete(m);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  bool _isGroupAdmin() {
    for (final g in s.myGroups) {
      if (g['id'] == c.gid) return g['role'] == 'owner' || g['role'] == 'admin';
    }
    return false;
  }

  Future<void> _togglePin(Map<String, dynamic> m) async {
    try {
      if (_pin != null && _pin!['k'] == m['k']) {
        await s.db.remove('${c.base}/pin');
      } else {
        await s.db.set('${c.base}/pin', <String, dynamic>{'k': m['k'], 'snip': _snip(m), 'by': s.me});
      }
    } catch (_) {
      _say('Could not pin that.');
    }
  }

  // ---------- build ----------
  List<Map<String, dynamic>> get _visible {
    final cl = c.kind == 'dm' ? ((s.clears[c.otherUid] as num?)?.toInt() ?? 0) : 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return _msgs.where((m) {
      if (m['gone'] == true) return false;
      if (m['exp'] is num && (m['exp'] as num) < now) return false;
      if (c.kind == 'dm' && (m['ts'] as int) <= cl) return false;
      return true;
    }).toList();
  }

  String _subtitle() {
    final names = _typing.entries.where((e) => e.key != s.uid).map((e) => e.value.toString()).toList();
    if (c.kind == 'dm') {
      if (names.isNotEmpty) return 'typing...';
      return s.isOnline(c.otherUid!) ? 'online' : '';
    }
    if (names.isEmpty) {
      if (c.kind == 'public') return '${s.presence.length} online';
      return '';
    }
    if (names.length == 1) return '${names[0]} is typing...';
    if (names.length == 2) return '${names[0]} and ${names[1]} are typing...';
    return '${names.length} people are typing...';
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.dulo;
    final other = c.otherUid;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: <Widget>[
            if (c.kind == 'dm' && other != null) userAvatar(s, other, size: 38) else if (c.kind == 'group') _groupAv(38) else const DuloAvatar(name: 'P', size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(c.kind == 'dm' ? s.nameOf(other!, c.title) : c.title,
                      overflow: TextOverflow.ellipsis, style: TextStyle(color: cc.ink, fontSize: 17, fontWeight: FontWeight.w800)),
                  if (_subtitle().isNotEmpty) Text(_subtitle(), style: TextStyle(color: cc.accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          if (!s.online)
            Container(
              width: double.infinity,
              color: cc.danger.withAlpha(30),
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text('Connecting...', textAlign: TextAlign.center, style: TextStyle(color: cc.danger, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          if (_pin != null) _pinBar(cc),
          Expanded(child: _body(cc)),
          if (!_locked && _ready) _composer(cc),
        ],
      ),
    );
  }

  Widget _groupAv(double size) {
    String? pic;
    for (final g in s.myGroups) {
      if (g['id'] == c.gid && g['pic'] is String) pic = g['pic'] as String;
    }
    return DuloAvatar(name: c.title, dataUrl: pic != null && pic.startsWith('data:') ? pic : null, imageUrl: pic != null && pic.startsWith('http') ? pic : null, size: size);
  }

  Widget _pinBar(DuloColors cc) {
    return InkWell(
      onTap: () {},
      child: Container(
        width: double.infinity,
        color: cc.soft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(Icons.push_pin_rounded, size: 16, color: cc.accent),
            const SizedBox(width: 8),
            Expanded(child: Text((_pin!['snip'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cc.ink, fontSize: 13.5))),
          ],
        ),
      ),
    );
  }

  Widget _body(DuloColors cc) {
    if (!_ready) return loadingBox();
    if (_locked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.lock_outline_rounded, size: 56, color: cc.accent),
              const SizedBox(height: 14),
              Text('Chats are locked', style: TextStyle(color: cc.ink, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Approve this device or enter your chat key to read your private chats and groups.', textAlign: TextAlign.center, style: TextStyle(color: cc.muted)),
              const SizedBox(height: 18),
              DuloButton(
                label: 'Unlock chats',
                onPressed: () {
                  setState(() => _ready = false);
                  _prepare();
                },
              ),
            ],
          ),
        ),
      );
    }
    if (_problem == 'denied') {
      return const EmptyState(icon: Icons.block_rounded, title: 'Cannot open this chat', message: 'The server did not allow you to read it.');
    }
    if (!_live) return loadingBox();
    final list = _visible;
    if (list.isEmpty) {
      return EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'No messages yet', message: c.kind == 'public' ? 'Say hello to everyone.' : 'Send the first message.');
    }
    // newest first, list is reversed so the bottom stays pinned
    final rev = list.reversed.toList();
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      itemCount: rev.length + 1,
      itemBuilder: (ctx, i) {
        if (i == rev.length) {
          if (_msgs.length >= _limit) {
            return Center(
              child: TextButton(
                onPressed: () {
                  _limit += 150;
                  _attach();
                },
                child: const Text('Load older messages'),
              ),
            );
          }
          return const SizedBox(height: 4);
        }
        final m = rev[i];
        final older = i + 1 < rev.length ? rev[i + 1] : null;
        final showDay = older == null || dayLabelOf(older['ts'] as int) != dayLabelOf(m['ts'] as int);
        final grouped = older != null && !showDay && older['uid'] == m['uid'] && older['type'] != 'sys' && older['type'] != 'call';
        return Column(
          children: <Widget>[
            if (showDay) _dayChip(cc, dayLabelOf(m['ts'] as int)),
            _row(cc, m, grouped),
          ],
        );
      },
    );
  }

  Widget _dayChip(DuloColors cc, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: cc.soft, borderRadius: BorderRadius.circular(12)),
            child: Text(t, style: TextStyle(color: cc.muted, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      );

  Widget _row(DuloColors cc, Map<String, dynamic> m, bool grouped) {
    final mine = m['uid'] == s.uid;
    if (m['type'] == 'sys' && m['deleted'] != true) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
        child: Text((m['text'] ?? '').toString(), textAlign: TextAlign.center, style: TextStyle(color: cc.muted, fontSize: 12.5)),
      );
    }
    if (m['type'] == 'call' && m['deleted'] != true) {
      final missed = m['status'] == 'missed';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(color: cc.soft, borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(missed ? Icons.call_missed_rounded : Icons.call_rounded, size: 16, color: missed && m['caller'] != s.uid ? cc.danger : cc.accent),
                const SizedBox(width: 6),
                Text(missed ? (m['caller'] == s.uid ? 'No answer' : 'Missed call') : 'Voice call', style: TextStyle(color: cc.ink, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(width: 8),
                Text(timeOf(m['ts'] as int), style: TextStyle(color: cc.muted, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }
    final deleted = m['deleted'] == true;
    final bg = mine ? cc.mine : cc.soft;
    final ink = mine ? cc.mineInk : cc.ink;
    final sub = mine ? cc.mineTime : cc.muted;
    final senderUid = (m['uid'] ?? '').toString();
    final showSender = !mine && !grouped && (c.kind == 'public' || c.kind == 'group');
    final seen = mine && c.kind == 'dm' && (m['ts'] as int) <= _otherRead;
    final children = <Widget>[];
    if (showSender) {
      final nm = s.hidden[senderUid] != null ? 'Unknown User' : (m['by'] ?? 'anonymous').toString();
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: NameWithTick(
          name: nm,
          official: s.isOfficial(senderUid),
          verified: s.isVerified(senderUid),
          style: TextStyle(color: HSLColor.fromAHSL(1, (senderUid.hashCode % 360).abs().toDouble(), 0.6, cc.bg.computeLuminance() > 0.5 ? 0.38 : 0.7).toColor(), fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ));
    }
    if (deleted) {
      children.add(Text(mine ? 'You deleted this message' : 'This message was deleted', style: TextStyle(color: sub, fontStyle: FontStyle.italic, fontSize: 14.5)));
    } else {
      if (m['fwd'] is Map) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text('Forwarded from ${(m['fwd'] as Map)['by'] ?? '?'}', style: TextStyle(color: sub, fontSize: 12, fontStyle: FontStyle.italic)),
        ));
      }
      if (m['reply'] is Map) {
        final r = m['reply'] as Map;
        children.add(Container(
          margin: const EdgeInsets.only(bottom: 5),
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
          decoration: BoxDecoration(color: Colors.black.withAlpha(mine ? 40 : 14), borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: mine ? Colors.white : cc.accent, width: 3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text((r['by'] ?? '').toString(), style: TextStyle(color: mine ? Colors.white : cc.accent, fontWeight: FontWeight.w800, fontSize: 12.5)),
              Text((r['snip'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: ink.withAlpha(220), fontSize: 13)),
            ],
          ),
        ));
      }
      children.add(_content(cc, m, ink, sub));
    }
    final meta = <Widget>[];
    if (m['edited'] != null && !deleted) meta.add(Text('edited ', style: TextStyle(color: sub, fontSize: 11)));
    meta.add(Text(timeOf(m['ts'] as int), style: TextStyle(color: sub, fontSize: 11)));
    if (mine && c.kind == 'dm' && !deleted) {
      meta.add(const SizedBox(width: 4));
      meta.add(Icon(seen ? Icons.done_all_rounded : Icons.done_rounded, size: 14, color: seen ? Colors.white : sub));
    }
    children.add(Padding(padding: const EdgeInsets.only(top: 3), child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: meta)));
    if (!deleted && m['react'] is Map) children.add(_reacts(cc, m, mine));
    return GestureDetector(
      onLongPress: () => _msgSheet(m),
      onDoubleTap: deleted ? null : () => _react(m, 'like'),
      child: Dismissible(
        key: ValueKey<String>('m${m['k']}'),
        direction: deleted ? DismissDirection.none : DismissDirection.startToEnd,
        confirmDismiss: (_) async {
          _setReply(m);
          return false;
        },
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
            margin: EdgeInsets.only(left: 12, right: 12, top: grouped ? 2 : 6, bottom: 1),
            padding: const EdgeInsets.fromLTRB(12, 8, 11, 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 5),
                bottomRight: Radius.circular(mine ? 5 : 18),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }

  Widget _reacts(DuloColors cc, Map<String, dynamic> m, bool mine) {
    final cnt = <String, int>{};
    (m['react'] as Map).forEach((u, e) {
      if (e is String) cnt[e] = (cnt[e] ?? 0) + 1;
    });
    if (cnt.isEmpty) return const SizedBox.shrink();
    final my = (m['react'] as Map)[s.uid];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: cnt.entries
            .map((e) => GestureDetector(
                  onTap: () => _react(m, e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: my == e.key ? cc.accent.withAlpha(60) : Colors.black.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${kReacts[e.key] ?? e.key}${e.value > 1 ? ' ${e.value}' : ''}', style: const TextStyle(fontSize: 13)),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _content(DuloColors cc, Map<String, dynamic> m, Color ink, Color sub) {
    final t = m['type'];
    if (t == 'text') {
      return Text((m['text'] ?? '').toString(), style: TextStyle(color: ink, fontSize: 15.5, height: 1.3));
    }
    if (t == 'gif' && m['url'] is String && (m['url'] as String).startsWith('https://')) {
      return ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(m['url'] as String, width: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Text('GIF', style: TextStyle(color: ink))));
    }
    if (t == 'image' && m['mid'] != null) {
      return _MediaImage(session: s, path: '${c.base}/media/${m['mid']}', once: m['once'] == true);
    }
    final label = previewOf(m);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.insert_drive_file_outlined, size: 18, color: ink),
        const SizedBox(width: 6),
        Flexible(child: Text('$label (open it on the web app for now)', style: TextStyle(color: ink, fontSize: 14))),
      ],
    );
  }

  Widget _composer(DuloColors cc) {
    final bar = _editing != null || _reply != null;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(color: cc.bg, border: Border(top: BorderSide(color: cc.line))),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (bar)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                decoration: BoxDecoration(color: cc.soft, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: cc.accent, width: 3))),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(_editing != null ? 'Editing message' : 'Replying to ${_reply!['by'] == s.me ? 'yourself' : _reply!['by']}', style: TextStyle(color: cc.accent, fontWeight: FontWeight.w800, fontSize: 12.5)),
                          Text(_editing != null ? (_editing!['text'] ?? '').toString() : (_reply!['snip'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cc.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(() {
                        if (_editing != null) _input.clear();
                        _editing = null;
                        _reply = null;
                      }),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) {
                      _pingTyping();
                      setState(() {});
                    },
                    style: TextStyle(color: cc.ink, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Message',
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cc.line)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cc.line)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cc.accent, width: 1.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: _input.text.trim().isEmpty ? cc.soft : cc.accent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _input.text.trim().isEmpty ? null : _send,
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: Icon(_editing != null ? Icons.check_rounded : Icons.send_rounded, color: _input.text.trim().isEmpty ? cc.muted : cc.accentInk, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Image inside a chat bubble. The picture itself is stored (encrypted) at base/media/<id>.
class _MediaImage extends StatefulWidget {
  final Session session;
  final String path;
  final bool once;
  const _MediaImage({required this.session, required this.path, required this.once});
  @override
  State<_MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<_MediaImage> {
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};
  Uint8List? _bytes;
  bool _fail = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _bytes = _cache[widget.path];
    if (_bytes == null && !widget.once) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _fail = false;
    });
    try {
      final v = await widget.session.db.once(widget.path);
      if (v is String && v.startsWith('data:') && v.contains(',')) {
        final b = base64.decode(v.substring(v.indexOf(',') + 1));
        _cache[widget.path] = b;
        if (mounted) setState(() => _bytes = b);
      } else {
        if (mounted) setState(() => _fail = true);
      }
    } catch (_) {
      if (mounted) setState(() => _fail = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.dulo;
    if (widget.once && _bytes == null) {
      return TextButton.icon(onPressed: _load, icon: const Icon(Icons.visibility_outlined), label: const Text('Tap to view photo'));
    }
    if (_bytes != null) {
      return GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(children: <Widget>[
              Center(child: InteractiveViewer(child: Image.memory(_bytes!))),
              Positioned(top: 30, left: 8, child: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.pop(context))),
            ]),
          ),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(_bytes!, width: 230, fit: BoxFit.cover, gaplessPlayback: true)),
      );
    }
    return Container(
      width: 200,
      height: 140,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: cc.line, borderRadius: BorderRadius.circular(10)),
      child: _fail ? TextButton(onPressed: _load, child: const Text('Tap to retry')) : const CircularProgressIndicator(strokeWidth: 2.4),
    );
  }
}
