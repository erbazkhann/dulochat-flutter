import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';

/// Small card that tests the connection to the Dulochat server.
class ServerCheckCard extends StatefulWidget {
  const ServerCheckCard({super.key});

  @override
  State<ServerCheckCard> createState() => _ServerCheckCardState();
}

class _ServerCheckCardState extends State<ServerCheckCard> {
  String _status = 'Not checked yet';
  bool _busy = false;
  bool? _ok;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _ok = null;
      _status = 'Checking...';
    });
    final started = DateTime.now();
    try {
      final r = await http.get(
        Uri.parse('${AppConfig.server}/'),
        headers: {'ngrok-skip-browser-warning': '1', 'User-Agent': 'DulochatApp/1.0 (Flutter)'},
      ).timeout(const Duration(seconds: 12));
      final ms = DateTime.now().difference(started).inMilliseconds;
      if (!mounted) return;
      setState(() {
        _ok = r.statusCode >= 200 && r.statusCode < 400;
        _status = _ok! ? 'Server reached (${r.statusCode}, $ms ms)' : 'Server answered ${r.statusCode}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _status = 'Could not reach the server. Is it running?';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    final color = _ok == null ? c.ink : (_ok! ? const Color(0xFF16A34A) : c.danger);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Server', style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(AppConfig.server, style: TextStyle(color: c.muted, fontSize: 12)),
          const SizedBox(height: 10),
          Text(_status, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          DuloButton(label: 'Check server', icon: Icons.wifi_tethering, busy: _busy, onPressed: _check),
        ],
      ),
    );
  }
}
