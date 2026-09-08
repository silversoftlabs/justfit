import 'package:flutter/material.dart';

import '../models/tipo_prenda.dart';
import '../theme/app_palette.dart';
import 'pressable_scale.dart';

/// Selector manual de prenda en 2 pasos: un `SegmentedButton` para elegir la
/// familia ([GrupoPrenda] — Superior, Inferior, Calzado, Enteros, Accesorios)
/// y, debajo, un grid de 3 columnas con los tipos de esa familia. Es un widget de contenido puro (sin `Scaffold`/`AppBar`
/// propios), pensado para usarse tanto embebido en una pantalla como dentro
/// de un `showModalBottomSheet`.
class SelectorPrendaWidget extends StatefulWidget {
  final ValueChanged<TipoPrenda> onPrendaSeleccionada;

  /// Prenda ya elegida, si la hay: fija el grupo inicial y resalta su
  /// tarjeta al abrir el selector.
  final TipoPrenda? seleccionInicial;

  const SelectorPrendaWidget({
    super.key,
    required this.onPrendaSeleccionada,
    this.seleccionInicial,
  });

  @override
  State<SelectorPrendaWidget> createState() => _SelectorPrendaWidgetState();
}

class _SelectorPrendaWidgetState extends State<SelectorPrendaWidget> {
  late GrupoPrenda _grupoActivo;
  TipoPrenda? _seleccionActual;

  @override
  void initState() {
    super.initState();
    _seleccionActual = widget.seleccionInicial;
    _grupoActivo = widget.seleccionInicial?.grupo ?? GrupoPrenda.superiores;
  }

  void _elegir(TipoPrenda tipo) {
    setState(() => _seleccionActual = tipo);
    widget.onPrendaSeleccionada(tipo);
  }

  @override
  Widget build(BuildContext context) {
    final prendasDelGrupo =
        tiposDePrenda.where((t) => t.grupo == _grupoActivo).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<GrupoPrenda>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                // Cinco familias (con Calzado): se aprieta el padding y la
                // fuente respecto a las cuatro anteriores para que "Accesorios"
                // (la etiqueta más larga) siga cabiendo en una línea en un
                // móvil estrecho de 360 dp.
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              segments: [
                for (final grupo in GrupoPrenda.values)
                  ButtonSegment(
                    value: grupo,
                    label: Text(
                      grupo.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                  ),
              ],
              selected: {_grupoActivo},
              onSelectionChanged: (selection) {
                setState(() => _grupoActivo = selection.first);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.85,
            ),
            itemCount: prendasDelGrupo.length,
            itemBuilder: (context, index) {
              final tipo = prendasDelGrupo[index];
              return _TipoPrendaCard(
                tipo: tipo,
                activa: _seleccionActual?.id == tipo.id,
                onTap: () => _elegir(tipo),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TipoPrendaCard extends StatelessWidget {
  final TipoPrenda tipo;
  final bool activa;
  final VoidCallback onTap;

  const _TipoPrendaCard({
    required this.tipo,
    required this.activa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final fg = activa ? scheme.primary : palette.strongText;

    return PressableScale(
      onTap: onTap,
      haptic: PressHaptic.selection,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: activa
              ? scheme.primary.withValues(alpha: 0.12)
              : palette.chipBeige,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: activa ? scheme.primary : palette.chipBeigeBorder,
            width: activa ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tipo.icono, size: 26, color: fg),
            const SizedBox(height: 8),
            Text(
              tipo.nombre,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: fg,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
