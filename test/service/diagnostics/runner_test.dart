import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/diagnostics/runner.dart';
import 'package:onexray/service/diagnostics/settings.dart';

import 'fixtures.dart';

/// Hands out queued states, then the last one forever.
class FakeReportHost implements NetworkReportHost {
  FakeReportHost(this.states, {this.startError});

  final List<NetworkReportStateResponse> states;
  final String? startError;
  final requests = <StartNetworkReportRequest>[];
  final cancelled = <String>[];
  var polls = 0;

  @override
  Future<String> start(StartNetworkReportRequest request) async {
    requests.add(request);
    if (startError != null) throw LibXrayInvokeException(startError!);
    return 'run-1';
  }

  @override
  Future<NetworkReportStateResponse> state(String id) async {
    final state = states[polls < states.length ? polls : states.length - 1];
    polls++;
    return state;
  }

  @override
  Future<void> cancel(String id) async => cancelled.add(id);
}

void main() {
  test('polls until the run ends and passes the settings on', () async {
    final host = FakeReportHost([
      const NetworkReportStateResponse(
        running: true,
        progress: NetworkReportProgress(section: 'dns', done: 1, total: 4),
        report: {'version': 1},
      ),
      NetworkReportStateResponse(
        running: false,
        progress: const NetworkReportProgress(
          section: 'udp',
          done: 4,
          total: 4,
        ),
        report: whitelistReport(),
      ),
    ]);
    final runner = NetworkReportRunner(
      host: host,
      pollInterval: const Duration(milliseconds: 5),
    );
    final snapshots = <NetworkReportSnapshot>[];
    await runner.start(
      settings: const NetworkReportSettings(
        checkUdp: false,
        saveTraffic: true,
        extraSites: ['example.org'],
      ),
      interfaceName: 'Ethernet 4',
      onSnapshot: snapshots.add,
    );
    for (var tick = 0; tick < 100 && runner.running; tick++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(runner.running, isFalse);
    final request = host.requests.single;
    expect(request.interfaceName, 'Ethernet 4');
    expect(request.sections, ['network', 'dns', 'sites', 'hosting']);
    expect(request.sites, ['example.org']);
    expect(request.maxBytes, 64 * 1024);
    expect(snapshots.first.running, isTrue);
    expect(
      snapshots.any((s) => s.section == 'dns' && s.fraction == 0.25),
      isTrue,
    );
    final last = snapshots.last;
    expect(last.running, isFalse);
    final report = last.present(const NetworkReportSettings())!;
    expect(report.facts!.mode, 'sni_whitelist');
    // Presented with the settings: the address is masked.
    expect(report.network!.ipv4!.ip, '198.51.100.0/24');
    runner.dispose();
  });

  test('an older libXray reads as unsupported', () async {
    final host = FakeReportHost(const [], startError: 'unknown method');
    final snapshots = <NetworkReportSnapshot>[];
    await NetworkReportRunner(
      host: host,
    ).start(settings: const NetworkReportSettings(), onSnapshot: snapshots.add);
    expect(snapshots.single.error, NetworkReportRunner.unsupported);
    expect(snapshots.single.running, isFalse);
  });

  test('stop cancels the run in libXray', () async {
    final host = FakeReportHost(const [
      NetworkReportStateResponse(running: true),
    ]);
    final runner = NetworkReportRunner(
      host: host,
      pollInterval: const Duration(milliseconds: 5),
    );
    await runner.start(
      settings: const NetworkReportSettings(),
      onSnapshot: (_) {},
    );
    await runner.stop();
    expect(host.cancelled, ['run-1']);
    runner.dispose();
  });
}
