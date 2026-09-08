import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/garment.dart';

class WardrobeProvider extends ChangeNotifier {
  static const _storageKey = 'wardrobe_garments';

  final List<Garment> _garments = [];
  bool _isLoading = true;

  WardrobeProvider() {
    _loadGarments();
  }

  /// Prendas activas (excluye las archivadas por 'Gestión de Armario').
  List<Garment> get garments => List.unmodifiable(_garments.where((g) => !g.isArchived));
  List<Garment> get archivedGarments => List.unmodifiable(_garments.where((g) => g.isArchived));
  bool get isLoading => _isLoading;

  List<Garment> bySuperCategory(GarmentSuperCategory? category) {
    if (category == null) return garments;
    return garments.where((g) => g.superCategory == category).toList();
  }

  Future<void> addGarment(Garment garment) async {
    _garments.add(garment);
    notifyListeners();
    await _persist();
  }

  Future<void> removeGarment(String id) async {
    _garments.removeWhere((g) => g.id == id);
    notifyListeners();
    await _persist();
  }

  /// Archiva las prendas activas cuya estación no está entre
  /// [activeSeasons] (las de estación 'Todo el año' nunca se archivan).
  /// Devuelve el número de prendas archivadas.
  ///
  /// Recibe un conjunto y no una estación suelta porque la preferencia del
  /// usuario agrupa estaciones ('Primavera/Verano' cubre dos).
  Future<int> archiveOutOfSeason(Set<GarmentSeason> activeSeasons) async {
    var count = 0;
    for (var i = 0; i < _garments.length; i++) {
      final g = _garments[i];
      if (!g.isArchived &&
          g.season != GarmentSeason.todoElAno &&
          !activeSeasons.contains(g.season)) {
        _garments[i] = g.copyWith(isArchived: true);
        count++;
      }
    }
    if (count > 0) {
      notifyListeners();
      await _persist();
    }
    return count;
  }

  /// Elimina todas las prendas del armario de forma irreversible.
  Future<void> clearAll() async {
    if (_garments.isEmpty) return;
    _garments.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _loadGarments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      _garments
        ..clear()
        ..addAll(
          decoded.map((e) => Garment.fromJson(e as Map<String, dynamic>)),
        );
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_garments.map((g) => g.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}
