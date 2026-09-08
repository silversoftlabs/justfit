import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tipo de vibración táctil a disparar al soltar el toque.
enum PressHaptic { light, medium, selection }

/// Envoltorio reutilizable para tarjetas y elementos táctiles (no botones):
/// aplica un efecto de "bounce" (escala al presionar) y feedback háptico.
///
/// Los botones nativos de Material (FilledButton, IconButton, etc.) ya
/// tienen su propio feedback de tinta/estado; no envolverlos aquí.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final bool enableHaptics;
  final PressHaptic haptic;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.96,
    this.enableHaptics = true,
    this.haptic = PressHaptic.light,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    if (_pressed != value) setState(() => _pressed = value);
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap == null ? null : _handleTap,
      child: AnimatedScale(
        scale: _pressed ? widget.scaleDown : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
