import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Round avatar. Shows [imageUrl] if given, otherwise the first letter of [name]
/// on a colour picked from the name (same name = same colour).
class DuloAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  final bool online;

  const DuloAvatar({super.key, required this.name, this.imageUrl, this.size = 44, this.online = false});

  static const _palette = <Color>[
    Color(0xFF1594EA),
    Color(0xFF7C5CFC),
    Color(0xFF12A07A),
    Color(0xFFE5484D),
    Color(0xFFEF8F1A),
    Color(0xFFD6409F),
    Color(0xFF0E8FA6),
  ];

  Color _colorFor(String s) {
    var h = 0;
    for (final r in s.runes) {
      h = (h * 31 + r) & 0x7fffffff;
    }
    return _palette[h % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    final letter = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase();
    final Widget inner = (imageUrl != null && imageUrl!.isNotEmpty)
        ? ClipOval(
            child: Image.network(
              imageUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _letter(letter),
            ),
          )
        : _letter(letter);
    if (!online) return inner;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        inner,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              shape: BoxShape.circle,
              border: Border.all(color: c.bg, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _letter(String letter) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _colorFor(name), shape: BoxShape.circle),
      child: Text(
        letter,
        style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w700),
      ),
    );
  }
}
