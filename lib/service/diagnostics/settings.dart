import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/service/diagnostics/report.dart';

/// How much of the user's own address a report shows.
enum ReportAddressMode {
  hidden,

  /// The /24 of an IPv4 address, the /48 of an IPv6 one: enough to tell
  /// the provider's network, not the subscriber.
  network,
  full,
}

enum ReportLocationMode { hidden, country, city }

/// What a report carries and shows, and which checks it runs. A device
/// preference: reports never leave the device unless the user shares them.
final class NetworkReportSettings {
  final ReportAddressMode address;
  final bool provider;
  final ReportLocationMode location;
  final bool connectionType;

  /// The adapter's name, model and local addresses.
  final bool adapter;
  final bool dnsServers;
  final bool device;

  final bool checkDns;
  final bool checkSites;
  final bool checkHosting;
  final bool checkUdp;

  /// Retries refused handshakes with the ClientHello cut up as the App's
  /// Fragment does (and DPI bypass tools like zapret at the application
  /// level), then fetches over it.
  final bool bypass;

  /// Smaller downloads, for metered networks.
  final bool saveTraffic;
  final List<String> extraSites;

  final bool hidePassed;
  final bool details;

  static const maxExtraSites = 20;

  const NetworkReportSettings({
    this.address = ReportAddressMode.network,
    this.provider = true,
    this.location = ReportLocationMode.country,
    this.connectionType = true,
    this.adapter = false,
    this.dnsServers = true,
    this.device = true,
    this.checkDns = true,
    this.checkSites = true,
    this.checkHosting = true,
    this.checkUdp = true,
    this.bypass = true,
    this.saveTraffic = false,
    this.extraSites = const [],
    this.hidePassed = false,
    this.details = false,
  });

  List<String> get sections => [
    ReportSection.network,
    if (checkDns) ReportSection.dns,
    if (checkSites) ReportSection.sites,
    if (checkHosting) ReportSection.hosting,
    if (checkUdp) ReportSection.udp,
  ];

  int get maxBytes => saveTraffic ? 64 * 1024 : 256 * 1024;

  NetworkReportSettings copyWith({
    ReportAddressMode? address,
    bool? provider,
    ReportLocationMode? location,
    bool? connectionType,
    bool? adapter,
    bool? dnsServers,
    bool? device,
    bool? checkDns,
    bool? checkSites,
    bool? checkHosting,
    bool? checkUdp,
    bool? bypass,
    bool? saveTraffic,
    List<String>? extraSites,
    bool? hidePassed,
    bool? details,
  }) => NetworkReportSettings(
    address: address ?? this.address,
    provider: provider ?? this.provider,
    location: location ?? this.location,
    connectionType: connectionType ?? this.connectionType,
    adapter: adapter ?? this.adapter,
    dnsServers: dnsServers ?? this.dnsServers,
    device: device ?? this.device,
    checkDns: checkDns ?? this.checkDns,
    checkSites: checkSites ?? this.checkSites,
    checkHosting: checkHosting ?? this.checkHosting,
    checkUdp: checkUdp ?? this.checkUdp,
    bypass: bypass ?? this.bypass,
    saveTraffic: saveTraffic ?? this.saveTraffic,
    extraSites: extraSites ?? this.extraSites,
    hidePassed: hidePassed ?? this.hidePassed,
    details: details ?? this.details,
  );

  /// Reads stored settings; unknown or broken values fall back to defaults
  /// one by one, so a newer build's settings still load.
  factory NetworkReportSettings.fromJson(Map<String, dynamic> json) {
    const defaults = NetworkReportSettings();
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    T option<T extends Enum>(List<T> values, String key, T fallback) {
      for (final value in values) {
        if (value.name == json[key]) return value;
      }
      return fallback;
    }

    final extra = json['extraSites'];
    return NetworkReportSettings(
      address: option(ReportAddressMode.values, 'address', defaults.address),
      provider: flag('provider', defaults.provider),
      location: option(
        ReportLocationMode.values,
        'location',
        defaults.location,
      ),
      connectionType: flag('connectionType', defaults.connectionType),
      adapter: flag('adapter', defaults.adapter),
      dnsServers: flag('dnsServers', defaults.dnsServers),
      device: flag('device', defaults.device),
      checkDns: flag('checkDns', defaults.checkDns),
      checkSites: flag('checkSites', defaults.checkSites),
      checkHosting: flag('checkHosting', defaults.checkHosting),
      checkUdp: flag('checkUdp', defaults.checkUdp),
      bypass: flag('bypass', defaults.bypass),
      saveTraffic: flag('saveTraffic', defaults.saveTraffic),
      extraSites: extra is List
          ? normalizeSites([for (final site in extra) '$site'])
          : const [],
      hidePassed: flag('hidePassed', defaults.hidePassed),
      details: flag('details', defaults.details),
    );
  }

  Map<String, dynamic> toJson() => {
    'address': address.name,
    'provider': provider,
    'location': location.name,
    'connectionType': connectionType,
    'adapter': adapter,
    'dnsServers': dnsServers,
    'device': device,
    'checkDns': checkDns,
    'checkSites': checkSites,
    'checkHosting': checkHosting,
    'checkUdp': checkUdp,
    'bypass': bypass,
    'saveTraffic': saveTraffic,
    'extraSites': extraSites,
    'hidePassed': hidePassed,
    'details': details,
  };

  static Future<NetworkReportSettings> read() async {
    try {
      final json = await PreferencesKey().readNetworkReport();
      return json == null
          ? const NetworkReportSettings()
          : NetworkReportSettings.fromJson(json);
    } on FormatException {
      return const NetworkReportSettings();
    }
  }

  Future<void> save() => PreferencesKey().saveNetworkReport(toJson());

  /// Host names from free text: one per line or separated by spaces or
  /// commas, scheme and path dropped, duplicates removed.
  static List<String> normalizeSites(Iterable<String> input) {
    final hosts = <String>[];
    for (final entry in input) {
      for (var host in entry.split(RegExp(r'[\s,;]+'))) {
        host = host.trim().toLowerCase();
        host = host.replaceFirst(RegExp(r'^[a-z]+://'), '');
        host = host.split(RegExp(r'[/?#:]')).first;
        if (host.endsWith('.')) host = host.substring(0, host.length - 1);
        if (!_hostPattern.hasMatch(host) || hosts.contains(host)) continue;
        hosts.add(host);
        if (hosts.length == maxExtraSites) return hosts;
      }
    }
    return hosts;
  }

  static final _hostPattern = RegExp(
    r'^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]$',
  );
}
