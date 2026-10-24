/// The network report as libXray's `netreport` writes it (format version 1).
///
/// Parsing is tolerant: a field a newer libXray adds is ignored, a missing one
/// reads as empty, so a report from another build still renders.
library;

const networkReportVersion = 1;

/// Probe and verdict codes, as libXray's `netreport.Status`.
abstract final class ReportStatus {
  static const ok = 'ok';
  static const timeout = 'timeout';
  static const reset = 'reset';
  static const refused = 'refused';
  static const unreachable = 'unreachable';
  static const closed = 'closed';
  static const alert = 'alert';
  static const certInvalid = 'cert_invalid';
  static const frozen = 'frozen';
  static const stalled = 'stalled';
  static const slow = 'slow';
  static const error = 'error';
  static const skipped = 'skipped';
  static const spoofed = 'spoofed';
  static const injected = 'injected';
  static const nxdomain = 'nxdomain';
  static const empty = 'empty';
  static const dnsOnly = 'dns_only';
  static const ipBlocked = 'ip_blocked';
  static const sniBlocked = 'sni_blocked';
  static const sniWhitelist = 'sni_whitelist';
  static const noSniOnly = 'nosni_only';
  static const tlsBlocked = 'tls_blocked';
  static const mitm = 'mitm';
  static const geo = 'geo';
  static const blocked = 'blocked';
  static const partial = 'partial';

  /// The other side answered: an alert or a wrong certificate still proves
  /// the path is open.
  static bool reached(String status) =>
      status == ok || status == alert || status == certInvalid;

  /// A site or provider the user can use as it is (a service refusing the
  /// country or crawling still answers).
  static bool usable(String verdict) =>
      verdict == ok || verdict == dnsOnly || verdict == geo || verdict == slow;

  static bool dnsForged(String status) =>
      status == spoofed ||
      status == injected ||
      status == nxdomain ||
      status == empty;
}

abstract final class ReportSection {
  static const network = 'network';
  static const dns = 'dns';
  static const sites = 'sites';
  static const hosting = 'hosting';
  static const udp = 'udp';

  static const all = [network, dns, sites, hosting, udp];
}

/// Network modes in [ReportFacts.mode].
abstract final class NetworkMode {
  static const open = 'open';
  static const filtered = 'filtered';

  /// A white list by address: only allowed networks answer at all, so a
  /// VPN server outside them cannot be reached either.
  static const whitelist = 'whitelist';

  /// A white list of names: the addresses answer, DPI passes only allowed
  /// server names (REALITY borrowing one, or Fragment, may get through).
  static const sniWhitelist = 'sni_whitelist';

  static bool restricted(String mode) =>
      mode == whitelist || mode == sniWhitelist;
  static const offline = 'offline';
}

/// Interface kinds in [ReportInterface.kind].
abstract final class InterfaceKind {
  static const ethernet = 'ethernet';
  static const wifi = 'wifi';
  static const usbTethering = 'usb_tethering';
  static const cellular = 'cellular';
  static const ppp = 'ppp';
  static const virtual = 'virtual';
  static const other = 'other';
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<Map<String, dynamic>> _maps(Object? value) =>
    value is List ? [for (final item in value) _map(item)] : const [];

List<String> _strings(Object? value) =>
    value is List ? [for (final item in value) '$item'] : const [];

String _string(Object? value) => value is String ? value : '';

int _int(Object? value) => value is num ? value.toInt() : 0;

bool _bool(Object? value) => value == true;

class ReportStep {
  final String status;
  final int ms;
  final String detail;

  const ReportStep({this.status = '', this.ms = 0, this.detail = ''});

  static ReportStep? read(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return ReportStep(
      status: _string(json['status']),
      ms: _int(json['ms']),
      detail: _string(json['detail']),
    );
  }

  bool get reached => ReportStatus.reached(status);
}

class ReportTransfer {
  final String status;
  final int http;
  final String location;
  final int bytes;
  final int rxBytes;
  final int ms;
  final int kbps;
  final bool geo;

