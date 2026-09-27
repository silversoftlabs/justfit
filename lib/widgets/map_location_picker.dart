import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/app_localizations.dart';
import '../services/place_search_service.dart';
import '../services/weather_service.dart';
import '../theme/app_palette.dart';
import '../theme/ios_design.dart';

/// Pantalla a pantalla completa para elegir la ubicación del tiempo sobre un
/// mapa interactivo, sin escribir nada y **sin pedir permisos de GPS**: el
/// punto sale siempre del centro de la cámara, nunca de la posición del
/// dispositivo.
///
/// El mapa usa las teselas estándar de OpenStreetMap
/// (`tile.openstreetmap.org`) — sin clave de API y libres para uso comercial —
/// y les aplica un filtro de inversión ([darkModeTileBuilder] de `flutter_map`)
/// para que casen con el tema oscuro de la app. Los basemaps oscuros de CARTO
/// (`basemaps.cartocdn.com/.../dark_all`) ya no valen: desde 2024 marcan cada
/// tesela con "API KEY REQUIRED" si la petición no lleva clave. Se respeta la
/// política de uso de OSM: `userAgentPackageName` propio en las peticiones y la
/// atribución "© OpenStreetMap" siempre visible (esquina inferior).
///
/// UX: el mapa se arrastra por debajo de un **pin fijo en el centro**; tocar un
/// punto acerca el mapa a ese punto (el pin "se mueve" a donde tocas). Mientras
/// el mapa se mueve, la tarjeta inferior invita a ajustar el punto; al parar,
/// una geocodificación inversa con rebote (`PlaceSearchService.reverseGeocode`)
/// muestra el nombre de la localidad/provincia bajo el pin — nunca las
/// coordenadas numéricas.
///
/// Al confirmar se toman las coordenadas del centro y se resuelven a un
/// [PlaceResult]:
///  1. `PlaceSearchService.reverseGeocode` (municipio local más cercano o la
///     localidad más próxima según WeatherAPI) — conserva las coordenadas
///     exactas elegidas, solo toma prestado el nombre.
///  2. Si nadie reconoce el punto (mar, zona sin cobertura, sin conexión), un
///     [PlaceResult] con las propias coordenadas como etiqueta.
///
/// En ambos casos, quien recibe el [PlaceResult] (`LocationProvider.setPlace`)
/// llama a `WeatherService.fetchAt` directamente con esa lat/lon, sin pasar por
/// la geocodificación de texto del buscador.
class MapLocationPicker extends StatefulWidget {
  const MapLocationPicker({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.tileProvider,
  });

  /// Centro inicial del mapa. Si es `null` se usa la ciudad por defecto de
  /// `WeatherService` (Madrid). Normalmente son las coordenadas de la ubicación
  /// que el usuario ya tiene configurada.
  final double? initialLatitude;
  final double? initialLongitude;

  /// Solo para tests: proveedor de teselas alternativo (evita tocar la red).
  /// En producción se deja `null` y se usa `NetworkTileProvider` sobre OSM.
  final TileProvider? tileProvider;

  /// Abre el selector como una ruta a pantalla completa y devuelve el
  /// [PlaceResult] elegido, o `null` si el usuario vuelve atrás sin confirmar.
  static Future<PlaceResult?> show(
    BuildContext context, {
    double? initialLatitude,
    double? initialLongitude,
  }) {
    return Navigator.of(context).push<PlaceResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MapLocationPicker(
          initialLatitude: initialLatitude,
          initialLongitude: initialLongitude,
        ),
      ),
    );
  }

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

/// El selector va siempre en oscuro (para casar con las teselas `dark_all`),
/// independientemente del modo del sistema. Estos tokens replican la superficie
/// "neutral-900" de la app y su acento verde salvia.
const _chromeSurface = Color(0xFF171717); // AppBar — neutral-900
const _cardSurface = Color(0xFF1E1E1E); // tarjeta flotante — modal oscuro
const _cardBorder = Color(0xFF333333);
const _onDark = Color(0xFFF9F8F6);
const _onDarkMuted = Color(0xFFA8A49E);
const _pinColor = Color(0xFFFF5A5F);

class _MapLocationPickerState extends State<MapLocationPicker> {
  static const _initialZoom = 11.0;
  static const _minZoom = 3.0;
  static const _maxZoom = 18.0;

  /// Espera tras el último movimiento del mapa antes de resolver el nombre del
  /// punto: suficiente para no lanzar una petición por cada frame de arrastre.
  static const _resolveDebounce = Duration(milliseconds: 500);

  final _mapController = MapController();

  late LatLng _center = LatLng(
    widget.initialLatitude ?? WeatherService.defaultLatitude,
    widget.initialLongitude ?? WeatherService.defaultLongitude,
  );

  bool _resolving = false;

  /// El mapa se está arrastrando/asentando ahora mismo: la tarjeta enseña la
  /// pista de ajuste en vez de un nombre a medio resolver.
  bool _moving = false;

  /// Hay una geocodificación inversa pendiente (rebote o petición en vuelo).
  bool _pendingName = false;

  /// Nombre de la localidad/provincia bajo el pin, ya resuelto. `null` si aún
  /// no se sabe o si nadie reconoce el punto.
  String? _placeName;

