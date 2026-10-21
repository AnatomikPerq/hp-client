import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/shared/share/xray_config_share.dart';
import 'package:onexray/service/shared/share/xray_share_reader.dart';
import 'package:onexray/service/shared/xray/validation.dart';
import 'package:onexray/service/shared/xray/remnawave.dart';

final class SubscriptionConfigurationResult {
  final List<CoreConfigCompanion> rows;
  final SubscriptionMode mode;

  SubscriptionConfigurationResult({
    required Iterable<CoreConfigCompanion> rows,
    required this.mode,
  }) : rows = List.unmodifiable(rows);

  int get count => rows.where((row) => row.type.value == activeType).length;

  String get activeType => mode == SubscriptionMode.providerManaged
      ? CoreConfigType.Remnawave.name
      : CoreConfigType.outbound.name;
}

/// A subscription's plaintext is classified before any single-node projection.
class SubscriptionConfigurationReader {
  final Future<String> Function(String, {String? ageSecretKey}) _decode;
  final Future<List<CoreConfigCompanion>> Function(String) _nodes;
  final Future<String> Function(String) _validate;
  final Future<void> Function(Future<void> Function()) _withFiles;

  SubscriptionConfigurationReader({
    Future<String> Function(String, {String? ageSecretKey})? decode,
    Future<List<CoreConfigCompanion>> Function(String)? readNodes,
    Future<String> Function(String)? validate,
    Future<void> Function(Future<void> Function())? withFiles,
  }) : _decode = decode ?? AppHostApi().decodeSubscriptionText,
       _nodes = readNodes ?? ((text) => XrayShareReader().parseShareText(text)),
       _validate = validate ?? AppHostApi().testXray,
       _withFiles =
           withFiles ?? ((action) => GeoDataService().withFiles(action));

  Future<SubscriptionConfigurationResult> read(
    String text,
    SubscriptionInput input,
  ) async {
    final plaintext = await _decode(
      text,
      ageSecretKey: input.normalizedAgeSecretKey,
    );
    Object? value;
    try {
      value = JsonTool.decoder.convert(plaintext);
    } on FormatException {
      final start = plaintext.trimLeft();
      if (start.startsWith('{') || start.startsWith('[')) rethrow;
    }
    final complete =
        value is List ||
        (value is Map<String, dynamic> &&
            value.keys.any((key) => key != 'outbounds'));
    if (!complete) {
      if (input.panel == SubscriptionPanel.remnawave ||
          input.mode == SubscriptionMode.providerManaged) {
        throw const FormatException(
          'The subscription must contain complete Xray JSON configurations',
        );
      }
      final rows = await _nodes(plaintext);
      if (rows.isEmpty) {
        throw const FormatException(
          'The subscription contains no usable nodes',
        );
      }
      return SubscriptionConfigurationResult(
        rows: rows,
        mode: SubscriptionMode.appManaged,
      );
    }

    final values = value is List ? value : [value];
    if (values.isEmpty || values.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException(
        'The subscription must contain Xray configuration objects',
      );
    }
    final configs = values.cast<Map<String, dynamic>>();
    final rows = <CoreConfigCompanion>[];
    await _withFiles(() async {
      for (final (index, config) in configs.indexed) {
        final error = await _validate(
          XrayValidation.raw(RemnawaveAdapter.adapt(config)),
        );
        if (error.isNotEmpty) throw FormatException(error);
        final name =
            [config['remarks'], config['name']]
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .firstOrNull ??
            '${input.name} ${index + 1}';
        rows.add(
          CoreConfigCompanion.insert(
            name: name,
            type: CoreConfigType.Remnawave.name,
            tags: '',
            data: Value(base64Encode(utf8.encode(jsonEncode(config)))),
            delay: PingDelayConstants.unknown,
            subId: DBConstants.defaultId,
          ),
        );
        // The same configuration's proxies as ordinary nodes, for the App's
        // own routing: named after its `remarks`, mux kept, chained ones
        // skipped (see xrayConfigOutbounds).
        for (final outbound
            in xrayConfigOutbounds(jsonEncode(config)) ?? const []) {
          rows.add(outboundCompanion(outbound));
        }
      }
    });
    final nodes = rows.where(
      (row) => row.type.value == CoreConfigType.outbound.name,
    );
    // App-managed by default: the provider's graph bypasses the App's
    // routing, live switch and leak protections, so it is opt-in. A source
    // whose configurations have no standalone node falls back to them.
    final result = SubscriptionConfigurationResult(
      rows: rows,
      mode:
          input.mode ??
          (nodes.isEmpty
              ? SubscriptionMode.providerManaged
              : SubscriptionMode.appManaged),
    );
    if (result.count == 0) {
      throw const FormatException(
        'The selected mode contains no usable configurations',
      );
    }
    return result;
  }
}
