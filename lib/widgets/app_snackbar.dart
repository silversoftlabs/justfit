import 'dart:async';

import 'package:flutter/material.dart';

enum AppSnackBarType { success, warning, error }

/// SnackBar flotante y personalizada con icono y color según el tipo de
/// acción, reemplazando el SnackBar plano por defecto de Flutter.
///
/// Diseñada como una píldora compacta de la misma altura que el
/// `FloatingActionButton.extended` de "Añadir ropa" (56dp en Material 3),
/// apoyada en la esquina inferior IZQUIERDA con el mismo margen (`bottom:
/// 16`) que Flutter usa por defecto para el FAB en la derecha
/// (`kFloatingActionButtonMargin`), para que ambas queden alineadas en la
/// misma fila en vez de una encima/detrás de la otra. Ver el artefacto de
/// diseño "wardrobe-toast-pill" (anatomía + comportamiento responsivo).
///
/// El propio [SnackBar] de Material SIEMPRE ocupa el ancho completo entre sus
/// `margin`s (lo decide `SnackBarState.build`, envolviendo `content` en un
/// `Expanded` interno pase lo que pase), así que un `shape`/`backgroundColor`
/// puesto directamente en el `SnackBar` produce una barra ancha, no una
/// píldora que se ciña al contenido. Por eso aquí el `SnackBar` en sí es
/// invisible (fondo transparente, sin elevación) y el fondo/borde/sombra de
/// la píldora los pinta un `Container` propio dentro de `content`, alineado
/// a la izquierda (`Alignment.centerLeft`) y con el ancho fijo que deja
/// libre el FAB — así el hueco vacío a su derecha, dentro del `SnackBar`
/// invisible, nunca intercepta toques: al pasar `margin`,
/// `Dismissible` (el gesto de deslizar para descartar que envuelve el
/// SnackBar) usa `HitTestBehavior.deferToChild` en vez de `opaque`, así que
/// solo responde donde de verdad hay algo pintado.
///
/// [show] devuelve el `ScaffoldFeatureController` de
/// [ScaffoldMessengerState.showSnackBar] para que quien lo llama pueda
/// reaccionar a su cierre (`controller.closed`) — por ejemplo, para volver a
/// expandir un FAB que se replegó mientras la notificación estaba visible
/// (ver `_AddGarmentFab` en `home_screen.dart`).
class AppSnackBar {
  AppSnackBar._();

