import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_enums.dart';
import '../models/garment.dart';
import '../providers/favorite_outfits_provider.dart';
import '../providers/wardrobe_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/category_badge.dart';
import '../widgets/outfit_flat_lay_view.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/shimmer_box.dart';
import 'add_garment_screen.dart';
import 'garment_detail_screen.dart';
import 'profile_sheet.dart';
import '../theme/ios_design.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Clave del FAB "Añadir prenda", para localizarlo en tests sin
  /// confundirlo con el botón homónimo de la tarjeta de estado vacío.
  @visibleForTesting
  static const addGarmentFabKey = ValueKey('add-garment-fab');

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  GarmentSuperCategory? _selectedSuperCategory;

  /// true mientras una [AppSnackBar] está visible: repliega el FAB de
  /// "Añadir ropa" a solo icono para cederle el ancho que la píldora
  /// necesita (ver `AppSnackBar._fabReserve`), y vuelve a `false` cuando la
  /// notificación se cierra (por su duración, por deslizarla o porque otra
  /// la reemplaza), no solo cuando termina su temporizador.
  bool _fabCompact = false;

  /// Evita solapar dos recuperaciones de captura abandonada
  /// ([_recoverAbandonedCaptureIfAny]) cuando `resumed` se dispara varias
  /// veces seguidas.
  bool _recoveringAbandonedCapture = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Al arrancar en frío tras una muerte del proceso, comprobar si quedó una
    // foto de la cámara sin entregar. En cualquier otro arranque
    // `retrieveLostData` viene vacío y es un no-op barato.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_recoverAbandonedCaptureIfAny());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverAbandonedCaptureIfAny());
    }
  }

  /// Red de seguridad para la captura con cámara cuando Android mata el
  /// proceso mientras la cámara está abierta (solo Android; en el resto de
  /// plataformas `retrieveLostData` siempre viene vacío). En ese caso el
  /// proceso reinicia en esta pantalla —`AddGarmentScreen` ya no existe en el
  /// árbol, así que su propia recuperación no puede ejecutarse— y aquí se
  /// reclama la foto y se reabre `AddGarmentScreen` para retomar el análisis
  /// sin que el usuario tenga que volver a hacerla. Si `AddGarmentScreen`
  /// sigue montada (el proceso no llegó a morir), se cede a su recuperación
  /// interna, que además conserva el formulario a medio rellenar.
  Future<void> _recoverAbandonedCaptureIfAny() async {
    if (AddGarmentScreen.isOpen || _recoveringAbandonedCapture) return;
    _recoveringAbandonedCapture = true;
    try {
      final LostDataResponse response = await ImagePicker().retrieveLostData();
      if (response.isEmpty || !mounted) return;
      final file = response.file;
      if (file == null) return;
      await _navigateToAddGarment(recoveredImage: file);
    } catch (e) {
      // `retrieveLostData` puede lanzar si el canal del plugin aún no está
      // listo; no es crítico (el usuario siempre puede volver a "Añadir
      // ropa") así que se ignora en vez de mostrar un aviso.
      debugPrint('[HomeScreen] retrieveLostData falló: $e');
    } finally {
      _recoveringAbandonedCapture = false;
    }
  }

  /// Notificación mostrada más recientemente. Cuando una sustituye a otra,
  /// `AppSnackBar.show` cierra la anterior y su `closed` se completa con la
  /// nueva aún en pantalla: solo el cierre de la vigente puede volver a
  /// expandir el FAB, o el FAB extendido pisaría la píldora.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _activeSnackBar;

  /// Muestra la notificación con el FAB replegado mientras siga visible.
  void _showSnackBarWithCompactFab(
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> Function() show,
  ) {
    setState(() => _fabCompact = true);
    final controller = show();
    _activeSnackBar = controller;
    controller.closed.whenComplete(() {
      if (!mounted || !identical(_activeSnackBar, controller)) return;
      _activeSnackBar = null;
      setState(() => _fabCompact = false);
    });
  }

  void _showDeleteSnackBar(Garment removed) {
    final t = AppLocalizations.of(context);
    _showSnackBarWithCompactFab(
      () => AppSnackBar.show(
        context,
        t.t('home_garment_deleted'),
        type: AppSnackBarType.warning,
        actionLabel: t.t('common_undo'),
        onAction: () => context.read<WardrobeProvider>().addGarment(removed),
      ),
    );
  }

  void _showSavedSnackBar() {
    _showSnackBarWithCompactFab(
      () => AppSnackBar.show(
        context,
        AppLocalizations.of(context).t('home_garment_saved'),
        type: AppSnackBarType.success,
      ),
    );
  }

  Future<void> _navigateToAddGarment({XFile? recoveredImage}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddGarmentScreen(recoveredImage: recoveredImage),
      ),
    );
    if (saved == true && mounted) _showSavedSnackBar();
  }

  String _greeting(AppLocalizations t) {
    final hour = DateTime.now().hour;
    if (hour < 12) return t.t('home_good_morning');
    if (hour < 20) return t.t('home_good_afternoon');
    return t.t('home_good_evening');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final wardrobe = context.watch<WardrobeProvider>();
    final favorites = context.watch<FavoriteOutfitsProvider>();
    final garments = wardrobe.bySuperCategory(_selectedSuperCategory);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // Transparente: deja ver el `AmbientBackdrop` de `MainNavigation`.
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _greeting(t),
                              style: TextStyle(
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              t.t('nav_wardrobe'),
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.6,
                                color: scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const _ProfileAvatar(),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _StatsBar(
                    garments: wardrobe.garments.length,
                    outfits: favorites.favorites.length,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      t.t('home_categories'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 76,
                  // Fundido en el borde derecho: indica que la fila se desplaza
                  // en vez de dejar el último chip cortado en seco.
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => LinearGradient(
                      colors: const [Colors.black, Colors.black, Colors.transparent],
                      stops: [0, 1 - 24 / bounds.width, 1],
                    ).createShader(bounds),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _CategoryChip(
                          icon: Icons.grid_view_rounded,
                          label: t.t('home_all'),
                          selected: _selectedSuperCategory == null,
                          onTap: () => setState(() => _selectedSuperCategory = null),
                        ),
                        for (final category in GarmentSuperCategory.values)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _CategoryChip(
                              icon: CategoryBadge.iconForSuperCategory(category),
                              label: t.superCategory(category),
                              selected: _selectedSuperCategory == category,
                              onTap: () =>
                                  setState(() => _selectedSuperCategory = category),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  // Fundido cruzado entre rejilla, estado vacío y carga (y entre
                  // categorías), en vez de sustituir el contenido de golpe.
                  child: _ContentSwitcher(
                    switchKey: wardrobe.isLoading
                        ? 'loading'
                        : '${garments.isEmpty ? 'empty' : 'grid'}-${_selectedSuperCategory?.name}',
                    child: wardrobe.isLoading
                        ? const _ShimmerGrid()
                        : garments.isEmpty
                            // La tarjeta ocupa todo el alto restante (sin hueco
                            // muerto sobre la barra inferior) y sigue siendo
                            // desplazable si la pantalla es más baja que su contenido.
                            ? CustomScrollView(
                                slivers: [
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: Padding(
                                      // + barra de navegación, que con
                                      // `extendBody` queda encima del cuerpo.
                                      padding: EdgeInsets.fromLTRB(
                                        20,
                                        0,
                                        20,
                                        20 + MediaQuery.paddingOf(context).bottom,
                                      ),
                                      child: _EmptyWardrobeCard(
                                        hasFilter: _selectedSuperCategory != null,
                                        onAdd: _navigateToAddGarment,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : GridView.builder(
                                padding: EdgeInsets.fromLTRB(
                                  kPageMargin,
                                  4,
                                  kPageMargin,
                                  88 + MediaQuery.paddingOf(context).bottom,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.75,
                                ),
                                itemCount: garments.length,
                                itemBuilder: (context, index) {
                                  final garment = garments[index];
                                  return _GarmentCard(
                                    garment: garment,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => GarmentDetailScreen(garment: garment),
                                        ),
                                      );
                                    },
                                    onDelete: () {
                                      HapticFeedback.lightImpact();
                                      final removed = garment;
                                      context.read<WardrobeProvider>().removeGarment(removed.id);
                                      _showDeleteSnackBar(removed);
                                    },
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: _ContentEndFloatFabLocation.of(context),
      // Siempre en el árbol: si se alterna con `null`, el `Scaffold` lo
      // anima con su transición por defecto (crece desde un punto girando).
      // `_FabPresence` lo hace aparecer/desaparecer con la suya, en sincronía
      // con el fundido del contenido — en una categoría vacía la tarjeta ya
      // trae su propio "Añadir prenda".
      floatingActionButton: _FabPresence(
        visible: !wardrobe.isLoading && garments.isNotEmpty,
        child: _AddGarmentFab(
          key: HomeScreen.addGarmentFabKey,
          compact: _fabCompact,
          onPressed: () {
            HapticFeedback.lightImpact();
            _navigateToAddGarment();
          },
        ),
      ),
    );
  }
}

/// Duración común del cambio de contenido y de la entrada/salida del FAB,
/// para que ambos se muevan como una sola transición.
const _kSwitchDuration = Duration(milliseconds: 320);

/// Fundido cruzado del contenido principal con un leve desplazamiento
/// vertical: el que entra sube 12 px mientras aparece.
///
/// Todos los hijos (el actual y los salientes) van envueltos en los mismos
/// widgets —solo cambian sus parámetros— para que un hijo que pasa de
/// actual a saliente conserve su estado (p. ej. el scroll de la rejilla) y
/// no salte a la posición inicial mientras se desvanece. Los salientes no
/// reciben toques ni participan en `Hero` (la rejilla que entra y la que
/// sale comparten los tags `garment-image-*`).
class _ContentSwitcher extends StatelessWidget {
  final String switchKey;
  final Widget child;

  const _ContentSwitcher({required this.switchKey, required this.child});

  static Widget _wrap(Widget child, {required bool active}) => HeroMode(
        enabled: active,
        child: IgnorePointer(ignoring: !active, child: child),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _kSwitchDuration,
      reverseDuration: const Duration(milliseconds: 200),
      switchInCurve: AppCurves.easeOut,
      switchOutCurve: AppCurves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [
          for (final p in previous) _wrap(p, active: false),
          if (current != null) _wrap(current, active: true),
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, 12 * (1 - animation.value)),
            child: child,
          ),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(switchKey), child: child),
    );
  }
}

/// Entrada/salida propia del FAB: fundido, subida de 24 px y escala de 0.9
/// a 1 anclada en la esquina inferior derecha, con el resorte de la app al
/// entrar y una salida más corta y acelerada. Oculto no recibe toques ni
/// aparece en la semántica.
class _FabPresence extends StatefulWidget {
  final bool visible;
  final Widget child;

  const _FabPresence({required this.visible, required this.child});

  @override
  State<_FabPresence> createState() => _FabPresenceState();
}

class _FabPresenceState extends State<_FabPresence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kSwitchDuration,
    reverseDuration: const Duration(milliseconds: 200),
    value: widget.visible ? 1 : 0,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: AppCurves.spring,
    reverseCurve: AppCurves.easeIn,
  );

  @override
  void didUpdateWidget(covariant _FabPresence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      widget.visible ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: ExcludeSemantics(
        excluding: !widget.visible,
        child: FadeTransition(
          opacity: _progress,
          child: AnimatedBuilder(
            animation: _progress,
            builder: (context, child) {
              final t = _progress.value;
              // Terminada la salida, fuera de escena: sigue montado (conserva
              // su estado) pero ni se pinta ni cuenta para layout/búsquedas.
              return Offstage(
                offstage: _controller.isDismissed,
                child: Transform.translate(
                  offset: Offset(0, 24 * (1 - t)),
                  child: Transform.scale(
                    scale: 0.9 + 0.1 * t,
                    alignment: Alignment.bottomRight,
                    child: child,
                  ),
                ),
              );
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// FAB de "Añadir ropa" que se repliega a un cuadrado de solo icono
/// (56×56, igual que un `FloatingActionButton` normal) mientras
/// [compact] es true, y vuelve a su forma extendida con etiqueta al
/// volver a `false` — ver `_HomeScreenState._showDeleteSnackBar` y el
/// artefacto de diseño "wardrobe-toast-pill".
///
/// No usa `FloatingActionButton`/`FloatingActionButton.extended`
/// directamente: Flutter no anima un cambio entre esos dos widgets (no
/// interpolan tamaño entre sí), así que aquí se replica su aspecto a mano
/// (mismo `scheme.primary`, mismo radio 16 del tema).
///
/// El `InkWell` envuelve un `Row` de tamaño natural (`MainAxisSize.min`): la
/// etiqueta simplemente deja de estar en el árbol cuando [compact], y
/// `AnimatedSize` interpola el ancho al aparecer/desaparecer. Así el área
/// pulsable SIEMPRE cubre exactamente el botón visible — antes el estado
/// replegado metía un `Row` a la fuerza en 56px, lo desbordaba y dejaba todo
/// el botón sin respuesta al tacto salvo el pixel exacto del icono.
class _AddGarmentFab extends StatelessWidget {
  final bool compact;
  final VoidCallback onPressed;

  const _AddGarmentFab({super.key, required this.compact, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    return PressableScale(
      onTap: onPressed,
      enableHaptics: false,
      // Cristal teñido de salvia (casi opaco para que el texto `onPrimary`
      // mantenga su contraste) con filo de luz y un halo suave del mismo tono.
      child: GlassCard(
        radius: AppRadius.medium,
        tint: scheme.primary,
        tintAlpha: 0.86,
        edgeColor: Colors.white.withValues(alpha: 0.35),
        shadows: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -6,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        child: AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: AppCurves.spring,
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints.tightFor(height: 56)
                .enforce(const BoxConstraints(minWidth: 56)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 24, color: scheme.onPrimary),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    Text(
                      t.t('home_add_garment_cta'),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: 0.4,
                      ),
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

/// `endFloat` con dos ajustes:
///
/// - Horizontal: alineado con el borde derecho de la columna de contenido
///   ([kMaxContentWidth]) en vez del de la ventana, para que en escritorio
///   quede junto a la notificación (que `AppSnackBar` alinea igual).
/// - Vertical: [overlaidBottom] más arriba, por encima de la barra de
///   navegación de cristal. Con `extendBody` en `MainNavigation`, el alto de
///   esa barra llega a este `Scaffold` solo como `MediaQuery.padding`, que
///   `endFloat` ignora (solo mira `viewPadding` y el teclado): sin esta
///   corrección el FAB quedaba debajo de la barra.
class _ContentEndFloatFabLocation extends FloatingActionButtonLocation {
  final double overlaidBottom;

  const _ContentEndFloatFabLocation({required this.overlaidBottom});

  /// Lo que la barra superpuesta añade a `padding` sobre `viewPadding`.
  factory _ContentEndFloatFabLocation.of(BuildContext context) =>
      _ContentEndFloatFabLocation(
        overlaidBottom: math.max(
          0.0,
          MediaQuery.paddingOf(context).bottom -
              MediaQuery.viewPaddingOf(context).bottom,
        ),
      );

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final base = FloatingActionButtonLocation.endFloat.getOffset(scaffoldGeometry);
    // `endFloat` deja 16 (`kFloatingActionButtonMargin`) al borde; se lleva
    // a `kPageMargin` para alinearlo con la rejilla de prendas.
    return base.translate(
      -contentSideInset(scaffoldGeometry.scaffoldSize.width) -
          (kPageMargin - kFloatingActionButtonMargin),
      -overlaidBottom,
    );
  }

  // Igualdad por valor: se crea una instancia en cada `build`, y `Scaffold`
  // anima el FAB (salida/entrada) cada vez que la ubicación "cambia".
  @override
  bool operator ==(Object other) =>
      other is _ContentEndFloatFabLocation && other.overlaidBottom == overlaidBottom;

  @override
  int get hashCode => overlaidBottom.hashCode;
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onTap: () => ProfileSheet.show(context),
      enableHaptics: false,
      child: GlassCard(
        radius: 22,
        child: SizedBox.square(
          dimension: 44,
          child: Icon(Icons.person_outline, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Resumen del armario: dos cifras con su etiqueta, cada una en su propia
/// tarjeta, en lugar de una frase con separador "|".
class _StatsBar extends StatelessWidget {
  final int garments;
  final int outfits;

  const _StatsBar({required this.garments, required this.outfits});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(child: _StatTile(value: garments, label: t.t('home_stat_garments'))),
        const SizedBox(width: 8),
        Expanded(child: _StatTile(value: outfits, label: t.t('home_stat_outfits'))),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final int value;
  final String label;

  const _StatTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      radius: AppRadius.medium,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: scheme.onSurface,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onTap: onTap,
      haptic: PressHaptic.selection,
      // Ancho fijo: todos los chips miden lo mismo sea cual sea su texto.
      // Sin desenfoque (`blur: false`): son elementos repetidos en una fila
      // desplazable (ver `GlassCard`).
      child: SizedBox(
        width: 96,
        child: GlassCard(
          blur: false,
          radius: 14,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          tint: selected ? scheme.primary : null,
          tintAlpha: selected ? 0.18 : 0.55,
          edgeColor: selected ? scheme.primary : null,
          edgeWidth: selected ? 1.5 : 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  // El texto seleccionado se distingue por peso, no por color:
                  // el salvia claro no llega a AA como texto pequeño en modo claro.
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyWardrobeCard extends StatelessWidget {
  final bool hasFilter;
  final VoidCallback onAdd;

  const _EmptyWardrobeCard({required this.hasFilter, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.12),
              ),
              child: Icon(Icons.checkroom_outlined, size: 48, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              hasFilter
                  ? t.t('home_empty_category_title')
                  : t.t('home_empty_wardrobe_title'),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? t.t('home_empty_category_body')
                  : t.t('home_empty_wardrobe_body'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PressableScale(
              onTap: onAdd,
              haptic: PressHaptic.light,
              // Mismo cristal teñido de salvia que el FAB.
              child: GlassCard(
                blur: false,
                radius: 30,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                tint: scheme.primary,
                tintAlpha: 0.86,
                edgeColor: Colors.white.withValues(alpha: 0.35),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 18, color: scheme.onPrimary),
                    const SizedBox(width: 8),
                    Text(
                      t.t('home_add_garment_cta'),
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerGrid extends StatelessWidget {
  const _ShimmerGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        kPageMargin,
        4,
        kPageMargin,
        88 + MediaQuery.paddingOf(context).bottom,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => const ShimmerGarmentCard(),
    );
  }
}

class _GarmentCard extends StatelessWidget {
  final Garment garment;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _GarmentCard({required this.garment, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    final t = AppLocalizations.of(context);
    return PressableScale(
      onTap: onTap,
      // Sin sombra: bajo un tinte translúcido se vería a través de la
      // tarjeta como un velo oscuro; el filo de luz de `GlassCard` la separa
      // del fondo.
      child: ClipRSuperellipse(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Sin desenfoque: celdas repetidas de una rejilla desplazable
            // (ver `GlassCard`).
            GlassCard(
              blur: false,
              radius: 16,
              padding: const EdgeInsets.all(8),
              child: AutocroppedGarment(
                imagePath: garment.imagePath,
                heroTag: 'garment-image-${garment.id}',
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: CategoryBadge.superCategory(garment.superCategory),
            ),
            Positioned(
              top: 34,
              left: 8,
              child: CategoryBadge.style(garment.style),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  iconSize: 19,
                  splashRadius: 20,
                  onPressed: onDelete,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.superCategory(garment.superCategory),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${garment.color} · ${t.style(garment.style)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
