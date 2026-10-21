import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/menus.dart';
import 'package:onexray/pages/servers/node_tile.dart';
import 'package:onexray/pages/servers/sort.dart';
import 'package:onexray/pages/servers/subscription/user_info.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/shared/widgets/country_flag.dart';
import 'package:onexray/pages/shared/widgets/name_emoji.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_empty_state.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';

bool _mobile(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;

/// The Servers tab: search, filters and every group as a collapsible card in
/// one scrolling list. A tap on a node selects it, nothing opens a detail pane.
class ServerBrowser extends StatelessWidget {
  final ServersController controller;
  final ScrollController scroll;
  const ServerBrowser({
    super.key,
    required this.controller,
    required this.scroll,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    if (controller.servers.isEmpty) {
      // Sources whose current mode has nothing cached yet.
      if (controller.sources.isNotEmpty) {
        return PageEmptyState(
          title: l.subscriptionModeNoCacheTitle,
          description: l.subscriptionModeNeedsRefresh,
          primaryLabel: l.prototypeUpdatesAndSources,
          onPrimary: () => controller.openSources(context),
          secondaryLabel: l.prototypeAddServer,
          onSecondary: () => controller.addServers(context),
          scrollController: scroll,
        );
      }
      return PageEmptyState(
        title: l.prototypeNoServersYet,
        description: l.prototypeAddProviderSubscriptionHint,
        primaryLabel: l.prototypeAddServer,
        onPrimary: () => controller.addServers(context),
        secondaryLabel: l.prototypeHowGetServers,
        onSecondary: () => controller.openServerHelp(context),
        scrollController: scroll,
      );
    }
    final groups = controller.groups(l);
    final favorites = controller.favoritesOnly
        ? const <CoreConfigData>[]
        : controller.favorites(l);
    final mobile = _mobile(context);
    final horizontal = mobile ? AppSpacing.mobilePage : AppSpacing.page;
    const gap = SliverToBoxAdapter(child: SizedBox(height: 10));
    // Groups are slivers so a subscription with hundreds of nodes only
    // builds the rows on screen.
    return CustomScrollView(
      controller: scroll,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            mobile ? 12 : 18,
            horizontal,
            mobile ? 22 : 32,
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(child: ServerToolbar(controller: controller)),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: ServerAutomaticTile(controller: controller),
              ),
              if (favorites.isNotEmpty) ...[
                gap,
                ServerGroupSliver(
                  controller: controller,
                  favorites: true,
                  group: ServerGroup(
                    id: 'favorites',
                    name: l.prototypeFavorites,
                    selection: const ServerSelection.automatic(),
                    rows: favorites,
                    visibleRows: favorites,
                  ),
                ),
              ],
              for (final group in groups) ...[
                gap,
                ServerGroupSliver(controller: controller, group: group),
              ],
              if (groups.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 28,
                    ),
                    child: Text(
                      controller.grouping == ServerGrouping.location
                          ? l.prototypeNoMatchingLocations
                          : l.prototypeNoMatchingSubscriptions,
                      textAlign: TextAlign.center,
                      style: AppTypography.settingsInput.copyWith(
                        color: palette.mutedForeground,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Search, grouping and filter chips above the server list.
class ServerToolbar extends StatelessWidget {
  const ServerToolbar({super.key, required this.controller});

  final ServersController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final mobile = _mobile(context);
    final grouping = _Segmented<ServerGrouping>(
      value: controller.grouping,
      onChanged: controller.groupBy,
      options: [
        (
          ServerGrouping.subscription,
          LucideIcons.layers,
          l.prototypeBySubscription,
        ),
        (ServerGrouping.location, LucideIcons.earth, l.prototypeByNodeLocation),
      ],
    );
    final protocols = controller.protocols();
    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _FilterChip(
          label: l.serversFilterAll,
          selected: !controller.filtering,
          onTap: () {
            controller.setProtocolFilter(null);
            controller.setFavoritesOnly(false);
          },
        ),
        if (controller.servers.any((row) => row.favorite))
          _FilterChip(
            icon: LucideIcons.star,
            label: l.prototypeFavorites,
            selected: controller.favoritesOnly,
            onTap: () => controller.setFavoritesOnly(!controller.favoritesOnly),
          ),
        if (protocols.length > 1)
          for (final protocol in protocols)
            _FilterChip(
              label: protocol,
              selected: controller.protocolFilter == protocol,
              onTap: () => controller.setProtocolFilter(
                controller.protocolFilter == protocol ? null : protocol,
              ),
            ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mobile) ...[
          _SearchField(controller: controller),
          const SizedBox(height: 10),
          grouping,
        ] else
          Row(
            children: [
              Expanded(child: _SearchField(controller: controller)),
              const SizedBox(width: 12),
              SizedBox(width: 340, child: grouping),
            ],
          ),
        const SizedBox(height: 10),
        chips,
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final ServersController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      borderSide: BorderSide(color: palette.border),
    );
    final field = TextField(
      controller: controller.search,
      onChanged: controller.searchChanged,
      textAlignVertical: TextAlignVertical.center,
      style: AppTypography.settingsInput.copyWith(color: palette.foreground),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: palette.card,
        contentPadding: const EdgeInsetsDirectional.only(end: 13),
        hintText: l.prototypeSearchSubscriptionsServers,
        hintStyle: AppTypography.settingsInput.copyWith(
          color: palette.mutedForeground,
        ),
        prefixIconConstraints: const BoxConstraints.tightFor(
          width: 40,
          height: 40,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(start: 13, end: 9),
          child: Icon(
            LucideIcons.search,
            size: 17,
            color: palette.mutedForeground,
          ),
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: palette.primary),
        ),
      ),
    );
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(child: field),
          const SizedBox(width: 4),
          ServerSortButton(controller: controller),
        ],
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, IconData, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (final (option, icon, label) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: option == value,
                child: Material(
                  color: option == value
                      ? palette.selectedSurface
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.compact),
                    side: BorderSide(
                      color: option == value
                          ? palette.primary.withValues(alpha: .5)
                          : Colors.transparent,
                    ),
                  ),
                  child: InkWell(
                    onTap: option == value ? null : () => onChanged(option),
                    borderRadius: BorderRadius.circular(AppRadii.compact),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 15,
                            color: option == value
                                ? palette.primary
                                : palette.mutedStrong,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.filterChip.copyWith(
                                color: option == value
                                    ? palette.primary
                                    : palette.mutedStrong,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final color = selected ? palette.primaryForeground : palette.mutedStrong;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? palette.primarySolid : palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          side: BorderSide(
            color: selected ? palette.primarySolid : palette.border,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: AppTypography.filterChip.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Automatic" as a node-like row: the best available entries, chosen by
/// latency when the connection starts.
class ServerAutomaticTile extends StatelessWidget {
  const ServerAutomaticTile({super.key, required this.controller});

  final ServersController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final selected = controller.selected(const ServerSelection.automatic());
    final result = controller.automaticResult(l);
    final radius = BorderRadius.circular(AppRadii.card);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? Color.lerp(palette.card, palette.primary, .07)
            : palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected
                ? palette.primary.withValues(alpha: .6)
                : palette.border,
          ),
        ),
        child: InkWell(
          onTap: controller.busy
              ? null
              : () => controller.choose(
                  context,
                  const ServerSelection.automatic(),
                ),
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 28,
                    child: Center(
                      // Background probes feed the automatic choice.
                      child: AppActivityBuilder(
                        builder: (context, activity) =>
                            activity.pinging ||
                                controller.selectingGroup(
                                  const ServerSelection.automatic(),
                                )
                            ? const ButtonProgressIndicator()
                            : Icon(
                                LucideIcons.zap,
                                size: 19,
                                color: palette.primary,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.prototypeAutomaticRecommended,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.nodeTitle.copyWith(
                            color: palette.foreground,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          result ?? l.prototypeChooseBySpeedAvailability,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.groupMeta.copyWith(
                            color: result == null
                                ? palette.mutedForeground
                                : palette.runningText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: Icon(
                        LucideIcons.circleCheck,
                        size: 19,
                        color: palette.primary,
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

/// A subscription, location or the favorites as one card with its nodes.
///
/// The header toggles the card; refresh, latency test, "use the group" and the
/// subscription menu sit on the header so nothing needs a second screen.
class ServerGroupCard extends StatelessWidget {
  const ServerGroupCard({
    super.key,
    required this.controller,
    required this.group,
    this.favorites = false,
    this.collapsible = true,
  });

  final ServersController controller;
  final ServerGroup group;
  final bool favorites;
  final bool collapsible;

  bool get _collapsed => collapsible && controller.collapsed(group.id);

  @override
  Widget build(BuildContext context) {
    final collapsed = _collapsed;
    return Material(
      key: ValueKey('server-group:${group.id}'),
      color: ColorManager.palette(context).card,
      shape: _shape(context),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, collapsed),
            if (!collapsed) ...[
              if (group.visibleRows.isEmpty) _empty(context),
              for (final row in group.visibleRows) _row(context, row),
            ],
          ],
        ),
      ),
    );
  }

  ShapeBorder _shape(BuildContext context) => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.dialog),
    side: BorderSide(color: ColorManager.palette(context).border),
  );

  Widget _empty(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final muted = ColorManager.palette(context).mutedForeground;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: group.source == null
          ? Text(
              l.prototypeNoServersYet,
              textAlign: TextAlign.center,
              style: AppTypography.rowValue.copyWith(color: muted),
            )
          // The source's current mode has no cached rows yet.
          : Column(
              children: [
                Text(
                  controller.providerGroup(group)
                      ? l.subscriptionModeProviderManaged
                      : l.subscriptionModeAppManaged,
                  textAlign: TextAlign.center,
                  style: AppTypography.rowTitle,
                ),
                const SizedBox(height: 8),
                Text(
                  l.subscriptionModeNoCacheTitle,
                  textAlign: TextAlign.center,
                  style: AppTypography.rowValue.copyWith(color: muted),
                ),
                const SizedBox(height: 8),
                Text(
                  l.subscriptionModeNeedsRefresh,
                  textAlign: TextAlign.center,
                  style: AppTypography.serverDetail.copyWith(color: muted),
                ),
              ],
            ),
    );
  }

  Widget _row(BuildContext context, CoreConfigData row) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: ServerNodeRow(
        key: ValueKey(row.id),
        controller: controller,
        row: row,
        detail: favorites || group.country != null
            ? controller.sourceName(l, row)
            : null,
      ),
    );
  }

  Widget _header(BuildContext context, bool collapsed) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final source = group.source;
    final package = source == null
        ? null
        : SubscriptionUserInfo.fromSubscription(source);
    final now = DateTime.now();
    final usage = package == null
        ? null
        : SubscriptionPackageSummary.usage(package);
    final meta = <String>[
      if (source != null) l.groupUpdatedAt(_time(l, source.timestamp, now)),
      if (package != null) SubscriptionPackageSummary.text(l, package, now),
      if (source == null && !favorites) controller.summary(l, group),
    ].where((value) => value.isNotEmpty).join(' · ');
    final error = source == null ? null : controller.sourceErrors[source.id];
    // A provider's emoji in the subscription name becomes its icon.
    final split = source == null ? null : splitNameEmoji(group.name);
    final emoji = split?.emoji;
    final title = emoji != null && split!.name.isNotEmpty
        ? split.name
        : group.name;
    final leading = favorites
        ? Icon(LucideIcons.star600, size: 18, color: palette.restarting)
        : group.country != null
        ? CountryFlag(code: group.country!.isEmpty ? null : group.country)
        : emoji != null
        ? NameIcon(emoji: emoji)
        : Icon(LucideIcons.layers, size: 18, color: palette.primary);
    final radius = BorderRadius.circular(AppRadii.card);
    return InkWell(
      onTap: collapsible ? () => controller.toggleGroup(group.id) : null,
      borderRadius: radius,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 0, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (collapsible) ...[
                  Icon(
                    collapsed
                        ? LucideIcons.chevronRightDir
                        : LucideIcons.chevronDown,
                    size: 16,
                    color: palette.mutedForeground,
                  ),
                  const SizedBox(width: 6),
                ],
                SizedBox.square(dimension: 24, child: Center(child: leading)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
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
                              style: AppTypography.groupTitle.copyWith(
                                color: palette.foreground,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          _CountBadge(count: group.rows.length),
                        ],
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        _meta(context, meta, package, now),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                ..._actions(context),
              ],
            ),
            if (usage != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: LinearProgressIndicator(
                  value: usage,
                  minHeight: 3,
                  backgroundColor: palette.muted,
                  color: usage >= .9 ? palette.restarting : palette.primary,
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(
                error,
                style: AppTypography.groupMeta.copyWith(
                  color: palette.destructive,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The provider's package details open from the line that summarizes them.
  Widget _meta(
    BuildContext context,
    String meta,
    SubscriptionUserInfo? package,
    DateTime now,
  ) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final text = Text(
      meta,
      key: ValueKey('server-group-meta:${group.id}'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.groupMeta.copyWith(
        color:
            package != null && SubscriptionPackageSummary.warning(package, now)
            ? palette.restartingText
            : palette.mutedForeground,
      ),
    );
    if (package == null) return text;
    return Tooltip(
      message: l.subscriptionPackageTitle,
      child: InkWell(
        onTap: () => showAppDialog<void>(
          context,
          (_) => AppDialog(
            title: group.name,
            body: SubscriptionPackageDetails(info: package),
          ),
        ),
        borderRadius: BorderRadius.circular(AppRadii.small),
        child: text,
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final source = group.source;
    final testing = controller.testingGroup(group);
    final cancelling = controller.cancellingGroup(group);
    // Narrow screens keep refresh in the subscription menu.
    final mobile = _mobile(context);
    // Provider configurations are chosen one by one and never pinged.
    final provider = controller.providerGroup(group);
    return [
      if (source != null && !mobile)
        _HeaderButton(
          tooltip: l.prototypeCheckForUpdates,
          icon: LucideIcons.refreshCw,
          busy: controller.sourceBusy(source.id),
          onPressed: controller.sourceBusy(source.id)
              ? null
              : () => controller.sourceAction(
                  context,
                  source,
                  SourceAction.update,
                ),
        ),
      if (!provider)
        _HeaderButton(
          tooltip: testing
              ? cancelling
                    ? l.prototypePleaseWait
                    : l.prototypeCancel
              : l.prototypeTestServers,
          icon: LucideIcons.gauge,
          // A running test spins; a tap cancels it.
          busy: testing,
          onPressed: testing
              ? cancelling
                    ? null
                    : () => controller.cancelTest(group.id)
              : group.rows.isEmpty || group.rows.any(controller.serverBusy)
              ? null
              : () => controller.test(context, group.rows, groupId: group.id),
        ),
      if (!favorites && !provider)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ServerUseButton(
            controller: controller,
            group: group,
            inline: true,
          ),
        ),
      if (source != null)
        SizedBox(
          width: 36,
          child: SourceMenu(controller: controller, source: source),
        ),
    ];
  }

  static String _time(AppLocalizations l, DateTime value, DateTime now) {
    final local = value.toLocal();
    return DateUtils.isSameDay(local, now.toLocal())
        ? DateFormat.Hm(l.localeName).format(local)
        : DateFormat.yMd(l.localeName).add_Hm().format(local);
  }
}

/// [ServerGroupCard] for a scroll view of slivers: the card is painted
/// behind a lazy list, so only visible nodes are built.
class ServerGroupSliver extends ServerGroupCard {
  const ServerGroupSliver({
    super.key,
    required super.controller,
    required super.group,
    super.favorites,
    super.collapsible,
  });

  @override
  Widget build(BuildContext context) {
    final collapsed = _collapsed;
    final rows = group.visibleRows;
    return DecoratedSliver(
      key: ValueKey('server-group:${group.id}'),
      decoration: ShapeDecoration(
        color: ColorManager.palette(context).card,
        shape: _shape(context),
      ),
      sliver: SliverPadding(
        padding: const EdgeInsets.all(5),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: _header(context, collapsed)),
            if (!collapsed)
              rows.isEmpty
                  ? SliverToBoxAdapter(child: _empty(context))
                  : SliverList.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) =>
                          _row(context, rows[index]),
                    ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: palette.selectedSurface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: palette.primary.withValues(alpha: .35)),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: AppTypography.groupBadge.copyWith(color: palette.primary),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      foregroundColor: ColorManager.palette(context).mutedStrong,
      iconSize: 16,
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: busy ? const ButtonProgressIndicator(size: 15) : Icon(icon),
  );
}

/// The route page for one group on narrow screens.
class ServerGroupView extends StatelessWidget {
  final ServersController controller;
  final ServerGroup group;
  final bool groupPage;
  final bool embedded;
  const ServerGroupView({
    super.key,
    required this.controller,
    required this.group,
    this.groupPage = false,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      return ServerGroupCard(
        controller: controller,
        group: group,
        collapsible: false,
      );
    }
    final mobile = _mobile(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: mobile
              ? const EdgeInsets.fromLTRB(15, 13, 15, 22)
              : const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.desktopPageTop,
                  AppSpacing.page,
                  AppSpacing.desktopPageBottom,
                ),
          sliver: ServerGroupSliver(
            controller: controller,
            group: group,
            collapsible: false,
          ),
        ),
      ],
    );
  }
}

/// Uses the whole group: automatic choice among its nodes.
class ServerUseButton extends StatelessWidget {
  final ServersController controller;
  final ServerGroup group;
  final bool inline;
  const ServerUseButton({
    super.key,
    required this.controller,
    required this.group,
    this.inline = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final count = controller.entryCount(group.selection);
    final enabled = controller.canUse(group);
    final selected = controller.selected(group.selection);
    final VoidCallback? choose = controller.busy || !enabled
        ? null
        : () => controller.choose(context, group.selection);
    final palette = ColorManager.palette(context);
    final compact = inline && _mobile(context);
    return Semantics(
      label: '${l.prototypeUseEntryServers(count)}: ${group.name}',
      button: true,
      selected: selected,
      enabled: choose != null,
      onTap: choose,
      excludeSemantics: true,
      child: Tooltip(
        message: enabled
            ? l.prototypeUseEntryServers(count)
            : l.prototypeNotEnoughServers,
        child: Opacity(
          opacity: choose == null ? .52 : 1,
          child: OutlinedButton(
            onPressed: choose,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, inline ? 30 : 36),
              padding: EdgeInsets.symmetric(horizontal: inline ? 7 : 9),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              foregroundColor: selected ? palette.primary : palette.foreground,
              backgroundColor: selected
                  ? palette.selectedSurface
                  : palette.card,
              side: BorderSide(
                color: selected
                    ? Color.lerp(palette.border, palette.primary, .48)!
                    : palette.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              textStyle: AppTypography.serverUseLabel,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.selectingGroup(group.selection))
                  const ButtonProgressIndicator(size: 14)
                else
                  Icon(
                    selected ? LucideIcons.circleCheck : LucideIcons.zap,
                    size: 14,
                  ),
                if (!compact) ...[
                  const SizedBox(width: 5),
                  Text(l.prototypeUse),
                ],
                const SizedBox(width: 5),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    color: selected
                        ? palette.primarySolid
                        : palette.surfaceHover,
                  ),
                  child: Text(
                    '$count',
                    style: AppTypography.serverGroupUseCount.copyWith(
                      color: selected
                          ? palette.primaryForeground
                          : palette.mutedStrong,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One node with the controller's selection, busy and menu wiring.
class ServerNodeRow extends StatelessWidget {
  final ServersController controller;
  final CoreConfigData row;
  final String? detail;
  const ServerNodeRow({
    super.key,
    required this.controller,
    required this.row,
    this.detail,
  });

  @override
  Widget build(BuildContext context) =>
      BlocSelector<AppEventBus, AppEventBusState, PingBatchResult?>(
        bloc: AppEventBus.instance,
        selector: (state) => state.pingFailures[row.id],
        builder: (context, failure) {
          final l = AppLocalizations.of(context)!;
          final enabled = controller.canChoose(row);
          final conflict = controller.exitConflict(row);
          final label = controller.nodeLabel(l, row);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ServerNodeTile(
                title: label.name,
                emoji: label.emoji,
                countryCode: label.code,
                // A provider configuration is a whole config, not one protocol.
                protocol: controller.providerRow(row)
                    ? row.type
                    : controller.protocol(row),
                detail: detail,
                delay: row.delay,
                running: controller.runningEntries.contains(row.id),
                chosen: controller.chosen(row),
                enabled: enabled,
                busy:
                    controller.selectingGroup(ServerSelection.server(row.id)) ||
                    controller.favoritingIds.contains(row.id),
                favorite: row.favorite,
                note: conflict ? l.prototypeFinalExitEntryConflict : null,
                onTap: controller.busy || conflict
                    ? null
                    : enabled
                    ? () => controller.chooseRow(context, row)
                    : () => ServerMenu.open(context, controller, row),
                trailing: SizedBox(
                  width: 38,
                  child: ServerMenu(controller: controller, row: row),
                ),
              ),
              if (failure != null && !controller.providerRow(row))
                Padding(
                  padding: const EdgeInsets.fromLTRB(48, 2, 16, 8),
                  child: SelectableText(
                    appFailureMessage(
                      l,
                      failure.success ? failure.locationError : failure.error,
                      operation: failure.success
                          ? l.prototypeByNodeLocation
                          : l.prototypeSpeedTest,
                    ),
                    // A failed location probe is a note, not a failure.
                    style: AppTypography.settingsDetailNote.copyWith(
                      color: failure.success
                          ? ColorManager.palette(context).mutedForeground
                          : ColorManager.palette(context).destructive,
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

class ServerMenu extends StatelessWidget {
  final ServersController controller;
  final CoreConfigData row;
  const ServerMenu({super.key, required this.controller, required this.row});

  /// Mobile: a bottom sheet with hints. Desktop: a popup at [context].
  static Future<void> open(
    BuildContext context,
    ServersController controller,
    CoreConfigData row,
  ) async {
    final l = AppLocalizations.of(context)!;
    final action = _mobile(context)
        ? await showServerActionsMenu(
            context,
            name: controller.serverName(row),
            source: controller.sourceName(l, row),
            favorite: row.favorite,
            provider: controller.providerRow(row),
          )
        : await showServerActionsPopup(
            context,
            favorite: row.favorite,
            provider: controller.providerRow(row),
          );
    if (context.mounted && action != null) {
      await controller.serverAction(context, row, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Builder(
      builder: (anchor) => IconButton(
        tooltip: '${l.prototypeMoreActions}: ${controller.serverName(row)}',
        onPressed: controller.serverBusy(row)
            ? null
            : () => open(anchor, controller, row),
        style: IconButton.styleFrom(
          foregroundColor: ColorManager.palette(context).mutedStrong,
          iconSize: 17,
          padding: EdgeInsets.zero,
          minimumSize: const Size(36, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(LucideIcons.ellipsis),
      ),
    );
  }
}

class SourceMenu extends StatelessWidget {
  final ServersController controller;
  final SubscriptionData source;
  const SourceMenu({super.key, required this.controller, required this.source});

  static Future<void> open(
    BuildContext context,
    ServersController controller,
    SubscriptionData source,
  ) async {
    final action = _mobile(context)
        ? await showSourceActionsMenu(
            context,
            name: source.name,
            count: controller.sourceCount(source.id),
            provider: controller.providerSource(source),
          )
        : await showSourceActionsPopup(
            context,
            provider: controller.providerSource(source),
          );
    if (context.mounted && action != null) {
      await controller.sourceAction(context, source, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Builder(
      builder: (anchor) => IconButton(
        tooltip: '${l.prototypeMoreActions}: ${source.name}',
        onPressed: controller.sourceBusy(source.id)
            ? null
            : () => open(anchor, controller, source),
        style: IconButton.styleFrom(
          foregroundColor: ColorManager.palette(context).mutedStrong,
          iconSize: 17,
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(LucideIcons.ellipsis),
      ),
    );
  }
}
