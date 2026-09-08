import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guarda el nombre de perfil mostrado en el `ProfileSheet`, editable por
/// el usuario desde el bottom sheet de Perfil.
class UserProfileProvider extends ChangeNotifier {
  static const _storageKey = 'profile_name';

  /// Nombre que el usuario escribe en el onboarding. Se usa como valor
  /// inicial mientras no haya editado el nombre desde el `ProfileSheet`
  /// (momento en que se escribe [_storageKey], que tiene prioridad).
  static const _onboardingNameKey = 'user_name';

  static const defaultName = 'Sofía Moreno';

  String _name = defaultName;

  UserProfileProvider() {
    _load();
  }

  String get name => _name;

  Future<void> setName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _name) return;
    _name = trimmed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, trimmed);
  }

  /// Vuelve a leer el nombre desde `SharedPreferences`. Lo llama el
  /// `ProfileSheet` al abrirse, para recoger el `user_name` que el onboarding
  /// pudo escribir después de que este provider se construyera (el onboarding
  /// no reinicia la app).
  Future<void> reload() => _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey) ?? prefs.getString(_onboardingNameKey);
    if (raw == null || raw.trim().isEmpty) return;
    _name = raw;
    notifyListeners();
  }
}
