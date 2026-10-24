import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/diagnostics/report.dart';
import 'package:onexray/service/diagnostics/text.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

enum ReportTone { good, warning, bad, neutral }

ReportTone toneOf(String status) => switch (status) {
  ReportStatus.ok => ReportTone.good,
  ReportStatus.geo ||
  ReportStatus.slow ||
  ReportStatus.dnsOnly ||
  ReportStatus.alert ||
  ReportStatus.partial => ReportTone.warning,
  ReportStatus.skipped || '' => ReportTone.neutral,
  _ => ReportTone.bad,
};

Color toneColor(AppPalette palette, ReportTone tone) => switch (tone) {
  ReportTone.good => palette.running,
  ReportTone.warning => palette.restarting,
  ReportTone.bad => palette.destructive,
  ReportTone.neutral => palette.mutedForeground,
};

Color toneSurface(AppPalette palette, ReportTone tone) => switch (tone) {
  ReportTone.good => palette.runningSurface,
  ReportTone.warning => palette.warningSurface,
  ReportTone.bad => palette.destructiveSurface,
  ReportTone.neutral => palette.muted,
};

/// A probe or verdict status as a small colored label.
class ReportStatusChip extends StatelessWidget {
  final String status;
  final String? label;

  const ReportStatusChip(this.status, {super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final tone = toneOf(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: toneSurface(palette, tone),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label ?? ReportText.status(l, status),
        style: AppTypography.badge.copyWith(color: toneColor(palette, tone)),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
      ),
    );
  }
}

/// A collapsible report section: the header carries the section's one-line
/// summary, the body its rows.
class ReportSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String summary;
  final ReportTone tone;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const ReportSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.tone,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: mobile ? 13 : 16,
                  vertical: mobile ? 12 : 14,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: toneColor(palette, tone)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppTypography.settingsRow.copyWith(
                              color: palette.foreground,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            summary,
                            style: AppTypography.settingsHint.copyWith(
                              color: palette.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 18,
                        color: palette.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded && children.isNotEmpty) ...[
            Divider(height: 1, color: palette.border),
            ...children,
          ],
        ],
      ),
    );
  }
}

/// One checked thing: name, optional detail line, status.
class ReportRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String status;
  final String? statusLabel;

  const ReportRow({
    super.key,
    required this.title,
    required this.status,
    this.subtitle,
    this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: mobile ? 13 : 16, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.rowValue.copyWith(
                    color: palette.foreground,
                  ),
                ),
                if (subtitle case final text? when text.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  SelectableText(
                    text,
                    style: AppTypography.settingsHint.copyWith(
                      color: palette.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ReportStatusChip(status, label: statusLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label and its value, for the network section.
class ReportFact extends StatelessWidget {
  final String label;
  final String value;

  const ReportFact(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: mobile ? 13 : 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: mobile ? 110 : 150,
            child: Text(
              label,
              style: AppTypography.settingsHint.copyWith(
                color: palette.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: AppTypography.rowValue.copyWith(color: palette.foreground),
            ),
          ),
        ],
      ),
    );
  }
}
