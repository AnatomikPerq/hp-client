import 'package:json_annotation/json_annotation.dart';

part 'ping_json.g.dart';

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PingJson {
  double? timeout;
  String? url;
  String? customUrl;
  @JsonKey(defaultValue: true)
  bool locationEnabled;

  PingJson(
    this.timeout,
    this.url,
    this.customUrl, {
    this.locationEnabled = true,
  });

  factory PingJson.fromJson(Map<String, dynamic> json) =>
      _$PingJsonFromJson(json);

  Map<String, dynamic> toJson() => _$PingJsonToJson(this);
}
