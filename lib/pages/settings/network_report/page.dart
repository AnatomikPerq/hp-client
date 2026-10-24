import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/settings/network_report/controller.dart';
import 'package:onexray/pages/settings/network_report/widgets.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/diagnostics/report.dart';
import 'package:onexray/service/diagnostics/runner.dart';
import 'package:onexray/service/diagnostics/summary.dart';
import 'package:onexray/service/diagnostics/text.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class NetworkReportPage extends StatelessWidget {
  const NetworkReportPage({super.key, this.createController});

  final NetworkReportController Function()? createController;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => createController?.call() ?? NetworkReportController(),
    child: BlocBuilder<NetworkReportController, NetworkReportPageState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final controller = context.read<NetworkReportController>();
        final width = MediaQuery.sizeOf(context).width;
        final mobile = width <= AppLayout.mobileBreakpoint;
        final gutter = mobile ? 12.0 : AppSpacing.advancedDesktopGutter(width);
        final report = state.report;
        return Scaffold(
          appBar: PageAppBar(
            title: Text(l.netReportTitle),
            actions: [
              if (report != null && !state.running)
                _ShareMenu(controller: controller),
              IconButton(
                tooltip: l.netReportSettingsTitle,
                icon: const Icon(LucideIcons.settings2),
                onPressed: () async {
                  await context.pushScoped(
                    AppPageDestination.networkReportSettings,
                  );
                  await controller.reloadSettings();
                },
              ),
            ],
          ),
          body: SafeArea(
            child: !state.loaded
                ? const Center(child: CircularProgressIndicator())
                : SettingsPageScroll(
                    desktopMaxWidth: AppLayout.advancedMaxWidth,
                    padding: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        mobile ? 12 : 32,
                        gutter,
                        mobile ? 24 : 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Controls(state: state, controller: controller),
                          if (report != null) ...[
                            const SizedBox(height: 16),
                            if (report.facts != null) ...[
                              _SummaryCard(report: report),
                              const SizedBox(height: 16),
                            ],
                            ..._sections(context, state, controller, report),
                            if (report.durationMs > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  l.netReportDuration(
                                    (report.durationMs / 1000).round(),
                                  ),
                                  textAlign: TextAlign.center,
                                  style: AppTypography.settingsHint.copyWith(
                                    color: ColorManager.palette(context)
                                        .mutedForeground,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    ),
  );

  List<Widget> _sections(
    BuildContext context,
    NetworkReportPageState state,
    NetworkReportController controller,
    NetworkReport report,
  ) {
    final l = AppLocalizations.of(context)!;
    final settings = state.settings;
    final cards = <Widget>[];
    void add(
      String id,
      IconData icon,
      String title,
      String summary,
      ReportTone tone,
      List<Widget> rows,
    ) {
      if (cards.isNotEmpty) cards.add(const SizedBox(height: 10));
      cards.add(
        ReportSectionCard(
          key: ValueKey('network-report-$id'),
          icon: icon,
          title: title,
          summary: summary,
          tone: tone,
          expanded: state.expanded.contains(id),
          onToggle: () => controller.toggle(id),
          children: rows,
        ),
      );
    }

    if (report.network case final network?) {
      final provider = network.provider;
      add(
        ReportSection.network,
        LucideIcons.network,
        l.netReportSectionNetwork,
        [
          if (network.interface?.kind case final kind? when kind.isNotEmpty)
            ReportText.kind(l, kind),
          if (provider != null) ReportText.provider(provider),
        ].where((part) => part.isNotEmpty).join(' · '),
        ReportTone.neutral,
        _networkRows(l, network, settings.details),
      );
    }
    if (report.dns case final dns?) {
      final forged = dns.resolvers.any((item) => item.forged.isNotEmpty);
      add(
        ReportSection.dns,
        LucideIcons.globe,
        l.netReportSectionDns,
        ReportText.dnsSummary(l, dns),
        forged || dns.port53Intercepted ? ReportTone.bad : ReportTone.good,
        [
          if (dns.port53Intercepted)
            ReportRow(title: l.netReportPort53, status: ReportStatus.spoofed),
          for (final resolver in dns.resolvers)
            _resolverRow(l, resolver, settings.details),
        ],
      );
    }
    if (report.sites.isNotEmpty) {
      final blocked = report.sites.where((site) => !site.usable).length;
      add(
        ReportSection.sites,
        LucideIcons.listChecks,
        l.netReportSectionSites,
        ReportText.sitesSummary(l, report.sites),
        blocked == 0 ? ReportTone.good : ReportTone.bad,
        [
          for (final site in report.sites)
            if (!settings.hidePassed || !site.usable)
              ReportRow(
                title: settings.details
                    ? '${site.name} · ${site.host}'
                    : site.name,
                subtitle: [
                  if (site.fragmentHelps) 'Fragment ✓',
                  if (settings.details) _siteDetail(l, site),
                ].join(' · '),
                status: site.verdict,
              ),
        ],
      );
    }
    if (report.sni case final sni?) {
      add(
        'sni',
        LucideIcons.lockKeyhole,
        l.netReportSectionSni,
        ReportText.sniSummary(l, sni),
        !sni.filtered
            ? ReportTone.good
            : (sni.passed.isEmpty ? ReportTone.bad : ReportTone.warning),
        [
          for (final name in sni.passed)
            ReportRow(title: name, status: ReportStatus.ok),
          if (!settings.hidePassed || sni.passed.isEmpty)
            for (final name in sni.failed)
              ReportRow(title: name, status: ReportStatus.blocked),
        ],
      );
    }
    if (report.hosting.isNotEmpty) {
      final open = report.hosting.where((item) => item.open).length;
      add(
        ReportSection.hosting,
        LucideIcons.server,
        l.netReportSectionHosting,
        ReportText.hostingSummary(l, report.hosting),
        open == report.hosting.length
            ? ReportTone.good
            : (open == 0 ? ReportTone.bad : ReportTone.warning),
        [
          for (final item in report.hosting)
            if (!settings.hidePassed || !item.open)
              ReportRow(
                title: item.label,
                subtitle: [
                  if (item.openWithWhiteName) '${item.whiteName} ✓',
                  if (item.fragmentHelps) 'Fragment ✓',
                  if (settings.details) _hostingDetail(l, item),
                ].join(' · '),
                // Closed to its own name but open to an allowed one: a way
                // through, not a dead end.
                status: item.openWithWhiteName
                    ? ReportStatus.partial
                    : item.verdict,
                statusLabel: item.openWithWhiteName
                    ? ReportText.status(l, item.verdict)
                    : null,
              ),
        ],
      );
    }
    if (report.udp case final udp?) {
      final facts = report.facts ?? const ReportFacts();
      add(
        ReportSection.udp,
        LucideIcons.radio,
        l.netReportSectionUdp,
        ReportText.udpSummary(l, udp, facts),
        toneOf(facts.udp == ReportStatus.blocked ? 'blocked' : facts.udp),
        [
          for (final probe in udp.stun)
            if (!settings.hidePassed || probe.status != ReportStatus.ok)
              ReportRow(
                title: 'STUN · ${probe.name}',
                subtitle: settings.details && probe.ms > 0
                    ? '${probe.ms} ms'
                    : null,
                status: probe.status,
              ),
          for (final probe in udp.quic)
            if (!settings.hidePassed || !ReportStatus.reached(probe.status))
              ReportRow(
                title: 'QUIC · ${probe.name}',
                subtitle: settings.details && probe.ms > 0
                    ? '${probe.ms} ms'
                    : null,
                status: probe.status,
              ),
          if (udp.symmetricNat == true)
            ReportRow(title: l.netReportNat, status: ReportStatus.partial),
        ],
      );
    }
    return cards;
  }

  List<Widget> _networkRows(
    AppLocalizations l,
    ReportNetwork network,
    bool details,
  ) {
    final adapter = network.interface;
    final provider = network.provider;
    return [
      if (adapter != null && adapter.kind.isNotEmpty)
        ReportFact(l.netReportConnection, ReportText.kind(l, adapter.kind)),
      if (provider != null && ReportText.provider(provider).isNotEmpty)
        ReportFact(l.netReportProvider, ReportText.provider(provider)),
      for (final external in [network.ipv4, network.ipv6])
        if (external != null && external.ip.isNotEmpty)
          ReportFact(l.netReportAddress, external.ip),
      if (adapter != null && adapter.name.isNotEmpty)
        ReportFact(
          l.netReportAdapter,
          [
            adapter.name,
            if (adapter.description.isNotEmpty) adapter.description,
            if (details && adapter.mtu > 0) 'MTU ${adapter.mtu}',
          ].join(' · '),
        ),
      if (adapter != null && adapter.dns.isNotEmpty)
        ReportFact(l.netReportDnsServers, adapter.dns.join(', ')),
    ];
  }

  Widget _resolverRow(
    AppLocalizations l,
    ReportResolver resolver,
    bool details,
  ) {
    final forged = resolver.forged;
    final parts = <String>[
      for (final name in forged)
        '${name.name}: ${ReportText.status(l, name.status)}',
      if (resolver.intercepted) l.netReportIntercepted,
      if (resolver.lossPct > 0) l.netReportLoss(resolver.lossPct),
      if (details && resolver.rttMs > 0) '${resolver.rttMs} ms',
      if (details && resolver.egressHolder.isNotEmpty) resolver.egressHolder,
      if (details && resolver.doh != null)
        'DoH: ${ReportText.status(l, resolver.doh!.status)}',
    ];
    return ReportRow(
      title: ReportText.resolverLabel(l, resolver),
      subtitle: parts.join('\n'),
      status: forged.isNotEmpty
          ? (forged.any((name) => name.status == ReportStatus.injected)
                ? ReportStatus.injected
                : ReportStatus.spoofed)
          : (resolver.intercepted ? ReportStatus.blocked : resolver.status),
    );
  }

  static String _step(AppLocalizations l, String label, ReportStep? step) =>
      step == null ? '' : '$label ${ReportText.status(l, step.status)}';

  String _siteDetail(AppLocalizations l, ReportSite site) {
    final http = site.http;
    return [
      'DNS ${ReportText.status(l, site.dns)}',
      _step(l, 'TCP', site.tcp),
      _step(l, 'TLS', site.tls),
      _step(l, 'SNI ∅', site.noSni),
      _step(l, 'SNI ?', site.randomSni),
      if (site.whiteName.isNotEmpty)
        _step(l, 'SNI ${site.whiteName}', site.whiteSni),
      _step(l, 'split', site.split),
      _step(l, 'Fragment', site.fragment),
      if (http != null)
        'HTTP ${http.http} · ${(http.bytes / 1024).toStringAsFixed(0)} KB',
      _step(l, 'QUIC', site.quic),
    ].where((part) => part.isNotEmpty).join(' · ');
  }

  String _hostingDetail(AppLocalizations l, ReportHosting item) {
    final transfer = item.transfer ?? item.whiteTransfer;
    return [
      _step(l, 'TLS', item.tls),
      _step(l, 'SNI ∅', item.noSni),
      _step(l, 'SNI ?', item.randomSni),
      _step(l, 'split', item.split),
      _step(l, 'Fragment', item.fragment),
      if (item.whiteName.isNotEmpty)
        _step(l, 'SNI ${item.whiteName}', item.whiteSni),
      if (transfer != null && transfer.rxBytes > 0)
        '${(transfer.rxBytes / 1024).toStringAsFixed(0)} KB'
            '${transfer.kbps > 0 ? ' · ${transfer.kbps} KB/s' : ''}',
    ].where((part) => part.isNotEmpty).join(' · ');
  }
}

class _Controls extends StatelessWidget {
  final NetworkReportPageState state;
  final NetworkReportController controller;

  const _Controls({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final error = state.snapshot.error;
    final noChecks = state.settings.sections.length <= 1;
    final notice = switch ((state.blocker, error)) {
      (NetworkReportBlocker.vpnConnected, _) => l.netReportVpnConnected,
      (_, NetworkReportRunner.unsupported) => l.netReportUnsupported,
      (_, final String reason) => l.netReportFailed(reason),
      _ when noChecks => l.netReportNoChecks,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.interfaces.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.card,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: SettingRow(
              title: l.netReportInterface,
              titleStyle: AppTypography.settingsRow,
              leading: const Icon(LucideIcons.cable),
              contentPadding: const EdgeInsetsDirectional.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              trailing: SettingSelect<String>(
                value: state.interfaceName,
                entries: {
                  for (final option in state.interfaces)
                    option.name: option.addresses.isEmpty
                        ? option.name
                        : '${option.name} · ${option.addresses.first}',
                },
                onChanged: state.running ? null : controller.selectInterface,
              ),
            ),
          ),
        if (state.interfaces.isNotEmpty) const SizedBox(height: 14),
        if (state.running) ...[
          LinearProgressIndicator(
            value: state.snapshot.fraction,
            minHeight: 4,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          const SizedBox(height: 8),
          Text(
            state.snapshot.total == 0
                ? l.netReportPreparing
                : l.netReportProgress(
                    ReportText.section(l, state.snapshot.section),
                    state.snapshot.done,
                    state.snapshot.total,
                  ),
            style: AppTypography.settingsHint.copyWith(
              color: palette.mutedForeground,
            ),
          ),
          const SizedBox(height: 12),
        ] else if (state.report == null && notice == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              l.netReportIntro(state.settings.saveTraffic ? 3 : 8),
              style: AppTypography.settingsNote.copyWith(
                color: palette.mutedForeground,
              ),
            ),
          ),
        if (notice != null)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.warningSurface,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                notice,
                style: AppTypography.settingsNote.copyWith(
                  color: palette.foreground,
                ),
              ),
            ),
          ),
        Wrap(
          alignment: mobile ? WrapAlignment.center : WrapAlignment.start,
          spacing: 10,
          runSpacing: 10,
          children: [
            if (state.blocker == NetworkReportBlocker.vpnConnected)
              OutlinedButton(
                onPressed: controller.disconnect,
                child: Text(l.netReportDisconnect),
              ),
            if (state.running)
              OutlinedButton.icon(
                onPressed: controller.stop,
                icon: const ButtonProgressIndicator(size: 14),
                label: Text(l.netReportStop),
              )
            else
              FilledButton.icon(
                onPressed: state.blocker != null || noChecks
                    ? null
                    : controller.start,
                icon: const Icon(LucideIcons.stethoscope, size: 16),
                label: Text(
                  state.report == null ? l.netReportStart : l.netReportRerun,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final NetworkReport report;

  const _SummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final summary = summarizeReport(report);
    final mode = summary.mode;
    final tone = switch (mode) {
      NetworkMode.whitelist ||
      NetworkMode.sniWhitelist ||
      NetworkMode.offline => ReportTone.bad,
      NetworkMode.filtered => ReportTone.warning,
      _ => ReportTone.good,
    };
    final network = report.network;
    final subtitle = [
      if (network?.interface?.kind case final kind? when kind.isNotEmpty)
        ReportText.kind(l, kind),
      if (network?.provider case final provider?) ReportText.provider(provider),
    ].where((part) => part.isNotEmpty).join(' · ');
    Widget group(AdviceKind kind, String title, IconData icon, Color color) {
      final items = summary.of(kind).toList();
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: AppTypography.rowTitle.copyWith(color: color),
                ),
              ],
            ),
            for (final item in items)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 21, top: 4),
                child: SelectableText(
                  ReportText.advice(l, item),
                  style: AppTypography.rowValue.copyWith(
                    color: palette.foreground,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('network-report-summary'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: toneSurface(palette, tone),
        borderRadius: BorderRadius.circular(AppRadii.dialog),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(switch (mode) {
                NetworkMode.whitelist ||
                NetworkMode.sniWhitelist => LucideIcons.shieldAlert,
                NetworkMode.offline => LucideIcons.wifiOff,
                NetworkMode.filtered => LucideIcons.triangleAlert,
                _ => LucideIcons.circleCheck,
              }, color: toneColor(palette, tone)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ReportText.mode(l, mode),
                  style: AppTypography.panelTitle.copyWith(
                    color: palette.foreground,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: AppTypography.settingsHint.copyWith(
                color: palette.mutedStrong,
              ),
            ),
          ],
          if (ReportText.modeDetail(l, mode) case final detail?) ...[
            const SizedBox(height: 6),
            Text(
              detail,
              style: AppTypography.settingsNote.copyWith(
                color: palette.foreground,
              ),
            ),
          ],
          group(
            AdviceKind.works,
            l.netReportWorks,
            LucideIcons.circleCheck,
            palette.running,
          ),
          group(
            AdviceKind.fails,
            l.netReportFails,
            LucideIcons.circleX,
            palette.destructive,
          ),
          group(
            AdviceKind.note,
            l.netReportNotes,
            LucideIcons.circleAlert,
            palette.mutedStrong,
          ),
        ],
      ),
    );
  }
}

class _ShareMenu extends StatelessWidget {
  final NetworkReportController controller;

  const _ShareMenu({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      tooltip: l.netReportShareText,
      icon: const Icon(LucideIcons.share2),
      onSelected: (action) async {
        switch (action) {
          case 'share':
            final box = context.findRenderObject() as RenderBox?;
            final origin = box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size;
            await controller.shareText(l, origin: origin);
          case 'copy':
            await controller.copyText(l);
            if (context.mounted) {
              ContextAlert.showToast(context, l.netReportCopied);
            }
          case 'json':
            await controller.saveJson();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'share',
          child: ListTile(
            leading: const Icon(LucideIcons.share2),
            title: Text(l.netReportShareText),
          ),
        ),
        PopupMenuItem(
          value: 'copy',
          child: ListTile(
            leading: const Icon(LucideIcons.copy),
            title: Text(l.netReportCopyText),
          ),
        ),
        PopupMenuItem(
          value: 'json',
          child: ListTile(
            leading: const Icon(LucideIcons.fileJson),
            title: Text(l.netReportSaveJson),
          ),
        ),
      ],
    );
  }
}
