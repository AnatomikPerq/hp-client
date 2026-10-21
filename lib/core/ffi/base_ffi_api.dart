import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show protected;
import 'package:isolate_manager/isolate_manager.dart';
import 'package:onexray/core/ffi/generated_bindings.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/atomic_file.dart';
import 'package:onexray/core/tools/empty.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:path/path.dart' as p;

/// TUN mode passes [dns] and [interfaceName] so the Core's own DNS stays on
/// the physical interface. System proxy mode has no tunnel and passes neither.
///
/// [configSha256] lets an elevated Core refuse a config swapped after launch:
/// the file lives in a directory every process of the user can write.
/// [stopFile] lets the App end the Core without terminating it, which for an
/// elevated Core would cost another UAC prompt. The Core writes `ready` to
/// [readyFile] once Xray runs and its tunnel passes the kill switch.
///
/// [killSwitch] makes a TUN Core block traffic outside the tunnel until the
/// App disconnects; [killSwitchApp] (the App itself) may still pass. Only the
/// elevated TUN Core can install the filters.
List<String> desktopCoreRunArguments({
  String dns = '',
  String interfaceName = '',
  required String configPath,
  String? errorFile,
  String? configSha256,
  String? stopFile,
  String? readyFile,
  DesktopKillSwitch? killSwitch,
  String? killSwitchApp,
}) {
  if (configPath.isEmpty || dns.isEmpty != interfaceName.isEmpty) {
    throw const FormatException(
      'Desktop Core DNS, interface, or config path is missing',
    );
  }
  if (killSwitch != null && dns.isEmpty) {
    throw const FormatException('The kill switch needs the TUN mode');
  }
  return <String>[
    'run',
    if (dns.isNotEmpty) ...['-dns', '$dns:53', '-interface', interfaceName],
    if (killSwitch != null) ...[
      '-kill-switch',
      if (killSwitch.allowLan) '-kill-switch-lan',
      if (killSwitch.strict) '-kill-switch-persistent',
      if (killSwitchApp != null) ...['-kill-switch-app', killSwitchApp],
    ],
    '-config',
    configPath,
    if (configSha256 != null) ...['-config-sha256', configSha256],
    if (errorFile != null) ...['-error-file', errorFile],
    if (stopFile != null) ...['-stop-file', stopFile],
    if (readyFile != null) ...['-ready-file', readyFile],
  ];
}

/// SHA-256 of exactly the bytes [BaseFfiApi.materializeRunXrayConfig] writes.
String desktopCoreConfigSha256(String xrayJson) =>
    sha256.convert(utf8.encode(xrayJson)).toString();

/// The Core stops gracefully once this file appears.
File desktopCoreStopFile(String runDirectory) =>
    File(p.join(runDirectory, 'core.stop'));

/// Asks the Core to stop through [stopFile]. Empty means a disconnect, and
/// the Core lifts its kill switch; [restart] (another Core follows) keeps it,
/// so nothing slips out in between. Written whole, so the Core never reads a
/// restart as an empty file.
Future<void> requestDesktopCoreStop(
  File stopFile, {
  bool restart = false,
}) async {
  await stopFile.parent.create(recursive: true);
  await writeBytesAtomically(stopFile, restart ? utf8.encode('restart') : []);
}

/// Desktop requests without TUN settings run the system proxy mode; the
/// SOCKS port is then the user-facing mixed inbound on 127.0.0.1.
int? desktopSystemProxyPort(StartVpnRequest request) {
  if (request.tun != null) return null;
  final port = int.tryParse(request.socksPort ?? '');
  if (port == null || port < 1 || port > 65535) {
    throw const FormatException('System proxy port is missing');
  }
  return port;
}

/// The user's hosts that bypass the system proxy in proxy mode.
List<String> desktopSystemProxyBypass(StartVpnRequest request) =>
    request.systemProxyBypass ?? const [];

File desktopCoreErrorFile(String configPath) => File('$configPath.error');

File desktopCoreReadyFile(String configPath) => File('$configPath.ready');

