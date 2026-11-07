import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'util.dart';

/// Dialogs the E2EE flow needs. The app implements this with real screens.
abstract class E2eeUi {
  Future<bool> waitApproval(Future<bool> Function() check);

  /// returns the typed key, null = "I don't have it", 'BACK', or 'XFER'
  Future<String?> askKey(bool wasBad);
  Future<void> showKey(String key, bool first);
  Future<bool> confirmFresh();
  Future<Map<String, dynamic>?> runTransfer();
}

class _Pub {
  final String kid;
  final String pub;
  final EcPublicKey key;
  final int at;
  _Pub(this.kid, this.pub, this.key, this.at);
}

class _Grp {
  int at = 0;
  Map<String, dynamic> info = <String, dynamic>{};
  final Map<int, Uint8List> raw = <int, Uint8List>{};
  final Map<int, SecretKey> key = <int, SecretKey>{};
}

/// End-to-end encryption, wire compatible with the web app
/// (ECDH P-256 identity, HKDF -> AES-GCM, 20 letter chat key, PBKDF2 250k).
class E2ee {
  final DuloApi api;
  E2ee(this.api);

  static const lockedText = '\u{1F512} Can’t decrypt this message on this device';
  static const _bkChars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  final _ecdh = Ecdh.p256(length: 32);
  final _aes = AesGcm.with256bits();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  String? uid;
  String state = 'idle'; // idle | init | ready | locked | none
  bool trusted = true;
  List<Map<String, dynamic>> ring = <Map<String, dynamic>>[];
  String? bk;
  E2eeUi? ui;
  Future<void>? readyP;
  Completer<void>? _unlockC;
  Future<bool>? _flowP;
  final Map<String, _Pub> _pubs = <String, _Pub>{};
  final Map<String, SecretKey> _keyc = <String, SecretKey>{};
  final Map<String, KeyPair> _privc = <String, KeyPair>{};
  final Map<String, _Grp> _grp = <String, _Grp>{};
  bool _showingKey = false;

  // ---------- storage ----------
  Future<String?> _lsGet(String k) async {
    try {
      return (await SharedPreferences.getInstance()).getString(k);
    } catch (_) {
      return null;
    }
  }

  Future<void> _lsSet(String k, String v) async {
    try {
      await (await SharedPreferences.getInstance()).setString(k, v);
    } catch (_) {}
  }

  Future<void> _lsDel(String k) async {
    try {
      await (await SharedPreferences.getInstance()).remove(k);
    } catch (_) {}
  }

  Future<void> _saveRing() => _lsSet('dulo-e2e:$uid', jsonEncode(ring));

  // ---------- low level crypto ----------
  Uint8List _pad32(List<int> b) {
    if (b.length == 32) return Uint8List.fromList(b);
    if (b.length > 32) return Uint8List.fromList(b.sublist(b.length - 32));
    return Uint8List.fromList(<int>[...List<int>.filled(32 - b.length, 0), ...b]);
  }

  Future<String> _kidOf(String pubB64) async {
    final h = await Sha256().hash(unb64(pubB64));
    return b64(h.bytes).substring(0, 12);
  }

  EcPublicKey _pubFromRaw(Uint8List raw) {
    return EcPublicKey(x: raw.sublist(1, 33), y: raw.sublist(33, 65), type: KeyPairType.p256);
  }

  Future<Map<String, dynamic>> _genIdentity() async {
    final kp = await _ecdh.newKeyPair();
    final d = await kp.extract();
    final data = d as EcKeyPairData;
    final x = _pad32(data.x), y = _pad32(data.y), dd = _pad32(data.d);
    final raw = Uint8List.fromList(<int>[4, ...x, ...y]);
    final pub = b64(raw);
    return <String, dynamic>{
      'kid': await _kidOf(pub),
      'pub': pub,
      'jwk': <String, dynamic>{
        'kty': 'EC',
        'crv': 'P-256',
        'x': b64(x),
        'y': b64(y),
        'd': b64(dd),
        'ext': true,
        'key_ops': <String>['deriveBits'],
      },
    };
  }

