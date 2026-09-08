/// Un color de referencia del armario: nombre legible, RGB representativo y
/// metadatos para razonar sobre él sin comparar cadenas por ahí sueltas.
///
/// El RGB es el CENTRO del tono, no un color exacto de ninguna prenda: es
/// contra estos centros contra los que [ColorExtractionService] busca el
/// vecino más cercano tras agrupar los píxeles reales de la foto. Ajustar un
/// tono que no convenza es cambiar aquí su [rgb], sin tocar el algoritmo.
class GarmentColorEntry {
  /// Nombre tal y como se muestra y se persiste en `Garment.color`.
  final String name;

  /// Color representativo del tono, como 0xRRGGBB.
  final int rgb;

  /// Neutros: combinan con casi cualquier otra prenda. Lo usa
  /// `VersatilityService` para puntuar y emparejar.
  final bool isNeutral;

  /// Tono base al que pertenece ('Azul marino' y 'Azul celeste' comparten
  /// familia 'Azul'), para agrupar en filtros y estadísticas sin perder el
  /// matiz del nombre completo.
  final String family;

  /// Los acromáticos (blancos, grises, negro) solo compiten entre ellos
  /// cuando el color medido tiene una saturación muy baja; así un gris
  /// ligeramente cálido no acaba etiquetado como 'Camel'.
  final bool isAchromatic;

  const GarmentColorEntry({
    required this.name,
    required this.rgb,
    required this.family,
    this.isNeutral = false,
    this.isAchromatic = false,
  });
}

/// Nombre reservado para prendas estampadas o de varios colores. No tiene un
/// RGB representativo, así que NO participa en la búsqueda por distancia: solo
/// lo asigna el detector de estampados de [ColorExtractionService].
const String multicolorName = 'Multicolor';

