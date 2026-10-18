import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/tools/traffic_format.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/country_flag.dart';
import 'package:onexray/pages/shared/widgets/name_emoji.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/shared/widgets/page_empty_state.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/connect/run_mode.dart';
import 'package:onexray/pages/connect/hero.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/health.dart';
import 'package:onexray/service/connect/failure.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Home: the connection and the servers in one column.
///
/// Fork layout after tunnel apps like INCY: mode, live speed and session
/// time above the orb, the selected node under it, then quick actions and
/// the current subscription's nodes, where one tap switches the connection.
class ConnectView extends StatelessWidget {
  const ConnectView({
    super.key,
    required this.view,
    this.trafficBuilder,
    required this.hasServers,
    required this.expert,
    required this.raws,
    required this.activeRawId,
    this.pendingChange,
    this.deletingRawIds = const {},
    required this.location,
    this.locationIcon = (emoji: null, code: null),
    this.runningPath,
    this.locationDetail,
    this.locationHealth,
    required this.method,
    this.methodDetail,
    required this.onConnection,
    required this.onAddServers,
    required this.onExpert,
    required this.onServer,
    required this.onMethod,
    required this.onWhy,
    required this.onRawAdd,
    required this.onRawSelect,
    required this.onRawActions,
    this.onPaste,
    this.servers,
    this.runMode,
    this.proxyPort = 0,
    this.onRunMode,
    this.livePing = LivePingView.idle,
    this.onLivePing,
    this.health = ConnectionHealth.none,
    this.activity,
  });
  final ConnectionView view;
  final Widget Function(bool desktop)? trafficBuilder;
  final bool hasServers;
  final bool expert;
  final List<CoreConfigData> raws;
  final int? activeRawId;
  final String? pendingChange;
  final Set<int> deletingRawIds;
  final String location;

  /// Flag beside [location]; null draws none.
  /// The first emoji of the node name, else its country.
  final ({NameEmoji? emoji, String? code}) locationIcon;
  final String? runningPath;
  final String? locationDetail, locationHealth, methodDetail;
  final String method;
  final VoidCallback onConnection,
      onAddServers,
      onServer,
      onMethod,
      onWhy,
      onRawAdd;
  final VoidCallback? onPaste;
  final ValueChanged<bool> onExpert;
  final ValueChanged<CoreConfigData> onRawSelect, onRawActions;

  /// The current subscription's nodes; Home shows them under the actions.
  final Widget? servers;

  /// Desktop only: null hides the TUN / system proxy switch.
  final DesktopRunMode? runMode;
  final int proxyPort;
  final ValueChanged<DesktopRunMode>? onRunMode;

  /// "Check connection" below the orb; null hides it.
  final LivePingView livePing;
  final VoidCallback? onLivePing;

  /// The background check: a connection that stopped carrying traffic
  /// says so instead of "connected".
  final ConnectionHealth health;

  /// Background work (tests, downloads) at the top end of the header.
  final Widget? activity;

