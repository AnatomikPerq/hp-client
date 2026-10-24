import 'dart:async';
import 'dart:io';

import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/service/advanced/tunnel/interface.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/diagnostics/privacy.dart';
import 'package:onexray/service/diagnostics/report.dart';
import 'package:onexray/service/diagnostics/settings.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The libXray calls a run needs, injectable for tests.
abstract interface class NetworkReportHost {
  Future<String> start(StartNetworkReportRequest request);
  Future<NetworkReportStateResponse> state(String id);
  Future<void> cancel(String id);
}

final class _LibXrayReportHost implements NetworkReportHost {
  const _LibXrayReportHost();

  @override
  Future<String> start(StartNetworkReportRequest request) =>
      AppHostApi().startNetworkReport(request);

  @override
  Future<NetworkReportStateResponse> state(String id) =>
      AppHostApi().networkReportState(id);

  @override
  Future<void> cancel(String id) => AppHostApi().cancelNetworkReport(id);
}

/// One snapshot of a run. [raw] is libXray's report as it is; what the page
/// shows and shares is [present]ed with the current settings, so changing
/// them redraws a finished report.
class NetworkReportSnapshot {
  final bool running;
  final String section;
  final int done;
  final int total;
  final Map<String, dynamic>? raw;
  final String? error;

  const NetworkReportSnapshot({
    this.running = false,
    this.section = '',
    this.done = 0,
    this.total = 0,
    this.raw,
    this.error,
  });

  NetworkReport? present(
    NetworkReportSettings settings, {
    ReportClient? client,
  }) => raw == null
      ? null
      : NetworkReport.fromJson(redactReport(raw!, settings, client: client));

  double? get fraction => total == 0 ? null : done / total;
}

/// Why a run cannot start.
enum NetworkReportBlocker {
  /// On a phone the App's own sockets go through a running VPN, so the run
  /// would measure the VPN.
  vpnConnected,
}

class NetworkReportRunner {
  NetworkReportRunner({
    NetworkReportHost? host,
    this.pollInterval = const Duration(milliseconds: 800),
  }) : _host = host ?? const _LibXrayReportHost();

  final NetworkReportHost _host;
  final Duration pollInterval;

  /// "unknown method" from a libXray older than the report.
  static const unsupported = 'unsupported';

  String? _id;
  Timer? _timer;
  bool _polling = false;

  bool get running => _timer != null;

  static NetworkReportBlocker? blocker() {
    if (!AppPlatform.isMobile) return null;
    final phase = ConnectionCoordinator.instance.state.value.phase;
    return phase == ConnectionPhase.disconnected
        ? null
        : NetworkReportBlocker.vpnConnected;
  }

  /// Desktop networks the run can bind to: the physical ones, the tunnel
  /// left out. The current internet one is first.
  static Future<List<OutboundInterfaceOption>> interfaces() async {
    if (!AppPlatform.isDesktop) return const [];
    final options = await queryXrayOutboundInterfaces();
    options.sort(
      (a, b) => (b.currentInternet ? 1 : 0) - (a.currentInternet ? 1 : 0),
    );
    return options;
  }

  /// Starts a run and reports every snapshot to [onSnapshot] until it ends.
  Future<void> start({
    required NetworkReportSettings settings,
    String? interfaceName,
    required void Function(NetworkReportSnapshot snapshot) onSnapshot,
  }) async {
    await stop();
    final String id;
    try {
      id = await _host.start(
        StartNetworkReportRequest(
          interfaceName: interfaceName == null || interfaceName.isEmpty
              ? null
              : interfaceName,
          sections: settings.sections,
          sites: settings.checkSites && settings.extraSites.isNotEmpty
              ? settings.extraSites
              : null,
          maxBytes: settings.maxBytes,
          bypass: settings.bypass,
        ),
      );
    } on LibXrayInvokeException catch (error) {
      onSnapshot(
        NetworkReportSnapshot(
          error: error.message.contains('unknown method')
              ? unsupported
              : error.message,
        ),
      );
      return;
    }
    _id = id;
    onSnapshot(const NetworkReportSnapshot(running: true));
    _timer = Timer.periodic(pollInterval, (_) async {
      if (_polling || _id != id) return;
      _polling = true;
      try {
        final state = await _host.state(id);
        if (_id != id) return;
        final snapshot = readSnapshot(state);
        if (!snapshot.running) _finish();
        onSnapshot(snapshot);
      } on LibXrayInvokeException catch (error) {
        if (_id != id) return;
        _finish();
        onSnapshot(NetworkReportSnapshot(error: error.message));
      } finally {
        _polling = false;
      }
    });
  }

  static NetworkReportSnapshot readSnapshot(NetworkReportStateResponse state) =>
      NetworkReportSnapshot(
        running: state.running,
        section: state.progress?.section ?? '',
        done: state.progress?.done ?? 0,
        total: state.progress?.total ?? 0,
        raw: state.report,
        error: state.error == null || state.error!.isEmpty ? null : state.error,
      );

  /// Cancels a running check; libXray keeps what already finished.
  Future<void> stop() async {
    final id = _id;
    if (id == null || _timer == null) return;
    try {
      await _host.cancel(id);
    } on LibXrayInvokeException {
      // The run already ended.
    }
  }

  void dispose() {
    final id = _id;
    _finish();
    _id = null;
    if (id != null) unawaited(_host.cancel(id).catchError((_) {}));
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
  }

  /// The App and system a report names, when the settings allow it.
  static Future<ReportClient> client() async {
    final version = (await PackageInfo.fromPlatform()).version;
    return ReportClient(
      app: 'HYPER CLIENT $version',
      system: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
  }
}
