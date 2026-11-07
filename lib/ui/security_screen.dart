import 'package:flutter/material.dart';

import '../core/session.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import 'common.dart';

/// Shows the chat backup key and lets you move chats to a new phone.
class SecurityScreen extends StatefulWidget {
  final Session session;
  const SecurityScreen({super.key, required this.session});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  String? _key;
  bool _loaded = false;
  bool _show = false;
  final _code = TextEditingController();
  bool _busy = false;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final k = await s.e2ee.backupKeyForDisplay();
    if (mounted) {
      setState(() {
        _key = k;
        _loaded = true;
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final c = _code.text.trim();
    if (c.isEmpty) return;
    setState(() => _busy = true);
    try {
      await s.e2ee.xferSend(c);
      if (mounted) {
        toast(context, 'Done. Your chats are moving to the new device.');
        _code.clear();
      }
    } catch (_) {
      if (mounted) toast(context, 'That code did not work. Check it and try again.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.dulo;
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: <Widget>[
          SectionCard(
            title: 'Chat backup key',
            children: <Widget>[
              Text('This key reads your old private chats on a new phone. Keep it somewhere safe. Nobody can recover it for you.', style: TextStyle(color: cc.muted, height: 1.35)),
              const SizedBox(height: 12),
              if (!_loaded)
                const Center(child: CircularProgressIndicator())
              else if (_key == null)
                Text('No key on this device yet. Open a private chat once to set it up.', style: TextStyle(color: cc.muted))
              else ...<Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: cc.soft, borderRadius: BorderRadius.circular(12), border: Border.all(color: cc.line)),
                  child: Text(_show ? _key! : '•••••-•••••-•••••-•••••', textAlign: TextAlign.center, style: TextStyle(color: cc.ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1, fontFamily: 'monospace')),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(child: DuloButton(label: _show ? 'Hide' : 'Show', outlined: true, icon: _show ? Icons.visibility_off_outlined : Icons.visibility_outlined, onPressed: () => setState(() => _show = !_show))),
                    const SizedBox(width: 10),
                    Expanded(child: DuloButton(label: 'Copy', icon: Icons.copy_rounded, onPressed: () => copyText(context, _key!, 'Key copied'))),
                  ],
                ),
              ],
            ],
          ),
          SectionCard(
            title: 'Link a new device',
            children: <Widget>[
              Text('On the new phone choose "Transfer from old phone", then type the code shown there.', style: TextStyle(color: cc.muted, height: 1.35)),
              const SizedBox(height: 12),
              DuloTextField(controller: _code, hint: 'dulo-xfer:...', prefixIcon: Icons.qr_code_2_rounded),
              const SizedBox(height: 10),
              DuloButton(label: 'Send my chats', busy: _busy, onPressed: _link),
            ],
          ),
        ],
      ),
    );
  }
}