  Future<KeyPair?> _privOf(String kid) async {
    final c = _privc[kid];
    if (c != null) return c;
    Map<String, dynamic>? e;
    for (final r in ring) {
      if (r['kid'] == kid) e = r;
    }
    if (e == null) return null;
    final jwk = Map<String, dynamic>.from(e['jwk'] as Map);
    final kp = EcKeyPairData(
      d: unb64(jwk['d'] as String),
      x: unb64(jwk['x'] as String),
      y: unb64(jwk['y'] as String),
      type: KeyPairType.p256,
    );
    _privc[kid] = kp;
    return kp;
  }

  Future<_Pub?> _getPub(String u, [String? kid]) async {
    final ck = '$u:${kid ?? 'cur'}';
    final hit = _pubs[ck];
    if (hit != null && (kid != null || DateTime.now().millisecondsSinceEpoch - hit.at < 45000)) return hit;
    final j = await api.get('/api/e2e/pub?uid=$u${kid != null ? '&kid=${Uri.encodeComponent(kid)}' : ''}');
    final keys = j['keys'];
    if (keys is! Map || keys[u] is! Map) return null;
    final r = keys[u] as Map;
    final o = _Pub(r['kid'] as String, r['pub'] as String, _pubFromRaw(unb64(r['pub'] as String)), DateTime.now().millisecondsSinceEpoch);
    _pubs['$u:${o.kid}'] = o;
    if (kid == null) _pubs['$u:cur'] = o;
    return o;
  }

  Future<SecretKey> _derive(KeyPair priv, EcPublicKey pub, String info) async {
    final shared = await _ecdh.sharedSecretKey(keyPair: priv, remotePublicKey: pub);
    final bits = await shared.extractBytes();
    return _hkdf.deriveKey(
      secretKey: SecretKey(bits),
      nonce: utf8.encode('dulochat-e2e-v1'),
      info: utf8.encode(info),
    );
  }

  Future<List<int>> _gcmEnc(SecretKey key, List<int> clear, Uint8List iv) async {
    final box = await _aes.encrypt(clear, secretKey: key, nonce: iv);
    return <int>[...box.cipherText, ...box.mac.bytes];
  }

  Future<List<int>> _gcmDec(SecretKey key, Uint8List iv, Uint8List ctAndTag) async {
    final n = ctAndTag.length - 16;
    final box = SecretBox(ctAndTag.sublist(0, n), nonce: iv, mac: Mac(ctAndTag.sublist(n)));
    return _aes.decrypt(box, secretKey: key);
  }

  Future<String> _aesEnc(SecretKey key, String s) async {
    final iv = randomBytes(12);
    final ct = await _gcmEnc(key, utf8.encode(s), iv);
    return '${b64(iv)}:${b64(ct)}';
  }

  Future<String> _aesDec(SecretKey key, String ivs, String cts) async {
    final out = await _gcmDec(key, unb64(ivs), unb64(cts));
    return utf8.decode(out);
  }

  Map<String, dynamic>? get _cur => ring.isEmpty ? null : ring.last;

  Future<bool> ready() async {
    if (readyP != null) await readyP;
    return state == 'ready';
  }

  static bool has(dynamic v) {
    if (v is String) return v.startsWith('e2e1:');
    if (v is Map) {
      for (final x in v.values) {
        if (has(x)) return true;
      }
    }
    if (v is List) {
      for (final x in v) {
        if (has(x)) return true;
      }
    }
    return false;
  }

  // ---------- private chats ----------
  Future<SecretKey?> _dmKey(String other, String myKid, String otherKid) async {
    final ck = 'dm:$other:$myKid:$otherKid';
    final hit = _keyc[ck];
    if (hit != null) return hit;
    final pr = await _privOf(myKid);
    final op = await _getPub(other, otherKid);
    if (pr == null || op == null) return null;
    final ids = <String>[uid!, other]..sort();
    final k = await _derive(pr, op.key, 'dm|${ids.join('|')}');
    _keyc[ck] = k;
    return k;
  }

  Future<String> _encDm(String other, String s) async {
    final me = _cur!;
    final op = await _getPub(other);
    if (op == null) throw ApiError('peer-no-e2e');
    final k = await _dmKey(other, me['kid'] as String, op.kid);
    if (k == null) throw ApiError('peer-no-e2e');
    return 'e2e1:d:${me['kid']}:${op.kid}:${await _aesEnc(k, s)}';
  }

  bool _hasKid(String kid) => ring.any((r) => r['kid'] == kid);

