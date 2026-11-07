import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config.dart';
import 'api.dart';
import 'e2ee.dart';
import 'util.dart';

typedef SnapCb = void Function(dynamic value);
typedef ErrCb = void Function(String code);

class DbSub {
  final int id;
  final String path;
  final Map<String, dynamic>? q;
  final SnapCb cb;
  final ErrCb? errCb;
  bool sent = false;
  Future<void>? chain;
  bool dead = false;
  DbSub(this.id, this.path, this.q, this.cb, this.errCb);
}

/// Realtime database client (same protocol as the web app talking to server.js).
class DuloDb {
  final DuloApi api;
  final E2ee e2ee;
  DuloDb(this.api, this.e2ee);

  WebSocket? _ws;
  bool _open = false;
  bool authed = false;
  int _retry = 0;
  Timer? _retryTimer;
  int _nextSub = 1;
  int _nextRid = 1;
  final Map<int, DbSub> _subs = <int, DbSub>{};
  final Map<int, Completer<dynamic>> _waiting = <int, Completer<dynamic>>{};
  final List<void Function()> _queue = <void Function()>[];
  final Map<String, Map<String, dynamic>> _od = <String, Map<String, dynamic>>{};

  /// true while connected and signed in to the server
  final StreamController<bool> _connC = StreamController<bool>.broadcast();
  Stream<bool> get connection => _connC.stream;

  /// pushes from the server: notif, groups, friends, dmreq
  final StreamController<Map<String, dynamic>> _pushC = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get pushes => _pushC.stream;

  /// called when the server says this session is over (code 4001 or auth failure)
  void Function(String? code)? onSignedOut;

  String? lastFailCode;

  bool _wantOn = false;

  void start() {
    _wantOn = true;
    _connect();
  }

  Future<void> _connect() async {
    if (_ws != null || api.token == null || !_wantOn) return;
    final host = AppConfig.server.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    WebSocket ws;
    try {
      ws = await WebSocket.connect('$host/ws', headers: api.headers(auth: false)).timeout(const Duration(seconds: 15));
    } catch (_) {
      _scheduleRetry();
      return;
    }
    if (!_wantOn) {
      try {
        await ws.close();
      } catch (_) {}
      return;
    }
    _ws = ws;
    ws.pingInterval = const Duration(seconds: 25);
    _open = true;
    ws.add(jsonEncode(<String, dynamic>{'t': 'auth', 'token': api.token, 'dev': api.deviceId}));
    ws.listen((dynamic data) {
      if (data is! String) return;
      Map<String, dynamic> m;
      try {
        final d = jsonDecode(data);
        if (d is! Map<String, dynamic>) return;
        m = d;
      } catch (_) {
        return;
      }
      _handle(m);
    }, onDone: () {
      if (_ws != ws) return;
      final code = ws.closeCode;
      _onClosed(code);
    }, onError: (Object e) {}, cancelOnError: false);
  }

  void _onClosed(int? code) {
    _ws = null;
    _open = false;
    final was = authed;
    authed = false;
    for (final c in _waiting.values) {
      if (!c.isCompleted) c.completeError(ApiError('network'));
    }
    _waiting.clear();
    if (was) _connC.add(false);
    if (code == 4001) {
      _signedOut('session-ended');
      return;
    }
    if (code == 4002 && api.token != null) {
      api.get('/api/me').then((_) => _scheduleRetry(), onError: (Object e) {
        if (e is ApiError && e.status == 401) {
          _signedOut('session-ended');
        } else {
          _scheduleRetry();
        }
      });
      return;
    }
    if (api.token != null && _wantOn) _scheduleRetry();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retry = _retry < 8 ? _retry + 1 : 8;
    _retryTimer = Timer(Duration(milliseconds: (1000 * _retry).clamp(1000, 8000).toInt()), _connect);
  }

  bool _send(Map<String, dynamic> o) {
    final ws = _ws;
    if (ws != null && _open) {
      try {
        ws.add(jsonEncode(o));
        return true;
      } catch (_) {}
    }
    return false;
  }

  void _signedOut(String? code) {
    lastFailCode = code;
    stop();
    final f = onSignedOut;
    if (f != null) f(code);
  }

  void _handle(Map<String, dynamic> m) {
    final t = m['t'];
    if (t == 'auth') {
      if (m['ok'] != true) {
        _signedOut((m['code'] ?? 'unauthorized').toString());
        return;
      }
      authed = true;
      _retry = 0;
      _send(<String, dynamic>{'t': 'vis', 'v': true});
      for (final s in _subs.values) {
        s.sent = false;
        _sendSub(s);
      }
      for (final o in _od.values) {
        _send(<String, dynamic>{'t': 'od', 'op': o['op'], 'path': o['path'], 'v': o['v']});
      }
      final q = List<void Function()>.from(_queue);
      _queue.clear();
      for (final f in q) {
        f();
      }
      _connC.add(true);
    } else if (t == 'notif' || t == 'groups' || t == 'friends' || t == 'dmreq') {
      _pushC.add(m);
    } else if (t == 'snap') {
      final s = _subs[(m['id'] as num).toInt()];
      if (s != null) _deliver(s, m['v']);
    } else if (t == 'err') {
      final s = _subs[(m['id'] as num).toInt()];
      if (s != null && s.errCb != null) s.errCb!('permission_denied');
    } else if (t == 'res') {
      final c = _waiting.remove((m['rid'] as num).toInt());
      if (c == null || c.isCompleted) return;
      if (m['ok'] == true) {
        c.complete(m['v']);
      } else {
        c.completeError(ApiError((m['code'] ?? 'error').toString()));
      }
    }
  }

