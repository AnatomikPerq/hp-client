import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/ffi/base_ffi_api.dart';
import 'package:onexray/core/ffi/core_process_monitor.dart';
import 'package:onexray/core/ffi/desktop_kill_switch.dart';
import 'package:onexray/core/ffi/desktop_core_exit.dart';
import 'package:onexray/core/ffi/linux_core_exit.dart';
import 'package:onexray/core/model/tun_json.dart';
import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/pigeon/model_reader.dart';
import 'package:onexray/core/system_proxy/manager.dart';
import 'package:onexray/core/system_proxy/platform.dart';
import 'package:onexray/core/tools/app_log.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:path/path.dart' as p;

class LinuxFfiApi extends BaseFfiApi {
  static final LinuxFfiApi _singleton = LinuxFfiApi._internal();

  factory LinuxFfiApi() => _singleton;

  LinuxFfiApi._internal()
    : _filesDirectory = null,
      _executablePath = null,
      _runCommand = Process.run,
      _startProcess = Process.start,
      _readRequest = StartVpnRequestReader.readFromStartFile,
      _watchExit = watchLinuxCoreExit,
      _notify = AppFlutterApi().vpnStatusChanged,
      _notifyError = AppFlutterApi().vpnStatusController.addError,
      _createSystemProxy = createSystemProxyManager,
      _injectedKillSwitch = null,
      _readyTimeout = desktopCoreReadyTimeout;

  @visibleForTesting
  LinuxFfiApi.forTesting({
    required String this._filesDirectory,
    required this._executablePath,
    required this._runCommand,
    required this._watchExit,
    Future<Process> Function(String, List<String>)? startProcess,
    Future<StartVpnRequest> Function()? readRequest,
    Future<void> Function(VpnStatus)? notify,
    void Function(Object)? notifyError,
    Future<SystemProxyManager?> Function(String runDirectory)? systemProxy,
    DesktopKillSwitchControl? killSwitch,
    this._readyTimeout = desktopCoreReadyTimeout,
  }) : _createSystemProxy = systemProxy ?? ((_) async => null),
       // Tests have no libXray: a kill switch with no filters by default.
       _injectedKillSwitch =
           killSwitch ??
           DesktopKillSwitchControl(
             runDirectory: () async => p.join(_filesDirectory, 'run'),
             invoke: (_) async =>
                 '{"success":true,"data":{"engaged":false,'
                 '"session":{"bootedAt":0,"logon":""}},"error":""}',
           ),
       _startProcess = startProcess ?? Process.start,
       _readRequest = readRequest ?? StartVpnRequestReader.readFromStartFile,
       _notify = notify ?? AppFlutterApi().vpnStatusChanged,
       _notifyError =
           notifyError ?? AppFlutterApi().vpnStatusController.addError;

  static const _coreBin = 'HyperClientCore';
  final String? _filesDirectory;
  final String? _executablePath;
  final Future<ProcessResult> Function(String, List<String>) _runCommand;
  final Future<Process> Function(String, List<String>) _startProcess;
  final Future<StartVpnRequest> Function() _readRequest;
  final DesktopCoreExitWatch Function(int) _watchExit;
  final Future<void> Function(VpnStatus) _notify;
  final void Function(Object) _notifyError;
  final Future<SystemProxyManager?> Function(String runDirectory)
  _createSystemProxy;
  Future<SystemProxyManager?>? _systemProxy;
  final DesktopKillSwitchControl? _injectedKillSwitch;
  final Duration _readyTimeout;
  bool _startCancelled = false;

  /// Linux has no TUN filters: the kill switch holds only the system proxy.
  late final DesktopKillSwitchControl _killSwitch =
      _injectedKillSwitch ??
      DesktopKillSwitchControl(
        runDirectory: () async => p.join(await getTunFilesDir(), 'run'),
        invoke: invoke,
      );
  late final _monitor = CoreProcessMonitor(
    discoverPids: _queryCorePids,
    watchExit: _watchProcessExit,
    canPublish: () => !_stopping && _transition == null,
    notify: (status) async {
      if (status == VpnStatus.disconnected) await _releaseAfterExit();
      await _notify(status);
    },
    notifyError: _notifyError,
  );
  Process? _coreProcess;
  VpnStatus? _transition;
  bool _stopping = false;
  String? _lastCoreError;

  @override
  Future<NativeVpnCommandResult> readVpnStatus() async {
    final running = await queryCoreRunning();
    if (running == null) {
      return commandFailed('Unable to read Linux Core process state.');
    }
    return commandSuccess(
      status:
          _transition ??
          (running ? VpnStatus.connected : VpnStatus.disconnected),
    );
  }

