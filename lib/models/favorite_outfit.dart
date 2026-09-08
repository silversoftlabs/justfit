/// Un outfit que el usuario ha marcado como favorito desde "Outfit del día".
///
/// Igual que [PlannedOutfit] (`planned_outfit.dart`), un outfit se guarda como
/// una lista de `Garment.id` (no como copias de las prendas): la vista de
/// Favoritos rehidrata las prendas contra el armario actual y tolera ids que
/// ya no existan (prenda borrada después de guardar).
class FavoriteOutfit {
  final String id;

  /// Nombre opcional que el usuario pone al outfit desde la hoja de detalle
  /// ("Editar"). `null` si nunca lo ha renombrado.
  final String? name;

  final List<String> garmentIds;
  final DateTime createdAt;

  /// Etiquetas de estilo. Se rellenan automáticamente al guardar (los estilos
  /// distintos de las prendas) y el usuario puede editarlas después.
  final List<String> tags;

  /// Ocasión con la que se generó el outfit (p. ej. "Trabajo", "Casual"),
  /// tal cual la etiqueta que trae `OutfitRecommendation.occasion`.
  final String? occasion;

  FavoriteOutfit({
    required this.id,
    this.name,
    required this.garmentIds,
    required this.createdAt,
    this.tags = const [],
    this.occasion,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'garmentIds': garmentIds,
      'createdAt': createdAt.toIso8601String(),
      'tags': tags,
      'occasion': occasion,
    };
  }

  factory FavoriteOutfit.fromJson(Map<String, dynamic> json) {
    return FavoriteOutfit(
      id: json['id'] as String,
      name: json['name'] as String?,
      garmentIds: (json['garmentIds'] as List<dynamic>).cast<String>(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      occasion: json['occasion'] as String?,
    );
  }
}
