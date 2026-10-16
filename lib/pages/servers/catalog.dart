import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/country_flag.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/connect/settings.dart';

enum ServerGrouping { subscription, location }

class ServerGroup {
  final String id;
  final String name;
  final String? country;
  final SubscriptionData? source;
  final ServerSelection selection;
  final List<CoreConfigData> rows;
  final List<CoreConfigData> visibleRows;
  const ServerGroup({
    required this.id,
    required this.name,
    this.country,
    this.source,
    required this.selection,
    required this.rows,
    required this.visibleRows,
  });
}

mixin ServerLabels {
  String selectionName(AppLocalizations l10n, ServerSelection selection) =>
      switch (selection.kind) {
        SelectionKind.automatic => l10n.prototypeAutomaticSelection,
        SelectionKind.region => selection.region ?? '',
        SelectionKind.source =>
          catalog.sourcesById[selection.id]?.name ??
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

  /// The list label: the name without emoji flags, and the flag to draw.
  /// A flag in the name wins over the measured location of the address.
  ({String? code, String name}) nodeLabel(
    AppLocalizations l10n,
    CoreConfigData row,
  ) {
    final split = splitFlagEmoji(serverName(row));
    final code = split.code ?? row.countryCode?.toUpperCase();
    final name = split.name.isNotEmpty
        ? split.name
        : code == null || code.isEmpty
        ? serverName(row)
        : l10n.countryRegionName(code);
    return (code: code == null || code.isEmpty ? null : code, name: name);
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

  String sourceName(AppLocalizations l, CoreConfigData row) =>
      catalog.sourcesById[row.subId]?.name ?? l.prototypeManualAdditions;

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
      final visible = !filter
          ? entry.value
          : wholeGroup
          ? entry.value.where(matchesFilters).toList()
          : entry.value.where((row) => matches(l, row)).toList();
      if (filter &&
          visible.isEmpty &&
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
        ),
      );
    }
    if (grouping == ServerGrouping.subscription) {
      result.sort((a, b) => a.selection.id!.compareTo(b.selection.id!));
    }
    return result;
  }
}
