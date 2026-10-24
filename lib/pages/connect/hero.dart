import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/starfield.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';

enum ConnectionHeroTone { idle, busy, connected, failed }

/// The live connection check shown next to the orb while connected.
class LivePingView {
  final bool running;
  final int? milliseconds;
  final bool failed;

  const LivePingView({
    this.running = false,
    this.milliseconds,
    this.failed = false,
  });

  static const idle = LivePingView();

  @override
  bool operator ==(Object other) =>
      other is LivePingView &&
      other.running == running &&
      other.milliseconds == milliseconds &&
      other.failed == failed;

  @override
  int get hashCode => Object.hash(running, milliseconds, failed);
}

/// The big round connection button with its orbit, over a starfield.
///
/// It mirrors the connection button below it: the text button stays the
/// accessible control, so the orb is excluded from semantics.
///
/// Its motion is finite, like the starfield's: the orb lifts under the
/// pointer and sinks when pressed, a ring runs out to the orbit on a tap and
/// on connect, and the satellite circles only while a connection is pending.
class ConnectionHero extends StatefulWidget {
  const ConnectionHero({
    super.key,
    required this.tone,
    required this.diameter,
    required this.onTap,
    this.livePing = LivePingView.idle,
    this.onLivePing,
  });

  final ConnectionHeroTone tone;
  final double diameter;
  final VoidCallback? onTap;
  final LivePingView livePing;
  final VoidCallback? onLivePing;

  /// Distance from the orb to its orbit.
  static const orbitMargin = 24.0;

  /// Room for the live check on both sides, so the orb stays centered.
  static const _sideSlot = 72.0;

  Color accent(AppPalette palette) => switch (tone) {
    ConnectionHeroTone.connected => palette.running,
    ConnectionHeroTone.failed => palette.destructive,
    _ => palette.primary,
  };

  @override
  State<ConnectionHero> createState() => _ConnectionHeroState();
}

class _ConnectionHeroState extends State<ConnectionHero>
    with SingleTickerProviderStateMixin {
  /// The ring that runs from the orb out to the orbit.
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _hovered = false;
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant ConnectionHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tone == ConnectionHeroTone.connected &&
        oldWidget.tone != ConnectionHeroTone.connected) {
      _startRipple();
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  void _startRipple() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _ripple.forward(from: 0);
  }

  void _tap() {
    _startRipple();
    widget.onTap?.call();
  }

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final color = widget.accent(palette);
    final connected = widget.tone == ConnectionHeroTone.connected;
    final showLivePing = connected && widget.onLivePing != null;
    final outer = widget.diameter + ConnectionHero.orbitMargin * 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: showLivePing ? ConnectionHero._sideSlot : 0),
        ExcludeSemantics(
          child: SizedBox.square(
            dimension: outer,
            child: Stack(
              alignment: Alignment.center,
              children: [
                OrbitRing(
                  diameter: outer,
                  color: color,
                  active: connected,
                  spinning: widget.tone == ConnectionHeroTone.busy,
                ),
                IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: Size.square(outer),
                      painter: _RipplePainter(
                        progress: _ripple,
                        color: color,
                        from: widget.diameter / 2,
                        to: outer / 2,
                      ),
                    ),
                  ),
                ),
                _orb(context, palette, color, connected),
              ],
            ),
          ),
        ),
        SizedBox(
          width: showLivePing ? ConnectionHero._sideSlot : 0,
          child: showLivePing
              ? Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _LivePingButton(
                    view: widget.livePing,
                    color: color,
                    onPressed: widget.onLivePing!,
                  ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _orb(
    BuildContext context,
    AppPalette palette,
    Color color,
    bool connected,
  ) {
    // The light theme is not a mirror of the dark one: a glow barely reads
    // there, so the orb gets a plain shadow and a denser border instead.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onTap != null;
    final pressed = enabled && _pressed;
    final lifted = enabled && _hovered && !pressed;
    final borderAlpha = connected
        ? 1.0
        : lifted
        ? (dark ? 0.6 : 0.8)
        : (dark ? 0.35 : 0.55);
    final glowAlpha =
        (connected ? (dark ? 0.42 : 0.30) : 0.12) + (lifted ? 0.10 : 0);
    final diameter = widget.diameter;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => _press(true) : null,
        onTapUp: enabled ? (_) => _press(false) : null,
        onTapCancel: enabled ? () => _press(false) : null,
        onTap: enabled ? _tap : null,
        child: AnimatedScale(
          scale: pressed
              ? 0.95
              : lifted
              ? 1.04
              : 1.0,
          duration: Duration(milliseconds: pressed ? 90 : 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.card,
              border: Border.all(
                color: color.withValues(alpha: borderAlpha),
                width: 2,
              ),
              boxShadow: [
                if (!dark)
                  BoxShadow(
                    color: palette.foreground.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                BoxShadow(
                  color: color.withValues(alpha: glowAlpha),
                  blurRadius: (connected ? 48 : 24) + (lifted ? 12 : 0),
                  spreadRadius: (connected ? 6 : 1) + (lifted ? 2 : 0),
                ),
              ],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.6, end: 1.0).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutBack,
                      ),
                    ),
                    child: child,
                  ),
                ),
                child: switch (widget.tone) {
                  ConnectionHeroTone.busy => SizedBox.square(
                    key: const ValueKey(ConnectionHeroTone.busy),
                    dimension: diameter * 0.3,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: color,
                    ),
                  ),
                  ConnectionHeroTone.failed => Icon(
                    LucideIcons.circleAlert,
                    key: const ValueKey(ConnectionHeroTone.failed),
                    size: diameter * 0.33,
                    color: color,
                  ),
                  _ => Icon(
                    LucideIcons.power,
                    key: const ValueKey(ConnectionHeroTone.idle),
                    size: diameter * 0.33,
                    color: color,
                  ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring that grows from the orb's edge to the orbit and fades out.
class _RipplePainter extends CustomPainter {
  _RipplePainter({
    required this.progress,
    required this.color,
    required this.from,
    required this.to,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double from;
  final double to;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final eased = Curves.easeOutCubic.transform(t);
    canvas.drawCircle(
      size.center(Offset.zero),
      from + (to - from) * eased,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * (1 - eased) + 0.5
        ..color = color.withValues(alpha: 0.55 * (1 - t)),
    );
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.from != from ||
      oldDelegate.to != to;
}

class _LivePingButton extends StatelessWidget {
  const _LivePingButton({
    required this.view,
    required this.color,
    required this.onPressed,
  });

  final LivePingView view;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final label = view.running
        ? null
        : view.milliseconds != null
        ? l.livePingResult(view.milliseconds!)
        : view.failed
        ? l.livePingFailed
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: l.livePingTitle,
          child: Semantics(
            button: true,
            label: l.livePingTitle,
            child: Material(
              color: palette.card,
              shape: CircleBorder(
                side: BorderSide(color: color.withValues(alpha: 0.45)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: view.running ? null : onPressed,
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: view.running
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: color,
                            ),
                          )
                        : Icon(LucideIcons.activity, size: 20, color: color),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.metadata.copyWith(
              color: view.failed
                  ? palette.destructive
                  : palette.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }
}

/// Starfield behind the connection status, tinted by the brand colors.
class ConnectionStarfield extends StatelessWidget {
  const ConnectionStarfield({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Starfield(
      active: active,
      // Light stars vanish on a light background; there the field is blue.
      idleColor: dark ? const Color(0xFFB4D6F0) : palette.primary,
      activeColor: palette.running,
    );
  }
}
