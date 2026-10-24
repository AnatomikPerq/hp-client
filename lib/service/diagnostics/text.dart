import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/diagnostics/report.dart';
import 'package:onexray/service/diagnostics/summary.dart';

/// User-facing words for the report, shared by the page and the text export.
abstract final class ReportText {
  static String status(AppLocalizations l, String code) => switch (code) {
    ReportStatus.ok => l.netReportStatusOk,
    ReportStatus.dnsOnly => l.netReportStatusDnsOnly,
    ReportStatus.ipBlocked => l.netReportStatusIpBlocked,
    ReportStatus.sniBlocked => l.netReportStatusSniBlocked,
    ReportStatus.sniWhitelist => l.netReportStatusSniWhitelist,
    ReportStatus.noSniOnly => l.netReportStatusNoSniOnly,
    ReportStatus.tlsBlocked => l.netReportStatusTlsBlocked,
    ReportStatus.mitm => l.netReportStatusMitm,
    ReportStatus.geo => l.netReportStatusGeo,
    ReportStatus.frozen => l.netReportStatusFrozen,
    ReportStatus.slow => l.netReportStatusSlow,
    ReportStatus.stalled => l.netReportStatusStalled,
    ReportStatus.timeout => l.netReportStatusTimeout,
    ReportStatus.reset => l.netReportStatusReset,
    ReportStatus.refused => l.netReportStatusRefused,
    ReportStatus.unreachable => l.netReportStatusUnreachable,
    ReportStatus.closed => l.netReportStatusClosed,
    ReportStatus.alert => l.netReportStatusAlert,
    ReportStatus.certInvalid => l.netReportStatusCertInvalid,
    ReportStatus.error => l.netReportStatusError,
    ReportStatus.skipped || '' => l.netReportStatusSkipped,
    ReportStatus.spoofed => l.netReportStatusSpoofed,
    ReportStatus.injected => l.netReportStatusInjected,
    ReportStatus.nxdomain => l.netReportStatusNxdomain,
    ReportStatus.empty => l.netReportStatusEmpty,
    ReportStatus.blocked => l.netReportStatusBlocked,
    ReportStatus.partial => l.netReportStatusPartial,
    _ => code,
  };

  static String mode(AppLocalizations l, String mode) => switch (mode) {
    NetworkMode.whitelist => l.netReportModeWhitelist,
    NetworkMode.sniWhitelist => l.netReportModeSniWhitelist,
    NetworkMode.filtered => l.netReportModeFiltered,
    NetworkMode.offline => l.netReportModeOffline,
    _ => l.netReportModeOpen,
  };

  /// What a white list mode means for the user, or null for other modes.
  static String? modeDetail(AppLocalizations l, String mode) => switch (mode) {
    NetworkMode.whitelist => l.netReportModeWhitelistDetail,
    NetworkMode.sniWhitelist => l.netReportModeSniWhitelistDetail,
    _ => null,
  };

  static String kind(AppLocalizations l, String kind) => switch (kind) {
    InterfaceKind.ethernet => l.netReportKindEthernet,
    InterfaceKind.wifi => l.netReportKindWifi,
    InterfaceKind.usbTethering => l.netReportKindUsbTethering,
    InterfaceKind.cellular => l.netReportKindCellular,
    InterfaceKind.ppp => 'PPP',
    InterfaceKind.virtual => l.netReportKindVirtual,
    _ => l.netReportKindOther,
  };

  static String section(AppLocalizations l, String section) =>
      switch (section) {
        ReportSection.network => l.netReportSectionNetwork,
        ReportSection.dns => l.netReportSectionDns,
        ReportSection.sites => l.netReportSectionSites,
        ReportSection.hosting => l.netReportSectionHosting,
        ReportSection.udp => l.netReportSectionUdp,
        'sni' => l.netReportSectionSni,
        _ => l.netReportPreparing,
      };

  static String list(Iterable<String> items) => items.join(', ');

  static String advice(AppLocalizations l, ReportAdvice advice) {
    final items = list([
      for (final item in advice.items)
        item == systemResolver ? l.netReportSystemResolver : item,
    ]);
    return switch (advice.code) {
      AdviceCode.realityWhite =>
        advice.items.isEmpty
            ? l.netReportAdviceRealityWhiteAny(list(advice.names))
            : l.netReportAdviceRealityWhite(list(advice.names), items),
      AdviceCode.tls => l.netReportAdviceTls(items),
      AdviceCode.tlsBlocked => l.netReportAdviceTlsBlocked(items),
      AdviceCode.cdn || AdviceCode.cdnBlocked => l.netReportAdviceCdn,
      AdviceCode.udp => l.netReportAdviceUdp,
      AdviceCode.udpPartial => l.netReportAdviceUdpPartial,
      AdviceCode.udpBlocked => l.netReportAdviceUdpBlocked,
      AdviceCode.relay => l.netReportAdviceRelay(items),
      AdviceCode.noSni => l.netReportAdviceNoSni(items),
      AdviceCode.frozen => l.netReportAdviceFrozen(items),
      AdviceCode.dns => l.netReportAdviceDns(items),
      AdviceCode.dnsLoss => l.netReportAdviceDnsLoss(items, advice.percent),
      AdviceCode.fragment => l.netReportAdviceFragment(items),
      AdviceCode.fragmentHosting => l.netReportAdviceFragmentHosting(items),
      AdviceCode.split => l.netReportAdviceSplit(items),
      AdviceCode.bypassUseless => l.netReportAdviceBypassUseless,
      AdviceCode.geo => l.netReportAdviceGeo(items),
    };
  }

