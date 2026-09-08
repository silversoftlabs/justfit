import 'package:armario_virtual/providers/favorite_outfits_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fastFail = Timeout(Duration(seconds: 30));

/// Crea el provider y espera a que termine la carga inicial desde
/// `SharedPreferences` (el constructor la dispara en segundo plano).
Future<FavoriteOutfitsProvider> _loadedProvider() async {
  final provider = FavoriteOutfitsProvider();
  var guard = 0;
  while (provider.isLoading && guard++ < 1000) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  return provider;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'addFavoriteOutfit marca el outfit como favorito (sin importar el orden)',
    () async {
      final provider = await _loadedProvider();

      await provider.addFavoriteOutfit(garmentIds: ['a', 'b', 'c'], tags: ['Trabajo']);

      expect(provider.favorites, hasLength(1));
      expect(provider.isFavorite(['a', 'b', 'c']), isTrue);
      expect(provider.isFavorite(['c', 'a', 'b']), isTrue);
      expect(provider.isFavorite(['a', 'b']), isFalse);
    },
    timeout: _fastFail,
  );

  test('no se duplica un favorito con el mismo conjunto de prendas', () async {
    final provider = await _loadedProvider();

    await provider.addFavoriteOutfit(garmentIds: ['a', 'b']);
    await provider.addFavoriteOutfit(garmentIds: ['b', 'a']);

    expect(provider.favorites, hasLength(1));
  });

  test('removeFavoriteOutfit lo quita', () async {
    final provider = await _loadedProvider();
    await provider.addFavoriteOutfit(garmentIds: ['a', 'b']);
    final id = provider.favorites.single.id;

    await provider.removeFavoriteOutfit(id);

    expect(provider.favorites, isEmpty);
    expect(provider.isFavorite(['a', 'b']), isFalse);
  });

  test('los favoritos persisten entre instancias del provider', () async {
    final first = await _loadedProvider();
    await first.addFavoriteOutfit(
      garmentIds: ['x', 'y'],
      tags: ['Casual', 'Deportivo'],
      occasion: 'Casual',
    );

    final second = await _loadedProvider();

    expect(second.favorites, hasLength(1));
    final favorite = second.favorites.single;
    expect(favorite.garmentIds, ['x', 'y']);
    expect(favorite.tags, ['Casual', 'Deportivo']);
    expect(favorite.occasion, 'Casual');
  });

  test('updateFavoriteOutfit renombra y reemplaza los tags', () async {
    final provider = await _loadedProvider();
    await provider.addFavoriteOutfit(
      garmentIds: ['a', 'b'],
      tags: ['Casual'],
      occasion: 'Casual',
    );
    final id = provider.favorites.single.id;

    await provider.updateFavoriteOutfit(
      id,
      name: '  Look oficina  ',
      tags: ['Trabajo', ' Formal ', ''],
    );

    final favorite = provider.favorites.single;
    expect(favorite.name, 'Look oficina');
    expect(favorite.tags, ['Trabajo', 'Formal']);
    expect(favorite.occasion, 'Casual', reason: 'la ocasión no se toca al editar');
  });

  test('updateFavoriteOutfit con nombre vacío lo deja en null', () async {
    final provider = await _loadedProvider();
    await provider.addFavoriteOutfit(garmentIds: ['a'], tags: const []);
    final id = provider.favorites.single.id;

    await provider.updateFavoriteOutfit(id, name: '   ', tags: const []);

    expect(provider.favorites.single.name, isNull);
  });
}
