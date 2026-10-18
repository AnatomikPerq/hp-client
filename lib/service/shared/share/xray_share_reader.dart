import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/amneziawg/share.dart';
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
    Future<String> check(String json) =>
        (validate ?? AppHostApi().testXray)(json);
    if (xrayConfigOutbounds(text) case final nodes?) {
      return readOutbounds(await _built(nodes, check, 'a JSON subscription'));
    }
    final convertLinks =
        convert ??
        (String text, String? key) =>
            AppHostApi().convertShareLinksToXrayJson(text, ageSecretKey: key);
    final split = splitMinewireLinks(text);
    final minewire = [for (final link in split.links) link.toOutbound()];
    // AmneziaWG nodes are checked one by one like JSON configs: a value the
    // engine refuses (an unknown I1 tag, overlapping headers) fails the
    // whole config it joins.
    final amnezia = splitAmneziaWGLinks(split.rest);
    if (amnezia.droppedKeys.isNotEmpty) {
      ygLogger(
        'AmneziaWG 1.5 keys dropped on import: ${amnezia.droppedKeys.join(', ')}',
      );
    }
    final local = [
      ...minewire,
      ...await _built(amnezia.nodes, check, 'an AmneziaWG'),
    ];
    final hadLocal = split.links.isNotEmpty || amnezia.nodes.isNotEmpty;
    List<Map<String, dynamic>> outbounds = const [];
    if (amnezia.rest.trim().isNotEmpty) {
      try {
        outbounds = await convertLinks(amnezia.rest, ageSecretKey);
      } catch (_) {
        // libXray fails when nothing it knows remains; minewire and
        // AmneziaWG nodes alone are still a valid import.
        if (!hadLocal) rethrow;
      }
    }
    return readOutbounds([...outbounds, ...local]);
  }

  /// [nodes] the core builds; the others are logged and left out.
  static Future<List<Map<String, dynamic>>> _built(
    List<Map<String, dynamic>> nodes,
    Future<String> Function(String xrayJson) check,
    String source,
  ) async {
    final valid = <Map<String, dynamic>>[];
    for (final node in nodes) {
      if ((await check(XrayValidation.nodes([node]))).isEmpty) {
        valid.add(node);
      } else {
        ygLogger('skipped $source node the core refused');
      }
    }
    return valid;
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
