import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/json.dart';

/// Authenticated access to a running desktop Core's API.
///
/// On Windows the TUN Core runs elevated, so every restart costs a UAC prompt.
/// A node switch only changes outbounds and routing, which the Core's
/// HandlerService and RoutingService apply to the live instance. Xray's gRPC
/// API itself has no authentication, and whoever reaches it can add inbounds
/// or reroute an elevated process's traffic. The Core therefore never opens
/// a raw API listener: this loopback SOCKS inbound with a random per-session
/// password is routed to the `api` outbound, and libXray's `controlXray`
/// dials through it.
class LiveControl {
  static const inboundTag = 'app-control';
  static const apiTag = 'api';
  static const username = 'app';

  final int port;
  final String password;

  const LiveControl({required this.port, required this.password});

  factory LiveControl.create(int port, {Random? random}) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(24, (_) => source.nextInt(256));
    return LiveControl(
      port: port,
      password: base64Url.encode(bytes).replaceAll('=', ''),
    );
  }

  factory LiveControl.fromJson(Map<String, dynamic> json) {
    final port = json['port'];
    final password = json['password'];
    if (port is! int ||
        port < 1 ||
        port > 65535 ||
        password is! String ||
        password.length < 16) {
      throw const FormatException('Invalid live control');
    }
    return LiveControl(port: port, password: password);
  }

  Map<String, dynamic> toJson() => {'port': port, 'password': password};

  String get server => '127.0.0.1:$port';

  /// Adds the control inbound, the API section and the first routing rule.
  void apply(Map<String, dynamic> config) {
    config['api'] = {
      'tag': apiTag,
      'services': ['HandlerService', 'RoutingService'],
    };
    config['inbounds'] = [
      ...(config['inbounds'] as List? ?? const []),
      {
        'tag': inboundTag,
        'listen': '127.0.0.1',
        'port': port,
        'protocol': 'socks',
        'settings': {
          'auth': 'password',
          'accounts': [
            {'user': username, 'pass': password},
          ],
          'udp': false,
        },
      },
    ];
    final current = config['routing'];
    final routing = <String, dynamic>{
      if (current is Map) ...current.cast<String, dynamic>(),
    };
    routing['rules'] = <dynamic>[
      {
        'ruleTag': inboundTag,
        'inboundTag': [inboundTag],
        'outboundTag': apiTag,
      },
      ...(routing['rules'] as List? ?? const []),
    ];
    config['routing'] = routing;
  }

  /// Whether [next] differs from [running] only in what the API can change
  /// on a live Core: outbounds, routing rules and balancers.
  static bool swappable(
    Map<String, dynamic> running,
    Map<String, dynamic> next,
  ) {
    Map<String, dynamic> fixed(Map<String, dynamic> config) {
      final copy = JsonTool.copyMap(config)..remove('outbounds');
      final routing = copy['routing'];
      if (routing is Map<String, dynamic>) {
        routing
          ..remove('rules')
          ..remove('balancers');
      }
      return copy;
    }

    return const DeepCollectionEquality().equals(fixed(running), fixed(next));
  }

  /// API calls that turn [running] into [next].
  ///
  /// Xray's first outbound handles traffic no rule matches. Removing the
  /// current default leaves none until the next outbound is added, which then
  /// becomes the default; so the first outbound is always replaced, and the
  /// others only when they changed. Routing is replaced in one step: rules
  /// and balancers together, including the control rule itself.
  static List<ControlXrayOperation> operations(
    Map<String, dynamic> running,
    Map<String, dynamic> next,
  ) {
    List<Map<String, dynamic>> outbounds(Map<String, dynamic> config) => [
      for (final value in config['outbounds'] as List? ?? const [])
        value as Map<String, dynamic>,
    ];
    final before = outbounds(running);
    final after = outbounds(next);
    if (after.isEmpty || after.any((outbound) => outbound['tag'] is! String)) {
      throw const FormatException('Live swap needs tagged outbounds');
    }
    const equality = DeepCollectionEquality();
    bool kept(Map<String, dynamic> outbound, int indexBefore) {
      if (indexBefore == 0) return false;
      final indexAfter = after.indexWhere(
        (candidate) => candidate['tag'] == outbound['tag'],
      );
      return indexAfter > 0 && equality.equals(after[indexAfter], outbound);
    }

    final keptTags = <String>{
      for (final (index, outbound) in before.indexed)
        if (kept(outbound, index)) outbound['tag'] as String,
    };
    return [
      for (final outbound in before)
        if (!keptTags.contains(outbound['tag']))
          ControlXrayOperation(
            'removeOutbound',
            tag: outbound['tag'] as String,
          ),
      for (final outbound in after)
        if (!keptTags.contains(outbound['tag']))
          ControlXrayOperation('addOutbound', outbound: outbound),
      ControlXrayOperation(
        'addRules',
        routing: {
          'rules': (next['routing'] as Map?)?['rules'] ?? const [],
          'balancers': ?(next['routing'] as Map?)?['balancers'],
        },
      ),
    ];
  }
}
