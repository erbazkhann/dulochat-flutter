import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'util.dart';

class ApiError implements Exception {
  final String code;
  final int status;
  final Map<String, dynamic> body;
  ApiError(this.code, {this.status = 0, this.body = const <String, dynamic>{}});
  @override
  String toString() => 'ApiError($code)';
}

/// HTTP side of the Dulochat server. Keeps token, device id and the device cookie.
class DuloApi {
  String? token;
  String deviceId = '';
  String? cookie; // value of dulo_dev
  final http.Client _c = http.Client();

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    var d = p.getString('dulo-dev') ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(d)) {
      d = randomHex(18);
      await p.setString('dulo-dev', d);
    }
    deviceId = d;
    cookie = p.getString('dulo-cookie');
    token = p.getString('dulo-token');
  }

  Future<void> saveToken(String? t) async {
    token = t;
    final p = await SharedPreferences.getInstance();
    if (t == null) {
      await p.remove('dulo-token');
    } else {
      await p.setString('dulo-token', t);
    }
  }

  Map<String, String> headers({bool json = false, bool auth = true}) {
    final h = <String, String>{
      'ngrok-skip-browser-warning': '1',
      'User-Agent': 'DulochatApp/1.0 (Android; Flutter)',
    };
    if (json) h['Content-Type'] = 'application/json';
    if (auth && token != null) h['Authorization'] = 'Bearer $token';
    if (cookie != null) h['Cookie'] = 'dulo_dev=$cookie';
    return h;
  }

  Future<void> _grabCookie(http.Response r) async {
    final sc = r.headers['set-cookie'];
    if (sc == null) return;
    final m = RegExp(r'dulo_dev=([A-Za-z0-9_-]{16,64})').firstMatch(sc);
    if (m != null && m.group(1) != cookie) {
      cookie = m.group(1);
      final p = await SharedPreferences.getInstance();
      await p.setString('dulo-cookie', cookie!);
    }
  }

  Future<Map<String, dynamic>> request(String method, String path,
      {Object? body, bool auth = true, Duration timeout = const Duration(seconds: 20)}) async {
    final uri = Uri.parse('${AppConfig.server}$path');
    http.Response r;
    try {
      final h = headers(json: body != null, auth: auth);
      final enc = body == null ? null : jsonEncode(body);
      if (method == 'GET') {
        r = await _c.get(uri, headers: h).timeout(timeout);
      } else if (method == 'DELETE') {
        r = await _c.delete(uri, headers: h, body: enc).timeout(timeout);
      } else {
        r = await _c.post(uri, headers: h, body: enc ?? '{}').timeout(timeout);
      }
    } catch (_) {
      throw ApiError('network');
    }
    await _grabCookie(r);
    Map<String, dynamic> j = <String, dynamic>{};
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map<String, dynamic>) j = d;
    } catch (_) {}
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiError((j['code'] ?? 'error').toString(), status: r.statusCode, body: j);
    }
    return j;
  }

  Future<Map<String, dynamic>> get(String path) => request('GET', path);
  Future<Map<String, dynamic>> post(String path, [Object? body]) => request('POST', path, body: body ?? <String, dynamic>{});
}
