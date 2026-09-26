import 'dart:io';

import 'package:onexray/core/system_proxy/model.dart';

typedef ProcessRunner = Future<ProcessResult> Function(String, List<String>);

/// GNOME-compatible desktops (GNOME, Cinnamon, Budgie, …) through gsettings.
///
/// The manual server is stored as `http=h:p;https=h:p;socks=h:p` so a
/// per-protocol setup survives a restore; the App's own proxy uses a single
/// `host:port` for all three, since its inbound speaks SOCKS and HTTP.
class GnomeSystemProxyBackend implements SystemProxyBackend {
  static const _schema = 'org.gnome.system.proxy';
  static const _protocols = ['http', 'https', 'socks'];

  final ProcessRunner _run;

  GnomeSystemProxyBackend({ProcessRunner? run}) : _run = run ?? Process.run;

  static Future<bool> available({ProcessRunner? run}) async {
    try {
      final result = await (run ?? Process.run)('gsettings', [
        'get',
        _schema,
        'mode',
      ]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<SystemProxySettings> read() async {
    final mode = _unquote(await _get(_schema, 'mode'));
    final servers = <String>[];
    for (final protocol in _protocols) {
      final host = _unquote(await _get('$_schema.$protocol', 'host'));
      final port =
          int.tryParse((await _get('$_schema.$protocol', 'port')).trim()) ?? 0;
      if (host.isNotEmpty && port > 0) servers.add('$protocol=$host:$port');
    }
    return SystemProxySettings(
      enabled: mode == 'manual',
      server: servers.join(';'),
      bypass: _parseList(await _get(_schema, 'ignore-hosts')).join(';'),
      autoConfigUrl: _unquote(await _get(_schema, 'autoconfig-url')),
      autoConfigEnabled: mode == 'auto',
    );
  }

  @override
  Future<void> write(SystemProxySettings settings) async {
    final perProtocol = <String, String>{};
    for (final part in settings.server.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final equals = trimmed.indexOf('=');
      if (equals < 0) {
        for (final protocol in _protocols) {
          perProtocol[protocol] = trimmed;
        }
      } else {
        perProtocol[trimmed.substring(0, equals)] = trimmed.substring(
          equals + 1,
        );
      }
    }
    for (final protocol in _protocols) {
      final endpoint = perProtocol[protocol] ?? '';
      final colon = endpoint.lastIndexOf(':');
      final host = colon > 0 ? endpoint.substring(0, colon) : '';
      final port = colon > 0
          ? int.tryParse(endpoint.substring(colon + 1)) ?? 0
          : 0;
      await _set('$_schema.$protocol', 'host', _quote(host));
      await _set('$_schema.$protocol', 'port', '$port');
    }
    final bypass = settings.bypass
        .split(';')
        .map((host) => host.trim())
        .where((host) => host.isNotEmpty && host != '<local>')
        .map(_quote)
        .join(', ');
    await _set(_schema, 'ignore-hosts', '[$bypass]');
    await _set(_schema, 'autoconfig-url', _quote(settings.autoConfigUrl));
    await _set(
      _schema,
      'mode',
      _quote(
        settings.enabled
            ? 'manual'
            : settings.autoConfigEnabled
            ? 'auto'
            : 'none',
      ),
    );
  }

  Future<String> _get(String schema, String key) async {
    final result = await _run('gsettings', ['get', schema, key]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'gsettings',
        ['get', schema, key],
        '${result.stderr}',
        result.exitCode,
      );
    }
    return '${result.stdout}'.trim();
  }

  Future<void> _set(String schema, String key, String value) async {
    final result = await _run('gsettings', ['set', schema, key, value]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'gsettings',
        ['set', schema, key, value],
        '${result.stderr}',
        result.exitCode,
      );
    }
  }

  static String _unquote(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2 &&
        trimmed.startsWith("'") &&
        trimmed.endsWith("'")) {
      return trimmed.substring(1, trimmed.length - 1).replaceAll(r"\'", "'");
    }
    return trimmed;
  }

  static String _quote(String value) => "'${value.replaceAll("'", r"\'")}'";

  static List<String> _parseList(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('@as')) return const [];
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return const [];
    return [
      for (final item in trimmed.substring(1, trimmed.length - 1).split(','))
        if (_unquote(item).isNotEmpty) _unquote(item),
    ];
  }
}
