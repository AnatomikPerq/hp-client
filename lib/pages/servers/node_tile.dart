import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/country_flag.dart';
import 'package:onexray/pages/shared/widgets/name_emoji.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';

/// One server in a list: icon, name, protocol tags, latency and a menu.
///
/// Home and Servers share it. Tapping the row is the selection itself; the
/// running entry is outlined in the connected color, a chosen one in primary.
class ServerNodeTile extends StatelessWidget {
  const ServerNodeTile({
    super.key,
    required this.title,
    this.emoji,
    this.countryCode,
    this.protocol = '',
    this.detail,
    this.delay = PingDelayConstants.unknown,
    this.running = false,
    this.chosen = false,
    this.enabled = true,
    this.busy = false,
    this.favorite = false,
    this.note,
    this.onTap,
    this.trailing,
  });

  final String title;

  /// The first emoji of the server name; [countryCode] is the fallback.
  final NameEmoji? emoji;
  final String? countryCode;

  /// `VLESS | XHTTP | REALITY` as the catalog labels it.
  final String protocol;
  final String? detail;
  final int delay;
  final bool running;
  final bool chosen;
  final bool enabled;
  final bool busy;
  final bool favorite;
  final String? note;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final highlighted = running || chosen;
    final accent = running ? palette.running : palette.primary;
    final radius = BorderRadius.circular(AppRadii.card);
    return Semantics(
      selected: highlighted,
      child: Material(
        color: highlighted
            ? Color.lerp(palette.card, accent, .07)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: highlighted
                ? accent.withValues(alpha: .6)
                : Colors.transparent,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: palette.surfaceHover,
          child: Opacity(
            opacity: enabled ? 1 : .6,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 2, 7),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 26,
                      child: busy
                          ? const Center(child: ButtonProgressIndicator())
                          : NameIcon(
                              emoji: emoji,
                              countryCode: countryCode,
                              size: 26,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _text(context, palette)),
                    const SizedBox(width: 8),
                    NodeLatency(delay: delay),
                    if (trailing != null)
                      trailing!
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _text(BuildContext context, AppPalette palette) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.nodeTitle.copyWith(
                color: palette.foreground,
              ),
            ),
          ),
          if (favorite) ...[
            const SizedBox(width: 5),
            Icon(LucideIcons.star600, size: 13, color: palette.restarting),
          ],
        ],
      ),
      if (protocol.isNotEmpty || (detail?.isNotEmpty ?? false)) ...[
        const SizedBox(height: 3),
        ProtocolTags(protocol: protocol, detail: detail),
      ],
      if (note != null) ...[
        const SizedBox(height: 3),
        Text(
          note!,
          style: AppTypography.metadata.copyWith(
            color: palette.mutedForeground,
          ),
        ),
      ],
    ],
  );
}

/// `VLESS · XHTTP · REALITY · Netherlands`, each part in its own color.
class ProtocolTags extends StatelessWidget {
  const ProtocolTags({super.key, required this.protocol, this.detail});

  final String protocol;
  final String? detail;

  static Color color(AppPalette palette, String tag, int index) {
    final value = tag.toUpperCase();
    if (index == 0) {
      return switch (value) {
        'VLESS' => palette.chart1,
        'VMESS' => palette.chart5,
        'TROJAN' => palette.chart3,
        'SHADOWSOCKS' || 'SS' => palette.chart4,
        'HYSTERIA' || 'HYSTERIA2' || 'HY2' || 'TUIC' => palette.restarting,
        'MINEWIRE' => palette.running,
        'WIREGUARD' || 'AMNEZIAWG' => palette.chart5,
        _ => palette.mutedStrong,
      };
    }
    return switch (value) {
      'REALITY' => palette.running,
      'TLS' || 'XTLS' => palette.chart5,
      _ => palette.mutedForeground,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final tags = protocol
        .split('|')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    final separator = TextSpan(
      text: ' · ',
      style: TextStyle(color: palette.mutedForeground),
    );
    final spans = <InlineSpan>[];
    for (final (index, tag) in tags.indexed) {
      if (spans.isNotEmpty) spans.add(separator);
      spans.add(
        TextSpan(
          text: tag,
          style: TextStyle(color: color(palette, tag, index)),
        ),
      );
    }
    final extra = detail;
    if (extra != null && extra.isNotEmpty) {
      if (spans.isNotEmpty) spans.add(separator);
      spans.add(
        TextSpan(
          text: extra,
          style: AppTypography.groupMeta.copyWith(
            color: palette.mutedForeground,
          ),
        ),
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.nodeTag,
    );
  }
}

/// The last probe: a colored dot and milliseconds, or "no response".
class NodeLatency extends StatelessWidget {
  const NodeLatency({super.key, required this.delay});

  final int delay;

  @override
  Widget build(BuildContext context) {
    if (delay == PingDelayConstants.unknown) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    if (!PingDelayConstants.isSuccessful(delay)) {
      return Text(
        l.livePingFailed,
        style: AppTypography.nodePing.copyWith(color: palette.mutedForeground),
      );
    }
    final color = ColorManager.nodeLatency(context, delay);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          l.livePingResult(delay),
          textDirection: TextDirection.ltr,
          style: AppTypography.nodePing.copyWith(color: color),
        ),
      ],
    );
  }
}
