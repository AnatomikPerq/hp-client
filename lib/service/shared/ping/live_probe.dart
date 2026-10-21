import 'dart:async';
import 'dart:io';

import 'package:onexray/core/tools/logger.dart';

/// Result of a live connection check.
class LivePingResult {
  const LivePingResult.success(this.milliseconds) : reachable = true;

  const LivePingResult.failure() : milliseconds = 0, reachable = false;

  final bool reachable;
  final int milliseconds;
}

/// Checks that the running connection really works end to end.
///
/// Node latency in the server list is measured in a temporary Core and says
/// nothing about the current connection. This request leaves the App along
/// the same path as the rest of the system's traffic: straight into the TUN,
/// or through the App's own system proxy in proxy mode. It never follows the
/// HTTP_PROXY environment, which may point at another client.
///
/// In TUN mode [tunAddress] binds the probe to the tunnel's own address. The
/// routes alone are not enough: while the TUN was still missing the probe
/// left through the physical interface, which the kill switch lets the App
/// use, and passed. Bound to an address that only the TUN carries it can
/// neither do that nor pass without the tunnel.
final class LivePingProbe {
  /// Empty 204 responses: minimal traffic, no dependency on page contents.
  static const defaultTargets = <String>[
    'https://cp.cloudflare.com/generate_204',
    'https://www.gstatic.com/generate_204',
  ];

  static const _timeout = Duration(seconds: 8);

  /// The App's local proxy in system proxy mode; null in TUN mode.
  final int? proxyPort;

  /// The TUN adapter's IPv4 address in TUN mode.
  final String? tunAddress;

  /// Tried in order until one answers.
  final List<String> targets;

  const LivePingProbe({
    this.proxyPort,
    this.tunAddress,
    this.targets = defaultTargets,
  });

  Future<LivePingResult> measure() async {
    for (final target in targets) {
      final result = await _probe(target);
      if (result.reachable) {
        return result;
      }
    }
    return const LivePingResult.failure();
  }

  Future<LivePingResult> _probe(String target) async {
    final port = proxyPort;
    final client = HttpClient()
      ..connectionTimeout = _timeout
      ..findProxy = ((_) => port == null ? 'DIRECT' : 'PROXY 127.0.0.1:$port')
      // A fresh connection: the whole path, not a reused socket.
      ..userAgent = null;
    final source = tunAddress;
    if (port == null && source != null) {
      client.connectionFactory = (uri, _, _) => _connectFrom(uri, source);
    }
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client.getUrl(Uri.parse(target)).timeout(_timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(_timeout);
      await response.drain<void>().timeout(_timeout);
      stopwatch.stop();
      if (response.statusCode >= 400) {
        return const LivePingResult.failure();
      }
      return LivePingResult.success(stopwatch.elapsedMilliseconds);
    } catch (error) {
      ygLogger('live ping to $target failed: ${error.runtimeType}');
      return const LivePingResult.failure();
    } finally {
      client.close(force: true);
    }
  }

  /// IPv4 only: the TUN's address is IPv4, and a socket bound to it cannot
  /// reach an IPv6 target. HttpClient leaves TLS to the factory.
  static Future<ConnectionTask<Socket>> _connectFrom(
    Uri uri,
    String source,
  ) async {
    final addresses = await InternetAddress.lookup(
      uri.host,
      type: InternetAddressType.IPv4,
    );
    if (addresses.isEmpty) {
      throw SocketException('No IPv4 address for ${uri.host}');
    }
    final task = await Socket.startConnect(
      addresses.first,
      uri.port,
      sourceAddress: source,
    );
    return ConnectionTask.fromSocket<Socket>(
      task.socket.then<Socket>(
        (socket) => uri.scheme == 'https'
            ? SecureSocket.secure(socket, host: uri.host)
            : socket,
      ),
      task.cancel,
    );
  }
}
