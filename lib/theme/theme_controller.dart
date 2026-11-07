import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers Light / Dark / System choice on the phone.
class ThemeController extends ChangeNotifier {
  static const _key = 'dulo-theme';
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_key);
      _mode = v == 'light' ? ThemeMode.light : (v == 'dark' ? ThemeMode.dark : ThemeMode.system);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> set(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, m == ThemeMode.light ? 'light' : (m == ThemeMode.dark ? 'dark' : 'system'));
    } catch (_) {}
  }
}
