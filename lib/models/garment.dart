enum GarmentCategory { camiseta, pantalon, calzado, chaqueta, sudadera, complemento }

/// Categorías que cuentan como "parte superior" al armar un outfit (camiseta,
/// chaqueta o sudadera), usado por el generador de outfits, la puntuación de
/// versatilidad y el calendario de outfits.
///
/// Aquí las tres se tratan como un único hueco indiferenciado (para
/// consumidores simples: badges, el generador rápido de `outfit_screen.dart`,
/// el selector manual del calendario...). El motor de reglas
/// (`OutfitMatchingService`) es quien SÍ distingue capa base/media/exterior
/// entre ellas (ver [GarmentCategoryLayer.layer]) y aplica ahí las reglas de
/// layering; el resto de la app sigue sin necesitar esa distinción.
const topGarmentCategories = {
  GarmentCategory.camiseta,
  GarmentCategory.chaqueta,
  GarmentCategory.sudadera,
};

/// Nivel de capa superior de una prenda para el layering de outfits: base
/// (camiseta), media (sudadera) o exterior (chaqueta). Las categorías que no
/// son parte superior no tienen nivel.
enum GarmentLayer { base, mid, outer }

extension GarmentCategoryLayer on GarmentCategory {
  GarmentLayer? get layer {
    switch (this) {
      case GarmentCategory.camiseta:
        return GarmentLayer.base;
      case GarmentCategory.sudadera:
        return GarmentLayer.mid;
      case GarmentCategory.chaqueta:
        return GarmentLayer.outer;
      case GarmentCategory.pantalon:
      case GarmentCategory.calzado:
      case GarmentCategory.complemento:
        return null;
    }
  }
}

extension GarmentCategoryLabel on GarmentCategory {
  String get label {
    switch (this) {
      case GarmentCategory.camiseta:
        return 'Camiseta';
      case GarmentCategory.pantalon:
        return 'Pantalón';
      case GarmentCategory.calzado:
        return 'Calzado';
      case GarmentCategory.chaqueta:
        return 'Chaqueta';
      case GarmentCategory.sudadera:
        return 'Sudadera';
      case GarmentCategory.complemento:
        return 'Complemento';
    }
  }
}

/// Supercategorías generales para la UI (chips de filtro de "Mi Armario" y
/// badges sobre la foto). NO se persisten ni las usa el motor de outfits: se
/// derivan en runtime de [GarmentCategory] + [Garment.tipoPrendaId] vía
/// [GarmentSuperCategoryOf.superCategory]. Agrupan las 6 [GarmentCategory] (y
/// las prendas de una sola pieza, hoy guardadas como camiseta) en las
/// familias con las que el usuario piensa el armario: una falda y un pantalón
/// son "Parte inferior", un vestido y un mono son "Pieza única", etc.
enum GarmentSuperCategory {
  parteSuperior,
  parteInferior,
  abrigos,
  piezaUnica,
  calzado,
  accesorios,
}

extension GarmentSuperCategoryLabel on GarmentSuperCategory {
  String get label {
    switch (this) {
      case GarmentSuperCategory.parteSuperior:
        return 'Parte superior';
      case GarmentSuperCategory.parteInferior:
        return 'Parte inferior';
      case GarmentSuperCategory.abrigos:
        return 'Abrigos';
      case GarmentSuperCategory.piezaUnica:
        return 'Pieza única';
      case GarmentSuperCategory.calzado:
        return 'Calzado';
      case GarmentSuperCategory.accesorios:
        return 'Accesorios';
    }
  }
}

/// `TipoPrenda.id` (ver `models/tipo_prenda.dart`) de las prendas de una sola
/// pieza — vestidos, monos, petos, trajes. Se guardan como
/// [GarmentCategory.camiseta] (no hay categoría propia en el modelo de
/// datos), así que [GarmentSuperCategoryOf.superCategory] los reconoce por su
/// `tipoPrendaId` para clasificarlos como [GarmentSuperCategory.piezaUnica].
/// Se listan como strings sueltos para no crear un import circular con
/// `tipo_prenda.dart` (que ya importa este archivo).
const piezaUnicaTipoPrendaIds = {'vestido', 'mono_peto', 'traje_completo'};