/// Paleta de referencia. Incluye los once nombres originales del proyecto
/// ('Negro', 'Blanco', 'Gris', 'Azul', 'Rojo', 'Verde', 'Amarillo', 'Rosa',
/// 'Marrón', 'Beige' y 'Multicolor') para que las prendas ya guardadas sigan
/// resolviendo su color, más los matices que permite distinguir el cálculo
/// local ahora que no depende de que un modelo elija de una lista corta.
const List<GarmentColorEntry> garmentPalette = [
  // --- Acromáticos --------------------------------------------------------
  GarmentColorEntry(
    name: 'Negro',
    rgb: 0x1A1A1A,
    family: 'Negro',
    isNeutral: true,
    isAchromatic: true,
  ),
  GarmentColorEntry(
    name: 'Gris marengo',
    rgb: 0x4A4E54,
    family: 'Gris',
    isNeutral: true,
    isAchromatic: true,
  ),
  GarmentColorEntry(
    name: 'Gris',
    rgb: 0x8A8D91,
    family: 'Gris',
    isNeutral: true,
    isAchromatic: true,
  ),
  GarmentColorEntry(
    name: 'Gris claro',
    rgb: 0xC6C8CB,
    family: 'Gris',
    isNeutral: true,
    isAchromatic: true,
  ),
  GarmentColorEntry(
    name: 'Blanco roto',
    rgb: 0xEFE9DF,
    family: 'Blanco',
    isNeutral: true,
    isAchromatic: true,
  ),
  GarmentColorEntry(
    name: 'Blanco',
    rgb: 0xF8F8F6,
    family: 'Blanco',
    isNeutral: true,
    isAchromatic: true,
  ),

  // --- Azules -------------------------------------------------------------
  GarmentColorEntry(name: 'Azul marino', rgb: 0x1F2A44, family: 'Azul', isNeutral: true),
  GarmentColorEntry(name: 'Azul', rgb: 0x2E5FA3, family: 'Azul'),
  GarmentColorEntry(name: 'Azul vaquero', rgb: 0x4A6FA5, family: 'Azul', isNeutral: true),
  GarmentColorEntry(name: 'Azul celeste', rgb: 0x9CC3E0, family: 'Azul'),

  // --- Verdes -------------------------------------------------------------
  GarmentColorEntry(name: 'Verde oliva', rgb: 0x6B6B3A, family: 'Verde', isNeutral: true),
  GarmentColorEntry(name: 'Verde', rgb: 0x3B7D4F, family: 'Verde'),
  GarmentColorEntry(name: 'Verde menta', rgb: 0xA8D5BA, family: 'Verde'),

  // --- Rojos y rosas ------------------------------------------------------
  GarmentColorEntry(name: 'Rojo', rgb: 0xC0392B, family: 'Rojo'),
  GarmentColorEntry(name: 'Burdeos', rgb: 0x6E2233, family: 'Rojo'),
  GarmentColorEntry(name: 'Rosa', rgb: 0xE79FB5, family: 'Rosa'),
  GarmentColorEntry(name: 'Rosa palo', rgb: 0xE8CFC9, family: 'Rosa'),

  // --- Cálidos ------------------------------------------------------------
  GarmentColorEntry(name: 'Naranja', rgb: 0xE0703A, family: 'Naranja'),
  GarmentColorEntry(name: 'Mostaza', rgb: 0xC9A227, family: 'Amarillo'),
  GarmentColorEntry(name: 'Amarillo', rgb: 0xE9CE4A, family: 'Amarillo'),

  // --- Tierras ------------------------------------------------------------
  GarmentColorEntry(name: 'Marrón', rgb: 0x6B4A32, family: 'Marrón', isNeutral: true),
  GarmentColorEntry(name: 'Camel', rgb: 0xB08A5E, family: 'Marrón', isNeutral: true),
  GarmentColorEntry(name: 'Beige', rgb: 0xD9C7A9, family: 'Beige', isNeutral: true),

  // --- Morados ------------------------------------------------------------
  GarmentColorEntry(name: 'Morado', rgb: 0x7A4B8C, family: 'Morado'),
  GarmentColorEntry(name: 'Lila', rgb: 0xC3AEDC, family: 'Morado'),

  // Sin RGB representativo: se excluye de la búsqueda por distancia (ver
  // [GarmentPalette.matchable]) y solo lo asigna el detector de estampados.
  GarmentColorEntry(name: multicolorName, rgb: 0x9E9E9E, family: multicolorName),
];

/// Consultas sobre [garmentPalette]. Todo lo que en el proyecto necesite
/// razonar sobre un nombre de color debe pasar por aquí en vez de comparar
/// cadenas sueltas, para que ampliar la paleta no rompa nada.
abstract final class GarmentPalette {
  static final Map<String, GarmentColorEntry> _byName = {
    for (final entry in garmentPalette) entry.name: entry,
  };

  /// Entradas candidatas al mapeo por distancia: todas menos 'Multicolor',
  /// que no representa un tono concreto.
  static final List<GarmentColorEntry> matchable =
      garmentPalette.where((entry) => entry.name != multicolorName).toList(growable: false);

  static GarmentColorEntry? entryFor(String name) => _byName[name];

  /// Un color desconocido (por ejemplo, uno guardado por una versión anterior
  /// que ya no esté en la paleta) se trata como NO neutro: es el criterio
  /// conservador, porque marcar de más inflaría la versatilidad de la prenda.
  static bool isNeutral(String name) => _byName[name]?.isNeutral ?? false;

  /// RGB representativo del nombre, para pintar una muestra cuando no se
  /// conserva el color medido (por ejemplo, en prendas ya guardadas).
  static int? rgbFor(String name) => _byName[name]?.rgb;
}

/// Nombres de color en el orden de la paleta, para el selector manual de la
/// pantalla de "Añadir prenda" y para cualquier otro desplegable.
final List<String> garmentColorOptions =
    garmentPalette.map((entry) => entry.name).toList(growable: false);
