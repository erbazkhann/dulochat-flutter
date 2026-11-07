import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'db.dart';
import 'e2ee.dart';

/// Everything about the signed-in person: login state, live data from the server.
class Session extends ChangeNotifier {
  final DuloApi api = DuloApi();
  late final E2ee e2ee = E2ee(api);
  late final DuloDb db = DuloDb(api, e2ee);

  bool booting = true;
  String uid = '';
  String me = '';
  String? failMessage;
  String? pendingPhrase; // 12 recovery words shown once after signup

  // live data
  Map<String, dynamic> users = <String, dynamic>{};
  Map<String, dynamic> presence = <String, dynamic>{};
  Map<String, dynamic> userChats = <String, dynamic>{};
  Map<String, dynamic> userGroups = <String, dynamic>{};
  Map<String, dynamic> official = <String, dynamic>{};
  Map<String, dynamic> verified = <String, dynamic>{};
  Map<String, dynamic> clears = <String, dynamic>{};
  Map<String, dynamic> hidden = <String, dynamic>{};
  Map<String, dynamic> blocked = <String, dynamic>{};
  Map<String, dynamic> prefPin = <String, dynamic>{};
  Map<String, dynamic> prefMute = <String, dynamic>{};
  Map<String, dynamic> prefArchive = <String, dynamic>{};
  Map<String, dynamic> prefTheme = <String, dynamic>{};
  bool chatsLoaded = false;
  bool online = false;
  int pubUnread = 0;
  int pubReadTs = 0;
  List<Map<String, dynamic>> pubMsgs = <Map<String, dynamic>>[];
  String openChatKey = ''; // which chat screen is open (so we do not count it as unread)

  // groups (REST)
  List<Map<String, dynamic>> myGroups = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> pendingGroups = <Map<String, dynamic>>[];
  bool groupsLoaded = false;

  final List<DbSub> _subs = <DbSub>[];
  StreamSubscription<bool>? _connSub;
  StreamSubscription<Map<String, dynamic>>? _pushSub;
  Timer? _notifyTimer;

  bool get signedIn => uid.isNotEmpty;

