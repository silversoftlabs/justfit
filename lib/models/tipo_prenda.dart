import 'package:flutter/material.dart';

import 'garment.dart';

/// Las cinco familias en las que se agrupan los tipos de prenda del selector
/// manual (ver [SelectorPrendaWidget] en
/// `widgets/selector_prenda_widget.dart`).
enum GrupoPrenda { superiores, inferiores, calzado, cuerpoEntero, accesorios }

extension GrupoPrendaLabel on GrupoPrenda {
  /// Palabra corta de una sola línea para el segmento del `SegmentedButton`
  /// del selector (ver `widgets/selector_prenda_widget.dart`).
  String get label {
    switch (this) {
      case GrupoPrenda.superiores:
        return 'Superior';
      case GrupoPrenda.inferiores:
        return 'Inferior';
      case GrupoPrenda.calzado:
        return 'Calzado';
      case GrupoPrenda.cuerpoEntero:
        return 'Enteros';
      case GrupoPrenda.accesorios:
        return 'Accesorios';
    }
  }
}

/// Un tipo de prenda concreto y seleccionable (p.ej. "Polo" o "Vestido"),
/// más granular que [GarmentCategory]. [id] es un slug estable en
/// snake_case usado para persistencia/comparación, independiente del texto
/// visible en [nombre].
class TipoPrenda {
  final String id;
  final String nombre;
  final GrupoPrenda grupo;
  final IconData icono;

  /// Rango de temperatura (°C) en el que esta prenda es adecuada, usado por
  /// `OutfitRecommendationService.filterGarmentsByTemperature` para filtrar
  /// el armario según la temperatura actual. Accesorios sin relación con el
  /// clima (cinturones, bolsos, joyería...) usan el rango completo
  /// [-10, 45] para no quedar nunca excluidos por temperatura.
  final double tempMin;
  final double tempMax;

  const TipoPrenda({
    required this.id,
    required this.nombre,
    required this.grupo,
    required this.icono,
    required this.tempMin,
    required this.tempMax,
  });
}

