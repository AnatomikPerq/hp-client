import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/preparation.dart';
import 'package:onexray/service/connect/runtime_host.dart';

void main() {
  test('a busy proxy port is reported before the Core starts', () async {
    final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(taken.close);
    await expectLater(
      ensureSystemProxyPortFree(taken.port),
      throwsA(
        isA<ConnectionHostException>().having(
          (error) => error.reason,
          'reason',
          'systemProxyPortBusy',
        ),
      ),
    );
  });

  test('runtime ports never reuse the fixed proxy port', () async {
    // The host API refuses free ports that hit an excluded one.
    List<int>? excluded;
    final ports = await allocateRuntimePorts(
      const [],
      excludePorts: [10820],
      getFreePorts: (_, {excludePorts}) async {
        excluded = excludePorts;
        return [40001, 40002];
      },
    );
    expect(ports, [40001, 40002]);
    expect(excluded, [10820]);
  });
}