/// The user stopped a start that was still waiting for the Core.
class DesktopCoreStartCancelled implements Exception {
  const DesktopCoreStartCancelled();

  @override
  String toString() => 'cancelled';
}

/// How long a start waits for Xray. In a memory-starved test VM loading the
/// geodata and creating the TUN adapter took over two minutes.
const desktopCoreReadyTimeout = Duration(minutes: 3);

/// Waits until the Core marks [readyFile] (created empty by the App before
/// launch). A running process is not a working connection: Home said
/// "connected" for two minutes while Xray was still starting, the TUN did not
/// exist yet and the kill switch kept everything offline.
///
/// Throws a [StateError] with the Core's own error when it exits first or
/// after [timeout], and [DesktopCoreStartCancelled] once [cancelled] says so.
Future<void> waitForDesktopCoreReady({
  required File readyFile,
  required String configPath,
  required Future<bool> Function() running,
  bool Function()? cancelled,
  String exited = 'The Core exited during start',
  Duration timeout = desktopCoreReadyTimeout,
  Duration poll = const Duration(milliseconds: 200),
}) async {
  final waiting = Stopwatch()..start();
  while (true) {
    try {
      if ((await readyFile.readAsString()).trim() == 'ready') return;
    } on FileSystemException {
      // The Core recreates nothing; a missing file just never becomes ready.
    }
    if (!await running()) {
      throw StateError(await readDesktopCoreStartError(configPath, exited));
    }
    if (cancelled?.call() ?? false) throw const DesktopCoreStartCancelled();
    if (waiting.elapsed >= timeout) {
      throw StateError(
        'The Core did not start Xray within ${timeout.inSeconds} s',
      );
    }
    await Future<void>.delayed(poll);
  }
}

Future<String> readDesktopCoreStartError(
  String configPath,
  String fallback,
) async {
  try {
    final file = desktopCoreErrorFile(configPath);
    final error = (await file.readAsString()).trim();
    if (error.isNotEmpty) return error;
  } on FileSystemException {
    // A crash before the CLI starts may leave no diagnostic file.
  }
  return fallback;
}

/// The Core's own logs in the run directory, as `ConnectionCompiler` names
/// them.
const desktopCoreLogNames = ['error.log', 'access.log'];

const desktopCoreLogMaxBytes = 4 << 20;

/// Rolls each Core log in [runDirectory] that has grown past [maxBytes] to
/// `*.1`, replacing the previous one. Xray only appends to them, session
/// after session: at debug level error.log reached 43 MB in three days.
///
/// Only while no Core runs: one holds the files open (and Windows refuses
/// the rename then). Only regular files are touched, and a failure never
/// fails the start.
Future<void> rotateDesktopCoreLogs(
  String runDirectory, {
  int maxBytes = desktopCoreLogMaxBytes,
}) async {
  for (final name in desktopCoreLogNames) {
    final file = File(p.join(runDirectory, name));
    final previous = File('${file.path}.1');
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() <= maxBytes) {
        continue;
      }
      switch (await FileSystemEntity.type(previous.path, followLinks: false)) {
        case FileSystemEntityType.file:
          await previous.delete();
        case FileSystemEntityType.notFound:
          break;
        default:
          continue;
      }
      await file.rename(previous.path);
    } on FileSystemException catch (error) {
      ygLogger('rotate Core log $name failed: $error');
    }
  }
}

abstract class BaseFfiApi {
  Future<String> getTunFilesDir() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  Future<NativeVpnCommandResult> readVpnStatus();

  /// Successful commands return the confirmed terminal status. Each platform
  /// owns its notification/wait mechanism; callers do not poll for completion.
  Future<NativeVpnCommandResult> startVpn();

  /// [restart] stops the Core for another one, where the desktop kill
  /// switch keeps what it holds; a plain stop is the user's disconnect.
  Future<NativeVpnCommandResult> stopVpn({bool restart = false});

  /// Stops waiting for a desktop Core that has not reported ready; the start
  /// then fails as cancelled and stops that Core.
  void cancelStart() {}

