import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Sistema de diseño estilo iOS (Human Interface Guidelines) de la app:
/// geometría "squircle" (esquinas continuas), cristal esmerilado
/// (`BackdropFilter`), curvas de movimiento naturales y hojas modales.
///
/// Todo lo visual que sea transversal vive aquí para que las pantallas solo
/// compongan tokens y widgets, sin repetir números mágicos.

/// Margen lateral estándar de las pantallas (HIG: 16–20 pt).
const double kPageMargin = 20;

/// Ancho máximo del contenido en pantallas anchas (tablet/escritorio): por
/// encima de él las pantallas se centran en vez de estirarse.
const double kMaxContentWidth = 720;

/// Hueco lateral que queda a cada lado de la columna de contenido
/// ([kMaxContentWidth]) en una pantalla de ancho [screenWidth]; 0 en móvil.
/// Lo usan los elementos flotantes (FAB, notificaciones) para alinearse con
/// la columna en vez de con los bordes de la ventana.
double contentSideInset(double screenWidth) =>
    math.max(0, (screenWidth - kMaxContentWidth) / 2);

/// Radios de esquina estándar.
class AppRadius {
  static const double small = 12;
  static const double medium = 16;
  static const double large = 20;
  static const double sheet = 28;
}

/// Esquinas continuas ("superelipse", como iOS) en vez del arco circular de
/// [RoundedRectangleBorder]: la curvatura entra y sale suavemente en lugar
/// de cambiar de golpe donde termina el borde recto.
OutlinedBorder squircle(double radius, {BorderSide side = BorderSide.none}) {
  return RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(radius),
    side: side,
  );
}

/// Curvas de movimiento. [spring] imita un resorte con velocidad inicial
/// (arranca rápido y se asienta sin rebote) y [easeOut] es la curva por
/// defecto para transiciones cortas.
class AppCurves {
  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeIn = Curves.easeInCubic;
  static const Curve spring = SpringOutCurve();
}

/// Decaimiento exponencial normalizado: pendiente inicial máxima que se
/// amortigua hasta asentarse en 1, sin sobrepasar (una hoja anclada abajo no
/// debe dejar un hueco al pasarse de su posición final).
class SpringOutCurve extends Curve {
  final double stiffness;

  const SpringOutCurve([this.stiffness = 5.5]);

  @override
  double transformInternal(double t) {
    return (1 - math.exp(-stiffness * t)) / (1 - math.exp(-stiffness));
  }
}

/// Tinte de cristal según el tema: mismo color que el fondo, translúcido.
Color glassTint(BuildContext context, {double alpha = 0.72, Color? base}) {
  return (base ?? Theme.of(context).scaffoldBackgroundColor)
      .withValues(alpha: alpha);
}

/// Línea fina de separación de las superficies de cristal.
Color glassHairline(BuildContext context) {
  final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
  return isDark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.black.withValues(alpha: 0.08);
}

/// Superficie de cristal esmerilado: desenfoca lo que hay detrás
/// ([BackdropFilter]) y encima pinta un tinte translúcido.
///
/// Sin [shape] es un rectángulo (barras); con [shape] se recorta a esa forma
/// (hojas modales, tarjetas flotantes). [edge] dibuja una línea fina en el
/// borde superior/inferior de una barra.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final ShapeBorder? shape;
  final double sigma;
  final double tintAlpha;
  final Color? tintBase;
  final AxisDirection? edge;

  const GlassSurface({
    super.key,
    required this.child,
    this.shape,
    this.sigma = 24,
    this.tintAlpha = 0.72,
    this.tintBase,
    this.edge,
  });

  @override
  Widget build(BuildContext context) {
    final tint = glassTint(context, alpha: tintAlpha, base: tintBase);
    final Decoration decoration;
    if (shape != null) {
      decoration = ShapeDecoration(color: tint, shape: shape!);
    } else {
      final line = BorderSide(color: glassHairline(context), width: 0.5);
      decoration = BoxDecoration(
        color: tint,
        border: switch (edge) {
          AxisDirection.up => Border(top: line),
          AxisDirection.down => Border(bottom: line),
          _ => null,
        },
      );
    }
    final filtered = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: DecoratedBox(decoration: decoration, child: child),
    );
    return shape == null
        ? ClipRect(child: filtered)
        : ClipPath(clipper: ShapeBorderClipper(shape: shape!), child: filtered);
  }
}

/// Filo de las tarjetas de cristal: una línea de luz de 1 px, más marcada
/// que [glassHairline], como el borde de un vidrio pulido.
Color glassEdge(BuildContext context) {
  final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
  return isDark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.70);
}

