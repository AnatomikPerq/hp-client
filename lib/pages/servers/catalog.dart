import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/name_emoji.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/connect/settings.dart';

enum ServerGrouping { subscription, location }

/// The section of manual nodes outside the user's groups.
const manualUngroupedId = 'manual:ungrouped';

class ServerGroup {
  final String id;
  final String name;
  final String? country;
  final SubscriptionData? source;
  final ServerSelection selection;

  /// A section of the manual card that is one of the user's own groups.
  final int? manualGroupId;

  /// A section of the manual card ("Ungrouped" or a group of the user's).
  bool get manual => id.startsWith('manual:');

  /// The card of every manual node, the one that holds the sections.
  bool get manualCard =>
      !manual && selection == const ServerSelection.source(0);
  final List<CoreConfigData> rows;
  final List<CoreConfigData> visibleRows;

  /// Fork: the manual card shows the user's groups as sections, "Ungrouped"
  /// first; null when there are no groups (or grouping by location). They
  /// only arrange the list: the card's selection still takes every manual
  /// node, as upstream's "all manual nodes" does.
  final List<ServerGroup>? sections;
  const ServerGroup({
    required this.id,
    required this.name,
    this.country,
    this.source,
    required this.selection,
    this.manualGroupId,
    required this.rows,
    required this.visibleRows,
    this.sections,
  });
}

mixin ServerLabels {
  String selectionName(AppLocalizations l10n, ServerSelection selection) =>
      switch (selection.kind) {
        SelectionKind.automatic => l10n.prototypeAutomaticSelection,
        SelectionKind.region => selection.region ?? '',
        SelectionKind.source =>
          selection.id == 0
              ? l10n.prototypeManualAdditions
              : catalog.sourcesById[selection.id]?.name ??
                    l10n.prototypeTemporarilyUnavailable,
        SelectionKind.server =>
          catalog.servers
                  .where((row) => row.id == selection.id)
                  .map(serverName)
                  .firstOrNull ??
              l10n.prototypeTemporarilyUnavailable,
      };

  ServerCatalog get catalog;
  String serverName(CoreConfigData row) => catalog.display(row).name;
  String protocol(CoreConfigData row) => catalog.display(row).protocol;

  /// `VLESS` out of `VLESS | XHTTP | REALITY`; empty when unreadable.
  String primaryProtocol(CoreConfigData row) =>
      protocol(row).split('|').first.trim();

  /// The list label: the name without its first emoji, which becomes the
  /// icon, and without flags Windows cannot draw. Names without an emoji
  /// show the flag of the measured location, [code], instead. Grouping by
  /// location keeps using that measured code, never the emoji.
  ({NameEmoji? emoji, String? code, String name}) nodeLabel(
    AppLocalizations l10n,
    CoreConfigData row,
  ) {
    final split = splitNameEmoji(serverName(row));
    final measured = row.countryCode?.toUpperCase();
    final code = measured == null || measured.isEmpty ? null : measured;
    final named = split.emoji?.country ?? code;
    final name = split.name.isNotEmpty
        ? split.name
        : named == null
        ? serverName(row)
        : l10n.countryRegionName(named);
    return (emoji: split.emoji, code: code, name: name);
  }

  String health(AppLocalizations l, CoreConfigData row) =>
      row.delay == PingDelayConstants.unknown
      ? l.prototypeNotTested
      : !PingDelayConstants.isSuccessful(row.delay)
      ? l.prototypeTemporarilyUnavailable
      : row.delay <= 500
      ? l.prototypeFastLatency(row.delay)
      : row.delay <= 1000
      ? l.prototypeSlowLatency(row.delay)
      : l.prototypeAvailableLatency(row.delay);
}

