import 'dart:io';

import 'package:onexray/core/ffi/base_ffi_api.dart';
import 'package:onexray/core/ffi/core_process_monitor.dart';
import 'package:onexray/core/ffi/windows/core_process.dart';
import 'package:onexray/core/ffi/windows/ffi_api.dart';
import 'package:onexray/core/ffi/windows/model.dart';
import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/pigeon/model_reader.dart';
import 'package:onexray/core/system_proxy/manager.dart';
import 'package:onexray/core/system_proxy/platform.dart';
import 'package:onexray/core/tools/app_log.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:path/path.dart' as p;

class WindowsExeFfiApi extends WindowsFfiApi {
  final WindowsCoreProcess _process;
  final String? _filesDirectory;
  final String _corePath;
  final Future<StartVpnRequest> Function() _readRequest;
  final Future<void> Function(VpnStatus) _notify;
  final void Function(Object) _notifyError;
  final Future<SystemProxyManager?> Function(String runDirectory)
  _createSystemProxy;
  Future<SystemProxyManager?>? _systemProxy;
  final Duration _gracefulStop;
  late final _monitor = CoreProcessMonitor(
    discoverPids: _process.findPids,
    watchExit: _process.watchExit,
    canPublish: () => _transition == null,
    notify: (status) async {
      // A Core that exited on its own left the system proxy pointing at a
      // closed port.
      if (status == VpnStatus.disconnected) await _restoreSystemProxy();
      await _notify(status);
    },
    notifyError: _notifyError,
  );
  VpnStatus? _transition;

  WindowsExeFfiApi({
    WindowsCoreProcess? process,
    this._filesDirectory,
    String? executable,
    Future<StartVpnRequest> Function()? readRequest,
    Future<void> Function(VpnStatus)? notify,
    void Function(Object)? notifyError,
    Future<SystemProxyManager?> Function(String runDirectory)? systemProxy,
    this._gracefulStop = const Duration(seconds: 3),
  }) : _process = process ?? WindowsCoreProcess(),
       _createSystemProxy = systemProxy ?? createSystemProxyManager,
       _corePath =
           executable ??
           p.join(
             p.dirname(Platform.resolvedExecutable),
             'HyperClientCore.exe',
           ),
       _readRequest = readRequest ?? StartVpnRequestReader.readFromStartFile,
       _notify = notify ?? AppFlutterApi().vpnStatusChanged,
       _notifyError =
           notifyError ?? AppFlutterApi().vpnStatusController.addError,
       super.base();

  @override
  Future<String> getTunFilesDir() async =>
      _filesDirectory ?? await super.getTunFilesDir();

  @override
  Future<void> ensureRuntime() => checkRuntimeFiles(const [
    'libXray.dll',
    'HyperClientCore.exe',
    'wintun.dll',
  ]);

  @override
  Future<void> observeVpnStatus() async {
    await _monitor.observe();
    // A proxy-mode Core that died with the App, or with the machine, left
    // the system proxy pointing at a closed port. Give the user theirs back.
    if (!await _running()) await _restoreSystemProxy();
  }

  Future<String> _runDirectory() async => p.join(await getTunFilesDir(), 'run');

  Future<SystemProxyManager?> _proxyManager() =>
      _systemProxy ??= _runDirectory().then(_createSystemProxy);

  /// Never fails the caller: a stop or an exit must still complete. The saved
  /// state stays on disk for the next attempt when the restore fails.
  Future<void> _restoreSystemProxy() async {
    try {
      // The manager logs what it handed back or found changed.
      await (await _proxyManager())?.restore();
    } catch (error) {
      AppLog.warning('restore system proxy failed: ${AppLog.reason(error)}');
    }
  }

  @override
  void disposeVpnStatus() => _monitor.dispose();

  Future<bool> _running() async => (await _monitor.readPids()).isNotEmpty;

  @override
  Future<NativeVpnCommandResult> readVpnStatus() async {
    try {
      final running = await _running();
      return commandSuccess(
        status:
            _transition ??
            (running ? VpnStatus.connected : VpnStatus.disconnected),
      );
    } catch (error, stackTrace) {
      return _failed('read', error, stackTrace);
    }
  }

  @override
  Future<bool?> cleanupStaleCore() async {
    // Discover existing named processes; legacy PID files are not consulted.
    final status = await readVpnStatus();
    return status.state == NativeVpnCommandState.success;
  }

