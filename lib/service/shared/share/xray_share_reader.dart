import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/minewire/share.dart';
import 'package:onexray/service/shared/share/xray_config_share.dart';
import 'package:onexray/service/shared/xray/validation.dart';

class XrayShareReader {
  Future<List<CoreConfigCompanion>> parseShareText(
    String text, {
    String? ageSecretKey,
    Future<List<Map<String, dynamic>>> Function(String text, String? key)?
    convert,
    Future<String> Function(String xrayJson)? validate,
  }) async {
    // Full client configs carry what links cannot, such as mux. They skip
    // libXray's link conversion, whose projection drops mux, but each node
    // must still build in the core: one that does not would break every
    // config it joins, the automatic selection included.
    if (xrayConfigOutbounds(text) case final nodes?) {
      final check = validate ?? AppHostApi().testXray;
      final valid = <Map<String, dynamic>>[];
      for (final node in nodes) {
        if ((await check(XrayValidation.nodes([node]))).isEmpty) {
          valid.add(node);
        } else {
          ygLogger('skipped a JSON subscription node the core refused');
        }
      }
      return readOutbounds(valid);
    }
    final convertLinks =
        convert ??
        (String text, String? key) =>
            AppHostApi().convertShareLinksToXrayJson(text, ageSecretKey: key);
    final split = splitMinewireLinks(text);
    final minewire = [for (final link in split.links) link.toOutbound()];
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
    return readOutbounds([...outbounds, ...minewire]);
  }

  Future<List<CoreConfigCompanion>> readOutbounds(
    List<Map<String, dynamic>> outbounds,
  ) async {
    final res = <CoreConfigCompanion>[];

    for (var index = 0; index < outbounds.length; index++) {
      if (index > 0 && index % 64 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final outbound = copyOutboundMap(outbounds[index]);
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
