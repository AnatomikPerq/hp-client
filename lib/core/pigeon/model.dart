import 'package:json_annotation/json_annotation.dart';
import 'package:onexray/core/model/tun_json.dart';
import 'package:onexray/core/tools/json.dart';

part 'model.g.dart';

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class StartVpnRequest {
  TunJson? tun;
  String? socksPort;
  String? metricsPort;
  String? coreInvokeText;
  String? snapshotToken;
  String? metadataJson;

  /// Desktop proxy mode only: the user's hosts that bypass the system proxy.
  /// Absent elsewhere, so the native start request contract is unchanged.
  List<String>? systemProxyBypass;

  /// Desktop only: keep apps offline when the Core dies, until the user
  /// disconnects. Absent when the kill switch is off and on other platforms.
  DesktopKillSwitch? killSwitch;

  StartVpnRequest(
    this.tun,
    this.socksPort,
    this.metricsPort,
    this.coreInvokeText, {
    this.snapshotToken,
    this.metadataJson,
    this.systemProxyBypass,
    this.killSwitch,
  });

  factory StartVpnRequest.fromJson(Map<String, dynamic> json) =>
      _$StartVpnRequestFromJson(json);

  Map<String, dynamic> toJson() => _$StartVpnRequestToJson(this);
}

/// What the desktop kill switch lets through and how long it holds.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class DesktopKillSwitch {
  /// TUN mode: the local network stays reachable while traffic is blocked.
  final bool allowLan;

  /// The block survives the end of the Windows session (log off, shutdown,
  /// restart). Otherwise a new session starts unblocked.
  final bool strict;

  const DesktopKillSwitch({required this.allowLan, required this.strict});

  factory DesktopKillSwitch.fromJson(Map<String, dynamic> json) =>
      _$DesktopKillSwitchFromJson(json);

  Map<String, dynamic> toJson() => _$DesktopKillSwitchToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class LibXrayInvokeResponse {
  final bool success;
  final Map<String, dynamic>? data;
  final String error;

  LibXrayInvokeResponse(this.success, this.data, this.error);

  factory LibXrayInvokeResponse.fromJson(Map<String, dynamic> json) =>
      _$LibXrayInvokeResponseFromJson(json);

  Map<String, dynamic> toJson() => _$LibXrayInvokeResponseToJson(this);
}