  @override
  Future<NativeVpnCommandResult> startVpn() async {
    _transition = VpnStatus.connecting;
    _startCancelled = false;
    try {
      await _notify(VpnStatus.connecting);
      final request = await _readRequest();
      final proxyPort = desktopSystemProxyPort(request);
      await _killSwitch.arm(request.killSwitch);
      // On failure the caller decides whether the kill switch stays: a
      // reconnect keeps it, a first connect does not.
      if (!await startCore(readRunXrayRequest(request), request.tun)) {
        final error = _lastCoreError;
        await stopVpn(restart: true);
        return commandFailed(error);
      }
      if (proxyPort != null) {
        try {
          final proxy = await _proxyManager();
          await proxy?.apply(
            host: '127.0.0.1',
            port: proxyPort,
            bypass: desktopSystemProxyBypass(request),
          );
        } catch (error) {
          await stopVpn(restart: true);
          return commandFailed(failureDetails(error));
        }
      }
      await _notify(VpnStatus.connected);
      return commandSuccess(status: VpnStatus.connected);
    } catch (error) {
      return commandFailed(failureDetails(error));
    } finally {
      _transition = null;
    }
  }

  @override
  void cancelStart() {
    if (_transition == VpnStatus.connecting) _startCancelled = true;
  }

  @override
  Future<NativeVpnCommandResult> stopVpn({bool restart = false}) async {
    _transition = VpnStatus.disconnecting;
    try {
      await _notify(VpnStatus.disconnecting);
      if (!await (restart ? _stopCoreProcess(restart: true) : stopCore())) {
        return commandFailed('Unable to stop the current Core process.');
      }
      if (!restart) await _killSwitch.disarm();
      await _notify(VpnStatus.disconnected);
      return commandSuccess(status: VpnStatus.disconnected);
    } finally {
      _transition = null;
    }
  }

  @override
  Future<String> getTunFilesDir() async =>
      _filesDirectory ?? await super.getTunFilesDir();

  @override
  Future<void> observeVpnStatus() async {
    await _monitor.observe();
    // Recover the user's proxy after a proxy-mode Core died unobserved,
    // unless the kill switch still holds it.
    if ((await _monitor.readPids()).isEmpty && !await _killSwitch.settle()) {
      await _restoreSystemProxy();
    }
  }

  /// With the kill switch the proxy stays at the closed port of a Core that
  /// exited on its own: apps fail instead of going direct.
  Future<void> _releaseAfterExit() async {
    if (await _killSwitch.hold() == null) {
      await _restoreSystemProxy();
    } else {
      AppLog.warning('the Core exited; the kill switch keeps apps offline');
    }
  }

  @override
  Future<bool> killSwitchBlocking() async {
    if (_transition != null || (await queryCoreRunning() ?? true)) {
      return false;
    }
    try {
      return await _killSwitch.hold() != null &&
          (await (await _proxyManager())?.holding() ?? false);
    } catch (error) {
      AppLog.warning('read kill switch failed: ${AppLog.reason(error)}');
      return false;
    }
  }

  @override
  void disposeVpnStatus() => _monitor.dispose();

  Future<SystemProxyManager?> _proxyManager() => _systemProxy ??=
      getTunFilesDir().then((dir) => _createSystemProxy(p.join(dir, 'run')));

  /// Never fails the caller; the saved state stays for the next attempt.
  Future<void> _restoreSystemProxy() async {
    try {
      await (await _proxyManager())?.restore();
    } catch (error) {
      AppLog.warning('restore system proxy failed: ${AppLog.reason(error)}');
    }
  }

  DesktopCoreExitWatch _watchProcessExit(int pid) {
    final process = _coreProcess;
    if (process?.pid != pid) return _watchExit(pid);
    var retired = false;
    return DesktopCoreExitWatch(
      process!.exitCode.then((_) {
        if (retired) return false;
        if (identical(_coreProcess, process)) _coreProcess = null;
        return true;
      }),
      () => retired = true,
    );
  }