  const ReportTransfer({
    this.status = '',
    this.http = 0,
    this.location = '',
    this.bytes = 0,
    this.rxBytes = 0,
    this.ms = 0,
    this.kbps = 0,
    this.geo = false,
  });

  static ReportTransfer? read(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return ReportTransfer(
      status: _string(json['status']),
      http: _int(json['http']),
      location: _string(json['location']),
      bytes: _int(json['bytes']),
      rxBytes: _int(json['rxBytes']),
      ms: _int(json['ms']),
      kbps: _int(json['kbps']),
      geo: _bool(json['geo']),
    );
  }
}

class ReportInterface {
  final String name;
  final String description;
  final String kind;
  final int mtu;
  final List<String> addresses;
  final List<String> gateways;
  final List<String> dns;

  const ReportInterface({
    this.name = '',
    this.description = '',
    this.kind = InterfaceKind.other,
    this.mtu = 0,
    this.addresses = const [],
    this.gateways = const [],
    this.dns = const [],
  });

  factory ReportInterface.fromJson(Map<String, dynamic> json) =>
      ReportInterface(
        name: _string(json['name']),
        description: _string(json['description']),
        kind: _string(json['kind']),
        mtu: _int(json['mtu']),
        addresses: _strings(json['addresses']),
        gateways: _strings(json['gateways']),
        dns: _strings(json['dns']),
      );
}

class ReportExternal {
  final String ip;
  final String prefix;
  final int asn;
  final String holder;
  final String country;
  final String city;

  const ReportExternal({
    this.ip = '',
    this.prefix = '',
    this.asn = 0,
    this.holder = '',
    this.country = '',
    this.city = '',
  });

  factory ReportExternal.fromJson(Map<String, dynamic> json) => ReportExternal(
    ip: _string(json['ip']),
    prefix: _string(json['prefix']),
    asn: _int(json['asn']),
    holder: _string(json['holder']),
    country: _string(json['country']),
    city: _string(json['city']),
  );
}

class ReportNetwork {
  final ReportInterface? interface;
  final ReportExternal? ipv4;
  final ReportExternal? ipv6;
  final bool nat;

  const ReportNetwork({this.interface, this.ipv4, this.ipv6, this.nat = false});

  factory ReportNetwork.fromJson(Map<String, dynamic> json) => ReportNetwork(
    interface: json['interface'] is Map<String, dynamic>
        ? ReportInterface.fromJson(json['interface'])
        : null,
    ipv4: json['ipv4'] is Map<String, dynamic>
        ? ReportExternal.fromJson(json['ipv4'])
        : null,
    ipv6: json['ipv6'] is Map<String, dynamic>
        ? ReportExternal.fromJson(json['ipv6'])
        : null,
    nat: _bool(json['nat']),
  );

  /// The provider as RIPE names it, IPv4 first.
  ReportExternal? get provider =>
      (ipv4?.asn ?? 0) != 0 ? ipv4 : ((ipv6?.asn ?? 0) != 0 ? ipv6 : ipv4);
}

class ReportName {
  final String name;
  final String status;

  const ReportName({this.name = '', this.status = ''});
}

class ReportResolver {
  final String id;
  final String name;
  final String address;
  final bool system;
  final String status;
  final int rttMs;
  final int lossPct;
  final bool intercepted;
  final String egressHolder;
  final ReportStep? doh;
  final List<ReportName> names;

  const ReportResolver({
    this.id = '',
    this.name = '',
    this.address = '',
    this.system = false,
    this.status = '',
    this.rttMs = 0,
    this.lossPct = 0,
    this.intercepted = false,
    this.egressHolder = '',
    this.doh,
    this.names = const [],
  });

