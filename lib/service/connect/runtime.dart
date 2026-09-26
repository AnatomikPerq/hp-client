import 'dart:convert';

import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/settings.dart';

/// One database value for all settings which can change a running connection.
class ConnectionConfiguration {
  final ConnectionSettings connection;
  final PlatformPolicy policy;

  ConnectionConfiguration({
    ConnectionSettings? connection,
    PlatformPolicy? policy,
  }) : connection = connection ?? ConnectionSettings(),
       policy = policy ?? PlatformPolicy.defaults();

  factory ConnectionConfiguration.fromJson(Map<String, dynamic> json) =>
      ConnectionConfiguration(
        connection: ConnectionSettings.fromJson(
          json['connection'] as Map<String, dynamic>? ?? {},
        ),
        policy: PlatformPolicy.fromJson(
          json['policy'] as Map<String, dynamic>? ?? {},
        ),
      );

  Map<String, dynamic> toJson() => {
    'connection': connection.toJson(),
    'policy': policy.toJson(),
  };
  String encode() => jsonEncode(toJson());
}

class RuntimeNode {
  final int id;
  final String name;

  const RuntimeNode({required this.id, required this.name});

  factory RuntimeNode.fromServer(ResolvedServer server) =>
      RuntimeNode(id: server.id, name: server.name);

  factory RuntimeNode.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! int || id <= 0 || name is! String || name.isEmpty) {
      throw const FormatException('Invalid runtime node');
    }
    return RuntimeNode(id: id, name: name);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// The prepared or active runtime input. It is never stored separately.
/// start.json retains only the small metadata required to restore the UI and
/// protect active nodes; the Xray JSON remains solely in coreInvokeText.
class ConnectionRuntime {
  final ConnectionConfiguration configuration;
  final ConnectionPlatform platform;
  final StartVpnRequest request;
  final String xrayJson;
  final List<RuntimeNode> entries;
  final RuntimeNode? finalExit;
  final String? notice;
  final DateTime startedAt;

  /// Local ports of the in-App minewire engines, by server id. A Core that
  /// outlives an App restart is compiled against them, so the next App
  /// session brings its engines back on the same ports.
  final Map<int, int> minewirePorts;

  ConnectionRuntime._({
    required this.configuration,
    required this.platform,
    required this.request,
    required this.xrayJson,
    required this.entries,
    required this.finalExit,
    required this.startedAt,
    this.notice,
    this.minewirePorts = const {},
  });

  factory ConnectionRuntime.create({
    required ConnectionConfiguration configuration,
    required CompiledConnection compiled,
    required ConnectionPlatform platform,
    required StartVpnRequest request,
    String? notice,
    DateTime? startedAt,
    Map<int, int> minewirePorts = const {},
  }) {
    startedAt ??= DateTime.now();
    final entries = [
      for (final server in compiled.entries) RuntimeNode.fromServer(server),
    ];
    final finalExit = compiled.finalExit == null
        ? null
        : RuntimeNode.fromServer(compiled.finalExit!);
    final metadataJson = jsonEncode({
      'version': 1,
      'startedAt': startedAt.microsecondsSinceEpoch,
      'platform': platform.name,
      'configuration': configuration.toJson(),
      'entries': [for (final entry in entries) entry.toJson()],
      'finalExit': finalExit?.toJson(),
      if (minewirePorts.isNotEmpty)
        'minewire': {
          for (final entry in minewirePorts.entries)
            '${entry.key}': entry.value,
        },
    });
    final storedRequest = StartVpnRequest(
      request.tun,
      request.socksPort,
      request.metricsPort,
      request.coreInvokeText,
      snapshotToken: request.snapshotToken,
      metadataJson: metadataJson,
    );
    return ConnectionRuntime._(
      configuration: configuration,
      platform: platform,
      request: storedRequest,
      xrayJson: compiled.xrayJson,
      entries: List.unmodifiable(entries),
      finalExit: finalExit,
      notice: notice,
      startedAt: startedAt,
      minewirePorts: Map.unmodifiable(minewirePorts),
    );
  }

  factory ConnectionRuntime.fromRequest(StartVpnRequest request) {
    final metadataText = request.metadataJson;
    final invokeText = request.coreInvokeText;
    if (metadataText == null ||
        utf8.encode(metadataText).length > 64 * 1024 ||
        invokeText == null) {
      throw const FormatException('Runtime metadata is unavailable');
    }
    final metadata = jsonDecode(metadataText);
    if (metadata is! Map<String, dynamic> ||
        metadata['version'] != 1 ||
        metadata['startedAt'] is! int ||
        metadata['platform'] is! String ||
        metadata['configuration'] is! Map<String, dynamic> ||
        metadata['entries'] is! List ||
        (metadata['entries'] as List).any(
          (entry) => entry is! Map<String, dynamic>,
        ) ||
        (metadata['finalExit'] != null &&
            metadata['finalExit'] is! Map<String, dynamic>)) {
      throw const FormatException('Invalid runtime metadata');
    }
    final run = LibXrayRunConfig.fromInvokeText(invokeText).request;
    if (run.xrayJson == null) {
      throw const FormatException('Invalid runtime request');
    }
    return ConnectionRuntime._(
      configuration: ConnectionConfiguration.fromJson(
        metadata['configuration'] as Map<String, dynamic>,
      ),
      platform: ConnectionPlatform.values.byName(
        metadata['platform'] as String,
      ),
      startedAt: DateTime.fromMicrosecondsSinceEpoch(
        metadata['startedAt'] as int,
      ),
      request: request,
      xrayJson: run.xrayJson!,
      entries: List.unmodifiable(
        (metadata['entries'] as List).map(
          (entry) => RuntimeNode.fromJson(entry as Map<String, dynamic>),
        ),
      ),
      finalExit: metadata['finalExit'] == null
          ? null
          : RuntimeNode.fromJson(metadata['finalExit'] as Map<String, dynamic>),
      minewirePorts: _minewirePorts(metadata['minewire']),
    );
  }

  static Map<int, int> _minewirePorts(Object? value) {
    if (value == null) return const {};
    if (value is! Map) throw const FormatException('Invalid minewire ports');
    final ports = <int, int>{};
    for (final entry in value.entries) {
      final id = int.tryParse('${entry.key}');
      final port = entry.value;
      if (id == null || id <= 0 || port is! int || port < 1 || port > 65535) {
        throw const FormatException('Invalid minewire ports');
      }
      ports[id] = port;
    }
    return Map.unmodifiable(ports);
  }

  String get identity =>
      '${startedAt.microsecondsSinceEpoch}:${request.metricsPort}';
  Set<int> get nodeIds => {
    for (final entry in entries) entry.id,
    if (finalExit != null) finalExit!.id,
  };
}
