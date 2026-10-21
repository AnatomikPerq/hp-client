import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/country_flag.dart';
import 'package:onexray/pages/shared/widgets/name_emoji.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/traffic.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Reads the same active-session sample as traffic; it owns no timer or probes.
class RuntimeObservatoryReadout extends StatelessWidget {
  const RuntimeObservatoryReadout({
    super.key,
    required this.view,
    this.desktop = false,
  });

  final ConnectionView view;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final runtime = view.runtime;
    if (view.phase != ConnectionPhase.connected || runtime == null) {
      return const SizedBox.shrink();
    }
    final paths = runtime.observationPaths;
    if (paths.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final samples = {
      for (final observation
          in view.traffic?.observations ?? const <RuntimePathObservation>[])
        observation.path.tag: observation,
    };
    return Container(
      key: const ValueKey('runtime-observatory'),
      padding: EdgeInsets.symmetric(vertical: desktop ? 18 : 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.runtimeRoutingStatus,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Tooltip(
                message: l.runtimeRoutingHint,
                child: Icon(
                  LucideIcons.circleHelp,
                  size: 17,
                  color: palette.mutedForeground,
                ),
              ),
            ],
          ),
          for (final path in paths)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _path(context, path, samples[path.tag]),
            ),
        ],
      ),
    );
  }

  Widget _path(
    BuildContext context,
    RuntimeObservationPath path,
    RuntimePathObservation? sample,
  ) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final availability = view.metricsAvailable
        ? sample?.availability ?? RuntimePathAvailability.unknown
        : RuntimePathAvailability.unknown;
    final (status, color) = switch (availability) {
      RuntimePathAvailability.unknown => (
        l.runtimeRoutingUnknown,
        palette.mutedStrong,
      ),
      RuntimePathAvailability.available => (
        l.runtimeRoutingAlive,
        palette.runningText,
      ),
      RuntimePathAvailability.failed => (
        l.runtimeRoutingFailed,
        palette.destructive,
      ),
    };
    // Fork: Windows prints emoji flags as letters ("NL"); the entry's first
    // emoji is drawn as an icon and flags leave the text, as in the lists.
    String plain(String name) {
      final split = splitFlagEmoji(name).name;
      return split.isEmpty ? name : split;
    }

    final entry = splitNameEmoji(path.entryName);
    final entryName = entry.name.isEmpty ? path.entryName : entry.name;
    final label = path.finalExitName == null
        ? entryName
        : '$entryName → ${plain(path.finalExitName!)}';
    final delay = availability == RuntimePathAvailability.available
        ? sample?.delayMs
        : null;
    final triedAt = sample?.lastTryTimeMs;
    final date = triedAt == null
        ? '—'
        : DateFormat.yMd(l.localeName)
              .add_Hms()
              .format(DateTime.fromMillisecondsSinceEpoch(triedAt).toLocal());
    return Column(
      key: ValueKey('runtime-path-${path.tag}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (entry.emoji != null) ...[
              NameIcon(emoji: entry.emoji, size: 16),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 8,
          runSpacing: 3,
          children: [
            Text(
              status,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: color),
            ),
            if (delay != null)
              Text('$delay ms', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          l.runtimeRoutingUpdatedAt(date),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: palette.mutedForeground),
        ),
      ],
    );
  }
}