  Future<String?> _decDm(String other, List<String> p) async {
    final sk = p[2], rk = p[3];
    SecretKey? k;
    if (_hasKid(sk)) {
      k = await _dmKey(other, sk, rk);
    } else if (_hasKid(rk)) {
      k = await _dmKey(other, rk, sk);
    } else {
      return null;
    }
    return k == null ? null : _aesDec(k, p[4], p[5]);
  }

  // ---------- groups ----------
  Future<Map<String, dynamic>> _wrapFor(String gid, int ver, Uint8List raw, String u, _Pub pubObj) async {
    final me = _cur!;
    final pr = (await _privOf(me['kid'] as String))!;
    final k = await _derive(pr, pubObj.key, 'gk|$gid|$ver');
    final iv = randomBytes(12);
    final ct = await _gcmEnc(k, raw, iv);
    return <String, dynamic>{'uid': u, 'wrapped': '${me['kid']}.${pubObj.kid}.${b64(iv)}.${b64(ct)}'};
  }

  Future<Uint8List?> _unwrap(String gid, int ver, String wrapped, String frm) async {
    final p = wrapped.split('.');
    if (p.length != 4) return null;
    final fk = p[0], tk = p[1];
    String other, mykid;
    if (frm == uid) {
      mykid = fk;
      other = uid!;
    } else {
      mykid = tk;
      other = frm;
    }
    final pr = await _privOf(mykid);
    if (pr == null) return null;
    final po = other == uid ? await _getPub(uid!, tk) : await _getPub(other, fk);
    if (po == null) return null;
    final k = await _derive(pr, po.key, 'gk|$gid|$ver');
    return Uint8List.fromList(await _gcmDec(k, unb64(p[2]), unb64(p[3])));
  }

