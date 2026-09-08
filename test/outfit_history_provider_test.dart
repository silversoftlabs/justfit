import 'package:armario_virtual/providers/outfit_history_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Espera a que `_load()` (asíncrono, disparado en el constructor) termine.
Future<OutfitHistoryProvider> _loadedProvider() async {
  final provider = OutfitHistoryProvider();
  // Un microtask-yield no basta: `_load()` hace `await SharedPreferences...`.
  while (!provider.isLoaded) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  return provider;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('recordOutfit empuja al frente; lastTopId / lastOutfitGarmentIds lo reflejan', () async {
    final provider = await _loadedProvider();

    await provider.recordOutfit(['topA', 'panA', 'zapA'], topId: 'topA');
    expect(provider.hasHistory, isTrue);
    expect(provider.lastTopId, 'topA');
    expect(provider.lastOutfitGarmentIds, {'topA', 'panA', 'zapA'});

    await provider.recordOutfit(['topB', 'panB', 'zapB'], topId: 'topB');
    expect(provider.lastTopId, 'topB');
    expect(provider.lastOutfitGarmentIds, {'topB', 'panB', 'zapB'});
  });

  test('un outfit sin capa base guarda topId nulo', () async {
    final provider = await _loadedProvider();
    await provider.recordOutfit(['abrigo', 'pan', 'zap'], topId: null);
    expect(provider.lastTopId, isNull);
  });

  test('se recorta a las 20 entradas más recientes', () async {
    final provider = await _loadedProvider();
    for (var i = 0; i < 25; i++) {
      await provider.recordOutfit(['top$i'], topId: 'top$i');
    }
    // La más reciente es la última grabada; la #4 (0-indexada) y anteriores
    // se han caído (25 - 20 = 5 descartadas: top0..top4).
    expect(provider.lastTopId, 'top24');
    final recent = provider.recentGarmentIds(lookback: 100);
    expect(recent, contains('top5'));
    expect(recent, isNot(contains('top4')));
    expect(recent.length, 20);
  });

  test('recentGarmentIds(lookback: 3) = unión de las 3 entradas más recientes', () async {
    final provider = await _loadedProvider();
    await provider.recordOutfit(['a1', 'a2'], topId: 'a1');
    await provider.recordOutfit(['b1', 'b2'], topId: 'b1');
    await provider.recordOutfit(['c1', 'c2'], topId: 'c1');
    await provider.recordOutfit(['d1', 'd2'], topId: 'd1');

    expect(
      provider.recentGarmentIds(lookback: 3),
      {'d1', 'd2', 'c1', 'c2', 'b1', 'b2'},
    );
  });

  test('el historial persiste y un provider nuevo lo recarga', () async {
    final first = await _loadedProvider();
    await first.recordOutfit(['topA', 'panA'], topId: 'topA');

    final second = await _loadedProvider();
    expect(second.hasHistory, isTrue);
    expect(second.lastTopId, 'topA');
    expect(second.lastOutfitGarmentIds, {'topA', 'panA'});
  });

  test('JSON corrupto en disco → carga vacío, isLoaded true, sin excepción', () async {
    SharedPreferences.setMockInitialValues({'outfit_history': '{no es una lista valida'});
    final provider = await _loadedProvider();
    expect(provider.isLoaded, isTrue);
    expect(provider.hasHistory, isFalse);
    expect(provider.recentGarmentIds(), isEmpty);
  });

  test('clear vacía el historial y persiste el vaciado', () async {
    final provider = await _loadedProvider();
    await provider.recordOutfit(['topA'], topId: 'topA');
    await provider.clear();
    expect(provider.hasHistory, isFalse);

    final reloaded = await _loadedProvider();
    expect(reloaded.hasHistory, isFalse);
  });
}