  Future<void> observeVpnStatus();
  void disposeVpnStatus();

  /// Whether no Core runs and the kill switch keeps apps offline. Desktop
  /// platforms that have one override it.
  Future<bool> killSwitchBlocking() async => false;

  @protected
  LibXrayRunConfig readRunXrayRequest(StartVpnRequest request) {
    if (!EmptyTool.checkString(request.coreInvokeText)) {
      return LibXrayRunConfig(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest(null).toJson(),
        ),
      );
    }
    return LibXrayRunConfig.fromInvokeText(request.coreInvokeText!);
  }

  Future<String?> materializeRunXrayConfig(LibXrayRunConfig request) async {
    final runPath = p.join(await getTunFilesDir(), 'run');
    final root = Directory(p.join(runPath, 'core-inputs'));
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await root.delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      throw const FormatException('Invalid desktop Core input directory');
    }
    await root.create(recursive: true);
    final xrayJson = request.request.xrayJson;
    if (xrayJson == null || xrayJson.isEmpty) {
      return null;
    }

    final directory = await root.createTemp('input-');
    try {
      final config = File(p.join(directory.path, 'xray.json'));
      await config.writeAsString(xrayJson, flush: true);
      return config.path;
    } catch (_) {
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    }
  }

  PlatformPermissionResult _permissionNotRequired() {
    return PlatformPermissionResult(
      kind: PlatformPermissionKind.none,
      state: PlatformPermissionState.notRequired,
    );
  }

  @protected
  NativeVpnCommandResult commandSuccess({VpnStatus? status}) {
    return NativeVpnCommandResult(
      state: NativeVpnCommandState.success,
      status: status,
      permission: _permissionNotRequired(),
    );
  }

  @protected
  NativeVpnCommandResult commandFailed([String? message]) {
    return NativeVpnCommandResult(
      state: NativeVpnCommandState.failed,
      permission: _permissionNotRequired(),
      message: message,
    );
  }

  final _sharedIsolate = IsolateManager.createShared(concurrent: 1);

  /// A ping batch holds its worker for up to the probe timeout (twice that
  /// with location probes). On the shared worker it queued every call behind
  /// it: the ports for Connect, a live node switch, minewire state, imports.
  /// libXray serializes pings itself; other methods run alongside.
  final _longIsolate = IsolateManager.createShared(concurrent: 1);

  void stopSharedIsolate() {
    _sharedIsolate.stop();
    _longIsolate.stop();
  }

  Future<String> invoke(String requestJson, {bool long = false}) async {
    return (long ? _longIsolate : _sharedIsolate).compute(
      _cgoInvoke,
      requestJson,
    );
  }
}

class _CoreLib {
  late final NativeLibrary _lib;

  static final _CoreLib _singleton = _CoreLib._internal();

  factory _CoreLib() => _singleton;

  _CoreLib._internal() {
    var libName = "";
    if (AppPlatform.isLinux) {
      libName = "libXray.so";
    } else if (AppPlatform.isWindows) {
      libName = "libXray.dll";
    }
    final lib = DynamicLibrary.open(libName);
    _lib = NativeLibrary(lib);
  }
}

@pragma('vm:entry-point')
@isolateManagerSharedWorker
String _cgoInvoke(String requestJson) {
  final req = _convertStringToPointer(requestJson);
  try {
    final resPointer = _CoreLib()._lib.CGoInvoke(req);
    return _convertPointerToString(resPointer);
  } finally {
    calloc.free(req);
  }
}

Pointer<Char> _convertStringToPointer(String text) {
  final pointer = text.toNativeUtf8().cast<Char>();
  return pointer;
}

String _convertPointerToString(Pointer<Char> pointer) {
  if (pointer == nullptr) {
    throw StateError('CGoInvoke returned a null response');
  }
  try {
    return pointer.cast<Utf8>().toDartString();
  } finally {
    _CoreLib()._lib.CGoFree(pointer);
  }
}