  void _poke() {
    if (_notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 60), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  Future<void> boot() async {
    await api.init();
    db.onSignedOut = _onServerSignedOut;
    if (api.token != null) {
      try {
        final r = await api.get('/api/me');
        final t = r['token'];
        if (t is String) await api.saveToken(t);
        uid = (r['uid'] ?? '').toString();
        me = (r['username'] ?? '').toString();
        if (uid.isEmpty) throw ApiError('unauthorized');
        _begin();
      } on ApiError catch (e) {
        if (e.code == 'network') {
          // offline: keep the token and try to continue from the saved name
          final p = await SharedPreferences.getInstance();
          uid = p.getString('dulo-uid') ?? '';
          me = p.getString('dulo-me') ?? '';
          if (uid.isNotEmpty) {
            _begin();
          } else {
            await api.saveToken(null);
          }
        } else {
          await api.saveToken(null);
          failMessage = _failText(e);
        }
      }
    }
    booting = false;
    notifyListeners();
  }

  String _failText(ApiError e) {
    final c = e.code;
    final until = e.body['until'];
    String when() {
      if (until is num) {
        final d = DateTime.fromMillisecondsSinceEpoch(until.toInt());
        return ' until ${d.day}/${d.month}/${d.year}';
      }
      return '';
    }

    if (c == 'disabled') return 'Your account has been disabled.';
    if (c == 'restricted') return 'Your account is temporarily restricted${when()}.';
    if (c == 'device-restricted') return 'Access from this device has been restricted.';
    if (c == 'device-limit') return 'This device already has 3 accounts. You cannot create or log in to another account on it.';
    if (c == 'session-ended' || c == 'unauthorized') return 'You were logged out on this device. Please login again.';
    return '';
  }

  /// Friendly text for login / signup errors.
  String authMessage(Object e) {
    if (e is! ApiError) return 'Something went wrong. Try again.';
    final f = _failText(e);
    if (f.isNotEmpty) return f;
    switch (e.code) {
      case 'account-exists':
      case 'username-taken':
        return 'Already have an account? Please Login.';
      case 'user-not-found':
        return 'User not found';
      case 'wrong-password':
        return 'Wrong password. Please try again.';
      case 'username-reserved':
        return 'That username is reserved. Pick another one.';
      case 'invalid-name':
        return 'Enter your full name (2 to 40 letters).';
      case 'invalid-gender':
        return 'Please select your gender.';
      case 'bio-short':
        return 'Bio must be at least 10 words.';
      case 'invalid-bio':
        return 'Bio can be up to 150 characters.';
      case 'invalid-dob':
        return 'Please enter a valid date of birth (13 years or older).';
      case 'invalid-link':
        return 'That link does not look right. Example: yourwebsite.com';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-username':
        return 'Username must be 3 to 20 characters: letters, numbers, _ . -';
      case 'too-many-requests':
        return 'Too many attempts. Wait a minute and try again.';
      case 'network':
        return 'No internet connection.';
      default:
        return 'Something went wrong (${e.code}). Try again.';
    }
  }

  Future<void> _enter(Map<String, dynamic> r) async {
    await api.saveToken(r['token'] as String);
    uid = (r['uid'] ?? '').toString();
    me = (r['username'] ?? '').toString();
    final p = await SharedPreferences.getInstance();
    await p.setString('dulo-uid', uid);
    await p.setString('dulo-me', me);
    failMessage = null;
    _begin();
    notifyListeners();
  }

  Future<void> login(String username, String password, {bool reactivate = false}) async {
    final body = <String, dynamic>{'username': username, 'password': password, 'device': api.deviceId};
    if (reactivate) body['reactivate'] = true;
    final r = await api.request('POST', '/api/login', body: body, auth: false);
    await _enter(r);
  }

  Future<void> signup(Map<String, dynamic> fields) async {
    final body = Map<String, dynamic>.from(fields);
    body['device'] = api.deviceId;
    final r = await api.request('POST', '/api/signup', body: body, auth: false);
    pendingPhrase = r['phrase'] as String?;
    await _enter(r);
  }

  Future<void> logout() async {
    try {
      await db.remove('presence/$uid');
    } catch (_) {}
    _end();
    await api.saveToken(null);
    notifyListeners();
  }

  void _onServerSignedOut(String? code) {
    failMessage = code == null ? null : _failText(ApiError(code == 'unauthorized' ? 'session-ended' : code));
    _end();
    api.saveToken(null);
    notifyListeners();
  }

  // ---------- live data ----------
  void _begin() {
    db.start();
    e2ee.onUser(uid);
    db.update(<String, dynamic>{'users/$uid/name': me}).catchError((Object e) {});
    _connSub = db.connection.listen((up) {
      online = up;
      if (up) {
        db.onDisconnectRemove('presence/$uid');
        db.set('presence/$uid', <String, dynamic>{'name': me, 'ts': <String, dynamic>{'.sv': 'timestamp'}}).catchError((Object e) {});
        loadGroups();
      }
      _poke();
    });
    _pushSub = db.pushes.listen((m) {
      if (m['t'] == 'groups') loadGroups();
      _poke();
    });
    chatsLoaded = false;
    _watch('prefs/$uid', (v) {
      final m = v is Map ? v : <String, dynamic>{};
      prefPin = _map(m['pin']);
      prefMute = _map(m['mute']);
      prefTheme = _map(m['theme']);
      prefArchive = _map(m['archive']);
    });
    _watch('users', (v) => users = _map(v));
    _watch('presence', (v) => presence = _map(v));
    _watch('official', (v) => official = _map(v));
    _watch('verified', (v) => verified = _map(v));
    _watch('userChats/$uid', (v) {
      userChats = _map(v);
      chatsLoaded = true;
    });
    _watch('rel/$uid', (v) {
      final m = v is Map ? v : <String, dynamic>{};
      hidden = _map(m['hidden']);
      blocked = _map(m['blocked']);
    });
    _watch('userGroups/$uid', (v) => userGroups = _map(v));
    _watch('clears/$uid', (v) => clears = _map(v));
    _loadPubRead();
    _subs.add(db.listen('public/messages', (v) {
      final arr = <Map<String, dynamic>>[];
      if (v is Map) {
        v.forEach((k, x) {
          if (x is Map && x['ts'] is num && x['deleted'] != true) {
            arr.add(<String, dynamic>{'ts': (x['ts'] as num).toInt(), 'uid': x['uid']});
          }
        });
      }
      pubMsgs = arr;
      _recountPub();
      _poke();
    }, orderBy: 'ts', limitToLast: 100));
  }

  void _watch(String path, void Function(dynamic v) fn) {
    _subs.add(db.listen(path, (v) {
      fn(v);
      _poke();
    }, onError: (c) {}));
  }

  Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  Future<void> _loadPubRead() async {
    try {
      final p = await SharedPreferences.getInstance();
      pubReadTs = int.tryParse(p.getString('dulo-pubread:$uid') ?? '') ?? 0;
    } catch (_) {}
    _recountPub();
  }

  void _recountPub() {
    if (openChatKey == 'public') {
      markPublicRead();
      return;
    }
    pubUnread = pubMsgs.where((m) => (m['ts'] as int) > pubReadTs && m['uid'] != uid).length;
  }

  Future<void> markPublicRead() async {
    var latest = pubReadTs;
    for (final m in pubMsgs) {
      if ((m['ts'] as int) > latest) latest = m['ts'] as int;
    }
    pubReadTs = latest;
    pubUnread = 0;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('dulo-pubread:$uid', latest.toString());
    } catch (_) {}
    _poke();
  }

