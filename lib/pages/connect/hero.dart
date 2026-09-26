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
class ConnectionHero extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final color = accent(palette);
    final connected = tone == ConnectionHeroTone.connected;
    final showLivePing = connected && onLivePing != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: showLivePing ? _sideSlot : 0),
        ExcludeSemantics(
          child: SizedBox.square(
            dimension: diameter + orbitMargin * 2,
            child: Stack(
              alignment: Alignment.center,
              children: [
                OrbitRing(
                  diameter: diameter + orbitMargin * 2,
                  color: color,
                  active: connected,
                ),
                _orb(context, palette, color, connected),
              ],
            ),
          ),
        ),
        SizedBox(
          width: showLivePing ? _sideSlot : 0,
          child: showLivePing
              ? Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _LivePingButton(
                    view: livePing,
                    color: color,
                    onPressed: onLivePing!,
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
    final borderAlpha = connected ? 1.0 : (dark ? 0.35 : 0.55);
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
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
                color: color.withValues(
                  alpha: connected ? (dark ? 0.42 : 0.30) : 0.12,
                ),
                blurRadius: connected ? 48 : 24,
                spreadRadius: connected ? 6 : 1,
              ),
            ],
          ),
          child: Center(
            child: tone == ConnectionHeroTone.busy
                ? SizedBox.square(
                    dimension: diameter * 0.3,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: color,
                    ),
                  )
                : Icon(
                    tone == ConnectionHeroTone.failed
                        ? LucideIcons.circleAlert
                        : LucideIcons.power,
                    size: diameter * 0.33,
                    color: color,
                  ),
          ),
        ),
      ),
    );
  }
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