/// Los 30 tipos de prenda del selector manual, organizados en las 5 familias
/// de [GrupoPrenda]. Los iconos son una aproximación con Material Icons: el
/// proyecto no tiene ilustraciones propias por prenda.
const List<TipoPrenda> tiposDePrenda = [
  // Superiores
  TipoPrenda(
    id: 'camiseta',
    nombre: 'Camiseta',
    grupo: GrupoPrenda.superiores,
    icono: Icons.checkroom_outlined,
    tempMin: 20,
    tempMax: 45,
  ),
  TipoPrenda(
    id: 'sudadera',
    nombre: 'Sudadera',
    grupo: GrupoPrenda.superiores,
    icono: Icons.layers_outlined,
    tempMin: 8,
    tempMax: 21,
  ),
  TipoPrenda(
    id: 'jersey_sueter',
    nombre: 'Jersey / Suéter',
    grupo: GrupoPrenda.superiores,
    icono: Icons.dry_cleaning_outlined,
    tempMin: 8,
    tempMax: 21,
  ),
  TipoPrenda(
    id: 'camisa_blusa',
    nombre: 'Camisa / Blusa',
    grupo: GrupoPrenda.superiores,
    icono: Icons.checkroom,
    tempMin: 12,
    tempMax: 28,
  ),
  TipoPrenda(
    id: 'top_crop',
    nombre: 'Top / Crop Top',
    grupo: GrupoPrenda.superiores,
    icono: Icons.crop_outlined,
    tempMin: 20,
    tempMax: 45,
  ),
  TipoPrenda(
    id: 'polo',
    nombre: 'Polo',
    grupo: GrupoPrenda.superiores,
    icono: Icons.sports_outlined,
    tempMin: 15,
    tempMax: 32,
  ),
  TipoPrenda(
    id: 'abrigo_parka',
    nombre: 'Abrigo / Parka',
    grupo: GrupoPrenda.superiores,
    icono: Icons.ac_unit_outlined,
    tempMin: -10,
    tempMax: 12,
  ),
  TipoPrenda(
    id: 'chaqueta_cazadora',
    nombre: 'Chaqueta / Cazadora',
    grupo: GrupoPrenda.superiores,
    icono: Icons.style_outlined,
    tempMin: 5,
    tempMax: 18,
  ),
  TipoPrenda(
    id: 'blazer_americana',
    nombre: 'Blazer / Americana',
    grupo: GrupoPrenda.superiores,
    icono: Icons.business_center_outlined,
    tempMin: 10,
    tempMax: 24,
  ),
  TipoPrenda(
    id: 'chaleco',
    nombre: 'Chaleco',
    grupo: GrupoPrenda.superiores,
    icono: Icons.layers,
    tempMin: 5,
    tempMax: 20,
  ),

  // Inferiores
  TipoPrenda(
    id: 'vaqueros',
    nombre: 'Vaqueros',
    grupo: GrupoPrenda.inferiores,
    icono: Icons.straighten_outlined,
    tempMin: 12,
    tempMax: 28,
  ),
  TipoPrenda(
    id: 'chino_vestir',
    nombre: 'Pantalón Chino / Vestir',
    grupo: GrupoPrenda.inferiores,
    icono: Icons.straighten,
    tempMin: 10,
    tempMax: 26,
  ),
  TipoPrenda(
    id: 'jogger_chandal',
    nombre: 'Jogger / Chándal',
    grupo: GrupoPrenda.inferiores,
    icono: Icons.directions_run_outlined,
    tempMin: 5,
    tempMax: 22,
  ),
  TipoPrenda(
    id: 'shorts_bermudas',
    nombre: 'Shorts / Bermudas',
    grupo: GrupoPrenda.inferiores,
    icono: Icons.directions_walk_outlined,
    tempMin: 20,
    tempMax: 45,
  ),
  TipoPrenda(
    id: 'falda',
    nombre: 'Falda',
    grupo: GrupoPrenda.inferiores,
    icono: Icons.female_outlined,
    tempMin: 18,
    tempMax: 35,
  ),
  TipoPrenda(
    id: 'leggings',
    nombre: 'Leggings',
    grupo: GrupoPrenda.inferiores,
    icono: Icons.accessibility_new_outlined,
    tempMin: 10,
    tempMax: 25,
  ),

  // Calzado. Material Icons no tiene un glifo de zapato genérico, así que se
  // usan aproximaciones (correr, senderismo, playa...) siguiendo el mismo
  // criterio que el resto del catálogo. Los rangos de temperatura cubren
  // cuándo tiene sentido ese calzado: unas sandalias solo con calor, unas
  // botas solo con frío, unas zapatillas casi todo el año.
  TipoPrenda(
    id: 'zapatillas',
    nombre: 'Zapatillas',
    grupo: GrupoPrenda.calzado,
    icono: Icons.directions_run_outlined,
    tempMin: 0,
    tempMax: 45,
  ),
  TipoPrenda(
    id: 'zapatos_formales',
    nombre: 'Zapatos Formales',
    grupo: GrupoPrenda.calzado,
    icono: Icons.work_outline,
    tempMin: 2,
    tempMax: 38,
  ),
  TipoPrenda(
    id: 'botas',
    nombre: 'Botas',
    grupo: GrupoPrenda.calzado,
    icono: Icons.hiking_outlined,
    tempMin: -10,
    tempMax: 16,
  ),
  TipoPrenda(
    id: 'botines',
    nombre: 'Botines',
    grupo: GrupoPrenda.calzado,
    icono: Icons.snowshoeing_outlined,
    tempMin: 0,
    tempMax: 20,
  ),
  TipoPrenda(
    id: 'sandalias',
    nombre: 'Sandalias',
    grupo: GrupoPrenda.calzado,
    icono: Icons.beach_access_outlined,
    tempMin: 20,
    tempMax: 45,
  ),

  // Cuerpo Entero
  TipoPrenda(
    id: 'vestido',
    nombre: 'Vestido',
    grupo: GrupoPrenda.cuerpoEntero,
    icono: Icons.accessibility_new,
    tempMin: 18,
    tempMax: 35,
  ),
  TipoPrenda(
    id: 'mono_peto',
    nombre: 'Mono / Peto',
    grupo: GrupoPrenda.cuerpoEntero,
    icono: Icons.checkroom,
    tempMin: 15,
    tempMax: 30,
  ),
  TipoPrenda(
    id: 'traje_completo',
    nombre: 'Traje Completo',
    grupo: GrupoPrenda.cuerpoEntero,
    icono: Icons.work_outline,
    tempMin: 8,
    tempMax: 22,
  ),

  // Accesorios. Los que no dependen del clima (cinturones, bolsos, joyería,
  // otros) usan el rango completo [-10, 45] para no quedar nunca excluidos
  // por temperatura; gorros/sombreros cubren tanto gorro de invierno como
  // sombrero de sol, así que también usan el rango completo.
  TipoPrenda(
    id: 'gorros_sombreros',
    nombre: 'Gorros y Sombreros',
    grupo: GrupoPrenda.accesorios,
    icono: Icons.face_retouching_natural_outlined,
    tempMin: -10,
    tempMax: 45,
  ),
  TipoPrenda(
    id: 'bufandas_guantes',
    nombre: 'Bufandas y Guantes',
    grupo: GrupoPrenda.accesorios,
    icono: Icons.ac_unit,
    tempMin: -10,
    tempMax: 12,
  ),
  TipoPrenda(
    id: 'cinturones',
    nombre: 'Cinturones',
    grupo: GrupoPrenda.accesorios,
    icono: Icons.horizontal_rule,
    tempMin: -10,
    tempMax: 45,
  ),
  TipoPrenda(
    id: 'bolsos_mochilas',
    nombre: 'Bolsos y Mochilas',
    grupo: GrupoPrenda.accesorios,
    icono: Icons.shopping_bag_outlined,
    tempMin: -10,
    tempMax: 45,
  ),
  TipoPrenda(
    id: 'joyeria_relojes',
    nombre: 'Joyería y Relojes',
    grupo: GrupoPrenda.accesorios,
    icono: Icons.watch_outlined,
    tempMin: -10,
    tempMax: 45,
  ),
  TipoPrenda(
    id: 'otros_accesorios',
    nombre: 'Otros Accesorios',
    grupo: GrupoPrenda.accesorios,
    icono: Icons.diamond_outlined,
    tempMin: -10,
    tempMax: 45,
  ),
];

