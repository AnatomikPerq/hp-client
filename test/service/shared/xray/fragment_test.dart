import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/shared/xray/fragment.dart';

Map<String, dynamic> _vless(String tag, String security) => {
  'tag': tag,
  'protocol': 'vless',
  'settings': {'address': 'node.example', 'port': 443},
  'streamSettings': {'network': 'tcp', 'security': security},
};

void main() {
  test('Fragment leaves REALITY entries direct', () {
    final entries = XrayFragment.connectEntries(
      [_vless('reality', 'reality'), _vless('tls', 'tls')],
      [XrayFragment.defaultOutbound()],
    );
    expect(outboundDialerProxy(entries.first), isNull);
    expect(outboundDialerProxy(entries.last), XrayFragment.tag);
  });

  test('Without the fragment helper no entry is linked', () {
    final entries = XrayFragment.connectEntries([_vless('tls', 'tls')], []);
    expect(outboundDialerProxy(entries.single), isNull);
  });
}
