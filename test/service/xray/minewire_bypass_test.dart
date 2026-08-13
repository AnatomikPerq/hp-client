import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/model/xray_standard.dart';
import 'package:onexray/service/core_routing_mode/state.dart';
import 'package:onexray/service/xray/minewire_bypass.dart';
import 'package:onexray/service/xray/profile/enum.dart';
import 'package:onexray/service/xray/routing_mode.dart';

XrayOutbound _outbound(String tag, String protocol) =>
    XrayOutboundStandard.standard
      ..tag = tag
      ..protocol = protocol;

XrayJson _config() {
  final json = XrayJsonStandard.standard;
  json.outbounds = <XrayOutbound>[
    _outbound(RoutingOutboundTag.proxy.name, 'socks'),
    _outbound(RoutingOutboundTag.direct.name, 'freedom'),
  ];
  final rule = XrayRoutingRuleStandard.standard
    ..outboundTag = RoutingOutboundTag.proxy.name
    ..ruleTag = 'existing';
  json.routing = XrayRoutingStandard.standard..rules = <XrayRoutingRule>[rule];
  return json;
}

void main() {
  group('XrayMinewireBypass', () {
    test('puts the server rule first so nothing can steal the traffic', () {
      final json = _config();
      XrayMinewireBypass.apply(json, ['1.2.3.4'], 25565);

      final rules = json.routing!.rules!;
      expect(rules.first.ruleTag, XrayMinewireBypass.ruleTag);
      expect(rules.first.ip, ['1.2.3.4/32']);
      expect(rules.first.port, '25565');
      expect(rules.first.outboundTag, RoutingOutboundTag.direct.name);
      expect(rules.last.ruleTag, 'existing');
    });

    test('survives Global mode, which wipes routing entirely', () {
      final json = _config();
      expect(
        XrayRoutingModeFix.applyToXrayJson(json, CoreRoutingMode.global),
        isTrue,
      );
      // Режим «Глобально» действительно сносит маршрутизацию...
      expect(json.routing, isNull);

      XrayMinewireBypass.apply(json, ['1.2.3.4'], 25565);

      // ...а обход возвращается поверх и тянет за собой direct-outbound,
      // иначе правилу некуда было бы отправить трафик.
      expect(json.routing?.rules?.first.ruleTag, XrayMinewireBypass.ruleTag);
      expect(
        json.outbounds!.any((o) => o.tag == RoutingOutboundTag.direct.name),
        isTrue,
      );
    });

    test('marks IPv6 addresses with the right prefix', () {
      final json = _config();
      XrayMinewireBypass.apply(json, ['2a00:1450::1', '1.2.3.4'], 443);
      expect(json.routing!.rules!.first.ip, ['2a00:1450::1/128', '1.2.3.4/32']);
    });

    test('does not stack duplicates across restarts', () {
      final json = _config();
      XrayMinewireBypass.apply(json, ['1.2.3.4'], 25565);
      XrayMinewireBypass.apply(json, ['5.6.7.8'], 25565);

      final tagged = json.routing!.rules!
          .where((rule) => rule.ruleTag == XrayMinewireBypass.ruleTag)
          .toList();
      expect(tagged, hasLength(1));
      expect(tagged.single.ip, ['5.6.7.8/32']);
    });

    test('does nothing without resolved addresses', () {
      final json = _config();
      XrayMinewireBypass.apply(json, const [], 25565);
      expect(json.routing!.rules!.single.ruleTag, 'existing');
    });
  });
}
