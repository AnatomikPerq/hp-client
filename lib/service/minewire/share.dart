import 'dart:convert';

import 'package:onexray/service/minewire/link.dart';

/// Share text with the minewire links taken out; [rest] goes to libXray.
class MinewireShareSplit {
  final List<MinewireLink> links;
  final String rest;

  const MinewireShareSplit(this.links, this.rest);
}

/// libXray drops schemes Xray does not know, so minewire links are taken out
/// first. Subscriptions often arrive as one base64 block, which is decoded
/// here to see its lines. age-encrypted text is decrypted only by libXray and
/// passes through untouched: minewire links inside it are not supported.
MinewireShareSplit splitMinewireLinks(String text) {
  if (text.contains('-----BEGIN AGE ENCRYPTED FILE-----')) {
    return MinewireShareSplit(const [], text);
  }
  final plain = _decodeBase64Body(text) ?? text;
  final links = <MinewireLink>[];
  final rest = <String>[];
  for (final line in const LineSplitter().convert(plain)) {
    if (MinewireLink.matches(line)) {
      final link = MinewireLink.parse(line);
      if (link != null) links.add(link);
    } else {
      rest.add(line);
    }
  }
  if (links.isEmpty) return MinewireShareSplit(const [], text);
  return MinewireShareSplit(links, rest.join('\n'));
}

String? _decodeBase64Body(String text) {
  final compact = text.replaceAll(RegExp(r'\s'), '');
  if (compact.isEmpty || compact.contains('://')) return null;
  try {
    final decoded = utf8.decode(
      base64.decode(
        base64.normalize(compact.replaceAll('-', '+').replaceAll('_', '/')),
      ),
    );
    return decoded.contains('://') ? decoded : null;
  } on FormatException {
    return null;
  }
}
