import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/base_ffi_api.dart';
import 'package:onexray/core/ffi/linux_ffi_api.dart';
import 'package:onexray/core/model/tun_json.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:path/path.dart' as p;

import '../../support/test_directory.dart';

void main() {
  test('the network DNS mode passes as is', () {
    expect(
      desktopCoreRunArguments(
        dns: desktopNetworkDns,
        interfaceName: 'Ethernet',
        configPath: r'C:\run\xray.json',
      ).take(5),
      ['run', '-dns', 'network', '-interface', 'Ethernet'],
    );
  });

  test('builds protected desktop Core arguments', () {
    expect(
      desktopCoreRunArguments(
        dns: '8.8.8.8',
        interfaceName: 'Ethernet',
        configPath: r'C:\run\xray.json',
        errorFile: r'C:\run\xray.json.error',
      ),
      <String>[
        'run',
        '-dns',
        '8.8.8.8:53',
        '-interface',
        'Ethernet',
        '-config',
        r'C:\run\xray.json',
        '-error-file',
        r'C:\run\xray.json.error',
      ],
    );
    expect(
      desktopCoreRunArguments(
        dns: '8.8.8.8',
        interfaceName: 'eth0',
        configPath: '/runtime-input/xray.json',
      ),
      [
        'run',
        '-dns',
        '8.8.8.8:53',
        '-interface',
        'eth0',
        '-config',
        '/runtime-input/xray.json',
      ],
    );
  });

  test('system proxy mode passes neither DNS pinning nor an interface', () {
    expect(
      desktopCoreRunArguments(
        configPath: r'C:\run\xray.json',
        configSha256: 'ab' * 32,
        errorFile: r'C:\run\xray.json.error',
        stopFile: r'C:\run\core.stop',
        readyFile: r'C:\run\xray.json.ready',
      ),
      <String>[
        'run',
        '-config',
        r'C:\run\xray.json',
        '-config-sha256',
        'ab' * 32,
        '-error-file',
        r'C:\run\xray.json.error',
        '-stop-file',
        r'C:\run\core.stop',
        '-ready-file',
        r'C:\run\xray.json.ready',
      ],
    );
    expect(
      () => desktopCoreRunArguments(dns: '8.8.8.8', configPath: 'xray.json'),
      throwsFormatException,
    );
  });

  test('the kill switch reaches only a TUN Core', () {
    expect(
      desktopCoreRunArguments(
        dns: '8.8.8.8',
        interfaceName: 'Ethernet',
        configPath: 'xray.json',
        killSwitch: const DesktopKillSwitch(allowLan: true, strict: true),
        killSwitchApp: r'C:\Program Files\HYPER CLIENT\HyperClient.exe',
      ),
      <String>[
        'run',
        '-dns',
        '8.8.8.8:53',
        '-interface',
        'Ethernet',
        '-kill-switch',
        '-kill-switch-lan',
        '-kill-switch-persistent',
        '-kill-switch-app',
        r'C:\Program Files\HYPER CLIENT\HyperClient.exe',
        '-config',
        'xray.json',
      ],
    );
    expect(
      () => desktopCoreRunArguments(
        configPath: 'xray.json',
        killSwitch: const DesktopKillSwitch(allowLan: false, strict: false),
      ),
      throwsFormatException,
    );
  });

  group('waiting for the Core', () {
    late Directory directory;
    late String config;
    late File ready;

    setUp(() async {
      directory = await createTestDirectory('core-ready-');
      config = p.join(directory.path, 'xray.json');
      ready = desktopCoreReadyFile(config);
      await ready.writeAsString('');
    });
    tearDown(() => directory.delete(recursive: true));

    Future<void> wait({
      Future<bool> Function()? running,
      bool Function()? cancelled,
      Duration timeout = const Duration(seconds: 5),
    }) => waitForDesktopCoreReady(
      readyFile: ready,
      configPath: config,
      running: running ?? () async => true,
      cancelled: cancelled,
      timeout: timeout,
      poll: const Duration(milliseconds: 20),
    );

    test('returns once the Core writes ready', () async {
      var polls = 0;
      await wait(
        running: () async {
          if (++polls == 3) await ready.writeAsString('ready');
          return true;
        },
      );
      expect(polls, 3);
    });

    test('reports the Core error when it exits first', () async {
      await desktopCoreErrorFile(config).writeAsString('tun: access denied');
      await expectLater(
        wait(running: () async => false),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'tun: access denied',
          ),
        ),
      );
    });

    test('stops when cancelled', () async {
      var cancelled = false;
      final waiting = wait(cancelled: () => cancelled);
      cancelled = true;
      await expectLater(waiting, throwsA(isA<DesktopCoreStartCancelled>()));
    });

    test('gives up after the timeout', () async {
      await expectLater(
        wait(timeout: const Duration(milliseconds: 100)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('did not start Xray'),
          ),
        ),
      );
    });
  });

  test('a stop request tells a restart from a disconnect', () async {
    final directory = await createTestDirectory('core-stop-');
    addTearDown(() => directory.delete(recursive: true));
    final stop = desktopCoreStopFile(directory.path);
    await requestDesktopCoreStop(stop, restart: true);
    expect(await stop.readAsString(), 'restart');
    await requestDesktopCoreStop(stop);
    expect(await stop.readAsString(), isEmpty);
  });

  test('a desktop request without TUN settings is the proxy mode', () {
    StartVpnRequest request(TunJson? tun, String? socks) =>
        StartVpnRequest(tun, socks, '18186', '{}');
    expect(desktopSystemProxyPort(request(null, '10820')), 10820);
    expect(
      desktopSystemProxyPort(
        request(TunJson.fromJson({'tunDnsIPv4': '8.8.8.8'}), '10820'),
      ),
      isNull,
    );
    for (final socks in [null, '', '0', '70000', 'x']) {
      expect(
        () => desktopSystemProxyPort(request(null, socks)),
        throwsFormatException,
      );
    }
  });

  test('the config hash covers exactly the bytes written', () async {
    final directory = await Directory.systemTemp.createTemp('config-hash-');
    addTearDown(() => directory.delete(recursive: true));
    const xrayJson = '{"log":{"loglevel":"none"},"remarks":"узел ✓"}';
    final file = File(p.join(directory.path, 'xray.json'));
    await file.writeAsString(xrayJson, flush: true);
    expect(
      desktopCoreConfigSha256(xrayJson),
      sha256.convert(await file.readAsBytes()).toString(),
    );
  });

  test('rolls only oversized regular Core logs over to *.1', () async {
    final directory = await createTestDirectory('onexray-core-logs-');
    addTearDown(() => directory.delete(recursive: true));
    File log(String name) => File(p.join(directory.path, name));
    await log('error.log').writeAsString('new session lines');
    await log('error.log.1').writeAsString('older');
    await log('access.log').writeAsString('small');
    await rotateDesktopCoreLogs(directory.path, maxBytes: 8);
    expect(await log('error.log').exists(), isFalse);
    expect(await log('error.log.1').readAsString(), 'new session lines');
    expect(await log('access.log').readAsString(), 'small');
    expect(await log('access.log.1').exists(), isFalse);

    // Something that is not a file in the way is never removed.
    await log('access.log').writeAsString('grown past the limit');
    await Directory(log('access.log.1').path).create();
    await rotateDesktopCoreLogs(directory.path, maxBytes: 8);
    expect(await log('access.log').readAsString(), 'grown past the limit');
    expect(await Directory(log('access.log.1').path).exists(), isTrue);

    // A missing directory or log is no error.
    await rotateDesktopCoreLogs(p.join(directory.path, 'missing'));
  });

  test(
    'replaces old inputs with one unique immutable runtime directory',
    () async {
      final directory = await createTestDirectory('onexray-desktop-inputs-');
      addTearDown(() => directory.delete(recursive: true));
      final api = _TestFfiApi(stopResult: true, directory: directory.path);
      addTearDown(api.stopSharedIsolate);
      final stale = File(
        p.join(directory.path, 'run', 'core-inputs', 'stale', 'xray.json'),
      );
      await stale.parent.create(recursive: true);
      await stale.writeAsString('stale');
      final sibling = File(p.join(directory.path, 'run', 'keep'));
      await sibling.writeAsString('keep');
      const text = '{"outbounds":[{"protocol":"freedom"}]}';
      final request = _request(text);
      final first = (await api.materializeRunXrayConfig(request))!;
      expect(
        p.dirname(p.dirname(first)),
        p.join(directory.path, 'run', 'core-inputs'),
      );
      expect(await stale.exists(), isFalse);
      expect(await sibling.readAsString(), 'keep');
      expect(await File(first).readAsString(), text);
      expect(await desktopCoreErrorFile(first).exists(), isFalse);
      await desktopCoreErrorFile(first).writeAsString('old startup failure');
      expect(
        await readDesktopCoreStartError(first, 'Core exited'),
        'old startup failure',
      );
      final second = (await api.materializeRunXrayConfig(request))!;
      expect(second, isNot(first));
      expect(await Directory(p.dirname(first)).exists(), isFalse);
      expect(await File(second).readAsString(), text);
      expect(await desktopCoreErrorFile(second).exists(), isFalse);
      await desktopCoreErrorFile(second).writeAsString('');
      expect(
        await readDesktopCoreStartError(second, 'Core exited'),
        'Core exited',
      );
      await desktopCoreErrorFile(second).delete();
      expect(
        await readDesktopCoreStartError(second, 'Core exited'),
        'Core exited',
      );
      final arguments = desktopCoreRunArguments(
        dns: '8.8.8.8',
        interfaceName: 'eth0',
        configPath: second,
      );
      expect(arguments, isNot(contains('-runtime')));
    },
  );

  test('reports disconnected only after Core stops successfully', () async {
    final api = _TestFfiApi(stopResult: true);
    addTearDown(api.stopSharedIsolate);

    final result = await api.stopVpn();

    expect(result.state, NativeVpnCommandState.success);
    expect(api.statuses, [VpnStatus.disconnecting, VpnStatus.disconnected]);
  });

  test('a stop failure never invents a connected state', () async {
    final api = _TestFfiApi(stopResult: false);
    addTearDown(api.stopSharedIsolate);

    final result = await api.stopVpn();

    expect(result.state, NativeVpnCommandState.failed);
    expect(api.statuses, [VpnStatus.disconnecting]);
  });
}

final class _TestFfiApi extends LinuxFfiApi {
  final bool stopResult;
  final String? directory;
  final List<VpnStatus> statuses;

  factory _TestFfiApi({required bool stopResult, String? directory}) =>
      _TestFfiApi._(stopResult, directory, []);

  _TestFfiApi._(this.stopResult, this.directory, this.statuses)
    : super.forTesting(
        filesDirectory: directory ?? '',
        executablePath: '',
        runCommand: (_, _) => throw UnimplementedError(),
        watchExit: (_) => throw UnimplementedError(),
        notify: (status) async => statuses.add(status),
      );

  @override
  Future<String> getTunFilesDir() async =>
      directory ?? await super.getTunFilesDir();

  @override
  Future<bool> stopCore() async => stopResult;
}

LibXrayRunConfig _request(String json) => LibXrayRunConfig(
  LibXrayInvokeRequest(
    method: LibXrayMethod.runXray,
    payload: RunXrayRequest(json).toJson(),
  ),
);
