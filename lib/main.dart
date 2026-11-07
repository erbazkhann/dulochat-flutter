import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

void main() => runApp(const DulochatApp());

class DulochatApp extends StatelessWidget {
  const DulochatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1594EA)),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const StartScreen(),
    );
  }
}

/// Part 1: proves the app builds, installs and can reach the Dulochat server.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
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
      final r = await http
          .get(
            Uri.parse('${AppConfig.server}/'),
            headers: {'ngrok-skip-browser-warning': '1', 'User-Agent': 'DulochatApp/1.0 (Flutter)'},
          )
          .timeout(const Duration(seconds: 12));
      final ms = DateTime.now().difference(started).inMilliseconds;
      setState(() {
        _ok = r.statusCode >= 200 && r.statusCode < 400;
        _status = _ok! ? 'Server reached (${r.statusCode}, $ms ms)' : 'Server answered ${r.statusCode}';
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _status = 'Could not reach the server. Check your internet and the server address.';
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blue = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(color: blue, shape: BoxShape.circle),
                  child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 42),
                ),
                const SizedBox(height: 16),
                Text(AppConfig.appName, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: blue)),
                const SizedBox(height: 6),
                const Text('Flutter app, Part 1', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 28),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: _ok == null ? Colors.black87 : (_ok! ? Colors.green.shade700 : Colors.red.shade700),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _check,
                  child: Text(_busy ? 'Please wait...' : 'Check server'),
                ),
                const SizedBox(height: 10),
                Text(AppConfig.server, style: const TextStyle(fontSize: 12, color: Colors.black45)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
