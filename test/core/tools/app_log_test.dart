import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/app_log.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  final defaultDirectory = AppLog.directory;
  final defaultMaxBytes = AppLog.maxBytes;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('app-log-test');
    AppLog.directory = () => directory.path;
  });

  tearDown(() async {
    AppLog.directory = defaultDirectory;
    AppLog.maxBytes = defaultMaxBytes;
    await directory.delete(recursive: true);
  });

  test('lines are appended, one per message, newlines folded', () async {
    AppLog.info('connected');
    AppLog.warning('no connection\nafter 3 probes');
    await AppLog.flush();
    final lines = await File(p.join(directory.path, AppLog.fileName))
        .readAsLines();
    expect(lines, hasLength(2));
    expect(
      lines[0],
      matches(RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d \[INFO\] connected$')),
    );
    expect(lines[1], endsWith('[WARN] no connection after 3 probes'));
  });

  test('a full file moves to app.log.1', () async {
    AppLog.maxBytes = 120;
    for (var i = 0; i < 4; i++) {
      AppLog.info('line $i ${'x' * 40}');
    }
    await AppLog.flush();
    final current = await File(p.join(directory.path, AppLog.fileName))
        .readAsLines();
    final previous = await File(p.join(directory.path, '${AppLog.fileName}.1'))
        .readAsLines();
    expect(current.single, contains('line 3'));
    expect(previous.last, contains('line 2'));
  });

  test('a reason keeps the diagnostic and cuts secrets out', () {
    // What a live switch failed with on 19.10: the bare type said nothing.
    expect(
      AppLog.reason(
        const LibXrayInvokeException(
          'control operation 2 (addRules): common/geodata: failed to open '
          r'geosite.dat > GetFileAttributesEx C:\App\geosite.dat',
        ),
      ),
      'LibXrayInvokeException: control operation 2 (addRules): '
      'common/geodata: failed to open geosite.dat > '
      r'GetFileAttributesEx C:\App\geosite.dat',
    );
    final secret = AppLog.reason(
      const LibXrayInvokeException(
        'bad link vless://3e762061-e7cf-46a1-95a5-6dd9374a22a2@host:443?pbk=x '
        'in {"outbounds":[{"settings":{"password":"hunter2"}}]} '
        'id 3e762061-e7cf-46a1-95a5-6dd9374a22a2 '
        'key AGT+DQBgAAAgACDgP5FmGxFQ2oQkXZun8pOSeo17aj3vvMwZ216',
      ),
    );
    expect(secret, isNot(contains('3e762061')));
    expect(secret, isNot(contains('hunter2')));
    expect(secret, isNot(contains('AGT+DQ')));
    expect(secret, contains('<link>'));
    expect(secret, contains('{…}'));
    // A host failure keeps its code.
    expect(
      AppLog.reason(const ConnectionHostException('swapUnavailable')),
      'ConnectionHostException: swapUnavailable',
    );
    expect(AppLog.reason(StateError('x' * 1000)).length, lessThan(340));
  });

  test('no directory, no file', () async {
    AppLog.directory = () => null;
    AppLog.warning('dropped');
    await AppLog.flush();
    expect(directory.listSync(), isEmpty);
  });
}