/// Tarjeta de cristal esmerilado: tinte translúcido con un brillo diagonal
/// (más claro arriba a la izquierda), filo de luz y, si [blur], desenfoque
/// de lo que hay detrás.
///
/// [blur] es opcional porque cada [BackdropFilter] cuesta una pasada extra
/// de render: en elementos repetidos (celdas de una rejilla, chips) se omite
/// y, sobre el [AmbientBackdrop] —que ya es un degradado suave—, el
/// resultado es visualmente el mismo.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool blur;
  final double sigma;

  /// Color base del tinte; por defecto `colorScheme.surface`.
  final Color? tint;
  final double tintAlpha;

  /// Color del filo; por defecto [glassEdge].
  final Color? edgeColor;
  final double edgeWidth;
  final List<BoxShadow>? shadows;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = AppRadius.large,
    this.padding,
    this.blur = true,
    this.sigma = 20,
    this.tint,
    this.tintAlpha = 0.55,
    this.edgeColor,
    this.edgeWidth = 1,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final base = tint ?? scheme.surface;
    final shape = squircle(
      radius,
      side: BorderSide(color: edgeColor ?? glassEdge(context), width: edgeWidth),
    );
    final highlight = Colors.white.withValues(alpha: isDark ? 0.07 : 0.35);
    Widget surface = DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(highlight, base.withValues(alpha: tintAlpha)),
            base.withValues(alpha: tintAlpha),
          ],
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (blur) {
      surface = ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: surface,
        ),
      );
    }
    if (shadows == null) return surface;
    return DecoratedBox(
      decoration: ShapeDecoration(shape: squircle(radius), shadows: shadows),
      child: surface,
    );
  }
}

/// Fondo ambiental de las pestañas principales: el color del fondo con dos
/// resplandores muy difusos (salvia y terracota). Da al cristal algo que
/// refractar; sobre un fondo liso, una superficie translúcida no se
/// distingue de una opaca.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.colorScheme.brightness == Brightness.dark;
    Widget glow(Alignment at, Color color, double alpha) => Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: at,
                radius: 0.9,
                colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
              ),
            ),
          ),
        );
    return IgnorePointer(
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: Stack(
          children: [
            glow(const Alignment(-1.1, -0.9), theme.colorScheme.primary, isDark ? 0.16 : 0.22),
            glow(const Alignment(1.2, 0.35), theme.colorScheme.secondary, isDark ? 0.10 : 0.14),
          ],
        ),
      ),
    );
  }
}

/// AppBar de cristal: el título y las acciones flotan sobre un fondo
/// desenfocado. Usar con `Scaffold.extendBodyBehindAppBar: true` para que el
/// contenido se deslice por debajo (ver [glassBodyTopPadding]).
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool? centerTitle;

  const GlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.centerTitle,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: const GlassSurface(
        edge: AxisDirection.down,
        child: SizedBox.expand(),
      ),
    );
  }
}

/// Alto que un cuerpo debe reservar arriba cuando el [Scaffold] usa
/// `extendBodyBehindAppBar` con una [GlassAppBar].
double glassBodyTopPadding(BuildContext context) =>
    MediaQuery.paddingOf(context).top + kToolbarHeight;

/// Superficie de las hojas modales: cristal con esquinas superiores
/// continuas y un tirador. Se combina con [showGlassSheet].
class GlassSheetSurface extends StatelessWidget {
  final Widget child;
  final bool showHandle;

  const GlassSheetSurface({
    super.key,
    required this.child,
    this.showHandle = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      sigma: 30,
      tintAlpha: 0.84,
      tintBase: scheme.surface,
      shape: RoundedSuperellipseBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        side: BorderSide(color: glassHairline(context), width: 0.5),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Padding(
            padding: EdgeInsets.only(top: showHandle ? 12 : 0),
            child: child,
          ),
          if (showHandle)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    decoration: ShapeDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.22),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Hoja modal estilo iOS: cristal, esquinas continuas, entrada con resorte,
/// arrastrar hacia abajo para cerrar (el asentamiento al soltar lo resuelve
/// un resorte físico del propio `BottomSheet`) y fondo atenuado.
///
/// Con [wrap] en `false` el [builder] pinta su propia superficie (p. ej. una
/// hoja que ya usa [GlassSheetSurface] internamente).
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool wrap = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    elevation: 0,
    enableDrag: true,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    sheetAnimationStyle: const AnimationStyle(
      curve: AppCurves.spring,
      reverseCurve: AppCurves.easeIn,
      duration: Duration(milliseconds: 420),
      reverseDuration: Duration(milliseconds: 260),
    ),
    builder: wrap
        ? (sheetContext) => GlassSheetSurface(child: builder(sheetContext))
        : builder,
  );
}

/// Diálogo con entrada de resorte (las esquinas continuas y el fondo salen
/// del `dialogTheme` de la app).
Future<T?> showSoftDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    animationStyle: const AnimationStyle(
      curve: AppCurves.spring,
      reverseCurve: AppCurves.easeIn,
      duration: Duration(milliseconds: 300),
      reverseDuration: Duration(milliseconds: 200),
    ),
    builder: builder,
  );
}
