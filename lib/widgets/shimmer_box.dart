import 'package:flutter/material.dart';

/// Placeholder de carga con efecto "shimmer" (barrido de brillo), construido
/// a mano con AnimationController + ShaderMask para no añadir dependencias
/// nuevas al proyecto.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  /// Color base del recuadro. Por defecto `scheme.surfaceContainerHighest`
  /// (el gris neutro de Material); se puede sobreescribir para que el
  /// shimmer combine con un lienzo concreto (p.ej. `garmentPhotoBackground`
  /// en `add_garment_screen.dart`) en vez del gris genérico.
  final Color? baseColor;

  /// Color del barrido de brillo. Por defecto blanco a baja opacidad; se
  /// sobreescribe junto con [baseColor] cuando ese blanco quedaría casi
  /// invisible sobre un lienzo ya muy claro.
  final Color? highlightColor;

  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = widget.baseColor ?? scheme.surfaceContainerHighest;
    final highlight = widget.highlightColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.55));

    return ClipRSuperellipse(
      borderRadius: widget.borderRadius,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final dx = _controller.value * 2 - 1;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment(-1.0 + dx, 0),
              end: Alignment(0.0 + dx, 0),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(bounds),
            child: child,
          );
        },
        child: Container(width: widget.width, height: widget.height, color: base),
      ),
    );
  }
}

/// Esqueleto con la misma forma que una tarjeta de prenda de la rejilla.
class ShimmerGarmentCard extends StatelessWidget {
  const ShimmerGarmentCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const ShimmerBox(borderRadius: BorderRadius.all(Radius.circular(16)));
  }
}