extension GarmentSuperCategoryOf on Garment {
  /// Supercategoría general de la prenda para la UI. Una prenda de una sola
  /// pieza (ver [piezaUnicaTipoPrendaIds]) es [GarmentSuperCategory.piezaUnica]
  /// aunque su [GarmentCategory] sea camiseta; el resto se deriva directamente
  /// de [category]. Una prenda antigua sin `tipoPrendaId` que en realidad era
  /// un vestido cae en "Parte superior" (no hay dato para distinguirla), mismo
  /// criterio conservador que el resto de la app.
  GarmentSuperCategory get superCategory {
    final id = tipoPrendaId;
    if (id != null && piezaUnicaTipoPrendaIds.contains(id)) {
      return GarmentSuperCategory.piezaUnica;
    }
    switch (category) {
      case GarmentCategory.camiseta:
      case GarmentCategory.sudadera:
        return GarmentSuperCategory.parteSuperior;
      case GarmentCategory.pantalon:
        return GarmentSuperCategory.parteInferior;
      case GarmentCategory.chaqueta:
        return GarmentSuperCategory.abrigos;
      case GarmentCategory.calzado:
        return GarmentSuperCategory.calzado;
      case GarmentCategory.complemento:
        return GarmentSuperCategory.accesorios;
    }
  }
}

/// Tipos de complemento (solo aplica cuando `Garment.category` es
/// [GarmentCategory.complemento]). Guardado en `Garment.accessoryType`.
///
/// `joyas` (genérico, "joyería y relojes") se sustituyó por tres tipos
/// específicos — [collar], [reloj], [pulsera] — para que el selector de
/// accesorios de "Outfit del día" (`daily_outfit_screen.dart`) pueda
/// distinguirlos y el usuario marque uno, varios o ninguno de forma
/// independiente. Una prenda persistida con el `accessoryType` antiguo
/// (`'joyas'`) se degrada a `null` al leerla (ver `_accessoryTypeFromJson`
/// más abajo): un valor no reconocido nunca rompe la carga, mismo criterio
/// que ya usa el resto del modelo para campos de versiones anteriores.
enum AccessoryType { gorra, bolso, cinturon, gafas, collar, reloj, pulsera }

extension AccessoryTypeLabel on AccessoryType {
  String get label {
    switch (this) {
      case AccessoryType.gorra:
        return 'Gorra';
      case AccessoryType.bolso:
        return 'Bolso';
      case AccessoryType.cinturon:
        return 'Cinturón';
      case AccessoryType.gafas:
        return 'Gafas';
      case AccessoryType.collar:
        return 'Collar';
      case AccessoryType.reloj:
        return 'Reloj';
      case AccessoryType.pulsera:
        return 'Pulsera';
    }
  }
}

enum GarmentStyle { casual, formal, deportivo, elegante, trabajo }

extension GarmentStyleLabel on GarmentStyle {
  String get label {
    switch (this) {
      case GarmentStyle.casual:
        return 'Casual';
      case GarmentStyle.formal:
        return 'Formal';
      case GarmentStyle.deportivo:
        return 'Deportivo';
      case GarmentStyle.elegante:
        return 'Elegante';
      case GarmentStyle.trabajo:
        return 'Trabajo';
    }
  }
}

/// Las cuatro estaciones más un comodín para las prendas de uso continuo.
///
/// Sustituye a un enum anterior de cuatro valores en el que primavera y otoño
/// iban juntas como `entretiempo`; ver [_seasonFromJson] para cómo se leen las
/// prendas guardadas con aquellos nombres.
enum GarmentSeason { primavera, verano, otono, invierno, todoElAno }

extension GarmentSeasonLabel on GarmentSeason {
  String get label {
    switch (this) {
      case GarmentSeason.primavera:
        return 'Primavera';
      case GarmentSeason.verano:
        return 'Verano';
      case GarmentSeason.otono:
        return 'Otoño';
      case GarmentSeason.invierno:
        return 'Invierno';
      case GarmentSeason.todoElAno:
        return 'Todo el año';
    }
  }
}