  /// "МегаФон · AS25159 · RU, Moscow".
  static String provider(ReportExternal external) => [
    if (external.holder.isNotEmpty) _holderName(external.holder),
    if (external.asn != 0) 'AS${external.asn}',
    [
      external.country,
      external.city,
    ].where((part) => part.isNotEmpty).join(', '),
  ].where((part) => part.isNotEmpty).join(' · ');

  /// RIPE and Cymru write "SONICDUO-AS - PJSC MegaFon, RU"; the part after
  /// the AS handle reads better.
  static String _holderName(String holder) {
    var name = holder;
    final dash = name.indexOf(' - ');
    if (dash > 0) name = name.substring(dash + 3);
    return name.replaceFirst(RegExp(r',\s*[A-Z]{2}$'), '').trim();
  }

  static String dnsSummary(AppLocalizations l, ReportDns dns) {
    final forging = [
      for (final resolver in dns.resolvers)
        if (resolver.forged.isNotEmpty) resolverLabel(l, resolver),
    ];
    return forging.isEmpty
        ? l.netReportDnsClean
        : l.netReportDnsForged(list(forging));
  }

  static String resolverLabel(AppLocalizations l, ReportResolver resolver) {
    if (resolver.system) {
      return resolver.address.isEmpty
          ? l.netReportSystemResolver
          : '${l.netReportSystemResolver} ${resolver.address}';
    }
    return resolver.address.isEmpty
        ? resolver.name
        : '${resolver.name} ${resolver.address}';
  }

  static String sitesSummary(AppLocalizations l, List<ReportSite> sites) {
    final blocked = sites.where((site) => !site.usable).length;
    return l.netReportSitesSummary(blocked, sites.length);
  }

  static String hostingSummary(
    AppLocalizations l,
    List<ReportHosting> hosting,
  ) {
    final open = hosting.where((item) => item.open).length;
    final white = hosting.where((item) => item.openWithWhiteName).length;
    return l.netReportHostingSummary(
      open,
      white,
      hosting.length - open - white,
    );
  }

  static String sniSummary(AppLocalizations l, ReportSni sni) {
    if (!sni.filtered) return l.netReportSniNotFiltered;
    return sni.passed.isEmpty
        ? l.netReportSniNone
        : l.netReportSniPassed(list(sni.passed));
  }

  static String udpSummary(
    AppLocalizations l,
    ReportUdp udp,
    ReportFacts facts,
  ) => 'UDP: ${status(l, facts.udp)} · QUIC: ${status(l, facts.quic)}';

  /// The report as text for a messenger; the JSON file carries the rest.
  static String render(AppLocalizations l, NetworkReport report) {
    final lines = <String>[];
    final started = report.started;
    lines.add(
      [l.netReportTextTitle, if (started != null) _date(started)].join(' · '),
    );
    final network = report.network;
    if (network != null) {
      final parts = <String>[
        if (network.interface case final adapter? when adapter.kind.isNotEmpty)
          kind(l, adapter.kind),
        if (network.provider case final external?) provider(external),
        if (network.ipv4?.ip case final ip? when ip.isNotEmpty) ip,
        if (network.ipv6?.ip case final ip? when ip.isNotEmpty) ip,
      ].where((part) => part.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        lines.add('${l.netReportSectionNetwork}: ${parts.join(' · ')}');
      }
    }
    final facts = report.facts;
    if (facts != null && facts.mode.isNotEmpty) {
      final detail = modeDetail(l, facts.mode);
      lines.add(
        detail == null
            ? mode(l, facts.mode)
            : '${mode(l, facts.mode)}: $detail',
      );
    }
    if (report.dns case final dns?) {
      lines.add('DNS: ${dnsSummary(l, dns)}');
    }
    if (report.sites.isNotEmpty) {
      lines.add('${l.netReportSectionSites}: ${sitesSummary(l, report.sites)}');
      // One line per way of blocking: thirty names in one row do not read.
      final byVerdict = <String, List<String>>{};
      for (final site in report.sites) {
        if (!site.usable) {
          byVerdict.putIfAbsent(site.verdict, () => []).add(site.name);
        }
      }
      for (final MapEntry(key: verdict, value: names) in byVerdict.entries) {
        lines.add('  ${status(l, verdict)}: ${list(names)}');
      }
    }
    if (report.sni case final sni?) {
      lines.add('SNI: ${sniSummary(l, sni)}');
    }
    if (report.hosting.isNotEmpty) {
      lines.add(
        '${l.netReportSectionHosting}: ${hostingSummary(l, report.hosting)}',
      );
      for (final item in report.hosting) {
        final white = item.openWithWhiteName ? ' → ${item.whiteName} ✓' : '';
        lines.add('  ${item.label}: ${status(l, item.verdict)}$white');
      }
    }
    if (report.udp case final udp? when facts != null) {
      lines.add(udpSummary(l, udp, facts));
    }
    final summary = summarizeReport(report);
    for (final (kind, title) in [
      (AdviceKind.works, l.netReportWorks),
      (AdviceKind.fails, l.netReportFails),
      (AdviceKind.note, l.netReportNotes),
    ]) {
      final items = summary.of(kind).toList();
      if (items.isEmpty) continue;
      lines.add('$title:');
      for (final item in items) {
        lines.add('  • ${advice(l, item)}');
      }
    }
    final client = report.raw['client'];
    if (client is Map<String, dynamic>) {
      lines.add('${l.netReportApp}: ${client['app']} · ${client['system']}');
    }
    return lines.join('\n');
  }

  static String _date(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}
