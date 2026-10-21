import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/connect/routing/profiles/profile.dart';

/// What the compiler may reference for the enabled profiles.
final class TrafficProfileContext {
  /// Installed codes of the default geosite.dat and geoip.dat, upper case.
  /// Built-in profiles drop categories that are missing, as a missing code
  /// stops the Core. Null leaves them unchecked (validation, tests).
  final Set<String>? geositeCodes;
  final Set<String>? geoipCodes;

  /// The runetfreedom lists are in the Geodata directory.
  final bool ruBlocked;

  /// The Core runs on a desktop and can look up a connection's program.
  final bool processes;

  const TrafficProfileContext({
    this.geositeCodes,
    this.geoipCodes,
    this.ruBlocked = false,
    this.processes = false,
  });

  TrafficProfileContext withProcesses(bool value) => TrafficProfileContext(
    geositeCodes: geositeCodes,
    geoipCodes: geoipCodes,
    ruBlocked: ruBlocked,
    processes: value,
  );
}

abstract final class TrafficProfiles {
  static const ruBlocked = 'ru-blocked';
  static const ai = 'ai';
  static const discord = 'discord';
  static const youtube = 'youtube';
  static const messengers = 'messengers';
  static const games = 'games';
  static const torrents = 'torrents';

  /// The runetfreedom category, kept in two App-managed Geodata files.
  static const ruBlockedCode = 'RU-BLOCKED';
  static const ruBlockedDomainFile = 'ru-blocked-domains.dat';
  static const ruBlockedIpFile = 'ru-blocked-ips.dat';
  static const ruBlockedDomains = 'ext:$ruBlockedDomainFile:$ruBlockedCode';
  static const ruBlockedIps = 'ext:$ruBlockedIpFile:$ruBlockedCode';

  /// Selective mode sends what matches no profile here.
  static const selectiveDirectTag = 'app-selective-direct';

  // Process names are matched exactly (Xray drops `.exe` on both sides), so
  // they follow each program's own spelling on Windows; Linux binaries
  // without the suffix match the same entries.
  static final List<TrafficProfile> builtIn = List.unmodifiable([
    TrafficProfile(
      id: ruBlocked,
      action: TrafficProfileAction.proxy,
      domains: const [ruBlockedDomains],
      ips: const [ruBlockedIps],
    ),
    TrafficProfile(
      id: ai,
      action: TrafficProfileAction.proxy,
      domains: const [
        'geosite:CATEGORY-AI-!CN',
        'geosite:OPENAI',
        'geosite:ANTHROPIC',
        'geosite:GOOGLE-GEMINI',
        'geosite:GOOGLE-DEEPMIND',
        'geosite:PERPLEXITY',
        'geosite:XAI',
        'geosite:GITHUB-COPILOT',
        'geosite:CURSOR',
        'geosite:HUGGINGFACE',
      ],
      processes: const [
        'claude.exe',
        'ChatGPT.exe',
        'Perplexity.exe',
        'Cursor.exe',
      ],
    ),
    TrafficProfile(
      id: discord,
      action: TrafficProfileAction.proxy,
      domains: const ['geosite:DISCORD'],
      processes: const ['Discord.exe', 'DiscordPTB.exe', 'DiscordCanary.exe'],
    ),
    TrafficProfile(
      id: youtube,
      action: TrafficProfileAction.proxy,
      domains: const ['geosite:YOUTUBE'],
    ),
    TrafficProfile(
      id: messengers,
      action: TrafficProfileAction.proxy,
      domains: const ['geosite:TELEGRAM', 'geosite:WHATSAPP', 'geosite:SIGNAL'],
      // Telegram connects to its own addresses without a name to sniff;
      // https://core.telegram.org/resources/cidr.txt
      ips: const [
        '91.105.192.0/23',
        '91.108.4.0/22',
        '91.108.8.0/22',
        '91.108.12.0/22',
        '91.108.16.0/22',
        '91.108.20.0/22',
        '91.108.56.0/22',
        '149.154.160.0/20',
        '185.76.151.0/24',
        '2001:67c:4e8::/48',
        '2001:b28:f23c::/48',
        '2001:b28:f23d::/48',
        '2001:b28:f23f::/48',
        '2a0a:f280::/32',
      ],
      processes: const [
        'Telegram.exe',
        'telegram-desktop',
        'WhatsApp.exe',
        'WhatsApp.Root.exe',
        'Signal.exe',
      ],
    ),
    TrafficProfile(
      id: games,
      action: TrafficProfileAction.direct,
      domains: const ['geosite:CATEGORY-GAMES'],
      processes: const [
        'steam.exe',
        'steamwebhelper.exe',
        'EpicGamesLauncher.exe',
        'Battle.net.exe',
        'RiotClientServices.exe',
        'EADesktop.exe',
      ],
    ),
    TrafficProfile(
      id: torrents,
      action: TrafficProfileAction.direct,
      protocols: const ['bittorrent'],
      processes: const [
        'qbittorrent.exe',
        'uTorrent.exe',
        'BitTorrent.exe',
        'transmission-qt.exe',
        'tixati.exe',
        'deluge.exe',
      ],
    ),
  ]);

