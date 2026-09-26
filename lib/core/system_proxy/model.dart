/// The OS-wide proxy of the current user, as far as the App needs to restore
/// it: whatever was configured before the App took over is written back as-is.
class SystemProxySettings {
  /// A manual proxy server is in use.
  final bool enabled;

  /// Manual proxy server, `host:port` or a per-protocol list.
  final String server;

  /// Hosts that bypass the manual proxy.
  final String bypass;

  /// PAC script URL. Kept even while PAC is off, like the Windows dialog does.
  final String autoConfigUrl;

  /// The PAC script is in use.
  final bool autoConfigEnabled;

  /// Web Proxy Auto-Discovery.
  final bool autoDetect;

  /// Backend-specific values restored verbatim, such as the legacy registry
  /// copy Windows keeps next to the WinINet settings. Other software may write
  /// only that copy, and it may disagree with the WinINet view.
  final Map<String, Object?> native;

  const SystemProxySettings({
    this.enabled = false,
    this.server = '',
    this.bypass = '',
    this.autoConfigUrl = '',
    this.autoConfigEnabled = false,
    this.autoDetect = false,
    this.native = const {},
  });

  factory SystemProxySettings.fromJson(Map<String, dynamic> json) {
    T read<T>(String key, T fallback) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! T) throw FormatException('Invalid system proxy $key');
      return value;
    }

    return SystemProxySettings(
      enabled: read('enabled', false),
      server: read('server', ''),
      bypass: read('bypass', ''),
      autoConfigUrl: read('autoConfigUrl', ''),
      autoConfigEnabled: read('autoConfigEnabled', false),
      autoDetect: read('autoDetect', false),
      native: Map<String, Object?>.unmodifiable(
        read<Map<String, dynamic>>('native', const {}),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'server': server,
    'bypass': bypass,
    'autoConfigUrl': autoConfigUrl,
    'autoConfigEnabled': autoConfigEnabled,
    'autoDetect': autoDetect,
    if (native.isNotEmpty) 'native': native,
  };

  @override
  bool operator ==(Object other) =>
      other is SystemProxySettings &&
      other.enabled == enabled &&
      other.server == server &&
      other.bypass == bypass &&
      other.autoConfigUrl == autoConfigUrl &&
      other.autoConfigEnabled == autoConfigEnabled &&
      other.autoDetect == autoDetect &&
      _sameNative(other.native, native);

  static bool _sameNative(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.entries.every(
        (entry) => b.containsKey(entry.key) && b[entry.key] == entry.value,
      );

  @override
  int get hashCode => Object.hash(
    enabled,
    server,
    bypass,
    autoConfigUrl,
    autoConfigEnabled,
    autoDetect,
    native.length,
  );

  @override
  String toString() => 'SystemProxySettings(${toJson()})';
}

/// Reads and writes one platform's proxy settings. Implementations are thin
/// and stateless; ownership and recovery live in `SystemProxyManager`.
abstract interface class SystemProxyBackend {
  Future<SystemProxySettings> read();

  Future<void> write(SystemProxySettings settings);
}

/// Local addresses that must never go through the App's proxy.
const systemProxyDefaultBypass = <String>[
  'localhost',
  '127.*',
  '10.*',
  '172.16.*',
  '172.17.*',
  '172.18.*',
  '172.19.*',
  '172.20.*',
  '172.21.*',
  '172.22.*',
  '172.23.*',
  '172.24.*',
  '172.25.*',
  '172.26.*',
  '172.27.*',
  '172.28.*',
  '172.29.*',
  '172.30.*',
  '172.31.*',
  '192.168.*',
  '<local>',
];