  factory ReportResolver.fromJson(Map<String, dynamic> json) => ReportResolver(
    id: _string(json['id']),
    name: _string(json['name']),
    address: _string(json['address']),
    system: _bool(json['system']),
    status: _string(json['status']),
    rttMs: _int(json['rttMs']),
    lossPct: _int(json['lossPct']),
    intercepted: _bool(json['intercepted']),
    egressHolder: _string(_map(json['egress'])['holder']),
    doh: ReportStep.read(json['doh']),
    names: [
      for (final name in _maps(json['names']))
        ReportName(
          name: _string(name['name']),
          status: _string(name['status']),
        ),
    ],
  );

  /// Names answered with forged records.
  List<ReportName> get forged => [
    for (final name in names)
      if (ReportStatus.dnsForged(name.status)) name,
  ];
}

class ReportDns {
  final List<String> system;
  final bool port53Intercepted;
  final List<ReportResolver> resolvers;

  const ReportDns({
    this.system = const [],
    this.port53Intercepted = false,
    this.resolvers = const [],
  });

  factory ReportDns.fromJson(Map<String, dynamic> json) => ReportDns(
    system: _strings(json['system']),
    port53Intercepted: _bool(json['port53Intercepted']),
    resolvers: [
      for (final resolver in _maps(json['resolvers']))
        ReportResolver.fromJson(resolver),
    ],
  );
}

class ReportSite {
  final String id;
  final String name;
  final String group;
  final String host;
  final bool custom;
  final String dns;
  final ReportStep tcp;
  final ReportStep tls;
  final ReportStep? noSni;
  final ReportStep? randomSni;
  final ReportStep? whiteSni;
  final String whiteName;
  final ReportStep? split;
  final ReportStep? fragment;
  final ReportTransfer? fragmentTransfer;
  final ReportTransfer? http;
  final ReportStep? quic;
  final String verdict;

  const ReportSite({
    this.id = '',
    this.name = '',
    this.group = '',
    this.host = '',
    this.custom = false,
    this.dns = '',
    this.tcp = const ReportStep(),
    this.tls = const ReportStep(),
    this.noSni,
    this.randomSni,
    this.whiteSni,
    this.whiteName = '',
    this.split,
    this.fragment,
    this.fragmentTransfer,
    this.http,
    this.quic,
    this.verdict = '',
  });

  factory ReportSite.fromJson(Map<String, dynamic> json) => ReportSite(
    id: _string(json['id']),
    name: _string(json['name']),
    group: _string(json['group']),
    host: _string(json['host']),
    custom: _bool(json['custom']),
    dns: _string(json['dns']),
    tcp: ReportStep.read(json['tcp']) ?? const ReportStep(),
    tls: ReportStep.read(json['tls']) ?? const ReportStep(),
    noSni: ReportStep.read(json['noSni']),
    randomSni: ReportStep.read(json['randomSni']),
    whiteSni: ReportStep.read(json['whiteSni']),
    whiteName: _string(json['whiteName']),
    split: ReportStep.read(json['split']),
    fragment: ReportStep.read(json['fragment']),
    fragmentTransfer: ReportTransfer.read(json['fragmentTransfer']),
    http: ReportTransfer.read(json['http']),
    quic: ReportStep.read(json['quic']),
    verdict: _string(json['verdict']),
  );

  bool get usable => ReportStatus.usable(verdict);

  /// The App's Fragment got through where the plain hello did not.
  bool get fragmentHelps => !usable && bypassWorks(fragment, fragmentTransfer);
}

/// A cut-up hello got through and so did the data after it.
bool bypassWorks(ReportStep? step, ReportTransfer? transfer) =>
    step != null &&
    step.reached &&
    (transfer == null ||
        transfer.status == ReportStatus.ok ||
        transfer.status == ReportStatus.slow);

class ReportHosting {
  final String id;
  final String name;
  final String country;
  final String host;
  final bool foreign;
  final ReportStep tcp;
  final ReportStep tls;
  final ReportStep? noSni;
  final ReportStep? randomSni;
  final ReportTransfer? transfer;
  final ReportStep? whiteSni;
  final String whiteName;
  final ReportTransfer? whiteTransfer;
  final ReportStep? split;
  final ReportStep? fragment;
  final ReportTransfer? fragmentTransfer;
  final String verdict;