  Future<Map<String, _Pub>> _pubsFor(List<String> uids) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final need = uids.where((u) => _pubs['$u:cur'] == null || now - _pubs['$u:cur']!.at > 45000).toList();
    if (need.isNotEmpty) {
      final j = await api.get('/api/e2e/pub?uids=${need.join(',')}');
      final keys = j['keys'];
      if (keys is Map) {
        for (final u in need) {
          final r = keys[u];
          if (r is Map) {
            final o = _Pub(r['kid'] as String, r['pub'] as String, _pubFromRaw(unb64(r['pub'] as String)), now);
            _pubs['$u:${o.kid}'] = o;
            _pubs['$u:cur'] = o;
          }
        }
      }
    }
    final out = <String, _Pub>{};
    for (final u in uids) {
      final p = _pubs['$u:cur'];
      if (p != null) out[u] = p;
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _makeKeys(String gid, int ver, Uint8List raw, List<String> uids) async {
    final pm = await _pubsFor(uids);
    final out = <Map<String, dynamic>>[];
    for (final u in uids) {
      final p = pm[u];
      if (p != null) out.add(await _wrapFor(gid, ver, raw, u, p));
    }
    return out;
  }

  List<String> _strList(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];

  Future<_Grp> _loadGroup(String gid, bool force) async {
    var g = _grp[gid];
    if (g != null && !force && DateTime.now().millisecondsSinceEpoch - g.at < 15000) return g;
    final j = await api.get('/api/e2e/group?gid=$gid');
    g = _grp[gid] ?? _Grp();
    _grp[gid] = g;
    g.at = DateTime.now().millisecondsSinceEpoch;
    g.info = j;
    final keys = j['keys'];
    if (keys is List) {
      for (final kk in keys) {
        if (kk is! Map) continue;
        final ver = (kk['ver'] as num).toInt();
        if (g.raw.containsKey(ver)) continue;
        try {
          final raw = await _unwrap(gid, ver, kk['wrapped'] as String, kk['frm'] as String);
          if (raw != null) {
            g.raw[ver] = raw;
            g.key[ver] = SecretKey(raw);
          }
        } catch (_) {}
      }
    }
    return g;
  }

  Future<_Grp> _syncGroup(String gid, bool force) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final g = await _loadGroup(gid, force || attempt > 0);
      final j = g.info;
      final members = _strList(j['members']);
      try {
        final cur = (j['cur'] as num?)?.toInt() ?? 0;
        if (j['init'] != true) {
          final raw = randomBytes(32);
          final ks = await _makeKeys(gid, 1, raw, members);
          await api.post('/api/e2e/group', <String, dynamic>{'gid': gid, 'ver': 1, 'keys': ks});
        } else if (j['rotate'] == true) {
          final raw = randomBytes(32);
          final ks = await _makeKeys(gid, cur + 1, raw, members);
          await api.post('/api/e2e/group', <String, dynamic>{'gid': gid, 'ver': cur + 1, 'keys': ks});
        } else if (g.raw.containsKey(cur)) {
          final have = _strList(j['have']);
          final miss = members.where((u) => !have.contains(u)).toList();
          if (miss.isNotEmpty) {
            final ks = await _makeKeys(gid, cur, g.raw[cur]!, miss);
            if (ks.isNotEmpty) await api.post('/api/e2e/group', <String, dynamic>{'gid': gid, 'ver': cur, 'keys': ks});
          }
          return g;
        } else {
          return g;
        }
      } on ApiError catch (e) {
        if (e.code == 'bad-version') continue;
        rethrow;
      }
      force = true;
    }
    return _loadGroup(gid, true);
  }

  Future<String> _encGroup(String s, _Grp g) async {
    final ver = (g.info['cur'] as num).toInt();
    final k = g.key[ver];
    if (k == null) throw ApiError('no-group-key');
    return 'e2e1:g$ver:${await _aesEnc(k, s)}';
  }

  Future<String?> _decGroup(String gid, List<String> p) async {
    final ver = int.parse(p[1].substring(1));
    var g = _grp[gid];
    if (g == null || !g.key.containsKey(ver)) {
      g = await _loadGroup(gid, g == null || DateTime.now().millisecondsSinceEpoch - g.at > 8000);
    }
    final k = g.key[ver];
    return k == null ? null : _aesDec(k, p[2], p[3]);
  }

  /// call when a group chat opens so new members get the key
  Future<void> groupReady(String gid, {bool force = false}) async {
    if (!(await ready())) throw ApiError('e2e-not-ready');
    final g = await _syncGroup(gid, force);
    final cur = (g.info['cur'] as num?)?.toInt() ?? 0;
    if (!g.key.containsKey(cur)) throw ApiError('no-group-key');
  }

  void dropGroups() => _grp.clear();

  // ---------- encrypt outgoing writes ----------
  String _otherOf(String pair) {
    final p = pair.split('_');
    return p[0] == uid ? p[1] : p[0];
  }

  Future<String> _encStr(bool dm, String? other, String? gid, _Grp? g, String s) async {
    if (s.isEmpty || has(s)) return s;
    return dm ? _encDm(other!, s) : _encGroup(s, g!);
  }

  Future<Map<String, dynamic>> _encMsg(bool dm, String? other, String? gid, _Grp? g, Map<String, dynamic> m0) async {
    final m = Map<String, dynamic>.from(cloneJson(m0) as Map);
    if (m['text'] is String) m['text'] = await _encStr(dm, other, gid, g, m['text'] as String);
    if (m['name'] is String) m['name'] = await _encStr(dm, other, gid, g, m['name'] as String);
    final rp = m['reply'];
    if (rp is Map && rp['snip'] is String) rp['snip'] = await _encStr(dm, other, gid, g, rp['snip'] as String);
    final poll = m['poll'];
    if (poll is Map) {
      if (poll['q'] is String) poll['q'] = await _encStr(dm, other, gid, g, poll['q'] as String);
      final opts = poll['opts'];
      if (opts is Map) {
        for (final k in opts.keys.toList()) {
          if (opts[k] is String) opts[k] = await _encStr(dm, other, gid, g, opts[k] as String);
        }
      }
    }
    if (!dm && m['type'] != 'call') m['kv'] = g!.info['cur'];
    return m;
  }

  Future<Map<String, dynamic>> _encOp(Map<String, dynamic> op) async {
    final v0 = op['v'];
    if (v0 == null) return op;
    final p = (op['p'] as String).split('/');
    final k = p[0];
    bool dm = true;
    String? other, gid;
    String? mode;
    if (k == 'dms' && p.length >= 4 && p[2] == 'messages') {
      other = _otherOf(p[1]);
      mode = p.length == 4 ? 'msg' : (p.length == 5 && p[4] == 'text' ? 'str' : null);
    } else if (k == 'dms' && p.length == 4 && p[2] == 'media') {
      other = _otherOf(p[1]);
      mode = 'str';
    } else if (k == 'dms' && p.length == 3 && p[2] == 'pin') {
      other = _otherOf(p[1]);
      mode = 'pin';
    } else if (k == 'userChats' && (p.length == 3 || (p.length == 4 && p[3] == 'last'))) {
      other = p[1] == uid ? p[2] : p[1];
      mode = p.length == 4 ? 'str' : 'uchat';
    } else if (k == 'groups' && p.length >= 4 && p[2] == 'messages') {
      dm = false;
      gid = p[1];
      mode = p.length == 4 ? 'msg' : (p.length == 5 && p[4] == 'text' ? 'str' : null);
    } else if (k == 'groups' && p.length == 4 && p[2] == 'media') {
      dm = false;
      gid = p[1];
      mode = 'str';
    } else if (k == 'groups' && p.length == 3 && p[2] == 'pin') {
      dm = false;
      gid = p[1];
      mode = 'pin';
    }
    if (mode == null) return op;
    if (!(await ready())) throw ApiError('e2e-not-ready');
    _Grp? g;
    if (!dm) {
      g = await _syncGroup(gid!, false);
      final cur = (g.info['cur'] as num?)?.toInt() ?? 0;
      if (!g.key.containsKey(cur)) throw ApiError('no-group-key');
    }
    dynamic v = v0;
    if (mode == 'str') {
      if (v is String) v = await _encStr(dm, other, gid, g, v);
    } else if (mode == 'msg') {
      if (v is Map) v = await _encMsg(dm, other, gid, g, Map<String, dynamic>.from(v));
    } else if (mode == 'pin') {
      v = cloneJson(v);
      if (v is Map && v['snip'] is String) v['snip'] = await _encStr(dm, other, gid, g, v['snip'] as String);
    } else if (mode == 'uchat') {
      v = cloneJson(v);
      if (v is Map && v['last'] is String) v['last'] = await _encStr(dm, other, gid, g, v['last'] as String);
    }
    return <String, dynamic>{'p': op['p'], 'v': v};
  }

  Future<List<Map<String, dynamic>>> encOps(List<Map<String, dynamic>> ops) async {
    final out = <Map<String, dynamic>>[];
    for (final o in ops) {
      out.add(await _encOp(o));
    }
    return out;
  }

  // ---------- decrypt incoming ----------
  Future<String> _decStr(List<String> P, String s) async {
    try {
      final p = s.split(':');
      String? r;
      if (p.length > 1 && p[1] == 'd' && p.length == 6) {
        String? other;
        if (P[0] == 'dms') {
          other = _otherOf(P[1]);
        } else if (P[0] == 'userChats') {
          other = P[1] == uid ? P[2] : P[1];
        }
        if (other != null) r = await _decDm(other, p);
      } else if (p.length == 4 && RegExp(r'^g\d+$').hasMatch(p[1]) && P[0] == 'groups') {
        r = await _decGroup(P[1], p);
      }
      if (r != null) return r;
    } catch (_) {}
    if ((P.length > 2 && P[2] == 'media')) return 'data:,';
    return lockedText;
  }

  Future<dynamic> _decTree(List<String> P, dynamic v) async {
    if (v is String) return has(v) ? _decStr(P, v) : v;
    if (v is Map) {
      for (final k in v.keys.toList()) {
        if (has(v[k])) v[k] = await _decTree(<String>[...P, k.toString()], v[k]);
      }
    }
    return v;
  }

  Future<dynamic> decAny(String path, dynamic v) async {
    if (!has(v)) return v;
    if (readyP != null) await readyP;
    return _decTree(path.split('/').where((e) => e.isNotEmpty).toList(), v);
  }

  // ---------- setup / restore ----------
  String newBackupKey() {
    final a = randomBytes(20);
    final sb = StringBuffer();
    for (var i = 0; i < 20; i++) {
      sb.write(_bkChars[a[i] % 32]);
      if (i % 5 == 4 && i < 19) sb.write('-');
    }
    return sb.toString();
  }

  static String normBk(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z2-9]'), '');

  String showBk(String k) {
    final n = normBk(k);
    final sb = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      sb.write(n[i]);
      if (i % 5 == 4 && i < n.length - 1) sb.write('-');
    }
    return sb.toString();
  }

  Future<SecretKey> _bkKey(String key, String saltB64) {
    final pb = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 250000, bits: 256);
    return pb.deriveKey(secretKey: SecretKey(utf8.encode(normBk(key))), nonce: unb64(saltB64));
  }

  Future<Map<String, dynamic>> _makeBackup(String key) async {
    final salt = b64(randomBytes(16));
    final k = await _bkKey(key, salt);
    final payload = jsonEncode(<String, dynamic>{
      'v': 1,
      'ring': ring.map((r) => <String, dynamic>{'kid': r['kid'], 'pub': r['pub'], 'jwk': r['jwk']}).toList(),
    });
    final iv = randomBytes(12);
    final ct = await _gcmEnc(k, utf8.encode(payload), iv);
    return <String, dynamic>{'salt': salt, 'blob': '${b64(iv)}.${b64(ct)}'};
  }

  Future<List<Map<String, dynamic>>> _openBackup(String key, Map backup) async {
    final k = await _bkKey(key, backup['salt'] as String);
    final p = (backup['blob'] as String).split('.');
    final pt = await _gcmDec(k, unb64(p[0]), unb64(p[1]));
    final j = jsonDecode(utf8.decode(pt)) as Map;
    return (j['ring'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _publish(String key) async {
    final me = _cur!;
    final b = await _makeBackup(key);
    await api.post('/api/e2e/setup', <String, dynamic>{'pub': me['pub'], 'backup': b});
    await _lsSet('dulo-e2ebk:$uid', key);
    bk = key;
  }

  Future<void> _fresh(bool newKey) async {
    if (newKey) {
      bk = null;
      await _lsDel('dulo-e2ebk:$uid');
    }
    final id = await _genIdentity();
    ring.add(id);
    _privc.clear();
    await _saveRing();
    final key = bk ?? await _lsGet('dulo-e2ebk:$uid') ?? newBackupKey();
    await _publish(key);
    await _lsSet('dulo-e2ebk-pending:$uid', '1');
  }

  /// shows the chat key popup once (first time private chats / groups open)
  Future<void> showPending() async {
    final k = 'dulo-e2ebk-pending:$uid';
    final key = bk ?? await _lsGet('dulo-e2ebk:$uid');
    if (_showingKey || uid == null || await _lsGet(k) != '1' || key == null || ui == null) return;
    _showingKey = true;
    try {
      await ui!.showKey(key, true);
      await _lsSet(k, '0');
    } finally {
      _showingKey = false;
    }
  }

  Future<String?> backupKeyForDisplay() async => bk ?? await _lsGet('dulo-e2ebk:$uid');

  void _done() {
    state = 'ready';
    final c = _unlockC;
    if (c != null && !c.isCompleted) c.complete();
    _unlockC = null;
  }

  Future<bool> _runUnlock() async {
    final id = uid;
    final u = ui;
    if (u == null) return false;
    while (!trusted) {
      final go = await u.waitApproval(() async {
        final m = await api.get('/api/e2e/me');
        trusted = m['trusted'] != false;
        return trusted;
      });
      if (!go || uid != id) return false;
    }
    final me = await api.get('/api/e2e/me');
    if (me['backup'] == null && me['kid'] == null) {
      await _fresh(false);
      _done();
      return true;
    }
    var bad = false;
    for (;;) {
      if (uid != id) return false;
      final key = await u.askKey(bad);
      bad = false;
      if (key == 'BACK') return false;
      if (key == 'XFER') {
        final tr = await u.runTransfer();
        if (tr != null && tr['ring'] is List && (tr['ring'] as List).isNotEmpty) {
          ring = (tr['ring'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _privc.clear();
          await _saveRing();
          if (tr['bk'] is String) {
            bk = tr['bk'] as String;
            await _lsSet('dulo-e2ebk:$id', bk!);
          }
          _done();
          return true;
        }
        continue;
      }
      if (key == null) {
        if (await u.confirmFresh()) {
          await _fresh(true);
          _done();
          return true;
        }
        continue;
      }
      try {
        final r = await _openBackup(key, me['backup'] as Map);
        ring = r;
        _privc.clear();
        await _saveRing();
        bk = showBk(key);
        await _lsSet('dulo-e2ebk:$id', bk!);
        if (_cur != null && _cur!['kid'] != me['kid']) await _publish(bk!);
        _done();
        return true;
      } catch (_) {
        bad = true;
      }
    }
  }

  /// call whenever the person opens private chats or groups
  Future<bool> gate() {
    if (state == 'locked') {
      _flowP ??= _runUnlock().then((ok) async {
        _flowP = null;
        if (ok) await showPending();
        return ok;
      }, onError: (Object e) {
        _flowP = null;
        return false;
      });
      return _flowP!;
    }
    if (state == 'ready') return showPending().then((_) => true);
    return Future<bool>.value(true);
  }

  bool get isLocked => state == 'locked';

  Future<void> _start(String u) async {
    uid = u;
    state = 'init';
    _pubs.clear();
    _keyc.clear();
    _privc.clear();
    _grp.clear();
    bk = await _lsGet('dulo-e2ebk:$u');
    try {
      final raw = await _lsGet('dulo-e2e:$u');
      ring = raw == null ? <Map<String, dynamic>>[] : (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      ring = <Map<String, dynamic>>[];
    }
    final me = await api.get('/api/e2e/me');
    final last = _cur;
    trusted = me['trusted'] != false;
    if (last != null && me['kid'] == last['kid']) {
      state = 'ready';
      return;
    }
    if (last != null && me['kid'] == null && trusted) {
      final had = bk != null;
      final bk0 = bk ?? newBackupKey();
      await _publish(bk0);
      if (!had) await _lsSet('dulo-e2ebk-pending:$u', '1');
      state = 'ready';
      return;
    }
    if (trusted && me['hasBackup'] != true && me['kid'] == null) {
      await _fresh(false);
      state = 'ready';
      return;
    }
    // new phone, or keys changed: chats stay locked until approved and the chat key is entered
    state = 'locked';
  }

  void onUser(String? u) {
    if (u == null) {
      uid = null;
      state = 'idle';
      readyP = null;
      ring = <Map<String, dynamic>>[];
      _grp.clear();
      _pubs.clear();
      _keyc.clear();
      _privc.clear();
      bk = null;
      return;
    }
    if (uid == u && readyP != null) return;
    readyP = _start(u).catchError((Object e) {
      state = 'none';
    });
  }

  // ---------- QR / code transfer ----------
  Future<Map<String, dynamic>?> xferReceive(void Function(String code) onCode, bool Function() cancelled) async {
    final kp = await _ecdh.newKeyPair();
    final data = await kp.extract() as EcKeyPairData;
    final pub = b64(<int>[4, ..._pad32(data.x), ..._pad32(data.y)]);
    final r = await api.post('/api/e2e/xfer/create', <String, dynamic>{'pub': pub});
    final id = r['id'] as String;
    onCode('dulo-xfer:$id:$pub');
    for (var i = 0; i < 200; i++) {
      if (cancelled()) return null;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      Map<String, dynamic> g;
      try {
        g = await api.get('/api/e2e/xfer/get?id=$id');
      } catch (_) {
        return null;
      }
      if (g['ready'] == true) {
        final op = _pubFromRaw(unb64(g['pub'] as String));
        final k = await _derive(kp, op, 'xfer|$id');
        final p = (g['blob'] as String).split('.');
        final pt = await _gcmDec(k, unb64(p[0]), unb64(p[1]));
        return Map<String, dynamic>.from(jsonDecode(utf8.decode(pt)) as Map);
      }
    }
    return null;
  }

  Future<void> xferSend(String code) async {
    final m = RegExp(r'^dulo-xfer:([0-9a-f]{16}):([A-Za-z0-9_-]{86,88})$').firstMatch(code.trim());
    if (m == null) throw ApiError('bad-code');
    if (!(await ready()) || ring.isEmpty) throw ApiError('e2e-not-ready');
    final kp = await _ecdh.newKeyPair();
    final data = await kp.extract() as EcKeyPairData;
    final np = _pubFromRaw(unb64(m.group(2)!));
    final k = await _derive(kp, np, 'xfer|${m.group(1)}');
    final iv = randomBytes(12);
    final payload = jsonEncode(<String, dynamic>{'ring': ring, 'bk': bk ?? await _lsGet('dulo-e2ebk:$uid')});
    final ct = await _gcmEnc(k, utf8.encode(payload), iv);
    await api.post('/api/e2e/xfer/send', <String, dynamic>{
      'id': m.group(1),
      'pub': b64(<int>[4, ..._pad32(data.x), ..._pad32(data.y)]),
      'blob': '${b64(iv)}.${b64(ct)}',
    });
  }
}
