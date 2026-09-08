import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controla el modo claro/oscuro de la app. Por defecto arranca en
/// [ThemeMode.dark] (la app es "dark first"); el usuario puede cambiarlo
/// desde Ajustes y su elección se persiste y tiene prioridad.
class ThemeModeProvider extends ChangeNotifier {
  static const _storageKey = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.dark;

  ThemeModeProvider() {
    _load();
  }

  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, mode.name);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => ThemeMode.dark,
    );
    notifyListeners();
  }
}
