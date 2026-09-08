/// Categoría de prenda editable por el usuario desde 'Gestión de Armario'.
///
/// Es independiente de [GarmentCategory] (usada al etiquetar cada prenda):
/// esta lista es la organización personal del armario que el usuario puede
/// renombrar, reordenar o ampliar con nuevas categorías propias.
class CategoriaArmario {
  final String id;
  final String emoji;
  final String nombre;

  const CategoriaArmario({required this.id, required this.emoji, required this.nombre});

  CategoriaArmario copyWith({String? emoji, String? nombre}) {
    return CategoriaArmario(
      id: id,
      emoji: emoji ?? this.emoji,
      nombre: nombre ?? this.nombre,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'emoji': emoji, 'nombre': nombre};

  factory CategoriaArmario.fromJson(Map<String, dynamic> json) => CategoriaArmario(
        id: json['id'] as String,
        emoji: json['emoji'] as String,
        nombre: json['nombre'] as String,
      );
}

/// Categorías por defecto del armario, alineadas con `GarmentCategory`.
const defaultCategorias = [
  CategoriaArmario(id: 'camiseta', emoji: '👕', nombre: 'Camiseta'),
  CategoriaArmario(id: 'pantalon', emoji: '👖', nombre: 'Pantalón'),
  CategoriaArmario(id: 'calzado', emoji: '👟', nombre: 'Calzado'),
  CategoriaArmario(id: 'chaqueta', emoji: '🧥', nombre: 'Chaqueta'),
];

/// Emojis sugeridos al crear una nueva categoría.
const categoriaEmojiOptions = [
  '👕', '👖', '👟', '🧥', '👗', '👔', '🧣', '🧤', '🧢', '👒',
  '🩳', '🩱', '👜', '🕶️', '💍', '⌚', '🧦', '👚', '🥾', '🎒',
];

enum EstiloPrincipal { casual, formal, sport, elegante }

extension EstiloPrincipalLabel on EstiloPrincipal {
  String get label {
    switch (this) {
      case EstiloPrincipal.casual:
        return 'Casual';
      case EstiloPrincipal.formal:
        return 'Formal';
      case EstiloPrincipal.sport:
        return 'Sport';
      case EstiloPrincipal.elegante:
        return 'Elegante';
    }
  }
}

enum EstacionActiva { primaveraVerano, otonoInvierno, todoElAno }

extension EstacionActivaLabel on EstacionActiva {
  String get label {
    switch (this) {
      case EstacionActiva.primaveraVerano:
        return 'Primavera/Verano';
      case EstacionActiva.otonoInvierno:
        return 'Otoño/Invierno';
      case EstacionActiva.todoElAno:
        return 'Todo el año';
    }
  }
}

/// Regla de combinación (activable/desactivable) escrita por el usuario.
/// Actualmente no la lee ningún generador de outfits: `OutfitMatchingService`
/// (motor de reglas local) no interpreta texto libre, ver su documentación.
class ReglaCombinacion {
  final String texto;
  final bool activa;

  const ReglaCombinacion({required this.texto, this.activa = false});

  ReglaCombinacion copyWith({bool? activa}) {
    return ReglaCombinacion(texto: texto, activa: activa ?? this.activa);
  }

  Map<String, dynamic> toJson() => {'texto': texto, 'activa': activa};

  factory ReglaCombinacion.fromJson(Map<String, dynamic> json) => ReglaCombinacion(
        texto: json['texto'] as String,
        activa: json['activa'] as bool? ?? false,
      );
}

/// Reglas de combinación sugeridas por defecto (desactivadas hasta que el
/// usuario las active).
const defaultReglas = [
  ReglaCombinacion(texto: 'Evitar mezcla de estampados'),
  ReglaCombinacion(texto: 'No combinar más de dos colores llamativos'),
  ReglaCombinacion(texto: 'Mantener paleta neutra en looks formales'),
  ReglaCombinacion(texto: 'No repetir la misma prenda en la misma semana'),
];
