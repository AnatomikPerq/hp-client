import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/service/advanced/platform_policy.dart';

/// TUN / system proxy switch shown under the connection button on desktop.
class RunModeSwitch extends StatelessWidget {
  const RunModeSwitch({
    super.key,
    required this.value,
    required this.proxyPort,
    required this.enabled,
    required this.pending,
    required this.onChanged,
  });

  final DesktopRunMode value;
  final int proxyPort;
  final bool enabled;
  final bool pending;
  final ValueChanged<DesktopRunMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: l.runModeLabel,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: palette.muted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                for (final mode in DesktopRunMode.values)
                  Expanded(
                    child: _Segment(
                      icon: mode == DesktopRunMode.tun
                          ? LucideIcons.network
                          : LucideIcons.globe,
                      label: mode == DesktopRunMode.tun
                          ? l.runModeTun
                          : l.runModeSystemProxy,
                      selected: mode == value,
                      pending: pending && mode != value,
                      onTap: enabled && mode != value
                          ? () => onChanged(mode)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value == DesktopRunMode.tun
              ? l.runModeTunHint
              : l.runModeSystemProxyHint(proxyPort),
          textAlign: TextAlign.center,
          style: AppTypography.supporting.copyWith(
            color: palette.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.pending,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool pending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final foreground = selected
        ? palette.primaryForeground
        : onTap == null
        ? palette.mutedForeground
        : palette.foreground;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? palette.primarySolid : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: ConstrainedBox(
            // Tappable targets stay at least 40pt high.
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (pending)
                    const ButtonProgressIndicator(size: 16)
                  else
                    Icon(icon, size: 16, color: foreground),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.connectCaption.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
