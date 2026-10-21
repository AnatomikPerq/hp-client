import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/ping/live_probe.dart';

void main() {
  late HttpServer server;
  late String target;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.noContent
        ..close();
    });
    target = 'http://127.0.0.1:${server.port}/generate_204';
  });
  tearDown(() => server.close(force: true));

  test('a probe bound to an address the machine has goes through', () async {
    final result = await LivePingProbe(
      tunAddress: '127.0.0.1',
      targets: [target],
    ).measure();
    expect(result.reachable, isTrue);
  });

  test('a probe bound to a missing TUN address cannot pass', () async {
    // 198.18.0.1 is the TUN's address: no interface here carries it, so the
    // probe must fail instead of leaving through another interface.
    final result = await LivePingProbe(
      tunAddress: '198.18.0.1',
      targets: [target],
    ).measure();
    expect(result.reachable, isFalse);
  });
}
