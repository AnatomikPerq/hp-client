// Public list parameters keep the settings API independent of private storage.
// ignore_for_file: prefer_initializing_formals

/// Where a traffic profile sends what it matches.
enum TrafficProfileAction { proxy, direct }

/// Sites, addresses, protocols and programs routed one way on top of the
/// routing mode. Built-in profiles live in `TrafficProfiles`; custom ones are
/// stored with the connection settings.
final class TrafficProfile {
  static const customPrefix = 'custom-';
  static const maxNameLength = 40;
  static const maxEntries = 1000;
  static const protocolValues = {'http', 'tls', 'quic', 'bittorrent'};

  final String id;

  /// The user's name of a custom profile; built-in names come from the UI.
  final String name;
  final TrafficProfileAction action;
  final List<String> domains;
  final List<String> ips;
  final List<String> protocols;

  /// Executable names (`Discord.exe`), absolute paths or folders ending in
  /// `/`, as Xray's `process` rule takes them. Desktop Cores only.
  final List<String> processes;

  TrafficProfile({
    required this.id,
    this.name = '',
    required this.action,
    Iterable<String> domains = const [],
    Iterable<String> ips = const [],
    Iterable<String> protocols = const [],
    Iterable<String> processes = const [],
  }) : domains = List.unmodifiable(domains),
       ips = List.unmodifiable(ips),
       protocols = List.unmodifiable(protocols),
       processes = List.unmodifiable(processes);

  bool get custom => id.startsWith(customPrefix);

  factory TrafficProfile.fromJson(Map<String, dynamic> json) => TrafficProfile(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    action: TrafficProfileAction.values.byName(
      json['action'] as String? ?? TrafficProfileAction.proxy.name,
    ),
    domains: _strings(json['domains']),
    ips: _strings(json['ips']),
    protocols: _strings(json['protocols']),
    processes: _strings(json['processes']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'action': action.name,
    'domains': domains,
    'ips': ips,
    'protocols': protocols,
    'processes': processes,
  };

  TrafficProfile copyWith({
    String? name,
    TrafficProfileAction? action,
    Iterable<String>? domains,
    Iterable<String>? ips,
    Iterable<String>? protocols,
    Iterable<String>? processes,
  }) => TrafficProfile(
    id: id,
    name: name ?? this.name,
    action: action ?? this.action,
    domains: domains ?? this.domains,
    ips: ips ?? this.ips,
    protocols: protocols ?? this.protocols,
    processes: processes ?? this.processes,
  );

  bool get isEmpty =>
      domains.isEmpty && ips.isEmpty && protocols.isEmpty && processes.isEmpty;

  /// Checks what the App owns; whether Xray accepts each value (a geosite
  /// category, a CIDR) is decided by `testXray` when the profile is saved.
  void validate() {
    if (!custom || id.length <= customPrefix.length) {
      throw const FormatException('Invalid custom profile id');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > maxNameLength) {
      throw const FormatException('A profile needs a name of 1–40 characters');
    }
    if (isEmpty) {
      throw const FormatException('A profile needs a site, address or program');
    }
    for (final list in [domains, ips, protocols, processes]) {
      if (list.length > maxEntries) {
        throw const FormatException('Too many entries in one profile');
      }
      for (final value in list) {
        if (value.trim() != value || value.isEmpty) {
          throw const FormatException('Profile entries cannot be blank');
        }
      }
    }
    for (final value in [...domains, ...ips]) {
      if (value.contains(RegExp(r'\s'))) {
        throw const FormatException('A site or address cannot contain spaces');
      }
    }
    if (protocols.any((value) => !protocolValues.contains(value))) {
      throw const FormatException('Unsupported profile protocol');
    }
  }

  /// One site per line. A bare host means the domain and its subdomains;
  /// Xray itself would read a bare word as a substring match.
  static String normalizeDomain(String input) {
    final value = input.trim();
    if (value.isEmpty || value.contains(':')) return value;
    final host = value.startsWith('*.') ? value.substring(2) : value;
    return host.contains('.') ? 'domain:${host.toLowerCase()}' : value;
  }

  /// Xray compares slash-separated paths and names without `.exe`.
  static String normalizeProcess(String input) =>
      input.trim().replaceAll(r'\', '/');

  static List<String> lines(String text, String Function(String) normalize) => {
    for (final line in text.split(RegExp(r'[\r\n]+')))
      if (normalize(line).isNotEmpty) normalize(line),
  }.toList();
}

/// Profiles chosen on top of the routing mode. Several can be on at once;
/// what they send through the VPN has priority over what they send direct.
final class TrafficProfileSettings {
  static const maxCustom = 5;

  final List<String> _enabled;
  final List<TrafficProfile> _custom;

  const TrafficProfileSettings({
    List<String> enabled = const [],
    List<TrafficProfile> custom = const [],
  }) : _enabled = enabled,
       _custom = custom;

  List<String> get enabled => List.unmodifiable(_enabled);
  List<TrafficProfile> get custom => List.unmodifiable(_custom);

  bool get isDefault => _enabled.isEmpty && _custom.isEmpty;
  bool isEnabled(String id) => _enabled.contains(id);

  factory TrafficProfileSettings.fromJson(Map<String, dynamic> json) =>
      TrafficProfileSettings(
        enabled: _strings(json['enabled']),
        custom: List.unmodifiable([
          for (final value in json['custom'] as List? ?? const [])
            TrafficProfile.fromJson(Map<String, dynamic>.from(value as Map)),
        ]),
      );

  /// Sorted, so the same choice always encodes the same way.
  Map<String, dynamic> toJson() => {
    'enabled': (_enabled.toSet().toList()..sort()),
    'custom': [for (final profile in _custom) profile.toJson()],
  };

  TrafficProfileSettings toggle(String id, bool on) => TrafficProfileSettings(
    enabled: List.unmodifiable({
      ..._enabled.where((value) => value != id),
      if (on) id,
    }),
    custom: _custom,
  );

  TrafficProfileSettings withCustom(TrafficProfile profile) {
    final index = _custom.indexWhere((value) => value.id == profile.id);
    return TrafficProfileSettings(
      enabled: _enabled,
      custom: List.unmodifiable([
        if (index < 0) ...[
          ..._custom,
          profile,
        ] else
          for (final value in _custom) value.id == profile.id ? profile : value,
      ]),
    );
  }

  TrafficProfileSettings withoutCustom(String id) => TrafficProfileSettings(
    enabled: List.unmodifiable(_enabled.where((value) => value != id)),
    custom: List.unmodifiable(_custom.where((value) => value.id != id)),
  );

  String nextCustomId() {
    var next = 1;
    for (final profile in _custom) {
      final number = int.tryParse(
        profile.id.substring(TrafficProfile.customPrefix.length),
      );
      if (number != null && number >= next) next = number + 1;
    }
    return '${TrafficProfile.customPrefix}$next';
  }

  void validate() {
    if (_custom.length > maxCustom) {
      throw const FormatException('At most five custom profiles are allowed');
    }
    if (_custom.map((profile) => profile.id).toSet().length != _custom.length) {
      throw const FormatException('Custom profile ids must be unique');
    }
    for (final profile in _custom) {
      profile.validate();
    }
  }
}

List<String> _strings(Object? value) => List.unmodifiable([
  for (final item in value as List? ?? const []) item as String,
]);
