import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:onexray/core/tools/file.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/advanced/tunnel/interface.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/diagnostics/privacy.dart';
import 'package:onexray/service/diagnostics/report.dart';
import 'package:onexray/service/diagnostics/runner.dart';
import 'package:onexray/service/diagnostics/settings.dart';
import 'package:onexray/service/diagnostics/text.dart';
import 'package:onexray/service/shared/share/outgoing_share.dart';

class NetworkReportPageState {
  final bool loaded;
  final NetworkReportSettings settings;
  final List<OutboundInterfaceOption> interfaces;

  /// The interface the next run binds to; empty is the default route.
  final String interfaceName;
  final NetworkReportSnapshot snapshot;

  /// [snapshot] with the settings applied: what the page shows and shares.
  final NetworkReport? report;
  final NetworkReportBlocker? blocker;
  final Set<String> expanded;

  const NetworkReportPageState({
    this.loaded = false,
    this.settings = const NetworkReportSettings(),
    this.interfaces = const [],
    this.interfaceName = '',
    this.snapshot = const NetworkReportSnapshot(),
    this.report,
    this.blocker,
    this.expanded = const {},
  });

  bool get running => snapshot.running;

  NetworkReportPageState copyWith({
    bool? loaded,
    NetworkReportSettings? settings,
    List<OutboundInterfaceOption>? interfaces,
    String? interfaceName,
    NetworkReportSnapshot? snapshot,
    NetworkReport? Function()? report,
    NetworkReportBlocker? Function()? blocker,
    Set<String>? expanded,
  }) => NetworkReportPageState(
    loaded: loaded ?? this.loaded,
    settings: settings ?? this.settings,
    interfaces: interfaces ?? this.interfaces,
    interfaceName: interfaceName ?? this.interfaceName,
    snapshot: snapshot ?? this.snapshot,
    report: report == null ? this.report : report(),
    blocker: blocker == null ? this.blocker : blocker(),
    expanded: expanded ?? this.expanded,
  );
}

class NetworkReportController extends PageCubit<NetworkReportPageState> {
  NetworkReportController({
    NetworkReportRunner? runner,
    OutgoingShare? share,
    Future<List<OutboundInterfaceOption>> Function()? interfaces,
  }) : _runner = runner ?? NetworkReportRunner(),
       _share = share ?? OutgoingShare(),
       _interfaces = interfaces ?? NetworkReportRunner.interfaces,
       super(const NetworkReportPageState()) {
    // Only a phone waits for the VPN to go down (see NetworkReportBlocker).
    if (AppPlatform.isMobile) {
      ConnectionCoordinator.instance.state.addListener(_connectionChanged);
    }
    load();
  }

  final NetworkReportRunner _runner;
  final OutgoingShare _share;
  final Future<List<OutboundInterfaceOption>> Function() _interfaces;
  ReportClient? _client;

  Future<void> load() async {
    final settings = await NetworkReportSettings.read();
    final interfaces = await _interfaces();
    if (!isPageActive) return;
    final current = state.interfaceName;
    emit(
      state.copyWith(
        loaded: true,
        settings: settings,
        interfaces: interfaces,
        interfaceName:
            interfaces.any((option) => option.name == current) || current == ''
            ? (current.isEmpty && interfaces.isNotEmpty
                  ? interfaces.first.name
                  : current)
            : (interfaces.isEmpty ? '' : interfaces.first.name),
        blocker: NetworkReportRunner.blocker,
      ),
    );
  }

  /// Settings changed on the data page: the shown report follows them.
  Future<void> reloadSettings() async {
    final settings = await NetworkReportSettings.read();
    if (!isPageActive) return;
    emit(
      state.copyWith(
        settings: settings,
        report: () =>
            state.snapshot.present(settings, client: _clientFor(settings)),
      ),
    );
  }

  ReportClient? _clientFor(NetworkReportSettings settings) =>
      settings.device ? _client : null;

  void _connectionChanged() {
    emit(state.copyWith(blocker: NetworkReportRunner.blocker));
  }

  void selectInterface(String? name) {
    if (name == null || state.running) return;
    emit(state.copyWith(interfaceName: name));
  }

  Future<void> start() async {
    if (state.running || state.blocker != null) return;
    _client ??= await NetworkReportRunner.client();
    await _runner.start(
      settings: state.settings,
      interfaceName: state.interfaceName,
      onSnapshot: (snapshot) {
        // A failed start or poll keeps the report the run had so far.
        final kept = snapshot.raw == null && !snapshot.running
            ? NetworkReportSnapshot(
                section: snapshot.section,
                raw: state.snapshot.raw,
                error: snapshot.error,
              )
            : snapshot;
        emit(
          state.copyWith(
            snapshot: kept,
            report: () => kept.present(
              state.settings,
              client: _clientFor(state.settings),
            ),
          ),
        );
      },
    );
  }

  Future<void> stop() => _runner.stop();

  Future<void> disconnect() => ConnectionCoordinator.instance.disconnect();

  void toggle(String section) {
    final expanded = {...state.expanded};
    if (!expanded.remove(section)) expanded.add(section);
    emit(state.copyWith(expanded: expanded));
  }

  String? text(AppLocalizations l) {
    final report = state.report;
    return report == null ? null : ReportText.render(l, report);
  }

  Future<void> shareText(AppLocalizations l, {Rect? origin}) async {
    final text = this.text(l);
    if (text == null) return;
    await _share.sendText(
      ShareText(title: l.netReportTitle, text: text),
      origin: origin,
    );
  }

  Future<void> copyText(AppLocalizations l) async {
    final text = this.text(l);
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// The JSON file carries the report with the privacy settings applied.
  Future<bool> saveJson() async {
    final report = state.report;
    if (report == null) return false;
    final bytes = utf8.encode(JsonTool.encoder.convert(report.raw));
    final stamp = report.started ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final name =
        'network-report-${stamp.year}${two(stamp.month)}${two(stamp.day)}-'
        '${two(stamp.hour)}${two(stamp.minute)}.json';
    return FileTool.saveData(Uint8List.fromList(bytes), name, 'json');
  }

  @override
  void disposePageResources() {
    if (AppPlatform.isMobile) {
      ConnectionCoordinator.instance.state.removeListener(_connectionChanged);
    }
    _runner.dispose();
  }
}
