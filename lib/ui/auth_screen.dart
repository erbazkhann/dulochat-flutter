import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../theme/colors.dart';
import '../widgets/widgets.dart';
import 'common.dart';

enum _Mode { landing, login, signup1, signup2 }

class AuthScreen extends StatefulWidget {
  final Session session;
  const AuthScreen({super.key, required this.session});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _Mode _mode = _Mode.landing;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _link = TextEditingController();
  String _gender = '';
  DateTime? _dob;
  bool _agree = false;
  bool _busy = false;
  String _err = '';

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    if (s.failMessage != null && s.failMessage!.isNotEmpty) {
      _mode = _Mode.login;
      _err = s.failMessage!;
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _pass2.dispose();
    _name.dispose();
    _bio.dispose();
    _link.dispose();
    super.dispose();
  }

  void _go(_Mode m) => setState(() {
        _mode = m;
        _err = '';
      });

  String get _u => _user.text.trim().toLowerCase();

  bool _checkLogin() {
    if (!RegExp(r'^[a-z0-9_.-]{3,20}$').hasMatch(_u)) {
      setState(() => _err = 'Username must be 3 to 20 characters: letters, numbers, _ . -');
      return false;
    }
    if (_pass.text.length < 6) {
      setState(() => _err = 'Password must be at least 6 characters.');
      return false;
    }
    return true;
  }

  Future<void> _doLogin({bool reactivate = false}) async {
    if (_busy || !_checkLogin()) return;
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      await s.login(_u, _pass.text, reactivate: reactivate);
    } catch (e) {
      if (e is ApiError && e.code == 'account-disabled' && mounted) {
        final yes = await confirmDialog(context, 'Account deactivated', 'This account was deactivated. Do you want to turn it on again?', yes: 'Reactivate');
        if (yes) {
          setState(() => _busy = false);
          return _doLogin(reactivate: true);
        }
      }
      if (mounted) setState(() => _err = s.authMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  void _toStep2() {
    final fn = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!RegExp(r"^[\p{L}\p{M} .'-]{2,40}$", unicode: true).hasMatch(fn)) {
      setState(() => _err = 'Enter your full name (2 to 40 letters).');
      return;
    }
    if (!RegExp(r'^[a-z0-9_.-]{3,20}$').hasMatch(_u)) {
      setState(() => _err = 'Username must be 3 to 20 characters: letters, numbers, _ . -');
      return;
    }
    if (_gender.isEmpty) {
      setState(() => _err = 'Please select your gender.');
      return;
    }
    if (_pass.text.length < 6) {
      setState(() => _err = 'Password must be at least 6 characters.');
      return;
    }
    if (_pass2.text != _pass.text) {
      setState(() => _err = 'Passwords do not match.');
      return;
    }
    if (!_agree) {
      setState(() => _err = 'Please tick the box to accept the Terms & Privacy Policy.');
      return;
    }
    _go(_Mode.signup2);
  }

  int _words(String t) => t.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).length;

