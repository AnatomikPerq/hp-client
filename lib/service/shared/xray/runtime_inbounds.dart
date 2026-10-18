import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/network/constants.dart';
import 'package:onexray/core/pigeon/constants.dart';

const lanProxyInboundTag = 'app-lan-proxy';
const defaultLanProxyPort = 11024;

XrayInbound createTunInbound({
  List<String>? gateway,
  List<String>? dns,
  List<String>? autoSystemRoutingTable,
  String? autoOutboundsInterface,
  List<String>? autoSystemWfpBlockLeak,
  bool fakeDns = false,
}) => XrayInbound(
  listen: NetConstants.proxyHost,
  protocol: 'tun',
  settings: XrayInboundTunSettings(
    name: 'HyperClientTun',
    mtu: VpnConstants.tunMtu,
    gateway: gateway,
    dns: dns,
    autoSystemRoutingTable: autoSystemRoutingTable,
    autoOutboundsInterface: autoOutboundsInterface,
    autoSystemWfpBlockLeak: autoSystemWfpBlockLeak,
  ).toJson(),
  tag: 'tunIn',
  sniffing: _createSniffing(fakeDns),
);

XrayInbound createSocksInbound(String port, {bool fakeDns = false}) =>
    XrayInbound(
      listen: NetConstants.proxyHost,
      port: port,
      protocol: 'socks',
      settings: XrayInboundSocksSettings(auth: 'noauth', udp: true).toJson(),
      tag: 'tunIn',
      sniffing: _createSniffing(fakeDns),
    );

/// SOCKS5 and HTTP for other devices on the network, always with an
/// account: an open proxy on every interface would serve anyone who finds it.
XrayInbound createLanProxyInbound(
  int port, {
  required String user,
  required String password,
  bool fakeDns = false,
}) {
  if (user.isEmpty || password.isEmpty) {
    throw const FormatException('LAN proxy sharing needs a login and password');
  }
  return XrayInbound(
    listen: '0.0.0.0',
    port: '$port',
    protocol: 'socks',
    settings: {
      ...XrayInboundSocksSettings(auth: 'password', udp: true).toJson(),
      'accounts': [
        {'user': user, 'pass': password},
      ],
    },
    tag: lanProxyInboundTag,
    sniffing: _createSniffing(fakeDns),
  );
}

XrayInboundSniffing _createSniffing(bool fakeDns) => XrayInboundSniffing(
  enabled: true,
  routeOnly: false,
  destOverride: ['http', 'tls', 'quic', if (fakeDns) 'fakedns'],
);