  /// Descarta respuestas de geocodificación que llegan tarde (el usuario ya
  /// movió el mapa a otro sitio).
  int _resolveSeq = 0;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Resuelve el nombre del punto inicial sin esperar a que el usuario toque
    // nada.
    _pendingName = true;
    _scheduleResolveName();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    // El centro de la cámara es lo que apunta el pin fijo. Se guarda en cada
    // cambio (arrastre, zoom o `move` programático) para tenerlo listo al
    // confirmar, sin recalcular nada en ese momento.
    setState(() {
      _center = camera.center;
      if (hasGesture) {
        _moving = true;
        _placeName = null;
      }
    });
    _scheduleResolveName();
  }

  void _onTap(TapPosition _, LatLng point) {
    // Tocar un punto lo lleva al centro (bajo el pin), conservando el zoom.
    _mapController.move(point, _mapController.camera.zoom);
  }

  /// (Re)programa la geocodificación inversa del centro actual tras
  /// [_resolveDebounce] sin más movimiento.
  void _scheduleResolveName() {
    _debounce?.cancel();
    _pendingName = true;
    _debounce = Timer(_resolveDebounce, _resolvePlaceName);
  }

  Future<void> _resolvePlaceName() async {
    final seq = ++_resolveSeq;
    final point = _center;

    PlaceResult? resolved;
    try {
      resolved = await PlaceSearchService.reverseGeocode(
        point.latitude,
        point.longitude,
      );
    } catch (_) {
      resolved = null;
    }

    // El usuario movió el mapa mientras resolvíamos: esta respuesta ya no vale.
    if (!mounted || seq != _resolveSeq) return;
    setState(() {
      _moving = false;
      _pendingName = false;
      _placeName = resolved?.displayName;
    });
  }

  Future<void> _confirm() async {
    if (_resolving) return;
    setState(() => _resolving = true);

    final point = _center;
    // Etiqueta de respaldo (coordenadas) resuelta ANTES del await, para no
    // usar el `BuildContext` tras el hueco asíncrono.
    final coordsLabel = AppLocalizations.of(context).t('map_picked_coords', {
      'lat': point.latitude.toStringAsFixed(4),
      'lon': point.longitude.toStringAsFixed(4),
    });

    PlaceResult? resolved;
    try {
      resolved = await PlaceSearchService.reverseGeocode(
        point.latitude,
        point.longitude,
      );
    } catch (_) {
      resolved = null;
    }

    final place = resolved ??
        PlaceResult(
          name: coordsLabel,
          displayName: coordsLabel,
          latitude: point.latitude,
          longitude: point.longitude,
        );

    if (!mounted) return;
    Navigator.of(context).pop(place);
  }

  /// Texto de la tarjeta inferior: nunca coordenadas. Mientras el mapa se mueve
  /// (o aún no se sabe el nombre), una pista de ajuste; si se resolvió un
  /// nombre, ese nombre; si nadie reconoce el punto, un aviso neutro.
  String _cardText(AppLocalizations t) {
    if (_moving) return t.t('map_picker_adjust');
    final name = _placeName;
    if (name != null && name.isNotEmpty) return name;
    if (_pendingName) return t.t('map_picker_adjust');
    return t.t('map_picker_unknown');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final showingName = !_moving &&
        !_pendingName &&
        (_placeName?.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: _chromeSurface,
      appBar: AppBar(
        backgroundColor: _chromeSurface,
        foregroundColor: _onDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(t.t('map_picker_title')),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _initialZoom,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              onPositionChanged: _onPositionChanged,
              onTap: _onTap,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                // Teselas estándar de OpenStreetMap (sin clave de API, libres
                // para uso comercial). `darkModeTileBuilder` les aplica una
                // inversión de color para que casen con el tema oscuro sin
                // depender de un basemap oscuro de pago.
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                // Requisito de la política de uso de OSM: identificar la app.
                userAgentPackageName: 'com.gamusinlab.justfit',
                tileProvider: widget.tileProvider ?? NetworkTileProvider(),
                tileBuilder: darkModeTileBuilder,
                maxNativeZoom: 19,
              ),
              // Atribución obligatoria de OpenStreetMap, siempre visible.
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4, right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: ShapeDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    '© OpenStreetMap',
                    style: TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),

          // Pin fijo en el centro: el mapa se mueve por debajo. Se desplaza
          // media altura hacia arriba para que la punta caiga en el centro
          // exacto. `IgnorePointer` para no robarle los gestos al mapa.
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Icon(
                  Icons.location_on,
                  size: 44,
                  color: _pinColor,
                  shadows: const [
                    Shadow(blurRadius: 6, color: Colors.black87),
                  ],
                ),
              ),
            ),
          ),

          // Nombre de la localidad (o pista de ajuste) + botón de confirmación,
          // en una tarjeta oscura flotante.
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 16),
                    decoration: ShapeDecoration(
                      color: _cardSurface,
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(color: _cardBorder),
                      ),
                      shadows: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                          spreadRadius: -8,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          showingName
                              ? Icons.place_outlined
                              : Icons.open_with_rounded,
                          size: 20,
                          color: _onDarkMuted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: Text(
                              _cardText(t),
                              key: ValueKey(_cardText(t)),
                              style: TextStyle(
                                fontSize: showingName ? 15 : 13.5,
                                fontWeight: showingName
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color:
                                    showingName ? _onDark : _onDarkMuted,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _resolving ? null : _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.5),
                        disabledForegroundColor:
                            Colors.white.withValues(alpha: 0.7),
                        shape: squircle(16),
                      ),
                      icon: _resolving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(t.t('map_picker_confirm')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
