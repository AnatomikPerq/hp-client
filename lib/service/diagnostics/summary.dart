import 'package:onexray/service/diagnostics/report.dart';

/// What a report suggests for getting around the blocks, derived only from
/// what it measured. Each advice names the evidence (providers, names,
/// resolvers), so a VPN provider can check it against the details.
enum AdviceKind { works, fails, note }

enum AdviceCode {
  /// REALITY borrowing a name that passes the white list.
  realityWhite,

  /// TLS (VLESS/Trojan, REALITY with a usual name) on open foreign hosting.
  tls,
  tlsBlocked,
  cdn,
  cdnBlocked,
  udp,
  udpPartial,
  udpBlocked,

  /// A relay in a Russian network the white list lets through.
  relay,
  noSni,
  frozen,
  dns,
  dnsLoss,

  /// The App's Fragment (the hello cut into small TLS records) opens
  /// refused sites; for providers it opens TLS with the provider's own name.
  fragment,
  fragmentHosting,

  /// Two TCP segments are enough on their own.
  split,

  /// Cut-up hellos were tried and opened nothing: the filter reassembles
  /// them, so DPI bypass tools would not help.
  bypassUseless,
  geo,
}

class ReportAdvice {
  final AdviceKind kind;
  final AdviceCode code;

  /// Provider labels, server names, resolver or service names.
  final List<String> items;

  /// Names borrowed for [AdviceCode.realityWhite].
  final List<String> names;
  final int percent;

  const ReportAdvice(
    this.kind,
    this.code, {
    this.items = const [],
    this.names = const [],
    this.percent = 0,
  });
}

class ReportSummary {
  final String mode;
  final List<ReportAdvice> advice;

  const ReportSummary(this.mode, this.advice);

  Iterable<ReportAdvice> of(AdviceKind kind) =>
      advice.where((item) => item.kind == kind);
}

const _russianHosting = {'selectel', 'yandex-cloud'};

/// Stands for the network's own resolver in advice items; the text layer
/// names it in the user's language.
const systemResolver = 'system';

ReportSummary summarizeReport(NetworkReport report) {
  final facts = report.facts ?? const ReportFacts();
  final advice = <ReportAdvice>[];
  final hosting = report.hosting;
  final foreign = [
    for (final item in hosting)
      if (item.foreign) item,
  ];

  final whiteNames = report.sni?.filtered == true
      ? report.sni!.passed
      : const <String>[];
  final whiteHosts = [
    for (final item in foreign)
      if (item.openWithWhiteName) item.label,
  ];
  if (whiteNames.isNotEmpty) {
    advice.add(
      ReportAdvice(
        AdviceKind.works,
        AdviceCode.realityWhite,
        items: whiteHosts,
        names: whiteNames,
      ),
    );
  }

  final openForeign = [
    for (final item in foreign)
      if (item.open && item.id != 'cloudflare') item.label,
  ];
  final blockedForeign = [
    for (final item in foreign)
      if (!item.open &&
          item.id != 'cloudflare' &&
          item.verdict != ReportStatus.error &&
          item.verdict.isNotEmpty)
        item.label,
  ];
  if (openForeign.isNotEmpty) {
    advice.add(
      ReportAdvice(AdviceKind.works, AdviceCode.tls, items: openForeign),
    );
  }
  if (blockedForeign.isNotEmpty) {
    advice.add(
      ReportAdvice(
        AdviceKind.fails,
        AdviceCode.tlsBlocked,
        items: blockedForeign,
      ),
    );
  }

  for (final item in hosting) {
    if (item.id != 'cloudflare' || item.verdict.isEmpty) continue;
    advice.add(
      item.open
          ? const ReportAdvice(AdviceKind.works, AdviceCode.cdn)
          : const ReportAdvice(AdviceKind.fails, AdviceCode.cdnBlocked),
    );
  }

  switch (facts.udp) {
    case ReportStatus.ok:
      advice.add(const ReportAdvice(AdviceKind.works, AdviceCode.udp));
    case ReportStatus.partial:
      advice.add(const ReportAdvice(AdviceKind.note, AdviceCode.udpPartial));
    case ReportStatus.blocked:
      advice.add(const ReportAdvice(AdviceKind.fails, AdviceCode.udpBlocked));
  }

  if (NetworkMode.restricted(facts.mode)) {
    final relays = [
      for (final item in hosting)
        if (_russianHosting.contains(item.id) &&
            (item.open || item.openWithWhiteName))
          item.label,
    ];
    if (relays.isNotEmpty) {
      advice.add(
        ReportAdvice(AdviceKind.works, AdviceCode.relay, items: relays),
      );
    }
  }

  final noSni = [
    for (final item in hosting)
      if (item.verdict == ReportStatus.noSniOnly) item.label,
  ];
  if (noSni.isNotEmpty) {
    advice.add(ReportAdvice(AdviceKind.note, AdviceCode.noSni, items: noSni));
  }

  final frozen = [
    for (final item in hosting)
      if (item.verdict == ReportStatus.frozen) item.label,
    for (final item in report.sites)
      if (item.verdict == ReportStatus.frozen) item.name,
  ];
  if (frozen.isNotEmpty) {
    advice.add(
      ReportAdvice(AdviceKind.fails, AdviceCode.frozen, items: frozen),
    );
  }

  final resolvers = report.dns?.resolvers ?? const <ReportResolver>[];
  final forging = [
    for (final resolver in resolvers)
      if (resolver.forged.isNotEmpty)
        resolver.system ? systemResolver : resolver.name,
  ];
  if (forging.isNotEmpty) {
    advice.add(ReportAdvice(AdviceKind.note, AdviceCode.dns, items: forging));
  }
  for (final resolver in resolvers) {
    if (resolver.status == ReportStatus.ok && resolver.lossPct >= 20) {
      advice.add(
        ReportAdvice(
          AdviceKind.note,
          AdviceCode.dnsLoss,
          items: [resolver.address.isEmpty ? resolver.name : resolver.address],
          percent: resolver.lossPct,
        ),
      );
    }
  }

  final fragmentSites = [
    for (final site in report.sites)
      if (site.fragmentHelps) site.name,
  ];
  final fragmentHosts = [
    for (final item in hosting)
      if (item.fragmentHelps) item.label,
  ];
  final split = [
    for (final site in report.sites)
      if (!site.usable && bypassWorks(site.split, null)) site.name,
  ];
  if (fragmentSites.isNotEmpty) {
    advice.add(
      ReportAdvice(AdviceKind.works, AdviceCode.fragment, items: fragmentSites),
    );
  }
  if (fragmentHosts.isNotEmpty) {
    advice.add(
      ReportAdvice(
        AdviceKind.works,
        AdviceCode.fragmentHosting,
        items: fragmentHosts,
      ),
    );
  }
  if (split.isNotEmpty) {
    advice.add(ReportAdvice(AdviceKind.note, AdviceCode.split, items: split));
  }
  if (facts.bypassTried > 0 &&
      fragmentSites.isEmpty &&
      fragmentHosts.isEmpty &&
      split.isEmpty) {
    advice.add(const ReportAdvice(AdviceKind.note, AdviceCode.bypassUseless));
  }

  final geo = [
    for (final site in report.sites)
      if (site.verdict == ReportStatus.geo) site.name,
  ];
  if (geo.isNotEmpty) {
    advice.add(ReportAdvice(AdviceKind.note, AdviceCode.geo, items: geo));
  }
  return ReportSummary(facts.mode, advice);
}