extension GarmentTipoPrenda on Garment {
  /// El [TipoPrenda] concreto con el que se creó la prenda, o `null` si se
  /// guardó antes de que existiera `tipoPrendaId` o si su id ya no está en el
  /// catálogo [tiposDePrenda]. Lo usan la pantalla de detalle y el badge de
  /// tipo para mostrar el nombre específico ("Sudadera / Jersey") en vez de
  /// la supercategoría.
  TipoPrenda? get tipoPrenda {
    final id = tipoPrendaId;
    if (id == null) return null;
    for (final t in tiposDePrenda) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// Traduce el tipo de prenda elegido al par [GarmentCategory]/[AccessoryType]
/// que espera [Garment]. El modelo de datos existente no se amplía: esta
/// extensión es el único punto donde vive el mapeo 25 → 6.
///
/// No existe una [GarmentCategory] para prendas de cuerpo entero (vestido,
/// mono, traje): se guardan como [GarmentCategory.camiseta], igual que el
/// resto de prendas de una sola pieza en la parte superior (ver
/// `topGarmentCategories`/`GarmentCategoryLayer` en `models/garment.dart`).
/// El grupo [GrupoPrenda.calzado] sí tiene su propia [GarmentCategory.calzado].
extension TipoPrendaMapping on TipoPrenda {
  GarmentCategory get categoria {
    switch (grupo) {
      case GrupoPrenda.superiores:
        switch (id) {
          case 'sudadera':
          case 'jersey_sueter':
            return GarmentCategory.sudadera;
          case 'abrigo_parka':
          case 'chaqueta_cazadora':
          case 'blazer_americana':
          case 'chaleco':
            return GarmentCategory.chaqueta;
          default:
            return GarmentCategory.camiseta;
        }
      case GrupoPrenda.inferiores:
        return GarmentCategory.pantalon;
      case GrupoPrenda.calzado:
        return GarmentCategory.calzado;
      case GrupoPrenda.cuerpoEntero:
        return GarmentCategory.camiseta;
      case GrupoPrenda.accesorios:
        return GarmentCategory.complemento;
    }
  }

  /// Solo relevante cuando [categoria] es [GarmentCategory.complemento];
  /// `null` en cualquier otro caso, y también cuando el tipo de complemento
  /// no tiene un [AccessoryType] equivalente (bufandas/guantes, otros).
  ///
  /// `joyeria_relojes` es un único tipo del catálogo de 25 que cubre tanto
  /// joyería (collares, pulseras) como relojes: al añadir una prenda con
  /// este tipo no hay forma de saber cuál de los tres [AccessoryType]
  /// específicos (`collar`/`reloj`/`pulsera`) es en realidad, así que se usa
  /// `collar` como valor por defecto razonable. Si se quiere que el usuario
  /// pueda registrar cada uno por separado, hace falta dividir esta entrada
  /// del catálogo en tres (fuera del alcance de este cambio, que solo toca
  /// el motor de recomendaciones y la pantalla de Outfit del día).
  AccessoryType? get accessoryType {
    switch (id) {
      case 'gorros_sombreros':
        return AccessoryType.gorra;
      case 'cinturones':
        return AccessoryType.cinturon;
      case 'bolsos_mochilas':
        return AccessoryType.bolso;
      case 'joyeria_relojes':
        return AccessoryType.collar;
      default:
        return null;
    }
  }
}
