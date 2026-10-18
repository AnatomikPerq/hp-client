import 'dart:convert';

/// The lines of a subscription that arrives as one base64 block (standard or
/// URL alphabet, with or without padding), or null when [text] is not one.
/// Links the App parses itself (minewire, AmneziaWG) are looked for in
/// these lines; libXray decodes the block on its own.
String? decodeBase64ShareBody(String text) {
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

/// Bytes of base64 in either alphabet, padded or not; null when malformed.
List<int>? decodeBase64Loose(String text) {
  final compact = text.replaceAll(RegExp(r'\s'), '');
  if (compact.isEmpty) return null;
  try {
    return base64.decode(
      base64.normalize(compact.replaceAll('-', '+').replaceAll('_', '/')),
    );
  } on FormatException {
    return null;
  }
}