mixin ServerGroups on ServerLabels {
  ServerGrouping get grouping;
  String get query;

  /// Narrow every group to one protocol, e.g. `VLESS`; null keeps all.
  String? get protocolFilter => null;
  bool get favoritesOnly => false;
  bool get filtering => protocolFilter != null || favoritesOnly;
  List<CoreConfigData> get servers => catalog.servers;
  List<SubscriptionData> get sources => catalog.sources;
  String countryName(AppLocalizations l, String? code) {
    final normalized = code?.toUpperCase();
    return normalized == null || normalized.isEmpty
        ? '—'
        : l.countryRegionName(normalized);
  }

  /// A manual node's group, or "Manual additions" when it has none.
  String sourceName(AppLocalizations l, CoreConfigData row) =>
      ServerCatalog.isManual(row)
      ? catalog.manualGroups
                .where((group) => group.id == row.manualGroupId)
                .firstOrNull
                ?.name ??
            l.prototypeManualAdditions
      : catalog.sourcesById[row.subId]?.name ?? l.prototypeManualAdditions;

  int sourceCount(int id) => servers.where((row) => row.subId == id).length;

  bool matchesFilters(CoreConfigData row) =>
      (!favoritesOnly || row.favorite) &&
      (protocolFilter == null ||
          primaryProtocol(row).toUpperCase() == protocolFilter);

  bool matches(AppLocalizations l, CoreConfigData row) {
    if (!matchesFilters(row)) return false;
    final query = this.query.trim().toLowerCase();
    return query.isEmpty ||
        [
          serverName(row),
          countryName(l, row.countryCode),
          row.countryCode ?? '',
          sourceName(l, row),
        ].any((value) => value.toLowerCase().contains(query));
  }

  /// Protocols present in the catalog, most common first.
  List<String> protocols() {
    final counts = <String, int>{};
    for (final row in servers) {
      final value = primaryProtocol(row).toUpperCase();
      if (value.isNotEmpty) counts[value] = (counts[value] ?? 0) + 1;
    }
    return counts.keys.toList()..sort((a, b) {
      final count = counts[b]!.compareTo(counts[a]!);
      return count == 0 ? a.compareTo(b) : count;
    });
  }

  List<CoreConfigData> favorites(AppLocalizations l) =>
      servers.where((row) => row.favorite && matches(l, row)).toList();

  List<ServerGroup> groups(AppLocalizations l, {bool filter = true}) {
    final buckets = <String, List<CoreConfigData>>{};
    final sectioned =
        grouping == ServerGrouping.subscription &&
        catalog.manualGroups.isNotEmpty;
    // The user's own groups stay listed while empty, so their card does too.
    if (sectioned) buckets['0'] = [];
    for (final row in servers) {
      final key = grouping == ServerGrouping.location
          ? (row.countryCode?.toUpperCase() ?? '')
          : '${row.subId}';
      buckets.putIfAbsent(key, () => []).add(row);
    }
    final result = <ServerGroup>[];
    for (final entry in buckets.entries) {
      final source = grouping == ServerGrouping.subscription
          ? catalog.sourcesById[int.parse(entry.key)]
          : null;
      final name = grouping == ServerGrouping.location
          ? countryName(l, entry.key)
          : source?.name ?? l.prototypeManualAdditions;
      final query = this.query.trim().toLowerCase();
      final wholeGroup = !filter || name.toLowerCase().contains(query);
      final sections = sectioned && entry.key == '0'
          ? _manualSections(
              l,
              entry.value,
              filter: filter,
              wholeCard: wholeGroup,
            )
          : null;
      final visible = sections != null
          ? [for (final section in sections) ...section.visibleRows]
          : !filter
          ? entry.value
          : wholeGroup
          ? entry.value.where(matchesFilters).toList()
          : entry.value.where((row) => matches(l, row)).toList();
      if (filter &&
          (sections?.isEmpty ?? visible.isEmpty) &&
          ((query.isNotEmpty && !wholeGroup) || filtering)) {
        continue;
      }
      result.add(
        ServerGroup(
          id: '${grouping.name}:${entry.key}',
          name: name,
          country: grouping == ServerGrouping.location ? entry.key : null,
          source: source,
          selection: grouping == ServerGrouping.location
              ? ServerSelection.region(entry.key)
              : ServerSelection.source(int.parse(entry.key)),
          rows: entry.value,
          visibleRows: visible,
          sections: sections,
        ),
      );
    }
    if (grouping == ServerGrouping.subscription) {
      result.sort((a, b) => a.selection.id!.compareTo(b.selection.id!));
    }
    return result;
  }

  /// "Ungrouped" first, then the user's groups in their saved order. A
  /// section matching the search by name shows all of its nodes.
  List<ServerGroup> _manualSections(
    AppLocalizations l,
    List<CoreConfigData> rows, {
    required bool filter,
    required bool wholeCard,
  }) {
    final query = this.query.trim().toLowerCase();
    final known = {for (final group in catalog.manualGroups) group.id};
    final sections = <ServerGroup>[];
    void add(String id, String name, int? groupId, List<CoreConfigData> rows) {
      final whole = !filter || wholeCard || name.toLowerCase().contains(query);
      final visible = !filter
          ? rows
          : whole
          ? rows.where(matchesFilters).toList()
          : rows.where((row) => matches(l, row)).toList();
      if (filter &&
          visible.isEmpty &&
          ((query.isNotEmpty && !whole) || filtering)) {
        return;
      }
      sections.add(
        ServerGroup(
          id: id,
          name: name,
          selection: const ServerSelection.source(0),
          manualGroupId: groupId,
          rows: rows,
          visibleRows: visible,
        ),
      );
    }

    final ungrouped = rows
        .where((row) => !known.contains(row.manualGroupId))
        .toList();
    // Without nodes "Ungrouped" would only be an empty heading.
    if (ungrouped.isNotEmpty) {
      add(manualUngroupedId, l.manualGroupUngrouped, null, ungrouped);
    }
    for (final group in catalog.orderedManualGroups) {
      add(
        'manual:${group.id}',
        group.name,
        group.id,
        rows.where((row) => row.manualGroupId == group.id).toList(),
      );
    }
    return sections;
  }
}
