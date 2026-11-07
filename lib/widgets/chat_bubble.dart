import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// One chat message bubble. [mine] bubbles are blue and on the right.
class ChatBubble extends StatelessWidget {
  final String text;
  final String time;
  final bool mine;
  final bool seen;

  const ChatBubble({super.key, required this.text, required this.time, this.mine = false, this.seen = false});

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    final bg = mine ? c.mine : c.soft;
    final ink = mine ? c.mineInk : c.ink;
    final sub = mine ? c.mineTime : c.muted;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
        padding: const EdgeInsets.fromLTRB(14, 9, 12, 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 5),
            bottomRight: Radius.circular(mine ? 5 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(text, style: TextStyle(color: ink, fontSize: 15.5, height: 1.3)),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time, style: TextStyle(color: sub, fontSize: 11)),
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(seen ? Icons.done_all : Icons.done, size: 14, color: sub),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
