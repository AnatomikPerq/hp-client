import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/system_proxy/manager.dart';
import 'package:onexray/core/system_proxy/model.dart';

class _FakeBackend implements SystemProxyBackend {
  SystemProxySettings current;
  int writes = 0;
  bool failWrites = false;

  _FakeBackend(this.current);

  @override
  Future<SystemProxySettings> read() async => current;

  @override
  Future<void> write(SystemProxySettings settings) async {
    if (failWrites) throw StateError('write failed');
    writes++;
    current = settings;
  }
}

void main() {
  late Directory directory;
  late File stateFile;
  const userProxy = SystemProxySettings(
    enabled: true,
    server: '127.0.0.1:10808',
    bypass: 'localhost;<local>',
    autoConfigUrl: 'http://corp.invalid/proxy.pac',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('system-proxy-test-');
    stateFile = File('${directory.path}/run/system-proxy.json');
  });

  tearDown(() => directory.delete(recursive: true));

  SystemProxyManager manager(_FakeBackend backend) =>
      SystemProxyManager(backend: backend, stateFile: stateFile);

  test(
    'apply saves the previous proxy before switching, restore puts it back',
    () async {
      final backend = _FakeBackend(userProxy);
      final proxy = manager(backend);

      await proxy.apply(host: '127.0.0.1', port: 10820);
      expect(backend.current.enabled, isTrue);
      expect(backend.current.server, '127.0.0.1:10820');
      expect(backend.current.autoConfigEnabled, isFalse);
      expect(backend.current.autoDetect, isFalse);
      expect(await stateFile.exists(), isTrue);

      expect(await proxy.restore(), SystemProxyRestore.restored);
      expect(backend.current, userProxy);
      expect(await stateFile.exists(), isFalse);
    },
  );

  test('a proxy changed by someone else is never overwritten', () async {
    final backend = _FakeBackend(userProxy);
    final proxy = manager(backend);
    await proxy.apply(host: '127.0.0.1', port: 10820);

    const foreign = SystemProxySettings(enabled: true, server: '10.0.0.1:3128');
    backend.current = foreign;
    final writes = backend.writes;

    expect(await proxy.restore(), SystemProxyRestore.keptForeign);
    expect(backend.current, foreign);
    expect(backend.writes, writes);
    expect(await stateFile.exists(), isFalse);
  });

  test('restore without a prior apply changes nothing', () async {
    final backend = _FakeBackend(userProxy);
    expect(await manager(backend).restore(), SystemProxyRestore.nothing);
    expect(backend.writes, 0);
  });

  test('a new process recovers the user proxy after a crash', () async {
    final backend = _FakeBackend(userProxy);
    await manager(backend).apply(host: '127.0.0.1', port: 10820);

    // The App died with the proxy applied; a fresh manager reads the state.
    final recovered = manager(backend);
    expect(await recovered.active, isTrue);
    expect(await recovered.restore(), SystemProxyRestore.restored);
    expect(backend.current, userProxy);
  });

  test('re-applying after a crash keeps the original snapshot', () async {
    final backend = _FakeBackend(userProxy);
    await manager(backend).apply(host: '127.0.0.1', port: 10820);
    // Crash, then the next session applies again (possibly another port).
    final next = manager(backend);
    await next.apply(host: '127.0.0.1', port: 10821);
    expect(backend.current.server, '127.0.0.1:10821');

    expect(await next.restore(), SystemProxyRestore.restored);
    expect(backend.current, userProxy);
  });

  test('a failed switch leaves the state needed to recover', () async {
    final backend = _FakeBackend(userProxy)..failWrites = true;
    final proxy = manager(backend);
    await expectLater(
      proxy.apply(host: '127.0.0.1', port: 10820),
      throwsStateError,
    );
    backend.failWrites = false;
    // Nothing of ours is active, so the user settings are simply kept.
    expect(await proxy.restore(), SystemProxyRestore.keptForeign);
    expect(backend.current, userProxy);
  });
}