  bool get _connectionPending => pendingChange == 'connection';
  bool get _busy => view.busy || _connectionPending;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final empty =
        !hasServers &&
        !expert &&
        activeRawId == null &&
        !view.canDisconnect &&
        !_busy;
    if (empty) {
      return ResponsiveContent(
        child: PageEmptyState(
          title: l.prototypeStartUsingOneXray,
          description: l.prototypeFirstConnectionHint,
          primaryLabel: l.prototypeAddServers,
          onPrimary: onAddServers,
          secondaryLabel: l.prototypeUseCompleteRawJson,
          onSecondary: () => onExpert(true),
        ),
      );
    }
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final horizontal = mobile ? AppSpacing.mobilePage : AppSpacing.page;
    return SingleChildScrollView(
      key: const ValueKey('home-scroll'),
      padding: EdgeInsets.fromLTRB(
        horizontal,
        mobile ? 8 : 14,
        horizontal,
        mobile ? 22 : 32,
      ),
      child: ResponsiveContent(
        desktopMaxWidth: AppLayout.homeMaxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hero(context),
            const SizedBox(height: 10),
            _checks(context),
            const SizedBox(height: 12),
            _actions(context),
            const SizedBox(height: 18),
            if (expert) _raws(context, desktop: !mobile) else ?servers,
            const SizedBox(height: 16),
            _expertSwitch(context),
          ],
        ),
      ),
    );
  }

  /// Mode, live metrics, the orb and what it is connected to.
  Widget _hero(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final connected = view.phase == ConnectionPhase.connected;
    final failed = view.failed && !connected;
    final unreachable =
        connected && health.unreachable && health.appliesTo(view.runtime);
    final presentationPhase = failed ? ConnectionPhase.failed : view.phase;
    final title = unreachable
        ? l.connectionHealthLost
        : switch (presentationPhase) {
            ConnectionPhase.disconnected => l.prototypeDisconnected,
            ConnectionPhase.preparing ||
            ConnectionPhase.connecting => l.prototypeConnecting,
            ConnectionPhase.connected => l.prototypeConnected,
            ConnectionPhase.disconnecting => l.prototypeDisconnecting,
            ConnectionPhase.failed => l.prototypeConnectionFailed,
          };
    final detail = unreachable
        ? health.minewireDown
              ? l.connectionHealthMinewireDetail
              : l.connectionHealthLostDetail
        : switch (presentationPhase) {
            ConnectionPhase.disconnected => l.prototypeReadyToProtectConnection,
            ConnectionPhase.preparing ||
            ConnectionPhase.connecting => l.prototypePreparingSecureConnection,
            ConnectionPhase.connected => runningPath ?? locationDetail,
            ConnectionPhase.disconnecting => l.prototypeFinishingConnection,
            ConnectionPhase.failed => connectionFailureMessage(
              l,
              issue: view.issue,
              error: view.error,
              permission: view.permission,
            ),
          };
    final color = failed || unreachable
        ? palette.destructive
        : connected
        ? palette.runningText
        : _busy
        ? palette.primary
        : palette.mutedStrong;
    // A pending command shows progress at once, even on a live connection.
    final tone = failed
        ? ConnectionHeroTone.failed
        : _busy
        ? ConnectionHeroTone.busy
        : unreachable
        ? ConnectionHeroTone.failed
        : connected
        ? ConnectionHeroTone.connected
        : ConnectionHeroTone.idle;
    final canTap =
        view.phase != ConnectionPhase.disconnecting &&
        (pendingChange == null || view.busy);
    final waitingForPhase = _connectionPending && !view.busy;
    final action = waitingForPhase
        ? l.prototypePleaseWait
        : view.canDisconnect
        ? l.prototypeDisconnect
        : view.phase == ConnectionPhase.disconnecting
        ? l.prototypePleaseWait
        : view.busy
        ? l.prototypeCancel
        : failed
        ? l.prototypeTryAgain
        : l.prototypeConnect;
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final runModeSwitch = runMode == null || onRunMode == null
        ? null
        : RunModeSwitch(
            value: runMode!,
            proxyPort: proxyPort,
            enabled: !_busy && pendingChange == null,
            pending: pendingChange == 'runMode',
            onChanged: onRunMode!,
            compact: true,
          );
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ?runModeSwitch,
                if (activity != null)
                  PositionedDirectional(end: 0, child: activity!),
              ],
            ),
          ),
          const SizedBox(height: 10),
          trafficBuilder?.call(!mobile) ??
              TrafficReadout(view: view, desktop: !mobile),
          const SizedBox(height: 6),
          Center(
            child: Semantics(
              button: true,
              enabled: canTap,
              label: action,
              onTap: canTap ? onConnection : null,
              child: Tooltip(
                message: action,
                excludeFromSemantics: true,
                child: ConnectionHero(
                  key: const ValueKey('home-connection-orb'),
                  tone: tone,
                  diameter: mobile ? 96 : 104,
                  onTap: canTap ? onConnection : null,
                ),
              ),
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.homeStatus.copyWith(color: color),
          ),
          const SizedBox(height: 6),
          if (!expert)
            Center(
              child: InkWell(
                onTap: onServer,
                borderRadius: BorderRadius.circular(AppRadii.card),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (locationIcon.emoji != null ||
                          locationIcon.code != null) ...[
                        NameIcon(
                          emoji: locationIcon.emoji,
                          countryCode: locationIcon.code,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.homeServer.copyWith(
                            color: connected
                                ? palette.runningText
                                : palette.foreground,
                          ),
                        ),
                      ),
                      if (connected && locationHealth != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          locationHealth!,
                          style: AppTypography.nodePing.copyWith(
                            color: palette.mutedForeground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (detail != null && detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                detail,
                textAlign: TextAlign.center,
                maxLines: failed ? 4 : 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.supporting.copyWith(
                  color: failed ? palette.destructive : palette.mutedForeground,
                ),
              ),
            ),
          if (view.issue == 'selectionReset')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l.prototypeNameActive(l.prototypeAutomaticSelection),
                  textAlign: TextAlign.center,
                  style: AppTypography.metadata,
                ),
              ),
            ),
          if (view.failed && !failed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l.prototypeCheckNetwork,
                style: AppTypography.supporting.copyWith(
                  color: palette.destructive,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
    return ClipRRect(
      key: const ValueKey('home-connection-panel'),
      borderRadius: BorderRadius.circular(AppRadii.dialog),
      child: Stack(
        children: [
          Positioned.fill(child: ConnectionStarfield(active: connected)),
          content,
        ],
      ),
    );
  }

  /// "Check connection" on one side, the routing method on the other.
  Widget _checks(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final connected = view.phase == ConnectionPhase.connected;
    final canCheck = connected && onLivePing != null && !livePing.running;
    final result = livePing.running
        ? null
        : livePing.milliseconds != null
        ? '✓ ${l.livePingResult(livePing.milliseconds!)}'
        : livePing.failed
        ? l.livePingFailed
        : null;
    final check = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: canCheck ? onLivePing : null,
          style: TextButton.styleFrom(
            foregroundColor: palette.primary,
            textStyle: AppTypography.homeLink,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(l.homeCheckConnection),
        ),
        if (livePing.running)
          const ButtonProgressIndicator(size: 14)
        else if (result != null)
          Text(
            result,
            style: AppTypography.nodePing.copyWith(
              color: livePing.failed ? palette.destructive : palette.running,
            ),
          ),
      ],
    );
    final routing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: methodDetail ?? l.prototypeTrafficMethod,
          child: Material(
            color: palette.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              side: BorderSide(color: palette.border),
            ),
            child: InkWell(
              key: const ValueKey('home-routing'),
              onTap: _busy ? null : onMethod,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (pendingChange == 'method')
                      const ButtonProgressIndicator(size: 14)
                    else
                      Icon(
                        LucideIcons.shieldCheck,
                        size: 15,
                        color: palette.primary,
                      ),
                    const SizedBox(width: 7),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        method,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.filterChip.copyWith(
                          color: palette.foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      LucideIcons.chevronDown,
                      size: 14,
                      color: palette.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: l.prototypeWhyThisConnection,
          onPressed: onWhy,
          style: IconButton.styleFrom(
            foregroundColor: palette.mutedForeground,
            minimumSize: const Size(34, 34),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(LucideIcons.circleHelp, size: 17),
        ),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: [check, if (!expert) routing],
    );
  }

  /// Add, paste from the clipboard and open every server.
  Widget _actions(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
    );
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('home-add'),
            onPressed: onAddServers,
            style: FilledButton.styleFrom(
              backgroundColor: palette.selectedSurface,
              foregroundColor: palette.primary,
              fixedSize: const Size.fromHeight(42),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: AppTypography.homeAction,
              shape: shape,
              side: BorderSide(color: palette.primary.withValues(alpha: .35)),
            ),
            icon: const Icon(LucideIcons.plus, size: 17),
            label: Text(l.prototypeAdd),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: l.homePasteHint,
            child: OutlinedButton.icon(
              key: const ValueKey('home-paste'),
              onPressed: onPaste,
              style: OutlinedButton.styleFrom(
                backgroundColor: palette.card,
                foregroundColor: palette.foreground,
                fixedSize: const Size.fromHeight(42),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: AppTypography.homeAction,
                shape: shape,
                side: BorderSide(color: palette.border),
              ),
              icon: const Icon(LucideIcons.clipboardPaste, size: 17),
              label: Text(l.homePaste),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const ValueKey('home-all-servers'),
          tooltip: l.homeAllServers,
          onPressed: onServer,
          style: IconButton.styleFrom(
            backgroundColor: palette.card,
            foregroundColor: palette.mutedStrong,
            fixedSize: const Size.square(42),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
              side: BorderSide(color: palette.border),
            ),
          ),
          icon: const Icon(LucideIcons.list, size: 18),
        ),
      ],
    );
  }

  Widget _expertSwitch(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.fileJson, size: 17, color: palette.mutedStrong),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.prototypeExpertMode,
              style: AppTypography.connectCaption.copyWith(
                color: palette.foreground,
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (pendingChange == 'expert') ...[
            const ButtonProgressIndicator(),
            const SizedBox(width: 8),
          ],
          Semantics(
            label: l.prototypeExpertMode,
            child: ShadSwitch(
              value: expert,
              enabled: !_busy && pendingChange == null,
              onChanged: onExpert,
            ),
          ),
        ],
      ),
    );
  }

  Widget _raws(BuildContext context, {bool desktop = false}) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: desktop ? 44 : 40),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Raw JSON',
                  style: desktop
                      ? AppTypography.connectDesktopRawTitle
                      : AppTypography.connectRawTitle,
                ),
              ),
              Text(
                '${raws.length} / 3',
                textDirection: TextDirection.ltr,
                style: AppTypography.connectRawCount.copyWith(
                  color: palette.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        if (view.phase == ConnectionPhase.connected && activeRawId == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l.prototypeOrdinaryConnectionRunning,
              style: AppTypography.supporting.copyWith(
                color: palette.mutedForeground,
              ),
            ),
          ),
        if (raws.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            shape: AppDashedBorder(
              side: BorderSide(color: palette.borderStrong),
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: desktop
                    ? AppLayout.connectDesktopRawEmptyMinHeight
                    : 160,
              ),
              child: Padding(
                padding: EdgeInsets.all(desktop ? 24 : 19),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: desktop
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.filePlus,
                      size: desktop ? 32 : 27,
                      color: palette.mutedStrong,
                    ),
                    const SizedBox(height: 11),
                    Text(
                      l.prototypeNoRawJson,
                      textAlign: TextAlign.center,
                      style: desktop
                          ? AppTypography.connectDesktopRawEmptyTitle
                          : AppTypography.connectRawEmptyTitle,
                    ),
                    const SizedBox(height: 9),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: desktop ? 330 : 270,
                      ),
                      child: Text(
                        l.prototypeAddRawJsonHint,
                        textAlign: TextAlign.center,
                        style:
                            (desktop
                                    ? AppTypography.connectDesktopRawEmptyDetail
                                    : AppTypography.connectRawEmptyDetail)
                                .copyWith(color: palette.mutedForeground),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: onRawAdd,
                      icon: const Icon(LucideIcons.plus, size: 17),
                      label: Text(l.prototypeAddRawJson),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (raws.isNotEmpty)
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final row in raws) ...[
                  if (row != raws.first) const Divider(),
                  _rawRow(context, row, desktop: desktop),
                ],
              ],
            ),
          ),
        if (raws.isNotEmpty && raws.length < 3)
          Padding(
            padding: const EdgeInsets.only(top: 11),
            child: OutlinedButton.icon(
              onPressed: onRawAdd,
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.primary,
                shape: AppDashedBorder(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
              ),
              icon: const Icon(LucideIcons.plus, size: 17),
              label: Text(l.prototypeAddRawJson),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.info, size: 16, color: palette.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.prototypeRawRuntimeOverrideNotice,
                style: AppTypography.connectRawNotice.copyWith(
                  color: palette.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rawRow(
    BuildContext context,
    CoreConfigData row, {
    bool desktop = false,
  }) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final active = activeRawId == row.id;
    return ColoredBox(
      color: active
          ? Color.lerp(palette.card, palette.selectedSurface, .6)!
          : palette.card,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: desktop ? 66 : 62),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap:
                    _busy ||
                        pendingChange != null ||
                        deletingRawIds.contains(row.id)
                    ? null
                    : () => onRawSelect(row),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: desktop ? 13 : 11,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      if (pendingChange == 'raw:${row.id}')
                        const ButtonProgressIndicator()
                      else
                        Icon(
                          LucideIcons.fileJson,
                          size: 21,
                          color: palette.primary,
                        ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.connectRawRowTitle,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              active
                                  ? l.prototypeActiveConfiguration
                                  : l.prototypeCompleteXrayConfiguration,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.connectRawRowDetail.copyWith(
                                color: palette.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 11),
                      Icon(
                        active ? LucideIcons.check : LucideIcons.circle,
                        size: active ? 19 : 18,
                        color: active
                            ? palette.primary
                            : palette.mutedForeground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: desktop ? 46 : 42,
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(color: palette.border),
                    ),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: '${l.prototypeMoreActions}: ${row.name}',
                    onPressed: deletingRawIds.contains(row.id)
                        ? null
                        : () => onRawActions(row),
                    icon: deletingRawIds.contains(row.id)
                        ? const ButtonProgressIndicator()
                        : const Icon(LucideIcons.ellipsis, size: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live upload and download speed around the session time, with the
/// session's totals under them. Read-only: nothing here opens a page.
class TrafficReadout extends StatelessWidget {
  const TrafficReadout({super.key, required this.view, this.desktop = false});
  final ConnectionView view;
  final bool desktop;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final connected = view.phase == ConnectionPhase.connected;
    final live = connected && view.metricsAvailable;
    final traffic = view.traffic;
    final upload = live
        ? '${formatTraffic(view.uploadSpeed, connection: true)}/s'
        : '—';
    final download = live
        ? '${formatTraffic(view.downloadSpeed, connection: true)}/s'
        : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _metric(
                context,
                LucideIcons.arrowUp,
                '${l.prototypeUpload} $upload',
                upload,
                palette.running,
                AlignmentDirectional.centerStart,
              ),
            ),
            Semantics(
              label: l.homeSessionTime,
              child: _SessionClock(
                startedAt: connected ? view.runtime?.startedAt : null,
              ),
            ),
            Expanded(
              child: _metric(
                context,
                LucideIcons.arrowDown,
                '${l.prototypeDownload} $download',
                download,
                palette.primary,
                AlignmentDirectional.centerEnd,
              ),
            ),
          ],
        ),
        if (connected && traffic != null) ...[
          const SizedBox(height: 4),
          Semantics(
            label: l.prototypeThisConnection,
            child: Text(
              '↑ ${formatTraffic(traffic.uplink, connection: true)}'
              '  ·  '
              '↓ ${formatTraffic(traffic.downlink, connection: true)}',
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: AppTypography.groupMeta.copyWith(
                color: palette.mutedForeground,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _metric(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color color,
    AlignmentGeometry alignment,
  ) => Semantics(
    label: label,
    excludeSemantics: true,
    child: Align(
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          // Narrow phones shrink the number instead of cutting it.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                textDirection: TextDirection.ltr,
                style: AppTypography.homeMetric.copyWith(
                  color: ColorManager.palette(context).foreground,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// mm:ss, then h:mm:ss, ticking once a second while connected.
class _SessionClock extends StatefulWidget {
  const _SessionClock({required this.startedAt});

  final DateTime? startedAt;

  @override
  State<_SessionClock> createState() => _SessionClockState();
}

class _SessionClockState extends State<_SessionClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_SessionClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = widget.startedAt == null
        ? null
        : Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final started = widget.startedAt;
    final elapsed = started == null
        ? Duration.zero
        : DateTime.now().difference(started);
    String two(int value) => value.toString().padLeft(2, '0');
    final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
    final hours = seconds ~/ 3600;
    final text = started == null
        ? '--:--'
        : hours > 0
        ? '$hours:${two(seconds % 3600 ~/ 60)}:${two(seconds % 60)}'
        : '${two(seconds ~/ 60)}:${two(seconds % 60)}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.clock, size: 13, color: palette.mutedForeground),
        const SizedBox(width: 5),
        Text(
          text,
          textDirection: TextDirection.ltr,
          style: AppTypography.homeMetric.copyWith(
            color: started == null
                ? palette.mutedForeground
                : palette.foreground,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