  static TrafficProfile? find(TrafficProfileSettings settings, String id) {
    for (final profile in [...builtIn, ...settings.custom]) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  /// Enabled profiles, built-ins first; unknown ids are ignored.
  static List<TrafficProfile> active(TrafficProfileSettings settings) => [
    for (final profile in [...builtIn, ...settings.custom])
      if (settings.isEnabled(profile.id)) profile,
  ];

  static bool usesRuBlocked(TrafficProfileSettings settings) =>
      settings.isEnabled(ruBlocked);

  /// Rules for the enabled profiles of [actions], VPN before direct, so a
  /// site one profile sends through the VPN never leaves directly because
  /// another sends it direct. Each kind of condition is one rule per
  /// direction: a program lookup costs a connection-table read per rule.
  ///
  /// [lanGuard] keeps the local network direct ahead of program rules, which
  /// would otherwise catch a profiled program's traffic to the LAN too.
  static List<XrayRoutingRule> rules(
    TrafficProfileSettings settings, {
    required TrafficProfileContext context,
    Set<TrafficProfileAction> actions = const {
      TrafficProfileAction.proxy,
      TrafficProfileAction.direct,
    },
    bool lanGuard = true,
  }) {
    final profiles = active(settings);
    final rules = <XrayRoutingRule>[];
    for (final action in TrafficProfileAction.values) {
      if (!actions.contains(action)) continue;
      final matching = profiles.where((profile) => profile.action == action);
      final domains = <String>{
        for (final profile in matching)
          ...profile.domains.where(
            (value) => _available(value, profile, context, domain: true),
          ),
      }.toList();
      final ips = <String>{
        for (final profile in matching)
          ...profile.ips.where(
            (value) => _available(value, profile, context, domain: false),
          ),
      }.toList();
      final protocols = <String>{
        for (final profile in matching) ...profile.protocols,
      }.toList();
      final processes = context.processes
          ? <String>{for (final profile in matching) ...profile.processes}
                .toList()
          : const <String>[];
      final via = action == TrafficProfileAction.proxy;
      XrayRoutingRule rule(String kind) => XrayRoutingRule(
        ruleTag: 'app-profiles-${action.name}-$kind',
        balancerTag: via ? 'proxy' : null,
        outboundTag: via ? null : 'direct',
      );
      if (via && processes.isNotEmpty && lanGuard) {
        rules.addAll(privateDirect('app-profiles-lan', context));
      }
      if (domains.isNotEmpty) rules.add(rule('domain')..domain = domains);
      if (ips.isNotEmpty) rules.add(rule('ip')..ip = ips);
      if (protocols.isNotEmpty) {
        rules.add(rule('protocol')..protocol = protocols);
      }
      if (processes.isNotEmpty) rules.add(rule('process')..process = processes);
    }
    return rules;
  }

  /// The local network and private names, direct.
  static List<XrayRoutingRule> privateDirect(
    String tag,
    TrafficProfileContext context,
  ) => [
    if (context.geositeCodes?.contains('PRIVATE') ?? true)
      XrayRoutingRule(
        ruleTag: '$tag-domain',
        domain: ['geosite:PRIVATE'],
        outboundTag: 'direct',
      ),
    if (context.geoipCodes?.contains('PRIVATE') ?? true)
      XrayRoutingRule(
        ruleTag: '$tag-ip',
        ip: ['geoip:PRIVATE'],
        outboundTag: 'direct',
      ),
  ];

  static bool _available(
    String value,
    TrafficProfile profile,
    TrafficProfileContext context, {
    required bool domain,
  }) {
    if (value == ruBlockedDomains || value == ruBlockedIps) {
      return context.ruBlocked;
    }
    if (profile.custom) return true;
    final prefix = domain ? 'geosite:' : 'geoip:';
    if (!value.startsWith(prefix)) return true;
    final codes = domain ? context.geositeCodes : context.geoipCodes;
    return codes?.contains(value.substring(prefix.length).toUpperCase()) ??
        true;
  }
}