  void setOpenChat(String key) {
    openChatKey = key;
    if (key == 'public') markPublicRead();
  }

  Future<void> loadGroups() async {
    if (!signedIn) return;
    try {
      final r = await api.get('/api/groups/mine');
      myGroups = (r['groups'] as List? ?? <dynamic>[]).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      pendingGroups = (r['pending'] as List? ?? <dynamic>[]).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
    groupsLoaded = true;
    _poke();
  }

  void _end() {
    for (final s in _subs) {
      db.cancel(s);
    }
    _subs.clear();
    _connSub?.cancel();
    _pushSub?.cancel();
    db.stop();
    e2ee.onUser(null);
    uid = '';
    me = '';
    users = <String, dynamic>{};
    presence = <String, dynamic>{};
    userChats = <String, dynamic>{};
    userGroups = <String, dynamic>{};
    official = <String, dynamic>{};
    verified = <String, dynamic>{};
    clears = <String, dynamic>{};
    hidden = <String, dynamic>{};
    blocked = <String, dynamic>{};
    prefPin = <String, dynamic>{};
    prefMute = <String, dynamic>{};
    prefArchive = <String, dynamic>{};
    prefTheme = <String, dynamic>{};
    myGroups = <Map<String, dynamic>>[];
    pendingGroups = <Map<String, dynamic>>[];
    groupsLoaded = false;
    chatsLoaded = false;
    pubMsgs = <Map<String, dynamic>>[];
    pubUnread = 0;
  }

  // ---------- helpers for the screens ----------
  String nameOf(String u, [String? fallback]) {
    if (hidden[u] != null) return 'Unknown User';
    final x = users[u];
    if (x is Map && x['name'] is String) return x['name'] as String;
    return fallback ?? 'Unknown';
  }

  String? picOf(String u) {
    final x = users[u];
    if (x is Map && x['pic'] is String && (x['pic'] as String).isNotEmpty) return x['pic'] as String;
    return null;
  }

  bool isOnline(String u) => presence[u] != null;
  bool isOfficial(String u) => official[u] != null;
  bool isVerified(String u) => verified[u] != null;
  bool isMuted(String key) => prefMute[key] != null && prefMute[key] != false;

  String chatIdFor(String other) {
    final ids = <String>[uid, other]..sort();
    return ids.join('_');
  }

  int get dmUnread {
    var n = 0;
    userChats.forEach((u, v) {
      if (v is Map && v['unread'] is num && (v['unread'] as num) > 0 && prefArchive[u] == null) n += (v['unread'] as num).toInt();
    });
    return n;
  }

  int get groupUnread {
    var n = 0;
    userGroups.forEach((g, v) {
      if (v is Map && v['unread'] is num && (v['unread'] as num) > 0) n += (v['unread'] as num).toInt();
    });
    return n;
  }
}
