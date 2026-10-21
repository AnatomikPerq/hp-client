import 'dart:convert';

import 'package:onexray/core/ffi/desktop_kill_switch.dart';

/// libXray's kill switch methods, without libXray: the filters are a flag.
class FakeKillSwitchLib {
  bool engaged = false;

  /// The App's user may not lift the filters (another account elevated the
  /// Core); only the elevated fallback can.
  bool denyLift = false;

  /// libXray itself fails.
  bool broken = false;
  int lifts = 0;
  int elevatedLifts = 0;
  Map<String, Object> session = {'bootedAt': 1000000, 'logon': '0-1'};

  Future<String> invoke(String requestJson) async {
    if (broken) {
      return jsonEncode({'success': false, 'data': null, 'error': 'broken'});
    }
    final method = (jsonDecode(requestJson) as Map<String, dynamic>)['method'];
    switch (method) {
      case 'killSwitchState':
        return jsonEncode({
          'success': true,
          'data': {'engaged': engaged, 'session': session},
          'error': '',
        });
      case 'liftKillSwitch':
        lifts++;
        if (denyLift && engaged) {
          return jsonEncode({
            'success': false,
            'data': null,
            'error': 'Access is denied.',
          });
        }
        engaged = false;
        return jsonEncode({'success': true, 'data': null, 'error': ''});
    }
    throw StateError('unexpected libXray method $method');
  }

  DesktopKillSwitchControl control(String runDirectory) =>
      DesktopKillSwitchControl(
        runDirectory: () async => runDirectory,
        invoke: invoke,
        liftElevated: () async {
          elevatedLifts++;
          engaged = false;
        },
      );
}
