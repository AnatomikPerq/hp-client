import 'dart:io';

import 'package:onexray/core/system_proxy/linux.dart';
import 'package:onexray/core/system_proxy/manager.dart';
import 'package:onexray/core/system_proxy/windows.dart';
import 'package:path/path.dart' as p;

/// The manager for this platform, or `null` where the App cannot change the
/// system proxy; proxy mode then still serves its local inbound.
Future<SystemProxyManager?> createSystemProxyManager(
  String runDirectory,
) async {
  final stateFile = File(p.join(runDirectory, 'system-proxy.json'));
  if (Platform.isWindows) {
    return SystemProxyManager(
      backend: const WindowsSystemProxyBackend(),
      stateFile: stateFile,
    );
  }
  if (Platform.isLinux && await GnomeSystemProxyBackend.available()) {
    return SystemProxyManager(
      backend: GnomeSystemProxyBackend(),
      stateFile: stateFile,
    );
  }
  return null;
}
