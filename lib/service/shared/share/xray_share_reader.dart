import 'package:flutter/foundation.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/minewire/share.dart';

class XrayShareReader {
  Future<List<CoreConfigCompanion>> parseShareText(
    String text, {
    String? ageSecretKey,
    Future<List<Map<String, dynamic>>> Function(String text, String? key)?
    convert,
  }) async {
    final split = splitMinewireLinks(text);
    final minewire = [for (final link in split.links) link.toOutbound()];
    final convertLinks =
        convert ??
        (String text, String? key) =>
            AppHostApi().convertShareLinksToXrayJson(text, ageSecretKey: key);
    List<Map<String, dynamic>> outbounds = const [];
    if (split.rest.trim().isNotEmpty) {
      try {
        outbounds = await convertLinks(split.rest, ageSecretKey);
      } catch (_) {
        // libXray fails when nothing it knows remains; minewire nodes alone
        // are still a valid import.
        if (minewire.isEmpty) rethrow;
      }
    }
    return readXrayJsonOutbounds({
      'outbounds': [...outbounds, ...minewire],
    });
  }

  @visibleForTesting
  Future<List<CoreConfigCompanion>> readXrayJsonOutbounds(
    Map<String, dynamic> xrayJson,
  ) async {
    final res = <CoreConfigCompanion>[];
    final outbounds = xrayJson['outbounds'];
    if (outbounds is! List<dynamic>) {
      return res;
    }

    for (var index = 0; index < outbounds.length; index++) {
      if (index > 0 && index % 64 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final value = outbounds[index];
      if (value is! Map<String, dynamic>) {
        continue;
      }
      final outbound = copyOutboundMap(value);
      try {
        res.add(outboundCompanion(outbound));
      } catch (error, stackTrace) {
        ygLogger(
          "Failed to read imported outbound (${error.runtimeType})\n$stackTrace",
        );
      }
    }
    return res;
  }
}
