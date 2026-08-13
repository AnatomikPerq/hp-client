import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/model/xray_standard.dart';
import 'package:onexray/service/xray/profile/enum.dart';

/// Выпускает собственный трафик sidecar'а minewire мимо туннеля.
///
/// Без этого правила подключение выглядит поднятым, но не работает:
/// в режиме TUN системный маршрут забирает ВЕСЬ трафик, включая исходящее
/// соединение самого minewire к серверу. Оно попадает в Xray, тот отправляет
/// его в outbound `proxy`, а `proxy` — это и есть локальный SOCKS minewire.
/// Получается замкнутая петля.
///
/// Ядро от такой петли защищено само: свои сокеты Xray привязывает к
/// физическому интерфейсу (`autoOutboundsInterface`). minewire — отдельный
/// процесс, на него это не распространяется, поэтому обход делаем правилом.
abstract final class XrayMinewireBypass {
  static const ruleTag = "minewire-direct";
  static const _freedomProtocol = "freedom";

  /// Вызывать ПОСЛЕ применения режима маршрутизации.
  ///
  /// Режим «Глобально» вырезает `routing` целиком, поэтому правило нужно
  /// возвращать поверх результата, а не добавлять в профиль заранее.
  /// Правила обхода отдельно от конфига: те же самые нужны и живому ядру
  /// через API, когда узел меняют без перезапуска.
  static List<XrayRoutingRule> buildRules(
    List<String> serverIps,
    int serverPort,
  ) {
    if (serverIps.isEmpty) {
      return const <XrayRoutingRule>[];
    }
    return <XrayRoutingRule>[
      XrayRoutingRuleStandard.standard
        ..ip = serverIps.map(_asCidr).toList()
        ..port = "$serverPort"
        ..outboundTag = RoutingOutboundTag.direct.name
        ..ruleTag = ruleTag,
    ];
  }

  static void apply(XrayJson xrayJson, List<String> serverIps, int serverPort) {
    final built = buildRules(serverIps, serverPort);
    if (built.isEmpty) {
      return;
    }
    _ensureDirectOutbound(xrayJson);

    final rule = built.first;
    final routing = xrayJson.routing ?? XrayRoutingStandard.standard;
    final rules = routing.rules ?? <XrayRoutingRule>[];
    rules.removeWhere((existing) => existing.ruleTag == ruleTag);
    // Строго первым: любое правило выше могло бы увести трафик в proxy.
    rules.insert(0, rule);
    routing.rules = rules;
    xrayJson.routing = routing;
  }

  static void _ensureDirectOutbound(XrayJson xrayJson) {
    final outbounds = xrayJson.outbounds ?? <XrayOutbound>[];
    final directTag = RoutingOutboundTag.direct.name;
    if (outbounds.any((outbound) => outbound.tag == directTag)) {
      xrayJson.outbounds = outbounds;
      return;
    }
    final direct = XrayOutboundStandard.standard
      ..protocol = _freedomProtocol
      ..tag = directTag;
    outbounds.add(direct);
    xrayJson.outbounds = outbounds;
  }

  static String _asCidr(String ip) {
    if (ip.contains('/')) {
      return ip;
    }
    return ip.contains(':') ? "$ip/128" : "$ip/32";
  }
}
