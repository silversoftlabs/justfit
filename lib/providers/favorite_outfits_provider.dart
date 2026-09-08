import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_outfit.dart';

/// Outfits favoritos del usuario, persistidos en `SharedPreferences` con el
/// mismo patrón que `OutfitPlanProvider`: una única clave `String` con el
/// `jsonEncode` de la lista de `toJson()`, y `notifyListeners()` antes de
/// `_persist()` en cada mutación para que la UI reaccione al instante.
class FavoriteOutfitsProvider extends ChangeNotifier {
  static const _storageKey = 'favorite_outfits';

  final List<FavoriteOutfit> _favorites = [];
  bool _isLoading = true;

  FavoriteOutfitsProvider() {
    _loadFavorites();
  }

  /// Favoritos ordenados del más reciente al más antiguo.
  List<FavoriteOutfit> get favorites {
    final sorted = [..._favorites]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(sorted);
  }

  bool get isLoading => _isLoading;

  /// Favorito cuyo conjunto de prendas coincide con [garmentIds] sin importar
  /// el orden, o `null` si no hay ninguno.
  FavoriteOutfit? favoriteFor(List<String> garmentIds) {
    final target = garmentIds.toSet();
    for (final fav in _favorites) {
      final ids = fav.garmentIds.toSet();
      if (ids.length == target.length && ids.containsAll(target)) return fav;
    }
    return null;
  }

  bool isFavorite(List<String> garmentIds) => favoriteFor(garmentIds) != null;

  Future<void> addFavoriteOutfit({
    String? name,
    required List<String> garmentIds,
    List<String> tags = const [],
    String? occasion,
  }) async {
    // Sin duplicados: si ya hay un favorito con exactamente estas prendas, no
    // se añade otro (el botón de "Outfit del día" es un toggle).
    if (favoriteFor(garmentIds) != null) return;
    _favorites.add(
      FavoriteOutfit(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        garmentIds: List<String>.from(garmentIds),
        createdAt: DateTime.now(),
        tags: List<String>.from(tags),
        occasion: occasion,
      ),
    );
    notifyListeners();
    await _persist();
  }

  /// Renombra un favorito y/o cambia sus tags (hoja de detalle → "Editar").
  /// Un [name] vacío o solo espacios se guarda como `null`.
  Future<void> updateFavoriteOutfit(
    String id, {
    required String? name,
    required List<String> tags,
  }) async {
    final index = _favorites.indexWhere((f) => f.id == id);
    if (index == -1) return;
    final current = _favorites[index];
    final trimmedName = name?.trim();
    _favorites[index] = FavoriteOutfit(
      id: current.id,
      name: (trimmedName == null || trimmedName.isEmpty) ? null : trimmedName,
      garmentIds: current.garmentIds,
      createdAt: current.createdAt,
      tags: tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      occasion: current.occasion,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> removeFavoriteOutfit(String id) async {
    _favorites.removeWhere((f) => f.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      _favorites
        ..clear()
        ..addAll(
          decoded.map(
            (e) => FavoriteOutfit.fromJson(e as Map<String, dynamic>),
          ),
        );
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_favorites.map((f) => f.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}