class Garment {
  final String id;
  final String imagePath;
  final GarmentCategory category;
  final String color;
  final GarmentStyle style;
  final GarmentSeason season;

  /// Solo tiene sentido cuando [category] es [GarmentCategory.complemento];
  /// `null` en cualquier otra categoría.
  final AccessoryType? accessoryType;

  /// `id` del [TipoPrenda] elegido al crear la prenda (ver `models/tipo_prenda.dart`),
  /// usado por `OutfitRecommendationService.filterGarmentsByTemperature` para
  /// leer su rango de temperatura. `null` en prendas guardadas antes de que
  /// existiera este campo: [category] por sí sola no distingue, p.ej., una
  /// "Camiseta" de una "Camisa/Blusa" (ambas son [GarmentCategory.camiseta]
  /// pero con rangos de temperatura distintos).
  final String? tipoPrendaId;

  final bool isFavorite;
  final bool isArchived;
  final DateTime createdAt;

  Garment({
    required this.id,
    required this.imagePath,
    required this.category,
    required this.color,
    required this.style,
    this.season = GarmentSeason.todoElAno,
    this.accessoryType,
    this.tipoPrendaId,
    this.isFavorite = false,
    this.isArchived = false,
    required this.createdAt,
  });

  Garment copyWith({
    String? id,
    String? imagePath,
    GarmentCategory? category,
    String? color,
    GarmentStyle? style,
    GarmentSeason? season,
    AccessoryType? accessoryType,
    String? tipoPrendaId,
    bool? isFavorite,
    bool? isArchived,
    DateTime? createdAt,
  }) {
    return Garment(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      category: category ?? this.category,
      color: color ?? this.color,
      style: style ?? this.style,
      season: season ?? this.season,
      accessoryType: accessoryType ?? this.accessoryType,
      tipoPrendaId: tipoPrendaId ?? this.tipoPrendaId,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'category': category.name,
      'color': color,
      'style': style.name,
      'season': season.name,
      'accessoryType': accessoryType?.name,
      'tipoPrendaId': tipoPrendaId,
      'isFavorite': isFavorite,
      'isArchived': isArchived,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Garment.fromJson(Map<String, dynamic> json) {
    return Garment(
      id: json['id'] as String,
      imagePath: json['imagePath'] as String,
      category: GarmentCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => GarmentCategory.camiseta,
      ),
      color: json['color'] as String,
      style: GarmentStyle.values.firstWhere(
        (s) => s.name == json['style'],
        orElse: () => GarmentStyle.casual,
      ),
      season: _seasonFromJson(json['season'] as String?),
      accessoryType: _accessoryTypeFromJson(json['accessoryType'] as String?),
      tipoPrendaId: json['tipoPrendaId'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      isArchived: json['isArchived'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// Lee el tipo de complemento persistido. A diferencia de [_seasonFromJson],
/// un valor ausente o no reconocido se degrada a `null` (no a un tipo por
/// defecto): la prenda simplemente no tiene tipo de complemento, en vez de
/// asignarle uno inventado.
AccessoryType? _accessoryTypeFromJson(String? raw) {
  if (raw == null) return null;
  for (final type in AccessoryType.values) {
    if (type.name == raw) return type;
  }
  return null;
}

/// Lee la temporada persistida, traduciendo los nombres del enum anterior.
///
/// `entretiempo` cubría primavera y otoño a la vez, así que no hay forma de
/// repartirlo sin inventarse el dato: se degrada a [GarmentSeason.todoElAno],
/// que es el valor que nunca provoca que la prenda se archive por estar fuera
/// de temporada. Sin esta traducción, el `orElse` mandaría además cualquier
/// nombre desconocido al mismo sitio en silencio.
GarmentSeason _seasonFromJson(String? raw) {
  switch (raw) {
    case 'entretiempo':
    case 'todas':
      return GarmentSeason.todoElAno;
  }
  return GarmentSeason.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => GarmentSeason.todoElAno,
  );
}
