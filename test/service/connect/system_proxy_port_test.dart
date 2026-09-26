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
    var calls = 0;
    final ports = await allocateRuntimePorts(
      const [],
      reserved: {10820},
      getFreePorts: (_) async => ++calls == 1 ? [10820, 40000] : [40001, 40002],
    );
    expect(ports, [40001, 40002]);
  });
}