  Future<void> _doSignup() async {
    if (_busy) return;
    final bio = _bio.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_dob == null) {
      setState(() => _err = 'Please enter your date of birth.');
      return;
    }
    final age = DateTime.now().difference(_dob!).inDays / 365.25;
    if (age < 13 || age > 110) {
      setState(() => _err = 'Please enter a valid date of birth (13 years or older).');
      return;
    }
    if (_words(bio) < 10) {
      setState(() => _err = 'Bio must be at least 10 words.');
      return;
    }
    final d = _dob!;
    final dobStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      await s.signup(<String, dynamic>{
        'username': _u,
        'password': _pass.text,
        'fullName': _name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
        'gender': _gender,
        'v2': true,
        'bio': bio,
        'dob': dobStr,
        'link': _link.text.trim(),
      });
    } catch (e) {
      if (mounted) {
        final code = e is ApiError ? e.code : '';
        setState(() {
          _err = s.authMessage(e);
          if (!<String>['bio-short', 'invalid-bio', 'invalid-dob', 'invalid-link'].contains(code)) {
            _mode = _Mode.signup1;
            if (code == 'account-exists') _mode = _Mode.login;
          }
        });
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final last = DateTime(now.year - 13, now.month, now.day);
    final p = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20, 1, 1),
      firstDate: DateTime(now.year - 100, 1, 1),
      lastDate: last,
      helpText: 'Date of birth',
    );
    if (p != null) setState(() => _dob = p);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(key: ValueKey<_Mode>(_mode), child: _body(c)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(DuloColors c) {
    switch (_mode) {
      case _Mode.landing:
        return _landing(c);
      case _Mode.login:
        return _login(c);
      case _Mode.signup1:
        return _signup1(c);
      case _Mode.signup2:
        return _signup2(c);
    }
  }

  Widget _errBox(DuloColors c) {
    if (_err.isEmpty) return const SizedBox(height: 6);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.danger.withAlpha(28), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, color: c.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(_err, style: TextStyle(color: c.danger, fontSize: 13.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _landing(DuloColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const DuloLogo(size: 92),
          const SizedBox(height: 22),
          Text('Dulochat', style: TextStyle(color: c.ink, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text('Private, end-to-end encrypted chat.\nTalk freely, share your thoughts.',
              textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 15.5, height: 1.4)),
          const SizedBox(height: 44),
          DuloButton(label: 'Create account', onPressed: () => _go(_Mode.signup1)),
          const SizedBox(height: 12),
          DuloButton(label: 'I already have an account', outlined: true, onPressed: () => _go(_Mode.login)),
        ],
      ),
    );
  }

  Widget _head(DuloColors c, String title, String sub, VoidCallback back) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        IconButton(onPressed: back, icon: const Icon(Icons.arrow_back_rounded), padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
        const SizedBox(height: 6),
        Text(title, style: TextStyle(color: c.ink, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
        const SizedBox(height: 6),
        Text(sub, style: TextStyle(color: c.muted, fontSize: 14.5)),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _login(DuloColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: <Widget>[
        _head(c, 'Welcome back', 'Log in to continue', () => _go(_Mode.landing)),
        DuloTextField(controller: _user, label: 'Username', hint: 'yourname', prefixIcon: Icons.alternate_email_rounded, textInputAction: TextInputAction.next),
        const SizedBox(height: 14),
        DuloTextField(controller: _pass, label: 'Password', hint: 'Password', password: true, prefixIcon: Icons.lock_outline_rounded, onSubmitted: (_) => _doLogin()),
        _errBox(c),
        DuloButton(label: 'Log in', busy: _busy, onPressed: _doLogin),
        const SizedBox(height: 6),
        Align(
          child: TextButton(onPressed: () => _forgot(), child: const Text('Forgot password?')),
        ),
        const SizedBox(height: 6),
        Align(
          child: TextButton(onPressed: () => _go(_Mode.signup1), child: const Text('New here? Create an account')),
        ),
      ],
    );
  }

  Future<void> _forgot() async {
    final c = context.dulo;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forgot password'),
        content: Text(
          'Open Dulochat in your browser (the web version), tap "Forgot password?" and enter your 12 recovery words. Password reset inside the app is coming soon.',
          style: TextStyle(color: c.muted),
        ),
        actions: <Widget>[TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Widget _signup1(DuloColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: <Widget>[
        _head(c, 'Create account', 'Step 1 of 2: your details', () => _go(_Mode.landing)),
        DuloTextField(controller: _name, label: 'Full name', hint: 'Your name', prefixIcon: Icons.person_outline_rounded, textInputAction: TextInputAction.next),
        const SizedBox(height: 14),
        DuloTextField(controller: _user, label: 'Username', hint: 'letters, numbers, _ . -', prefixIcon: Icons.alternate_email_rounded, textInputAction: TextInputAction.next),
        const SizedBox(height: 14),
        Text('Gender', style: TextStyle(color: c.muted, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          segments: const <ButtonSegment<String>>[
            ButtonSegment<String>(value: 'male', label: Text('Male')),
            ButtonSegment<String>(value: 'female', label: Text('Female')),
            ButtonSegment<String>(value: 'other', label: Text('Other')),
          ],
          selected: _gender.isEmpty ? <String>{} : <String>{_gender},
          onSelectionChanged: (v) => setState(() => _gender = v.isEmpty ? '' : v.first),
        ),
        const SizedBox(height: 14),
        DuloTextField(controller: _pass, label: 'Password', hint: 'At least 6 characters', password: true, prefixIcon: Icons.lock_outline_rounded, textInputAction: TextInputAction.next),
        const SizedBox(height: 14),
        DuloTextField(controller: _pass2, label: 'Confirm password', hint: 'Type it again', password: true, prefixIcon: Icons.lock_outline_rounded),
        const SizedBox(height: 10),
        CheckboxListTile(
          value: _agree,
          onChanged: (v) => setState(() => _agree = v == true),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text('I accept the Terms & Privacy Policy', style: TextStyle(color: c.ink, fontSize: 14)),
        ),
        _errBox(c),
        DuloButton(label: 'Continue', onPressed: _toStep2),
        const SizedBox(height: 6),
        Align(child: TextButton(onPressed: () => _go(_Mode.login), child: const Text('Already have an account? Log in'))),
      ],
    );
  }

  Widget _signup2(DuloColors c) {
    final d = _dob;
    final dobText = d == null ? 'Select date of birth' : '${d.day}/${d.month}/${d.year}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: <Widget>[
        _head(c, 'About you', 'Step 2 of 2: almost done', () => _go(_Mode.signup1)),
        DuloTextField(controller: _bio, label: 'Bio (at least 10 words)', hint: 'Tell people about yourself', maxLines: 3, maxLength: 150, onChanged: (_) => setState(() {})),
        Align(
          alignment: Alignment.centerRight,
          child: Text('${_words(_bio.text)} words', style: TextStyle(color: c.muted, fontSize: 12)),
        ),
        const SizedBox(height: 10),
        Text('Date of birth', style: TextStyle(color: c.muted, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _pickDob,
          icon: const Icon(Icons.cake_outlined),
          label: Align(alignment: Alignment.centerLeft, child: Text(dobText)),
        ),
        const SizedBox(height: 14),
        DuloTextField(controller: _link, label: 'Link (optional)', hint: 'yourwebsite.com', prefixIcon: Icons.link_rounded, keyboardType: TextInputType.url),
        _errBox(c),
        DuloButton(label: 'Create account', busy: _busy, onPressed: _doSignup),
      ],
    );
  }
}
