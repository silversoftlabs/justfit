import 'dart:async';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';

import '../services/place_search_service.dart';

/// Campo de búsqueda de ciudad con autocompletado en tiempo real. Envuelve el
/// widget [Autocomplete] de Flutter (sin dependencias externas) sobre
/// [PlaceSearchService] (API de búsqueda de WeatherAPI), con un pequeño
/// _debounce_ para no llamar a la API en cada tecla.
///
/// Se usa tanto en el onboarding (tema claro fijo) como en Ajustes (tema de la
/// app): al heredar el `Theme` ambiente, el campo y el desplegable se ven bien
/// en ambos sitios. Quien lo usa recibe la [PlaceResult] elegida por
/// [onSelected] (con nombre, etiqueta y coordenadas ya resueltas).
class CityAutocompleteField extends StatefulWidget {
  const CityAutocompleteField({
    super.key,
    required this.onSelected,
    this.initialValue,
    this.decoration,
    this.autofocus = false,
  });

  /// Se invoca cuando el usuario toca una sugerencia de la lista.
  final ValueChanged<PlaceResult> onSelected;

  /// Ciudad ya elegida: solo fija el texto inicial del campo. No dispara
  /// [onSelected].
  final PlaceResult? initialValue;

  /// Decoración del `TextField` interno. Si es `null` se usa una por defecto
  /// con lupa e `hintText` genérico.
  final InputDecoration? decoration;

  final bool autofocus;

  @override
  State<CityAutocompleteField> createState() => _CityAutocompleteFieldState();
}

class _CityAutocompleteFieldState extends State<CityAutocompleteField> {
  Timer? _debounce;
  Completer<List<PlaceResult>>? _pending;

  @override
  void dispose() {
    _debounce?.cancel();
    if (_pending != null && !_pending!.isCompleted) _pending!.complete(const []);
    super.dispose();
  }

  Future<Iterable<PlaceResult>> _optionsBuilder(TextEditingValue value) {
    final query = value.text.trim();
    if (query.length < PlaceSearchService.minQueryLength) {
      return SynchronousFuture(const <PlaceResult>[]);
    }

    // Debounce: cada tecla cancela la búsqueda anterior. `Autocomplete` ya
    // descarta resultados obsoletos si el texto cambia mientras el Future
    // está en vuelo, así que aquí solo hace falta espaciar las llamadas.
    _debounce?.cancel();
    if (_pending != null && !_pending!.isCompleted) _pending!.complete(const []);
    final completer = Completer<List<PlaceResult>>();
    _pending = completer;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await PlaceSearchService.search(query);
      if (!completer.isCompleted) completer.complete(results);
    });
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<PlaceResult>(
      initialValue: widget.initialValue == null
          ? null
          : TextEditingValue(text: widget.initialValue!.displayName),
      displayStringForOption: (place) => place.displayName,
      optionsBuilder: _optionsBuilder,
      onSelected: (place) {
        FocusManager.instance.primaryFocus?.unfocus();
        widget.onSelected(place);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        final base = widget.decoration ??
            const InputDecoration(hintText: 'Escribe tu ciudad…');
        return TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: widget.autofocus,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onFieldSubmitted(),
          decoration: base.copyWith(
            prefixIcon: base.prefixIcon ?? const Icon(Icons.search),
          ),
        );
      },
    );
  }
}