  void setVisible(bool v) {
    if (authed) _send(<String, dynamic>{'t': 'vis', 'v': v});
  }

  void _deliver(DbSub s, dynamic v) {
    final need = E2ee.has(v);
    if (!need && s.chain == null) {
      _deliverNow(s, v);
      return;
    }
    final prev = s.chain ?? Future<void>.value();
    late Future<void> p;
    p = prev.then((_) async {
      dynamic out = v;
      try {
        out = need ? await e2ee.decAny(s.path, v) : v;
      } catch (_) {
        out = need ? null : v;
      }
      if (!s.dead && _subs[s.id] == s) _deliverNow(s, out);
    }).whenComplete(() {
      if (s.chain == p) s.chain = null;
    });
    s.chain = p;
  }

  void _deliverNow(DbSub s, dynamic v) {
    try {
      s.cb(v);
    } catch (_) {}
  }

  void _sendSub(DbSub s) {
    if (s.sent || !authed) return;
    s.sent = true;
    final msg = <String, dynamic>{'t': 'sub', 'id': s.id, 'path': s.path};
    if (s.q != null) msg['q'] = s.q;
    _send(msg);
  }

  /// Listen to a path. Value callback gets the full value each time it changes.
  DbSub listen(String path, SnapCb cb, {ErrCb? onError, String? orderBy, int? limitToLast}) {
    final id = _nextSub++;
    Map<String, dynamic>? q;
    if (orderBy != null || limitToLast != null) {
      q = <String, dynamic>{'oc': orderBy ?? r'$key', 'ltl': limitToLast ?? 0};
    }
    final s = DbSub(id, _norm(path), q, cb, onError);
    _subs[id] = s;
    _sendSub(s);
    if (!authed && api.token != null && _ws == null) _connect();
    return s;
  }

  void cancel(DbSub? s) {
    if (s == null) return;
    s.dead = true;
    if (_subs.remove(s.id) != null) _send(<String, dynamic>{'t': 'unsub', 'id': s.id});
  }

  static String _norm(String p) => p.split('/').where((e) => e.isNotEmpty).join('/');

  void _whenReady(void Function() fn, void Function(Object) rej) {
    if (authed && _open) {
      fn();
      return;
    }
    var done = false;
    late void Function() run;
    final timer = Timer(const Duration(seconds: 10), () {
      if (done) return;
      done = true;
      _queue.remove(run);
      rej(ApiError('network'));
    });
    run = () {
      if (done) return;
      done = true;
      timer.cancel();
      fn();
    };
    _queue.add(run);
    if (_ws == null && api.token != null) _connect();
  }

  Future<dynamic> _request(Map<String, dynamic> msg) {
    final c = Completer<dynamic>();
    _whenReady(() {
      final rid = _nextRid++;
      msg['rid'] = rid;
      _waiting[rid] = c;
      if (!_send(msg)) {
        _waiting.remove(rid);
        if (!c.isCompleted) c.completeError(ApiError('network'));
      }
    }, (Object e) {
      if (!c.isCompleted) c.completeError(e);
    });
    return c.future;
  }

  /// read a value once
  Future<dynamic> once(String path) async {
    final p = _norm(path);
    final v = await _request(<String, dynamic>{'t': 'once', 'path': p});
    return E2ee.has(v) ? await e2ee.decAny(p, v) : v;
  }

  Future<void> _write(List<Map<String, dynamic>> ops) async {
    for (var n = 0;; n++) {
      try {
        final enc = await e2ee.encOps(ops);
        await _request(<String, dynamic>{'t': 'w', 'ops': enc});
        return;
      } on ApiError catch (e) {
        if (n < 2 && (e.code == 'rekey' || e.code == 'no-group-key')) {
          e2ee.dropGroups();
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> set(String path, dynamic v) => _write(<Map<String, dynamic>>[
        <String, dynamic>{'p': _norm(path), 'v': v}
      ]);

  Future<void> remove(String path) => set(path, null);

  /// multi path update: keys are full paths
  Future<void> update(Map<String, dynamic> map) {
    final ops = <Map<String, dynamic>>[];
    map.forEach((k, v) => ops.add(<String, dynamic>{'p': _norm(k), 'v': v}));
    return _write(ops);
  }

  /// writes a new child with a time ordered key, returns the key
  Future<String> push(String path, dynamic v) async {
    final key = pushKey();
    await set('${_norm(path)}/$key', v);
    return key;
  }

  void onDisconnectRemove(String path) {
    final p = _norm(path);
    _od[p] = <String, dynamic>{'op': 'remove', 'path': p, 'v': null};
    _send(<String, dynamic>{'t': 'od', 'op': 'remove', 'path': p});
  }

  void onDisconnectCancel(String path) {
    final p = _norm(path);
    _od.remove(p);
    _send(<String, dynamic>{'t': 'od', 'op': 'cancel', 'path': p});
  }

  void stop() {
    _wantOn = false;
    _retryTimer?.cancel();
    final ws = _ws;
    _ws = null;
    _open = false;
    final was = authed;
    authed = false;
    for (final c in _waiting.values) {
      if (!c.isCompleted) c.completeError(ApiError('network'));
    }
    _waiting.clear();
    _queue.clear();
    _subs.clear();
    _od.clear();
    if (ws != null) {
      try {
        ws.close();
      } catch (_) {}
    }
    if (was) _connC.add(false);
  }
}
