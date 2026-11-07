import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Main button. [busy] shows a spinner and blocks taps.
class DuloButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool outlined;
  final bool danger;
  final IconData? icon;

  const DuloButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.outlined = false,
    this.danger = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    final VoidCallback? tap = busy ? null : onPressed;
    final child = busy
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: outlined ? c.accent : c.accentInk,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    if (outlined) {
      return OutlinedButton(
        onPressed: tap,
        style: danger ? OutlinedButton.styleFrom(foregroundColor: c.danger, side: BorderSide(color: c.danger)) : null,
        child: child,
      );
    }
    return FilledButton(
      onPressed: tap,
      style: danger ? FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: Colors.white) : null,
      child: child,
    );
  }
}
