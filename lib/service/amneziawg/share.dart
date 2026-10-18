import 'dart:convert';

import 'package:onexray/service/amneziawg/conf.dart';
import 'package:onexray/service/amneziawg/link.dart';
import 'package:onexray/service/shared/share/share_text.dart';

/// Share text with the AmneziaWG and WireGuard nodes taken out; [rest] goes
/// to libXray.
class AmneziaWGShareSplit {
  final List<Map<String, dynamic>> nodes;
  final String rest;

  /// AmneziaWG 1.5 keys the nodes lost, such as `J1`, for the log.
  final List<String> droppedKeys;

  const AmneziaWGShareSplit(
    this.nodes,
    this.rest, [
    this.droppedKeys = const [],
  ]);
}

/// Takes out `awg://`, `vpn://`, `wireguard://` and `wg://` links and whole
/// `.conf` files (each runs from its [Interface] line to the next link or
/// [Interface]), in a base64 block too. age-encrypted text passes through
/// untouched, as for minewire.
AmneziaWGShareSplit splitAmneziaWGLinks(String text) {
  if (text.contains('-----BEGIN AGE ENCRYPTED FILE-----')) {
    return AmneziaWGShareSplit(const [], text);
  }
  final plain = decodeBase64ShareBody(text) ?? text;
  if (!AmneziaWG.looksLikeConf(plain) &&
      !const LineSplitter().convert(plain).any(AmneziaWGLinks.matches)) {
    return AmneziaWGShareSplit(const [], text);
  }
  final nodes = <Map<String, dynamic>>[];
  final dropped = <String>{};
  final rest = <String>[];
  List<String>? conf;
  void finishConf() {
    if (conf == null) return;
    final text = conf!.join('\n');
    if (AmneziaWG.fromConf(text) case final node?) nodes.add(node);
    dropped.addAll(AmneziaWG.droppedKeys(text));
    conf = null;
  }

  for (final line in const LineSplitter().convert(plain)) {
    if (AmneziaWGLinks.matches(line)) {
      finishConf();
      nodes.addAll(AmneziaWGLinks.parse(line));
      final body = line.split('#').first;
      if (line.trimLeft().toLowerCase().startsWith('awg://')) {
        final bytes = decodeBase64Loose(
          body.substring(body.indexOf('://') + 3),
        );
        if (bytes != null) {
          dropped.addAll(
            AmneziaWG.droppedKeys(utf8.decode(bytes, allowMalformed: true)),
          );
        }
      }
    } else if (RegExp(
      r'^\s*\[interface\]\s*$',
      caseSensitive: false,
    ).hasMatch(line)) {
      finishConf();
      conf = [line];
    } else if (conf != null && !line.contains('://')) {
      conf!.add(line);
    } else {
      finishConf();
      rest.add(line);
    }
  }
  finishConf();
  return AmneziaWGShareSplit(nodes, rest.join('\n'), dropped.toList());
}
