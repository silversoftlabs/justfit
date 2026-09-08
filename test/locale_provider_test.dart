import 'package:armario_virtual/providers/locale_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('por defecto arranca en español', () {
    expect(LocaleProvider().languageCode, 'es');
    expect(LocaleProvider(initialLanguageCode: null).languageCode, 'es');
    expect(LocaleProvider(initialLanguageCode: 'xx').languageCode, 'es');
  });

  test('respeta el idioma inicial pasado por main()', () {
    expect(LocaleProvider(initialLanguageCode: 'en').languageCode, 'en');
    expect(LocaleProvider(initialLanguageCode: ' EN ').languageCode, 'en');
  });

  test('setLanguage cambia el locale, notifica y persiste en app_language', () async {
    final provider = LocaleProvider();
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.setLanguage('en');
    expect(provider.locale.languageCode, 'en');
    expect(notifications, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocaleProvider.storageKey), 'en');

    // Cambiar al mismo idioma no hace nada.
    await provider.setLanguage('en');
    expect(notifications, 1);

    // Un idioma no soportado se ignora.
    await provider.setLanguage('de');
    expect(provider.locale.languageCode, 'en');
    expect(notifications, 1);
  });

  test('load() recupera el idioma persistido', () async {
    SharedPreferences.setMockInitialValues({LocaleProvider.storageKey: 'en'});
    final provider = LocaleProvider(); // sin initialLanguageCode
    expect(provider.languageCode, 'es');
    await provider.load();
    expect(provider.languageCode, 'en');
  });
}