  Future<bool> startCore(LibXrayRunConfig request, TunJson? tun) async {
    _lastCoreError = null;
    try {
      if (!await _stopCoreProcess(restart: true)) {
        _lastCoreError = 'The previous Core process is still running.';
        return false;
      }
      await rotateDesktopCoreLogs(p.join(await getTunFilesDir(), 'run'));
      final inputs = await materializeRunXrayConfig(request);
      if (inputs == null) {
        _lastCoreError = 'The Xray configuration is empty.';
        return false;
      }
      final errorFile = desktopCoreErrorFile(inputs);
      await errorFile.writeAsString('', flush: true);
      final readyFile = desktopCoreReadyFile(inputs);
      await readyFile.writeAsString('', flush: true);
      final process = await _startProcess(
        corePath,
        // No TUN settings: system proxy mode, which needs no DNS pinning.
        desktopCoreRunArguments(
          dns: tun == null ? '' : desktopNetworkDns,
          interfaceName: tun?.autoOutboundsInterface ?? '',
          configPath: inputs,
          errorFile: errorFile.path,
          readyFile: readyFile.path,
        ),
      );
      _coreProcess = process;
      _bindProcess(process);
      unawaited(_monitor.waitForExit(process.pid));
      try {
        await waitForDesktopCoreReady(
          readyFile: readyFile,
          configPath: inputs,
          running: () async =>
              (await _monitor.readPids()).contains(process.pid),
          cancelled: () => _startCancelled,
          exited: 'The Core process exited during startup.',
          timeout: _readyTimeout,
        );
      } on StateError catch (error) {
        _lastCoreError = error.message;
        return false;
      }
      return true;
    } catch (error) {
      _lastCoreError = failureDetails(error);
      ygLogger('start core failed: $_lastCoreError');
      await _stopCoreProcess(restart: true);
      return false;
    }
  }

  // Existing named processes are discovered directly; old PID files are unused.
  Future<bool> cleanupStaleCore() async => await queryCoreRunning() != null;

  Future<bool> stopCore() => _stopCoreProcess();

  Future<bool> _stopCoreProcess({bool restart = false}) async {
    _stopping = true;
    _monitor.clearWatches();
    // Hand the proxy back first, so apps never see a closed local port;
    // unless the kill switch wants exactly that until the next Core is up.
    if (!restart || await _killSwitch.hold() == null) {
      await _restoreSystemProxy();
    }
    try {
      var pids = await _monitor.readPids();
      for (final (signal, timeout) in const [
        ('-TERM', Duration(seconds: 3)),
        ('-KILL', Duration(seconds: 2)),
      ]) {
        if (pids.isEmpty) break;
        final exits = [for (final pid in pids) _monitor.waitForExit(pid)];
        final arguments = [signal, '-x', _coreBin];
        final result = await _runCommand('pkill', arguments);
        if (result.exitCode != 0 && result.exitCode != 1) {
          throw ProcessException(
            'pkill',
            arguments,
            'Core stop command failed',
            result.exitCode,
          );
        }
        if (result.exitCode == 0) {
          await Future.wait(exits).timeout(timeout, onTimeout: () => []);
        }
        // pkill 0 means at least one signal was sent, not that every Core exited.
        // Exit 1 can mean either no matches or a permission failure.
        pids = await _monitor.readPids();
        if (result.exitCode == 1 && pids.isNotEmpty) return false;
      }
      final stopped = pids.isEmpty;
      if (stopped) {
        _coreProcess = null;
        _monitor.clearWatches();
      }
      return stopped;
    } catch (error) {
      ygLogger('stop desktop Core failed (${error.runtimeType})');
      return false;
    } finally {
      _stopping = false;
    }
  }

  Future<bool?> queryCoreRunning() async {
    try {
      final pids = await _monitor.readPids();
      return pids.isNotEmpty;
    } catch (_) {
      return null;
    }
  }

  Future<Set<int>> _queryCorePids() async {
    // procps does the name/state scan natively. Do not match full command lines
    // or include zombies/dead processes when reporting a running VPN.
    const arguments = ['-x', '-r', 'R,S,D,T,t,I', _coreBin];
    final result = await _runCommand('pgrep', arguments);
    if (result.exitCode != 0 && result.exitCode != 1) {
      throw ProcessException(
        'pgrep',
        arguments,
        'Core process query failed',
        result.exitCode,
      );
    }
    final pids = result.exitCode == 1
        ? <int>{}
        : {
            for (final value in '${result.stdout}'.trim().split(RegExp(r'\s+')))
              int.parse(value),
          };
    if (pids.any((pid) => pid <= 0)) {
      throw const FormatException('Invalid Core PID returned by pgrep');
    }
    return pids;
  }

  String get corePath {
    if (_executablePath != null) return _executablePath;
    if (kReleaseMode) {
      return p.join(p.dirname(Platform.resolvedExecutable), _coreBin);
    }
    final homeDir = Platform.environment['HOME'];
    return homeDir == null
        ? _coreBin
        : p.join(homeDir, 'work', 'vpn', _coreBin);
  }

  void _bindProcess(Process process) {
    process.stdout.listen((data) {
      if (!kReleaseMode) ygLogger(utf8.decode(data));
    });
    process.stderr.listen((data) {
      if (!kReleaseMode) ygLogger(utf8.decode(data));
    });
  }
}
