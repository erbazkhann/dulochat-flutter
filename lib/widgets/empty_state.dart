import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Placeholder shown on screens that are built in a later part.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyState({super.key, required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: c.soft, shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: c.accent),
            ),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(color: c.ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 14, height: 1.35)),
          ],
        ),
      ),
    );
  }
}
