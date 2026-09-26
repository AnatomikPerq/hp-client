import 'dart:io';

import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/service/minewire/link.dart';
import 'package:onexray/service/shared/ping/batch.dart';

/// Reachability of a minewire server as TCP connect time.
///
/// libXray's probe builds a temporary Xray around the node, which minewire is
/// not; starting a throwaway engine would take a port and a server session
/// just to measure. The connect time is what users compare nodes by, and a
/// failure means the server cannot be reached at all. No location lookup.
Future<PingBatchResult> minewireTcpPing(
  MinewireLink link,
  int timeoutSeconds, {
  Future<Socket> Function(String host, int port, Duration timeout)? connect,
}) async {
  final timeout = Duration(seconds: timeoutSeconds > 0 ? timeoutSeconds : 5);
  final open =
      connect ??
      (String host, int port, Duration timeout) =>
          Socket.connect(host, port, timeout: timeout);
  final watch = Stopwatch()..start();
  try {
    final socket = await open(link.host, link.port, timeout).timeout(timeout);
    final elapsed = watch.elapsedMilliseconds;
    socket.destroy();
    return PingBatchResult(true, elapsed < 1 ? 1 : elapsed, '');
  } on SocketException catch (error) {
    final timedOut = watch.elapsed >= timeout;
    return PingBatchResult(
      false,
      timedOut ? PingDelayConstants.timeout : PingDelayConstants.error,
      error.message,
    );
  } catch (error) {
    return PingBatchResult(false, PingDelayConstants.timeout, '$error');
  }
}
