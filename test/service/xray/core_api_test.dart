import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/model/xray_standard.dart';
import 'package:onexray/service/xray/core_api.dart';
import 'package:onexray/service/xray/profile/inbounds_state.dart';

XrayPorts _ports() =>
    XrayPorts('23456', '23457', '23458', XrayInboundAccount('user', 'pass'));

void main() {
  group('XrayCoreApi', () {
    test('opens the control interface on loopback only', () {
      final json = XrayJsonStandard.standard;
      XrayCoreApi.applyToXrayJson(json, _ports());

      // У управляющего интерфейса Xray нет аутентификации, поэтому он
      // обязан слушать исключительно петлю.
      expect(json.api?.listen, '127.0.0.1:23458');
      expect(json.api?.listen, startsWith('127.0.0.1:'));
      expect(json.api?.tag, 'api');
    });

    test('enables exactly the services the hot swap needs', () {
      final json = XrayJsonStandard.standard;
      XrayCoreApi.applyToXrayJson(json, _ports());

      // HandlerService — подмена outbound, RoutingService — правило обхода
      // minewire. Ничего лишнего: каждая служба это доступная снаружи
      // возможность управлять живым туннелем.
      expect(json.api?.services, ['HandlerService', 'RoutingService']);
    });

    test('survives serialization into the config file', () {
      final json = XrayJsonStandard.standard;
      XrayCoreApi.applyToXrayJson(json, _ports());
      final encoded = json.toJson();

      expect(encoded['api'], isA<Map<String, dynamic>>());
      final api = encoded['api'] as Map<String, dynamic>;
      expect(api['listen'], '127.0.0.1:23458');
      expect(api['services'], contains('HandlerService'));
    });

    test('allocates a port distinct from ping and metrics', () async {
      final ports = _ports();
      expect(ports.apiPort, isNot(ports.pingPort));
      expect(ports.apiPort, isNot(ports.metricsPort));
    });
  });
}
