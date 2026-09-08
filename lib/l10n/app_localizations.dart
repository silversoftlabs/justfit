import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

/// Traducciones de la app. Las cadenas viven en `assets/l10n/<code>.json`
/// (planas, `"clave": "texto"`) y se cargan al construir el `Locale`.
///
/// Uso: `AppLocalizations.of(context).t('clave')`, o el atajo
/// `context.l10n.t('clave')` (ver [AppLocalizationsContext] más abajo).
///
/// No usa `flutter gen-l10n`: un diccionario JSON plano + este delegado es
/// suficiente para dos idiomas, sin paso de codegen. Los widgets de Material
/// (selectores de fecha, semántica, RTL) sí se localizan con
/// `flutter_localizations` (ver `localizationsDelegates` en `main.dart`).
class AppLocalizations {
  AppLocalizations(this.locale, this._strings);

  final Locale locale;
  final Map<String, String> _strings;

  /// Idiomas soportados. `es` es el de referencia (100% de las claves) y hace
  /// de respaldo para cualquier clave que falte en otro idioma.
  static const supportedLocales = <Locale>[Locale('es'), Locale('en')];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final instance = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(instance != null, 'Falta AppLocalizations.delegate en MaterialApp.localizationsDelegates');
    return instance!;
  }

  /// Diccionarios ya cargados, por código de idioma. Una vez calientes, [load]
  /// resuelve de forma SÍNCRONA (`SynchronousFuture`), así que cambiar de
  /// idioma no produce un frame en blanco.
  static final Map<String, Map<String, String>> _cache = {};

  static Future<Map<String, String>> _loadStrings(String code) async {
    if (_cache.containsKey(code)) return _cache[code]!;
    final raw = await rootBundle.loadString('assets/l10n/$code.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final map = decoded.map((key, value) => MapEntry(key, value.toString()));
    _cache[code] = map;
    return map;
  }

  static AppLocalizations _build(Locale locale) {
    final es = _cache['es']!;
    final own = _cache[locale.languageCode] ?? es;
    final merged = identical(own, es) ? es : {...es, ...own};
    return AppLocalizations(locale, merged);
  }

  static Future<AppLocalizations> load(Locale locale) {
    final code = locale.languageCode;
    if (_cache.containsKey('es') && _cache.containsKey(code)) {
      return SynchronousFuture(_build(locale));
    }
    return Future(() async {
      await _loadStrings('es');
      if (code != 'es') await _loadStrings(code);
      return _build(locale);
    });
  }

  /// Precarga los dos diccionarios. Útil en tests (`setUpAll`) para que el
  /// texto localizado esté disponible desde el primer frame.
  static Future<void> ensureLoaded() async {
    await _loadStrings('es');
    await _loadStrings('en');
  }

  /// Texto para [key]. Si falta (no debería), devuelve la propia clave para
  /// que el hueco se vea en pantalla en vez de romper. [params] sustituye
  /// `{nombre}` por su valor.
  String t(String key, [Map<String, Object?>? params]) {
    var value = _strings[key];
    if (value == null) {
      if (kDebugMode) debugPrint('[i18n] clave sin traducir: "$key" (${locale.languageCode})');
      return key;
    }
    if (params != null) {
      params.forEach((name, replacement) {
        value = value!.replaceAll('{$name}', '$replacement');
      });
    }
    return value!;
  }

  bool get isSpanish => locale.languageCode == 'es';
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) => AppLocalizations.load(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Atajo: `context.l10n.t('clave')`.
extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
