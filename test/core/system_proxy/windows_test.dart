@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/system_proxy/windows.dart';

// Read-only on purpose. Writing through WinINet is never isolated: even a
// throwaway per-connection entry also rewrites the legacy LAN values
// (ProxyEnable, ProxyServer, ...) in the Internet Settings key, which other
// software on a developer machine may depend on. Writes are covered by the
// manager tests with a fake backend and verified manually in the App.
void main() {
  test('LAN snapshot carries the legacy registry copy verbatim', () async {
    final settings = await const WindowsSystemProxyBackend(notify: false)
        .read();
    final registry = await _registryValues();

    expect(
      settings.native.keys,
      containsAll(<String>[
        'ProxyEnable',
        'ProxyServer',
        'ProxyOverride',
        'AutoConfigURL',
      ]),
    );
    for (final name in ['ProxyServer', 'ProxyOverride', 'AutoConfigURL']) {
      expect(settings.native[name], registry[name], reason: name);
    }
    final enable = registry['ProxyEnable'];
    expect(
      settings.native['ProxyEnable'],
      enable == null ? null : int.parse(enable.substring(2), radix: 16),
    );
  });
}

Future<Map<String, String>> _registryValues() async {
  final result = await Process.run('reg', [
    'query',
    r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
  ]);
  final values = <String, String>{};
  for (final line in '${result.stdout}'.split('\n')) {
    final match = RegExp(
      r'^\s+(ProxyEnable|ProxyServer|ProxyOverride|AutoConfigURL)\s+REG_\w+\s+(.*?)\s*$',
    ).firstMatch(line);
    if (match != null) values[match[1]!] = match[2]!;
  }
  return values;
}