  const ReportHosting({
    this.id = '',
    this.name = '',
    this.country = '',
    this.host = '',
    this.foreign = false,
    this.tcp = const ReportStep(),
    this.tls = const ReportStep(),
    this.noSni,
    this.randomSni,
    this.transfer,
    this.whiteSni,
    this.whiteName = '',
    this.whiteTransfer,
    this.split,
    this.fragment,
    this.fragmentTransfer,
    this.verdict = '',
  });

  factory ReportHosting.fromJson(Map<String, dynamic> json) => ReportHosting(
    id: _string(json['id']),
    name: _string(json['name']),
    country: _string(json['country']),
    host: _string(json['host']),
    foreign: _bool(json['foreign']),
    tcp: ReportStep.read(json['tcp']) ?? const ReportStep(),
    tls: ReportStep.read(json['tls']) ?? const ReportStep(),
    noSni: ReportStep.read(json['noSni']),
    randomSni: ReportStep.read(json['randomSni']),
    transfer: ReportTransfer.read(json['transfer']),
    whiteSni: ReportStep.read(json['whiteSni']),
    whiteName: _string(json['whiteName']),
    whiteTransfer: ReportTransfer.read(json['whiteTransfer']),
    split: ReportStep.read(json['split']),
    fragment: ReportStep.read(json['fragment']),
    fragmentTransfer: ReportTransfer.read(json['fragmentTransfer']),
    verdict: _string(json['verdict']),
  );

  /// "Hetzner DE", or just the name for providers without one location.
  String get label => country.isEmpty ? name : '$name $country';

  bool get open => verdict == ReportStatus.ok || verdict == ReportStatus.slow;

  /// A borrowed allowed name carried the whole transfer where the provider's
  /// own failed: a REALITY server here would work.
  bool get openWithWhiteName =>
      !open && whiteTransfer?.status == ReportStatus.ok;

  bool get fragmentHelps => !open && bypassWorks(fragment, fragmentTransfer);
}

class ReportSni {
  final bool filtered;
  final List<String> passed;
  final List<String> failed;

  const ReportSni({
    this.filtered = false,
    this.passed = const [],
    this.failed = const [],
  });

  factory ReportSni.fromJson(Map<String, dynamic> json) => ReportSni(
    filtered: _bool(json['filtered']),
    passed: _strings(json['passed']),
    failed: _strings(json['failed']),
  );
}

class ReportProbe {
  final String id;
  final String name;
  final String status;
  final int ms;

  const ReportProbe({
    this.id = '',
    this.name = '',
    this.status = '',
    this.ms = 0,
  });

  factory ReportProbe.fromJson(Map<String, dynamic> json) => ReportProbe(
    id: _string(json['id']),
    name: _string(json['name']),
    status: _string(json['status']),
    ms: _int(json['ms']),
  );
}

class ReportUdp {
  final List<ReportProbe> stun;
  final List<ReportProbe> quic;
  final bool? symmetricNat;

  const ReportUdp({
    this.stun = const [],
    this.quic = const [],
    this.symmetricNat,
  });

  factory ReportUdp.fromJson(Map<String, dynamic> json) => ReportUdp(
    stun: [for (final item in _maps(json['stun'])) ReportProbe.fromJson(item)],
    quic: [for (final item in _maps(json['quic'])) ReportProbe.fromJson(item)],
    symmetricNat: json['symmetricNat'] is bool ? json['symmetricNat'] : null,
  );
}

class ReportFacts {
  final String mode;
  final bool sniFiltering;
  final bool whitelistBySni;
  final List<String> dnsSpoofing;
  final bool dnsInjection;
  final List<String> dnsIntercepted;
  final List<String> dnsLossy;
  final List<String> blockedSites;
  final List<String> geoBlocked;
  final List<String> frozen;
  final List<String> blockedHosting;
  final List<String> openHosting;
  final List<String> splitHelps;
  final List<String> fragmentHelps;