  @override
  Future<NativeVpnCommandResult> startVpn({
    String? configYaml,
    WindowsVpnNetworkSettings? networkSettings,
    WindowsVpnPolicy policy = const WindowsVpnPolicy(
      alwaysOn: false,
      allowLocalNetwork: true,
      excludedCidrs: [],
    ),
  }) async {
    _transition = VpnStatus.connecting;
    var launchAttempted = false;
    try {
      await _notify(VpnStatus.connecting);
      await _stop();
      await rotateDesktopCoreLogs(await _runDirectory());
      final request = await _readRequest();
      final proxyPort = desktopSystemProxyPort(request);
      final run = readRunXrayRequest(request);
      final config = await materializeRunXrayConfig(run);
      final xrayJson = run.request.xrayJson;
      if (config == null || xrayJson == null) {
        throw const FormatException('xrayJson is empty');
      }
      // Create as the App user before Windows starts an elevated Core.
      final errorFile = desktopCoreErrorFile(config);
      await errorFile.writeAsString('', flush: true);
      final stopFile = desktopCoreStopFile(await _runDirectory());
      if (await stopFile.exists()) await stopFile.delete();
      final arguments = desktopCoreRunArguments(
        dns: proxyPort == null ? request.tun?.tunDnsIPv4 ?? '' : '',
        interfaceName: proxyPort == null
            ? request.tun?.autoOutboundsInterface ?? ''
            : '',
        configPath: config,
        errorFile: errorFile.path,
        configSha256: desktopCoreConfigSha256(xrayJson),
        stopFile: stopFile.path,
      );
      launchAttempted = true;
      // Only the TUN adapter needs administrator rights; a local proxy does
      // not cost the user a UAC prompt.
      final pid = proxyPort == null
          ? await _process.start(_corePath, arguments)
          : await _process.startUnelevated(_corePath, arguments);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!(await _monitor.readPids()).contains(pid)) {
        throw StateError(
          await readDesktopCoreStartError(
            config,
            'Windows Core exited during start',
          ),
        );
      }
      if (proxyPort != null) {
        final proxy = await _proxyManager();
        await proxy?.apply(
          host: '127.0.0.1',
          port: proxyPort,
          bypass: desktopSystemProxyBypass(request),
        );
      }
      await _notify(VpnStatus.connected);
      return commandSuccess(status: VpnStatus.connected);
    } catch (error, stackTrace) {
      try {
        if (launchAttempted) await _stop();
        if (!await _running()) await _notify(VpnStatus.disconnected);
      } catch (cleanupError) {
        ygLogger('clean up failed Windows Core start: $cleanupError');
      }
      return _failed('start', error, stackTrace);
    } finally {
      _transition = null;
    }
  }

  @override
  Future<NativeVpnCommandResult> stopVpn() async {
    _transition = VpnStatus.disconnecting;
    try {
      await _notify(VpnStatus.disconnecting);
      await _stop();
      await _notify(VpnStatus.disconnected);
      return commandSuccess(status: VpnStatus.disconnected);
    } catch (error, stackTrace) {
      return _failed('stop', error, stackTrace);
    } finally {
      _transition = null;
    }
  }

  Future<void> _stop() async {
    // A denied stop must still retire older queries, but keep live exit watches.
    _monitor.invalidateQueries();
    // Hand the proxy back first, so apps never see a closed local port.
    await _restoreSystemProxy();
    await _stopGracefully();
    await _process.stopAll();
    _monitor.clearWatches();
  }

  /// Asks the Core to exit through its stop file. An elevated Core cannot be
  /// terminated by the App without another UAC prompt; the stop file needs
  /// none. A Core too old to know the flag is terminated as before.
  Future<void> _stopGracefully() async {
    // Created even when nothing runs: it is harmless, and the next start
    // deletes it before launching.
    final stopFile = desktopCoreStopFile(await _runDirectory());
    try {
      await stopFile.create(recursive: true);
    } on FileSystemException catch (error) {
      ygLogger('request graceful Core stop failed: $error');
      return;
    }
    final waiting = Stopwatch()..start();
    while (waiting.elapsed < _gracefulStop) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        if ((await _process.findPids()).isEmpty) return;
      } catch (_) {
        // The terminating stop below reports query failures.
        return;
      }
    }
  }

  NativeVpnCommandResult _failed(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    ygLogger('$operation Windows Core failed: $error\n$stackTrace');
    return commandFailed(error.toString());
  }
}
