import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';
import '../widgets/widgets.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

void toast(BuildContext context, String msg) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}

Future<void> copyText(BuildContext context, String text, [String done = 'Copied']) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, done);
}

/// Round blue logo used on the first screens.
class DuloLogo extends StatelessWidget {
  final double size;
  const DuloLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[c.accent, const Color(0xFF0B6FC2)],
        ),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x331594EA), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Icon(Icons.chat_bubble_rounded, color: Colors.white, size: size * 0.5),
    );
  }
}

/// Card with a title, used by settings style screens.
class SectionCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsets padding;
  const SectionCard({super.key, this.title, required this.children, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Text(title!, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// One tappable row (icon, title, optional subtitle, chevron).
class DuloTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;
  const DuloTile({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.trailing, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    final col = danger ? c.danger : c.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 20, color: danger ? c.danger : c.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: TextStyle(color: col, fontWeight: FontWeight.w600, fontSize: 15.5)),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(color: c.muted, fontSize: 12.5)),
                ],
              ),
            ),
            trailing ?? (onTap == null ? const SizedBox.shrink() : Icon(Icons.chevron_right_rounded, color: c.muted)),
          ],
        ),
      ),
    );
  }
}

/// Verified / official tick next to names.
class NameWithTick extends StatelessWidget {
  final String name;
  final bool official;
  final bool verified;
  final TextStyle? style;
  const NameWithTick({super.key, required this.name, this.official = false, this.verified = false, this.style});

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    final tick = official || verified;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: style)),
        if (tick) ...<Widget>[
          const SizedBox(width: 4),
          Icon(Icons.verified_rounded, size: 16, color: official ? const Color(0xFF16A34A) : c.accent),
        ],
      ],
    );
  }
}

Future<bool> confirmDialog(BuildContext context, String title, String body, {String yes = 'OK', String no = 'Cancel', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: danger ? TextButton.styleFrom(foregroundColor: ctx.dulo.danger) : null,
          child: Text(yes),
        ),
      ],
    ),
  );
  return r == true;
}

Widget loadingBox() => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));

/// Small pill badge for unread counts.
class CountBadge extends StatelessWidget {
  final int n;
  const CountBadge(this.n, {super.key});
  @override
  Widget build(BuildContext context) {
    if (n <= 0) return const SizedBox.shrink();
    final c = context.dulo;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(10)),
      child: Text(n > 99 ? '99+' : '$n', textAlign: TextAlign.center, style: TextStyle(color: c.accentInk, fontSize: 11.5, fontWeight: FontWeight.w800)),
    );
  }
}

/// Avatar helper that reads picture and online state from the session.
Widget userAvatar(dynamic session, String uid, {double size = 46, bool showOnline = true, String? fallbackName}) {
  final String name = session.nameOf(uid, fallbackName) as String;
  final String? pic = session.picOf(uid) as String?;
  final bool on = showOnline && (session.isOnline(uid) as bool);
  return DuloAvatar(name: name, imageUrl: pic != null && pic.startsWith('http') ? pic : null, dataUrl: pic != null && pic.startsWith('data:') ? pic : null, size: size, online: on);
}