  /// Refusals the cut-up hellos were tried on; 0 when bypass checks were off.
  final int bypassTried;
  final String udp;
  final String quic;

  const ReportFacts({
    this.mode = '',
    this.sniFiltering = false,
    this.whitelistBySni = false,
    this.dnsSpoofing = const [],
    this.dnsInjection = false,
    this.dnsIntercepted = const [],
    this.dnsLossy = const [],
    this.blockedSites = const [],
    this.geoBlocked = const [],
    this.frozen = const [],
    this.blockedHosting = const [],
    this.openHosting = const [],
    this.splitHelps = const [],
    this.fragmentHelps = const [],
    this.bypassTried = 0,
    this.udp = '',
    this.quic = '',
  });

  factory ReportFacts.fromJson(Map<String, dynamic> json) => ReportFacts(
    mode: _string(json['mode']),
    sniFiltering: _bool(json['sniFiltering']),
    whitelistBySni: _bool(json['whitelistBySni']),
    dnsSpoofing: _strings(json['dnsSpoofing']),
    dnsInjection: _bool(json['dnsInjection']),
    dnsIntercepted: _strings(json['dnsIntercepted']),
    dnsLossy: _strings(json['dnsLossy']),
    blockedSites: _strings(json['blockedSites']),
    geoBlocked: _strings(json['geoBlocked']),
    frozen: _strings(json['frozen']),
    blockedHosting: _strings(json['blockedHosting']),
    openHosting: _strings(json['openHosting']),
    splitHelps: _strings(json['splitHelps']),
    fragmentHelps: _strings(json['fragmentHelps']),
    bypassTried: _int(json['bypassTried']),
    udp: _string(json['udp']),
    quic: _string(json['quic']),
  );
}

class NetworkReport {
  final int version;
  final DateTime? started;
  final int durationMs;
  final ReportNetwork? network;
  final ReportDns? dns;
  final List<ReportSite> sites;
  final List<ReportHosting> hosting;
  final ReportSni? sni;
  final ReportUdp? udp;
  final ReportFacts? facts;

  /// The report as libXray wrote it, for the JSON export.
  final Map<String, dynamic> raw;

  const NetworkReport({
    this.version = 0,
    this.started,
    this.durationMs = 0,
    this.network,
    this.dns,
    this.sites = const [],
    this.hosting = const [],
    this.sni,
    this.udp,
    this.facts,
    this.raw = const {},
  });

  factory NetworkReport.fromJson(Map<String, dynamic> json) => NetworkReport(
    version: _int(json['version']),
    started: DateTime.tryParse(_string(json['started']))?.toLocal(),
    durationMs: _int(json['durationMs']),
    network: json['network'] is Map<String, dynamic>
        ? ReportNetwork.fromJson(json['network'])
        : null,
    dns: json['dns'] is Map<String, dynamic>
        ? ReportDns.fromJson(json['dns'])
        : null,
    sites: [for (final site in _maps(json['sites'])) ReportSite.fromJson(site)],
    hosting: [
      for (final hosting in _maps(json['hosting']))
        ReportHosting.fromJson(hosting),
    ],
    sni: json['sni'] is Map<String, dynamic>
        ? ReportSni.fromJson(json['sni'])
        : null,
    udp: json['udp'] is Map<String, dynamic>
        ? ReportUdp.fromJson(json['udp'])
        : null,
    facts: json['facts'] is Map<String, dynamic>
        ? ReportFacts.fromJson(json['facts'])
        : null,
    raw: json,
  );

  bool get supported => version <= networkReportVersion;

  ReportSite? site(String id) {
    for (final site in sites) {
      if (site.id == id) return site;
    }
    return null;
  }
}
