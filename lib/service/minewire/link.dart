/// A minewire node: `mw://<password>@<host>:<port>?mode=fast#<name>`.
///
/// Xray-core does not know the scheme and libXray silently drops such links,
/// so they are parsed here, before libXray. The node is stored as an ordinary
/// server row whose outbound has `"protocol": "minewire"`; the runtime swaps
/// it for a `socks` outbound to the engine's local port when it connects.
class MinewireLink {
  const MinewireLink({
    required this.password,
    required this.host,
    required this.port,
    required this.name,
    this.mode = defaultMode,
  });

  static const scheme = 'mw';
  static const protocol = 'minewire';
  static const defaultMode = 'fast';
  static const modes = {'fast', 'realistic'};
  static const defaultName = 'minewire';

  final String password;
  final String host;
  final int port;
  final String name;

  /// Traffic shaping; has to match the server.
  final String mode;

  static bool matches(String raw) =>
      raw.trimLeft().toLowerCase().startsWith('$scheme://');

  /// `null` for anything malformed: a subscription may carry anything, and
  /// one broken node must not fail the whole import.
  static MinewireLink? parse(String raw) {
    final text = raw.trim();
    if (!matches(text)) return null;
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return null;
    }
    final password = _decode(uri.userInfo);
    final mode = (uri.queryParameters['mode'] ?? defaultMode).toLowerCase();
    if (uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port <= 0 ||
        uri.port > 65535 ||
        password == null ||
        password.isEmpty ||
        !modes.contains(mode)) {
      return null;
    }
    final name = _decode(uri.fragment) ?? '';
    return MinewireLink(
      password: password,
      host: uri.host,
      port: uri.port,
      name: name.trim().isEmpty ? defaultName : name.trim(),
      mode: mode,
    );
  }

  static String? _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return null; // Percent escapes that are not UTF-8.
    } on ArgumentError {
      return null;
    }
  }

  static bool isOutbound(Map<String, dynamic> outbound) =>
      outbound['protocol'] == protocol;

  /// Reads a stored outbound back; `null` when it is not a valid minewire one.
  static MinewireLink? fromOutbound(Map<String, dynamic> outbound) {
    if (!isOutbound(outbound)) return null;
    final settings = outbound['settings'];
    if (settings is! Map) return null;
    final host = settings['address'];
    final port = settings['port'];
    final password = settings['password'];
    final mode = settings['mode'] ?? defaultMode;
    if (host is! String ||
        host.isEmpty ||
        port is! int ||
        port <= 0 ||
        port > 65535 ||
        password is! String ||
        password.isEmpty ||
        mode is! String ||
        !modes.contains(mode)) {
      return null;
    }
    final tag = outbound['tag'];
    return MinewireLink(
      password: password,
      host: host,
      port: port,
      name: tag is String && tag.isNotEmpty ? tag : defaultName,
      mode: mode,
    );
  }

  Map<String, dynamic> toOutbound() => {
    'tag': name,
    'protocol': protocol,
    'settings': {
      'address': host,
      'port': port,
      'password': password,
      'mode': mode,
    },
  };

  String toShareLink() => Uri(
    scheme: scheme,
    userInfo: Uri.encodeComponent(password),
    host: host,
    port: port,
    queryParameters: {'mode': mode},
    fragment: name,
  ).toString();
}
