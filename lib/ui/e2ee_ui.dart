import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/e2ee.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import 'common.dart';

/// Real screens for the chat key steps (approval, enter key, show key, transfer).
class AppE2eeUi implements E2eeUi {
  final E2ee e2ee;
  AppE2eeUi(this.e2ee);

  BuildContext? get _ctx => navKey.currentContext;

  @override
  Future<void> showKey(String key, bool first) async {
    final ctx = _ctx;
    if (ctx == null) return;
    await showDialog<void>(
      context: ctx,
      barrierDismissible: !first,
      builder: (_) => _ShowKeyDialog(keyText: key, first: first),
    );
  }

  @override
  Future<String?> askKey(bool wasBad) async {
    final ctx = _ctx;
    if (ctx == null) return 'BACK';
    final r = await showDialog<String?>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _AskKeyDialog(bad: wasBad),
    );
    return r;
  }

  @override
  Future<bool> waitApproval(Future<bool> Function() check) async {
    final ctx = _ctx;
    if (ctx == null) return false;
    final r = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _WaitDialog(check: check),
    );
    return r == true;
  }

  @override
  Future<bool> confirmFresh() async {
    final ctx = _ctx;
    if (ctx == null) return false;
    return confirmDialog(
      ctx,
      'Start with a new chat key?',
      'Without the backup key your old private chats and group messages cannot be read on this device. New messages will work normally. Other people can still read the old chats on their side.',
      yes: 'Start fresh',
      no: 'Back',
      danger: true,
    );
  }

  @override
  Future<Map<String, dynamic>?> runTransfer() async {
    final ctx = _ctx;
    if (ctx == null) return null;
    return showDialog<Map<String, dynamic>?>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _TransferDialog(e2ee: e2ee),
    );
  }
}

class _ShowKeyDialog extends StatefulWidget {
  final String keyText;
  final bool first;
  const _ShowKeyDialog({required this.keyText, required this.first});
  @override
  State<_ShowKeyDialog> createState() => _ShowKeyDialogState();
}

class _ShowKeyDialogState extends State<_ShowKeyDialog> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    return PopScope(
      canPop: !widget.first,
      child: AlertDialog(
        title: Text(widget.first ? 'Your chats are now end-to-end encrypted' : 'Chat backup key'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Save this key somewhere safe (screenshot or notes). It is the only way to read your old chats on a new phone or after you log out. Nobody, not even Dulochat, can recover it for you.',
                style: TextStyle(color: c.muted, height: 1.35),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.accent, width: 1.4)),
                child: SelectableText(
                  widget.keyText,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1, fontFamily: 'monospace'),
                ),
              ),
              if (widget.first)
                CheckboxListTile(
                  value: _saved,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) => setState(() => _saved = v == true),
                  title: const Text('I have saved this key', style: TextStyle(fontSize: 14)),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => copyText(context, widget.keyText, 'Key copied'), child: const Text('Copy key')),
          TextButton(
            onPressed: (!widget.first || _saved) ? () => Navigator.pop(context) : null,
            child: Text(widget.first ? 'Done' : 'Close'),
          ),
        ],
      ),
    );
  }
}

class _AskKeyDialog extends StatefulWidget {
  final bool bad;
  const _AskKeyDialog({required this.bad});
  @override
  State<_AskKeyDialog> createState() => _AskKeyDialogState();
}

class _AskKeyDialogState extends State<_AskKeyDialog> {
  final _t = TextEditingController();
  String _err = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.bad) _err = 'That key did not work. Check it and try again.';
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Restore your encrypted chats'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Enter your chat backup key to read your old chats on this device, or move them from your old phone with a QR code.',
                  style: TextStyle(color: c.muted, height: 1.35)),
              const SizedBox(height: 14),
              TextField(
                controller: _t,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                style: TextStyle(color: c.ink, fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 1),
                decoration: const InputDecoration(hintText: 'XXXXX-XXXXX-XXXXX-XXXXX'),
              ),
              SizedBox(
                height: 24,
                child: Text(_err, style: TextStyle(color: c.danger, fontSize: 12.5)),
              ),
              DuloButton(label: 'Transfer from old phone (QR)', outlined: true, icon: Icons.qr_code_2_rounded, onPressed: () => Navigator.pop(context, 'XFER')),
              const SizedBox(height: 8),
              Text('If you lost your backup key and have no old phone, your old chats can never be recovered.',
                  style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.3)),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, 'BACK'), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('I don’t have it')),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    if (E2ee.normBk(_t.text).length != 20) {
                      setState(() => _err = 'The key has 20 letters and numbers.');
                      return;
                    }
                    setState(() => _busy = true);
                    Navigator.pop(context, _t.text);
                  },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }
}

class _WaitDialog extends StatefulWidget {
  final Future<bool> Function() check;
  const _WaitDialog({required this.check});
  @override
  State<_WaitDialog> createState() => _WaitDialogState();
}

class _WaitDialogState extends State<_WaitDialog> {
  Timer? _t;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 3500), (_) async {
      if (_checking) return;
      _checking = true;
      try {
        if (await widget.check() && mounted) {
          _t?.cancel();
          Navigator.pop(context, true);
        }
      } catch (_) {}
      _checking = false;
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Chats are locked'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'This is a new device. We sent a notification to your main device. Open Dulochat there, tap the notification and choose "It’s my device". Your chats unlock here as soon as you do.',
              style: TextStyle(color: c.muted, height: 1.35),
            ),
            const SizedBox(height: 16),
            Row(children: <Widget>[
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)),
              const SizedBox(width: 10),
              Text('Waiting for approval...', style: TextStyle(color: c.muted)),
            ]),
          ],
        ),
        actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back'))],
      ),
    );
  }
}

class _TransferDialog extends StatefulWidget {
  final E2ee e2ee;
  const _TransferDialog({required this.e2ee});
  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  String _code = '';
  bool _stop = false;

  @override
  void initState() {
    super.initState();
    widget.e2ee.xferReceive((code) {
      if (mounted) setState(() => _code = code);
    }, () => _stop).then((r) {
      if (_stop || !mounted) return;
      Navigator.pop(context, r);
    }, onError: (Object e) {
      if (_stop || !mounted) return;
      Navigator.pop(context, null);
    });
  }

  @override
  void dispose() {
    _stop = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Transfer from your old phone'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('On your old phone open Dulochat > Settings > Security > Link new device, then scan this code or type it in.',
                  style: TextStyle(color: c.muted, height: 1.35)),
              const SizedBox(height: 14),
              if (_code.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
              else ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: QrImageView(data: _code, size: 200, backgroundColor: Colors.white),
                ),
                const SizedBox(height: 10),
                SelectableText(_code, style: TextStyle(fontSize: 11, color: c.muted)),
              ],
              const SizedBox(height: 10),
              Text('Waiting for your old phone...', style: TextStyle(color: c.muted)),
            ],
          ),
        ),
        actions: <Widget>[
          if (_code.isNotEmpty) TextButton(onPressed: () => copyText(context, _code, 'Code copied'), child: const Text('Copy code')),
          TextButton(
            onPressed: () {
              _stop = true;
              Navigator.pop(context, null);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
