/// Un outfit asignado a un día concreto del Planificador semanal.
class PlannedOutfit {
  final String id;
  final DateTime date;
  final List<String> garmentIds;
  final DateTime createdAt;

  /// Ocasión asociada al outfit (p. ej. "Trabajo", "Cena"), opcional: se
  /// rellena al asignar una sugerencia de IA o elegirla a mano.
  final String? occasion;

  PlannedOutfit({
    required this.id,
    required DateTime date,
    required this.garmentIds,
    required this.createdAt,
    this.occasion,
  }) : date = DateTime(date.year, date.month, date.day);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'garmentIds': garmentIds,
      'createdAt': createdAt.toIso8601String(),
      'occasion': occasion,
    };
  }

  factory PlannedOutfit.fromJson(Map<String, dynamic> json) {
    return PlannedOutfit(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      garmentIds: (json['garmentIds'] as List<dynamic>).cast<String>(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      occasion: json['occasion'] as String?,
    );
  }
}
