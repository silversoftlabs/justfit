import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Historial de las últimas sugerencias mostradas en "Outfit del día", para
/// que el motor de recomendación (`OutfitMatchingService`) pueda penalizar las
/// prendas usadas hace poco (cooldown) y la pantalla pueda forzar la rotación
/// de la parte superior. Persistido en `SharedPreferences` con el mismo patrón
/// que [FavoriteOutfitsProvider] / `OutfitPlanProvider`: una única clave
/// `String` con el `jsonEncode` de la lista, `notifyListeners()` antes de
/// `_persist()` en cada mutación.
///
/// Solo guarda ids de prenda (nunca copias) y solo se usa como señal *suave*
/// de puntuación o como exclusión de un único top (nunca como filtro que pueda
/// dejar al usuario sin outfit). Un historial obsoleto —el usuario borra y
/// vuelve a añadir prendas, o vuelve tras un largo parón— como mucho produce
/// un ranking algo raro durante una generación y se auto-cura en cuanto se
/// registra la siguiente sugerencia (los ids que ya no existen no penalizan
/// nada).
class OutfitHistoryProvider extends ChangeNotifier {
  static const _storageKey = 'outfit_history';

  /// Tope de entradas guardadas: suficiente para un cooldown útil de varios
  /// días sin que el JSON crezca sin control.
  static const _maxEntries = 20;

  final List<_OutfitHistoryEntry> _entries = [];
  bool _isLoaded = false;

  OutfitHistoryProvider() {
    _load();
  }

  /// `false` hasta que `_load()` termina (primera lectura de disco). La
  /// pantalla no bloquea nada esperándolo: si aún no ha cargado, el historial
  /// se comporta como vacío (sin cooldown, sin rotación forzada).
  bool get isLoaded => _isLoaded;

  bool get hasHistory => _entries.isNotEmpty;

  /// Id de la parte superior (capa base) de la sugerencia más reciente, o
  /// `null` si no hay historial o ese outfit no tenía capa base (outfit solo
  /// de abrigo).
  String? get lastTopId => _entries.isEmpty ? null : _entries.first.topId;

  /// Todos los ids de prenda de la sugerencia más reciente.
  Set<String> get lastOutfitGarmentIds =>
      _entries.isEmpty ? const {} : _entries.first.garmentIds.toSet();

  /// Unión de los ids de prenda de las últimas [lookback] sugerencias
  /// registradas: el "pool" de cooldown. Basado en conteo de entradas, no en
  /// una ventana temporal, para que el provider sea determinista y testeable
  /// sin inyectar un reloj.
  Set<String> recentGarmentIds({int lookback = 5}) {
    final ids = <String>{};
    for (final entry in _entries.take(lookback)) {
      ids.addAll(entry.garmentIds);
    }
    return ids;
  }

  /// Registra una sugerencia recién mostrada al usuario: la empuja al frente,
  /// recorta a [_maxEntries] y persiste. [topId] es el id de su prenda de capa
  /// base (`null` si el outfit no tiene una). El `_entries` en memoria se
  /// actualiza de forma síncrona antes del `await` de persistencia, así que
  /// una regeneración inmediata ya ve el nuevo estado aunque el `_persist()`
  /// siga en curso.
  Future<void> recordOutfit(List<String> garmentIds, {String? topId}) async {
    _entries.insert(
      0,
      _OutfitHistoryEntry(
        garmentIds: List<String>.from(garmentIds),
        topId: topId,
        shownAt: DateTime.now(),
      ),
    );
    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }
    notifyListeners();
    await _persist();
  }

  /// Vacía el historial (helper de test/debug y de un futuro "empezar de
  /// cero" en ajustes).
  Future<void> clear() async {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _entries
          ..clear()
          ..addAll(
            decoded.map(
              (e) => _OutfitHistoryEntry.fromJson(e as Map<String, dynamic>),
            ),
          );
        if (_entries.length > _maxEntries) {
          _entries.removeRange(_maxEntries, _entries.length);
        }
      }
    } catch (_) {
      // Historial ilegible (formato viejo, JSON corrupto): es dato
      // desechable, así que se arranca en blanco en vez de propagar el error.
      _entries.clear();
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}

/// Una sugerencia mostrada: el conjunto de prendas que la formaban, cuál era
/// su parte superior (capa base) y cuándo se mostró. `shownAt` se guarda para
/// depuración y usos futuros; hoy ninguna lógica lo lee (el lookback es por
/// conteo, ver [OutfitHistoryProvider.recentGarmentIds]).
class _OutfitHistoryEntry {
  final List<String> garmentIds;
  final String? topId;
  final DateTime shownAt;

  const _OutfitHistoryEntry({
    required this.garmentIds,
    required this.topId,
    required this.shownAt,
  });

  Map<String, dynamic> toJson() => {
        'garmentIds': garmentIds,
        'topId': topId,
        'shownAt': shownAt.toIso8601String(),
      };

  factory _OutfitHistoryEntry.fromJson(Map<String, dynamic> json) {
    return _OutfitHistoryEntry(
      garmentIds: (json['garmentIds'] as List<dynamic>).cast<String>(),
      topId: json['topId'] as String?,
      shownAt: DateTime.parse(json['shownAt'] as String),
    );
  }
}