final class LibXrayInvokeException implements Exception {
  const LibXrayInvokeException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class LibXrayErrorMessage {
  static const invalidAgeSecretKey = 'invalid or unsupported age secret key';
  static const missingAgeSecretKey = 'missing age secret key';
  static const ageDecryptFailed = 'unable to decrypt age subscription';
  static const malformedAgeArmor = 'malformed age armor';
  static const agePlaintextTooLarge =
      'decrypted subscription exceeds the 16 MiB size limit';
  static const agePlaintextUnsupported =
      'decrypted subscription is unsupported';
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class GetFreePortsResponse {
  List<int>? ports;

  GetFreePortsResponse(this.ports);

  factory GetFreePortsResponse.fromJson(Map<String, dynamic> json) =>
      _$GetFreePortsResponseFromJson(json);

  Map<String, dynamic> toJson() => _$GetFreePortsResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ConvertXrayJsonToShareLinksResponse {
  String? links;

  ConvertXrayJsonToShareLinksResponse(this.links);

  factory ConvertXrayJsonToShareLinksResponse.fromJson(
    Map<String, dynamic> json,
  ) => _$ConvertXrayJsonToShareLinksResponseFromJson(json);

  Map<String, dynamic> toJson() =>
      _$ConvertXrayJsonToShareLinksResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PingBatchResponse {
  List<PingBatchItemResponse>? results;

  PingBatchResponse(this.results);

  factory PingBatchResponse.fromJson(Map<String, dynamic> json) =>
      _$PingBatchResponseFromJson(json);

  Map<String, dynamic> toJson() => _$PingBatchResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PingBatchItemResponse {
  bool? success;
  int? delay;
  String? error;
  String? locationJson;
  String? locationError;

  PingBatchItemResponse(
    this.success,
    this.delay,
    this.error, {
    this.locationJson,
    this.locationError,
  });

  factory PingBatchItemResponse.fromJson(Map<String, dynamic> json) =>
      _$PingBatchItemResponseFromJson(json);

  Map<String, dynamic> toJson() => _$PingBatchItemResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayVersionResponse {
  String? version;

  XrayVersionResponse(this.version);

  factory XrayVersionResponse.fromJson(Map<String, dynamic> json) =>
      _$XrayVersionResponseFromJson(json);

  Map<String, dynamic> toJson() => _$XrayVersionResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class CountGeoDataRequest {
  String? name;
  String? geoType;
  String? datDir;

  CountGeoDataRequest(this.name, this.geoType, {this.datDir});

  factory CountGeoDataRequest.fromJson(Map<String, dynamic> json) =>
      _$CountGeoDataRequestFromJson(json);

  Map<String, dynamic> toJson() => _$CountGeoDataRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PingBatchRequest {
  List<PingBatchItemRequest>? configs;
  int? timeout;
  String? url;
  String? locationUrl;

  PingBatchRequest(this.configs, this.timeout, this.url, {this.locationUrl});

  factory PingBatchRequest.fromJson(Map<String, dynamic> json) =>
      _$PingBatchRequestFromJson(json);

  Map<String, dynamic> toJson() => _$PingBatchRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PingBatchItemRequest {
  String? xrayJson;
  String? outboundTag;

  PingBatchItemRequest(this.xrayJson, {this.outboundTag});

  factory PingBatchItemRequest.fromJson(Map<String, dynamic> json) =>
      _$PingBatchItemRequestFromJson(json);

  Map<String, dynamic> toJson() => _$PingBatchItemRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class RunXrayRequest {
  String? xrayJson;

  RunXrayRequest(this.xrayJson);

  factory RunXrayRequest.fromJson(Map<String, dynamic> json) =>
      _$RunXrayRequestFromJson(json);

  Map<String, dynamic> toJson() => _$RunXrayRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class TestXrayRequest {
  String? xrayJson;

  TestXrayRequest(this.xrayJson);

  factory TestXrayRequest.fromJson(Map<String, dynamic> json) =>
      _$TestXrayRequestFromJson(json);

  Map<String, dynamic> toJson() => _$TestXrayRequestToJson(this);
}

enum LibXrayMethod {
  @JsonValue("getFreePorts")
  getFreePorts,
  @JsonValue("convertShareLinksToXrayJson")
  convertShareLinksToXrayJson,
  @JsonValue("convertXrayJsonToShareLinks")
  convertXrayJsonToShareLinks,
  @JsonValue("generateAgeKeyPair")
  generateAgeKeyPair,
  @JsonValue("countGeoData")
  countGeoData,
  @JsonValue("pingBatch")
  pingBatch,
  @JsonValue("testXray")
  testXray,
  @JsonValue("runXray")
  runXray,
  @JsonValue("stopXray")
  stopXray,
  @JsonValue("xrayVersion")
  xrayVersion,
  @JsonValue("startMinewire")
  startMinewire,
  @JsonValue("stopMinewire")
  stopMinewire,
  @JsonValue("minewireState")
  minewireState,
  @JsonValue("controlXray")
  controlXray,
  @JsonValue("killSwitchState")
  killSwitchState,
  @JsonValue("liftKillSwitch")
  liftKillSwitch,
  @JsonValue("resolveHost")
  resolveHost,
}

/// Starts one embedded minewire engine (HYPER CLIENT libXray fork). The server
/// address is already resolved: once the tunnel is up, DNS may depend on it.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class StartMinewireRequest {
  String? serverAddress;
  String? password;
  String? mode;
  int? localPort;

  /// Binds the engine's uplink to this interface (desktop TUN). Older
  /// libXray builds ignore it.
  @JsonKey(name: 'interface')
  String? interfaceName;

  /// The engine's diagnostics file (`run/minewire.log`); throwaway ping
  /// engines leave it empty. Older libXray builds ignore it.
  String? logFile;

  StartMinewireRequest(
    this.serverAddress,
    this.password, {
    this.mode,
    this.localPort,
    this.interfaceName,
    this.logFile,
  });

  factory StartMinewireRequest.fromJson(Map<String, dynamic> json) =>
      _$StartMinewireRequestFromJson(json);

  Map<String, dynamic> toJson() => _$StartMinewireRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class StartMinewireResponse {
  int? localPort;

  StartMinewireResponse(this.localPort);

  factory StartMinewireResponse.fromJson(Map<String, dynamic> json) =>
      _$StartMinewireResponseFromJson(json);

  Map<String, dynamic> toJson() => _$StartMinewireResponseToJson(this);
}

/// Stops the engine on [localPort], or every engine when it is omitted.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class StopMinewireRequest {
  int? localPort;

  StopMinewireRequest({this.localPort});

  factory StopMinewireRequest.fromJson(Map<String, dynamic> json) =>
      _$StopMinewireRequestFromJson(json);

  Map<String, dynamic> toJson() => _$StopMinewireRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class MinewireEngineState {
  int? localPort;
  bool? running;
  bool? connected;
  String? lastError;

  MinewireEngineState(
    this.localPort,
    this.running,
    this.connected,
    this.lastError,
  );

  factory MinewireEngineState.fromJson(Map<String, dynamic> json) =>
      _$MinewireEngineStateFromJson(json);

  Map<String, dynamic> toJson() => _$MinewireEngineStateToJson(this);
}

/// Resolves a server name with libXray's own resolver, from the App process.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ResolveHostRequest {
  final String host;
  final int? timeoutSeconds;

  const ResolveHostRequest(this.host, {this.timeoutSeconds});

  factory ResolveHostRequest.fromJson(Map<String, dynamic> json) =>
      _$ResolveHostRequestFromJson(json);

  Map<String, dynamic> toJson() => _$ResolveHostRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ResolveHostResponse {
  final List<String>? addresses;

  const ResolveHostResponse(this.addresses);

  factory ResolveHostResponse.fromJson(Map<String, dynamic> json) =>
      _$ResolveHostResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ResolveHostResponseToJson(this);
}

/// The user's session as libXray reads it: the boot and the logon.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class KillSwitchSession {
  /// Unix milliseconds; clock corrections move it a little.
  final int bootedAt;
  final String logon;

  const KillSwitchSession({required this.bootedAt, required this.logon});

  /// Whether [other] was read in this session: the same logon of the same
  /// boot. Fast startup keeps the boot time across a shutdown, not the logon.
  bool sameAs(KillSwitchSession other) =>
      logon == other.logon &&
      (bootedAt - other.bootedAt).abs() <=
          const Duration(minutes: 2).inMilliseconds;

  factory KillSwitchSession.fromJson(Map<String, dynamic> json) =>
      _$KillSwitchSessionFromJson(json);

  Map<String, dynamic> toJson() => _$KillSwitchSessionToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class KillSwitchStateResponse {
  final bool engaged;
  final KillSwitchSession session;

  const KillSwitchStateResponse({required this.engaged, required this.session});

  factory KillSwitchStateResponse.fromJson(Map<String, dynamic> json) =>
      _$KillSwitchStateResponseFromJson(json);

  Map<String, dynamic> toJson() => _$KillSwitchStateResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class MinewireStateResponse {
  List<MinewireEngineState>? engines;

  MinewireStateResponse(this.engines);

  factory MinewireStateResponse.fromJson(Map<String, dynamic> json) =>
      _$MinewireStateResponseFromJson(json);

  Map<String, dynamic> toJson() => _$MinewireStateResponseToJson(this);
}

/// One call on a running Core's API, applied in order by `controlXray`.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ControlXrayOperation {
  /// `removeOutbound`, `addOutbound`, `removeRule` or `addRules`.
  String op;
  String? tag;
  Map<String, dynamic>? outbound;
  Map<String, dynamic>? routing;
  bool? append;

  ControlXrayOperation(
    this.op, {
    this.tag,
    this.outbound,
    this.routing,
    this.append,
  });

  factory ControlXrayOperation.fromJson(Map<String, dynamic> json) =>
      _$ControlXrayOperationFromJson(json);

  Map<String, dynamic> toJson() => _$ControlXrayOperationToJson(this);
}

/// The Core's API is reachable only through its password-protected loopback
/// SOCKS inbound; see `controlXray` in the libXray fork.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ControlXrayRequest {
  String server;
  String username;
  String password;
  int? timeoutSeconds;
  List<ControlXrayOperation> operations;

  /// Where geosite.dat and geoip.dat are. The rules are built in the App's
  /// process, which, unlike the Core, has no asset location of its own.
  String? assetDir;

  ControlXrayRequest(
    this.server,
    this.username,
    this.password,
    this.operations, {
    this.timeoutSeconds,
    this.assetDir,
  });

  factory ControlXrayRequest.fromJson(Map<String, dynamic> json) =>
      _$ControlXrayRequestFromJson(json);

  Map<String, dynamic> toJson() => _$ControlXrayRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class LibXrayInvokeRequest {
  int? apiVersion;
  LibXrayMethod? method;
  Map<String, dynamic>? payload;

  LibXrayInvokeRequest({this.method, this.payload}) : apiVersion = 3;

  factory LibXrayInvokeRequest.fromJson(Map<String, dynamic> json) =>
      _$LibXrayInvokeRequestFromJson(json);

  Map<String, dynamic> toJson() => _$LibXrayInvokeRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class GetFreePortsRequest {
  int? count;
  List<int>? excludePorts;

  GetFreePortsRequest(this.count, {this.excludePorts});

  factory GetFreePortsRequest.fromJson(Map<String, dynamic> json) =>
      _$GetFreePortsRequestFromJson(json);

  Map<String, dynamic> toJson() => _$GetFreePortsRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ConvertShareLinksToXrayJsonRequest {
  String? text;
  AgeDecryptConfig? age;

  ConvertShareLinksToXrayJsonRequest(this.text, {this.age});

  factory ConvertShareLinksToXrayJsonRequest.fromJson(
    Map<String, dynamic> json,
  ) => _$ConvertShareLinksToXrayJsonRequestFromJson(json);

  Map<String, dynamic> toJson() =>
      _$ConvertShareLinksToXrayJsonRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class AgeDecryptConfig {
  String? secretKey;

  AgeDecryptConfig(this.secretKey);

  factory AgeDecryptConfig.fromJson(Map<String, dynamic> json) =>
      _$AgeDecryptConfigFromJson(json);

  Map<String, dynamic> toJson() => _$AgeDecryptConfigToJson(this);
}

enum AgeKeyType {
  @JsonValue("x25519")
  x25519,
  @JsonValue("hybrid")
  hybrid,
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class GenerateAgeKeyPairRequest {
  AgeKeyType? keyType;

  GenerateAgeKeyPairRequest(this.keyType);

  factory GenerateAgeKeyPairRequest.fromJson(Map<String, dynamic> json) =>
      _$GenerateAgeKeyPairRequestFromJson(json);

  Map<String, dynamic> toJson() => _$GenerateAgeKeyPairRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class GenerateAgeKeyPairResponse {
  String? secretKey;
  String? publicKey;

  GenerateAgeKeyPairResponse(this.secretKey, this.publicKey);

  factory GenerateAgeKeyPairResponse.fromJson(Map<String, dynamic> json) =>
      _$GenerateAgeKeyPairResponseFromJson(json);

  Map<String, dynamic> toJson() => _$GenerateAgeKeyPairResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ConvertXrayJsonToShareLinksRequest {
  String? xrayJson;

  ConvertXrayJsonToShareLinksRequest(this.xrayJson);

  factory ConvertXrayJsonToShareLinksRequest.fromJson(
    Map<String, dynamic> json,
  ) => _$ConvertXrayJsonToShareLinksRequestFromJson(json);

  Map<String, dynamic> toJson() =>
      _$ConvertXrayJsonToShareLinksRequestToJson(this);
}

class LibXrayRunConfig {
  final LibXrayInvokeRequest invoke;
  final RunXrayRequest request;

  LibXrayRunConfig(this.invoke)
    : request = RunXrayRequest.fromJson(invoke.payload ?? const {});

  factory LibXrayRunConfig.fromInvokeText(String text) {
    final data = JsonTool.decoder.convert(text) as Map<String, dynamic>;
    final invoke = LibXrayInvokeRequest.fromJson(data);
    return LibXrayRunConfig(invoke);
  }
}
