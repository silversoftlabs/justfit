import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/planned_outfit.dart';

class OutfitPlanProvider extends ChangeNotifier {
  static const _storageKey = 'outfit_plans';

  final List<PlannedOutfit> _plans = [];
  bool _isLoading = true;

  OutfitPlanProvider() {
    _loadPlans();
  }

  List<PlannedOutfit> get plans => List.unmodifiable(_plans);
  bool get isLoading => _isLoading;

  PlannedOutfit? planForDate(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    for (final plan in _plans) {
      if (plan.date == key) return plan;
    }
    return null;
  }

  Future<void> assignOutfit(
    DateTime day,
    List<String> garmentIds, {
    String? occasion,
  }) async {
    final key = DateTime(day.year, day.month, day.day);
    _plans.removeWhere((p) => p.date == key);
    _plans.add(
      PlannedOutfit(
        id: '${key.toIso8601String()}-${DateTime.now().microsecondsSinceEpoch}',
        date: key,
        garmentIds: garmentIds,
        createdAt: DateTime.now(),
        occasion: occasion,
      ),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> removeAssignment(DateTime day) async {
    final key = DateTime(day.year, day.month, day.day);
    _plans.removeWhere((p) => p.date == key);
    notifyListeners();
    await _persist();
  }

  Future<void> _loadPlans() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      _plans
        ..clear()
        ..addAll(
          decoded.map((e) => PlannedOutfit.fromJson(e as Map<String, dynamic>)),
        );
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_plans.map((p) => p.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}
