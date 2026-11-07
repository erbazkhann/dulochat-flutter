import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// base64url without padding (same format as the web app).
String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List unb64(String s) {
  var t = s.replaceAll('-', '+').replaceAll('_', '/');
  while (t.length % 4 != 0) {
    t += '=';
  }
  return Uint8List.fromList(base64.decode(t));
}

Uint8List randomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

String randomHex(int bytes) {
  final b = randomBytes(bytes);
  final sb = StringBuffer();
  for (final x in b) {
    sb.write(x.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

const _keyChars = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';
int _lastPush = 0;
List<int> _lastRand = <int>[];

/// Firebase-style push id (time ordered), same as the web app.
String pushKey() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final dup = now == _lastPush;
  _lastPush = now;
  var t = '';
  var n = now;
  for (var i = 7; i >= 0; i--) {
    t = _keyChars[n % 64] + t;
    n = n ~/ 64;
  }
  if (!dup) {
    final r = Random.secure();
    _lastRand = List<int>.generate(12, (_) => r.nextInt(64));
  } else {
    var k = 11;
    while (k >= 0 && _lastRand[k] == 63) {
      _lastRand[k] = 0;
      k--;
    }
    if (k >= 0) _lastRand[k]++;
  }
  return t + _lastRand.map((x) => _keyChars[x]).join();
}

/// Server value placeholders.
Map<String, dynamic> svTimestamp() => <String, dynamic>{'.sv': 'timestamp'};
Map<String, dynamic> svIncrement(int n) => <String, dynamic>{
      '.sv': <String, dynamic>{'increment': n}
    };

/// Deep copy of decoded JSON.
dynamic cloneJson(dynamic v) => v == null ? null : jsonDecode(jsonEncode(v));

String timeOf(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  var h = d.hour % 12;
  if (h == 0) h = 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String shortTimeOf(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final now = DateTime.now();
  final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
  if (sameDay) return timeOf(ts);
  final y = now.subtract(const Duration(days: 1));
  if (d.year == y.year && d.month == y.month && d.day == y.day) return 'Yesterday';
  const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${mon[d.month - 1]}';
}

String dayLabelOf(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final now = DateTime.now();
  bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (same(d, now)) return 'Today';
  if (same(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${mon[d.month - 1]} ${d.year}';
}
