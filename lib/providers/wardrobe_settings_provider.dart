import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/wardrobe_settings.dart';

/// Preferencias de 'Gestión de Armario': categorías personales, estilo y
/// estación activa, y reglas de combinación en texto libre (ver
/// `ReglaCombinacion`, actualmente sin efecto sobre la generación de
/// outfits). Persistidas por separado de `WardrobeProvider` (que solo guarda
/// las prendas).
class WardrobeSettingsProvider extends ChangeNotifier {
  static const _storageKey = 'wardrobe_settings';

  List<CategoriaArmario> _categorias = List.of(defaultCategorias);
  EstiloPrincipal _estiloPrincipal = EstiloPrincipal.casual;
  EstacionActiva _estacionActiva = EstacionActiva.todoElAno;
  List<ReglaCombinacion> _reglas = List.of(defaultReglas);
  bool _isLoading = true;

  WardrobeSettingsProvider() {
    _load();
  }

  List<CategoriaArmario> get categorias => List.unmodifiable(_categorias);
  EstiloPrincipal get estiloPrincipal => _estiloPrincipal;
  EstacionActiva get estacionActiva => _estacionActiva;
  List<ReglaCombinacion> get reglas => List.unmodifiable(_reglas);
  bool get isLoading => _isLoading;

  /// Texto de las reglas activadas, listo para inyectar en el prompt de
  /// `OutfitRecommendationService`.
  List<String> get activeCombinationRules =>
      _reglas.where((r) => r.activa).map((r) => r.texto).toList();

  Future<void> setEstiloPrincipal(EstiloPrincipal estilo) async {
    if (_estiloPrincipal == estilo) return;
    _estiloPrincipal = estilo;
    notifyListeners();
    await _persist();
  }

  Future<void> setEstacionActiva(EstacionActiva estacion) async {
    if (_estacionActiva == estacion) return;
    _estacionActiva = estacion;
    notifyListeners();
    await _persist();
  }

  Future<void> toggleRegla(int index) async {
    if (index < 0 || index >= _reglas.length) return;
    _reglas[index] = _reglas[index].copyWith(activa: !_reglas[index].activa);
    notifyListeners();
    await _persist();
  }

  Future<void> addRegla(String texto) async {
    final trimmed = texto.trim();
    if (trimmed.isEmpty) return;
    _reglas.add(ReglaCombinacion(texto: trimmed, activa: true));
    notifyListeners();
    await _persist();
  }

  Future<void> removeRegla(int index) async {
    if (index < 0 || index >= _reglas.length) return;
    _reglas.removeAt(index);
    notifyListeners();
    await _persist();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final categoriasJson = decoded['categorias'] as List<dynamic>?;
      if (categoriasJson != null && categoriasJson.isNotEmpty) {
        _categorias = categoriasJson
            .map((e) => CategoriaArmario.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      final reglasJson = decoded['reglas'] as List<dynamic>?;
      if (reglasJson != null) {
        _reglas = reglasJson
            .map((e) => ReglaCombinacion.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      _estiloPrincipal = EstiloPrincipal.values.firstWhere(
        (e) => e.name == decoded['estiloPrincipal'],
        orElse: () => EstiloPrincipal.casual,
      );
      _estacionActiva = EstacionActiva.values.firstWhere(
        (e) => e.name == decoded['estacionActiva'],
        orElse: () => EstacionActiva.todoElAno,
      );
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      'categorias': _categorias.map((c) => c.toJson()).toList(),
      'reglas': _reglas.map((r) => r.toJson()).toList(),
      'estiloPrincipal': _estiloPrincipal.name,
      'estacionActiva': _estacionActiva.name,
    });
    await prefs.setString(_storageKey, encoded);
  }
}
