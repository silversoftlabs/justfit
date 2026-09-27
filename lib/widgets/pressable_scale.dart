import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// Tipo de vibración táctil a disparar al soltar el toque.
enum PressHaptic { light, medium, selection }

/// Envoltorio reutilizable para tarjetas y elementos táctiles (no botones):
/// aplica un efecto de escala al presionar movido por un resorte físico
/// (baja rápido con el dedo y vuelve con un rebote apenas perceptible) y
/// feedback háptico.
///
/// Los botones nativos de Material (FilledButton, IconButton, etc.) ya
/// tienen su propio feedback de tinta/estado y su propio `onPressed`: para
/// darles también la escala, envolverlos con [PressableScale.passive], que
/// solo escucha el puntero (no compite en la arena de gestos) y deja que el
/// botón siga gestionando el toque.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final bool enableHaptics;
  final PressHaptic haptic;
  final bool _passive;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.97,
    this.enableHaptics = true,
    this.haptic = PressHaptic.light,
  }) : _passive = false;

  /// Solo aporta la escala al presionar; el [child] (p. ej. un `FilledButton`)
  /// conserva su propio manejo del toque.
  const PressableScale.passive({
    super.key,
    required this.child,
    this.scaleDown = 0.97,
  })  : onTap = null,
        enableHaptics = false,
        haptic = PressHaptic.light,
        _passive = true;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 700,
    ratio: 0.72,
  );

  /// Escala actual; `unbounded` para permitir el rebote por encima de 1.
  late final AnimationController _scale =
      AnimationController.unbounded(vsync: this, value: 1);

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (widget.onTap == null && !widget._passive) return;
    _scale.animateWith(
      SpringSimulation(
        _spring,
        _scale.value,
        value ? widget.scaleDown : 1.0,
        _scale.velocity,
      ),
    );
  }

  void _handleTap() {
    final onTap = widget.onTap;
    if (onTap == null) return;
    if (widget.enableHaptics) {
      switch (widget.haptic) {
        case PressHaptic.light:
          HapticFeedback.lightImpact();
        case PressHaptic.medium:
          HapticFeedback.mediumImpact();
        case PressHaptic.selection:
          HapticFeedback.selectionClick();
      }
    }
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final scaled = AnimatedBuilder(
      animation: _scale,
      child: widget.child,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
    );
    if (widget._passive) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: scaled,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap == null ? null : _handleTap,
      child: scaled,
    );
  }
}
