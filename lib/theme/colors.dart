import 'package:flutter/material.dart';

/// Dulochat colours, same values as the web app (white / black themes, blue accent).
class DuloColors extends ThemeExtension<DuloColors> {
  final Color bg;
  final Color surface;
  final Color soft;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color accentInk;
  final Color mine;
  final Color mineInk;
  final Color mineTime;
  final Color danger;

  const DuloColors({
    required this.bg,
    required this.surface,
    required this.soft,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentInk,
    required this.mine,
    required this.mineInk,
    required this.mineTime,
    required this.danger,
  });

  static const light = DuloColors(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    soft: Color(0xFFF1F7FC),
    ink: Color(0xFF000000),
    muted: Color(0xFF66798A),
    line: Color(0xFFE6EDF3),
    accent: Color(0xFF1594EA),
    accentInk: Color(0xFFFFFFFF),
    mine: Color(0xFF1594EA),
    mineInk: Color(0xFFFFFFFF),
    mineTime: Color(0xFFDCF0FF),
    danger: Color(0xFFE5484D),
  );

  static const dark = DuloColors(
    bg: Color(0xFF000000),
    surface: Color(0xFF000000),
    soft: Color(0xFF101114),
    ink: Color(0xFFFFFFFF),
    muted: Color(0xFFA3AAB2),
    line: Color(0xFF202226),
    accent: Color(0xFF2EA0FF),
    accentInk: Color(0xFF001426),
    mine: Color(0xFF1A86E0),
    mineInk: Color(0xFFFFFFFF),
    mineTime: Color(0xFFCBE8FF),
    danger: Color(0xFFFF8F7C),
  );

  @override
  DuloColors copyWith({
    Color? bg,
    Color? surface,
    Color? soft,
    Color? ink,
    Color? muted,
    Color? line,
    Color? accent,
    Color? accentInk,
    Color? mine,
    Color? mineInk,
    Color? mineTime,
    Color? danger,
  }) {
    return DuloColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      soft: soft ?? this.soft,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      mine: mine ?? this.mine,
      mineInk: mineInk ?? this.mineInk,
      mineTime: mineTime ?? this.mineTime,
      danger: danger ?? this.danger,
    );
  }

  @override
  DuloColors lerp(ThemeExtension<DuloColors>? other, double t) {
    if (other is! DuloColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return DuloColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      soft: l(soft, other.soft),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      line: l(line, other.line),
      accent: l(accent, other.accent),
      accentInk: l(accentInk, other.accentInk),
      mine: l(mine, other.mine),
      mineInk: l(mineInk, other.mineInk),
      mineTime: l(mineTime, other.mineTime),
      danger: l(danger, other.danger),
    );
  }
}

extension DuloColorsContext on BuildContext {
  DuloColors get dulo => Theme.of(this).extension<DuloColors>()!;
}