  /// Ancho reservado a la derecha de la píldora para el FAB de "Añadir ropa"
  /// replegado a solo icono (56 de lado + su propio margen de 16) más un
  /// hueco de separación de 12, para que nunca lleguen a tocarse. Asume que
  /// quien muestra la notificación repliega el FAB mientras esté visible
  /// (ver `_HomeScreenState`); si no lo hace, la píldora igualmente nunca
  /// pisa el FAB porque el FAB extendido cabe en el resto del ancho.
  static const double _fabReserve = 56 + 16 + 12;

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    String message, {
    AppSnackBarType type = AppSnackBarType.success,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (type) {
      AppSnackBarType.success => (
        Icons.check_circle_outline,
        const Color(0xFF3F7A52),
      ),
      AppSnackBarType.warning => (Icons.error_outline, scheme.secondary),
      AppSnackBarType.error => (Icons.highlight_off, scheme.error),
    };
    final pillBackground = scheme.brightness == Brightness.dark
        ? const Color(0xFF221F1D)
        : Colors.white;

    // 16 es el margen izquierdo de la propia píldora (ver `margin` abajo):
    // se resta aquí, no en `_fabReserve`, porque ese margen lo define este
    // mismo método y no el hueco del FAB.
    //
    // Se usa como ancho fijo de la píldora (no solo como límite máximo) para
    // que su borde derecho llegue de forma consistente hasta `_fabReserve`
    // del FAB en vez de ceñirse al contenido y dejar un hueco vacío.
    final maxPillWidth = MediaQuery.sizeOf(context).width - 16 - _fabReserve;
    final pillWidth = maxPillWidth > 0 ? maxPillWidth : null;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    return messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.only(left: 16, bottom: 16, right: 16),
        padding: EdgeInsets.zero,
        duration: duration,
        content: Align(
          alignment: Alignment.centerLeft,
          // Ancho fijo (`pillWidth`) en vez de solo un `maxWidth`: así el
          // fondo de la píldora siempre se expande hasta el hueco disponible
          // junto al FAB, no solo hasta donde llega su contenido. En el caso
          // límite de una pantalla demasiado estrecha (`pillWidth == null`)
          // se cae de vuelta al comportamiento anterior de ceñirse al
          // contenido, para no forzar un ancho negativo/infinito.
          //
          // `_SlideInPill` sustituye el fundido/aparición brusca por defecto
          // de `SnackBar` por un deslizamiento propio desde la izquierda; no
          // toca `duration` ni el `ScaffoldFeatureController` devuelto por
          // `showSnackBar`, así que ni el temporizador de 3s ni el repliegue
          // del FAB en `_HomeScreenState` (atado a `controller.closed`) se
          // ven afectados.
          child: _SlideInPill(
            visibleDuration: duration,
            child: Container(
              height: 56,
              width: pillWidth,
              padding: const EdgeInsets.only(left: 6, right: 4),
              decoration: ShapeDecoration(
                color: pillBackground,
                shape: StadiumBorder(
                  side: BorderSide(color: color.withValues(alpha: 0.35)),
                ),
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                    spreadRadius: -6,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: pillWidth == null
                    ? MainAxisSize.min
                    : MainAxisSize.max,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.12),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 8),
                  // `Expanded`/`Flexible` (según si la píldora tiene ancho
                  // fijo o se ciñe al contenido) para que el mensaje ocupe
                  // el hueco real que quede libre entre el icono y el botón
                  // "Deshacer": sin esto, en pantallas estrechas con acción
                  // presente, el mensaje podía quedarse literalmente en 0px
                  // de ancho (invisible) en vez de solo truncarse con "…".
                  pillWidth == null
                      ? Flexible(
                          child: Text(
                            message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        )
                      : Expanded(
                          child: Text(
                            message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(width: 4),
                    _UndoButton(
                      label: actionLabel,
                      color: color,
                      onPressed: onAction,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Envuelve la píldora en un deslizamiento de entrada desde la izquierda
/// (en vez del fundido/aparición brusca por defecto de [SnackBar]) y, para
/// el caso común de cierre automático por temporizador, en el deslizamiento
/// inverso de salida.
///
/// No hay forma pública de leer la `Animation` interna que [SnackBarState]
/// usa para mostrar/ocultar la barra (no se expone a `content`), así que
/// esto se resuelve con un `AnimationController` propio: entra en cuanto se
/// monta y, si `visibleDuration` deja margen, programa la salida para que
/// termine justo cuando [AppSnackBar.show] la cierra por temporizador — por
/// eso no hace falta tocar `duration` ni `controller.closed` en
/// [AppSnackBar.show] (ver ahí cómo los usa `_HomeScreenState` para el FAB).
/// Un cierre manual (deslizar para descartar, o que otro snackbar la
/// reemplace) sigue desapareciendo con el fundido por defecto de Flutter en
/// vez de este deslizamiento, ya que ese cierre no pasa por aquí.
class _SlideInPill extends StatefulWidget {
  final Duration visibleDuration;
  final Widget child;

  const _SlideInPill({required this.visibleDuration, required this.child});

  @override
  State<_SlideInPill> createState() => _SlideInPillState();
}

class _SlideInPillState extends State<_SlideInPill>
    with SingleTickerProviderStateMixin {
  static const _transitionDuration = Duration(milliseconds: 320);

  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _transitionDuration,
    );
    _offset = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();

    final exitDelay = widget.visibleDuration - _transitionDuration;
    if (exitDelay > Duration.zero) {
      _exitTimer = Timer(exitDelay, () {
        if (mounted) _controller.reverse();
      });
    }
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(position: _offset, child: widget.child);
  }
}

/// Botón de acción ("Deshacer") propio en vez de [SnackBarAction]: el
/// `action` de [SnackBar] se ancla al borde derecho del `SnackBar` completo
/// (todo el ancho entre `margin`s), no justo tras el mensaje — exactamente
/// el desencaje que este rediseño corrige. Como widget aparte para poder
/// darle su propio estado de presión sin tocar el resto de la píldora.
class _UndoButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _UndoButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
