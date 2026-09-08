import 'package:armario_virtual/providers/user_profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sin nombre guardado usa el nombre por defecto', () {
    expect(UserProfileProvider().name, UserProfileProvider.defaultName);
  });

  test('reload() recoge el user_name que el onboarding escribe después', () async {
    final provider = UserProfileProvider();
    expect(provider.name, UserProfileProvider.defaultName);

    // El onboarding termina y escribe la clave `user_name`.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', 'Lucía');

    await provider.reload();
    expect(provider.name, 'Lucía');
  });

  test('el nombre editado en el Perfil (profile_name) tiene prioridad', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', 'Lucía');
    await prefs.setString('profile_name', 'Lucía Fernández');

    final provider = UserProfileProvider();
    await provider.reload();
    expect(provider.name, 'Lucía Fernández');
  });

  test('setName persiste en profile_name y notifica', () async {
    final provider = UserProfileProvider();
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.setName('Marina');
    expect(provider.name, 'Marina');
    expect(notifications, greaterThan(0));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('profile_name'), 'Marina');
  });
}
