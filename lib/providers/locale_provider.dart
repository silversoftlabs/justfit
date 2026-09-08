import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Idioma elegido por el usuario (onboarding o Ajustes del Perfil). Cambiar
/// [locale] reconstruye `MaterialApp` y con ella toda la app, sin reinicio.
///
/// Persiste en `SharedPreferences` con la clave `app_language` (`'es'` /
/// `'en'`). `main()` la lee antes de `runApp` para evitar un parpadeo en el
/// primer frame; por eso el constructor acepta un [initialLanguageCode].
class LocaleProvider extends ChangeNotifier {
  static const storageKey = 'app_language';
  static const supportedLanguageCodes = <String>['es', 'en'];

  Locale _locale;

  LocaleProvider({String? initialLanguageCode})
      : _locale = _localeFor(initialLanguageCode) ?? const Locale('es');

  Locale get locale => _locale;
  String get languageCode => _locale.languageCode;

  static Locale? _localeFor(String? code) {
    if (code == null) return null;
    final normalized = code.trim().toLowerCase();
    if (!supportedLanguageCodes.contains(normalized)) return null;
    return Locale(normalized);
  }

  /// Lee `app_language` de disco (por si `main()` no la pasó). Idempotente.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = _localeFor(prefs.getString(storageKey));
    if (stored != null && stored.languageCode != _locale.languageCode) {
      _locale = stored;
      notifyListeners();
    }
  }

  /// Cambia el idioma de toda la app al instante y lo persiste.
  Future<void> setLanguage(String code) async {
    final next = _localeFor(code);
    if (next == null || next.languageCode == _locale.languageCode) return;
    _locale = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, next.languageCode);
  }
}
