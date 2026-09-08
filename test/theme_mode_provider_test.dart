import 'package:armario_virtual/providers/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sin preferencia guardada, la app arranca en modo oscuro', () {
    expect(ThemeModeProvider().themeMode, ThemeMode.dark);
  });

  test('la elección del usuario persiste y notifica', () async {
    final provider = ThemeModeProvider();
    var notified = false;
    provider.addListener(() => notified = true);

    await provider.setThemeMode(ThemeMode.light);

    expect(provider.themeMode, ThemeMode.light);
    expect(notified, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'light');
  });

  test('un provider nuevo recupera la elección persistida (no el dark por defecto)',
      () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
    final provider = ThemeModeProvider();

    var guard = 0;
    while (provider.themeMode == ThemeMode.dark && guard++ < 200) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    expect(provider.themeMode, ThemeMode.light);
  });
}
