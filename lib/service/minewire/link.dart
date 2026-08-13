import 'package:onexray/core/tools/logger.dart';

/// Узел minewire, описанный ссылкой вида
/// `mw://<пароль>@<хост>:<порт>?mode=fast&proxy=socks5#<имя>`.
///
/// libXray такие ссылки не понимает и молча их пропускает, поэтому разбор
/// живёт здесь, в Dart, и выполняется ДО обращения к ядру. Трогать libXray
/// нельзя: любая правка там превращает обновление апстрима в ручное слияние.
class MinewireLink {
  const MinewireLink({
    required this.password,
    required this.host,
    required this.port,
    required this.name,
    this.mode = defaultMode,
    this.proxyType = defaultProxyType,
  });

  static const scheme = "mw";
  static const defaultMode = "fast";
  static const defaultProxyType = "socks5";
  static const defaultName = "minewire";

  final String password;
  final String host;
  final int port;
  final String name;
  final String mode;
  final String proxyType;

  /// Начинается ли строка со ссылки minewire.
  static bool matches(String raw) {
    return raw.trimLeft().toLowerCase().startsWith("$scheme://");
  }

  /// Возвращает `null` на любой некорректной ссылке: подписка может
  /// содержать что угодно, и один битый узел не должен ронять импорт.
  static MinewireLink? parse(String raw) {
    final text = raw.trim();
    if (!matches(text)) {
      return null;
    }
    try {
      final uri = Uri.parse(text);
      final host = uri.host;
      final port = uri.port;
      final password = Uri.decodeComponent(uri.userInfo);
      if (host.isEmpty || port == 0 || password.isEmpty) {
        return null;
      }
      final fragment = uri.fragment.isEmpty
          ? ""
          : Uri.decodeComponent(uri.fragment);
      return MinewireLink(
        password: password,
        host: host,
        port: port,
        name: fragment.isEmpty ? defaultName : fragment,
        mode: uri.queryParameters["mode"] ?? defaultMode,
        proxyType: uri.queryParameters["proxy"] ?? defaultProxyType,
      );
    } catch (error) {
      ygLogger("parse minewire link failed: $error");
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "password": password,
      "host": host,
      "port": port,
      "name": name,
      "mode": mode,
      "proxy": proxyType,
    };
  }

  static MinewireLink? fromJson(Map<String, dynamic> json) {
    final host = json["host"];
    final port = json["port"];
    final password = json["password"];
    if (host is! String || password is! String || port is! int) {
      return null;
    }
    if (host.isEmpty || password.isEmpty || port == 0) {
      return null;
    }
    final name = json["name"];
    final mode = json["mode"];
    final proxy = json["proxy"];
    return MinewireLink(
      password: password,
      host: host,
      port: port,
      name: name is String && name.isNotEmpty ? name : defaultName,
      mode: mode is String && mode.isNotEmpty ? mode : defaultMode,
      proxyType: proxy is String && proxy.isNotEmpty ? proxy : defaultProxyType,
    );
  }

  /// Конфиг для `minewire.exe -config <файл>`.
  ///
  /// Значения берём в кавычки: пароль генерируется сервером и может
  /// содержать символы, которые YAML иначе прочитает как синтаксис.
  /// [serverHost] позволяет подставить уже разрешённый IP вместо имени:
  /// пока туннель поднят, DNS может быть недоступен, а адрес сервера нужен
  /// sidecar'у до того, как соединение заработает.
  String yaml(int localPort, {String? serverHost}) {
    final target = serverHost == null || serverHost.isEmpty
        ? host
        : serverHost;
    return [
      'local_port: "127.0.0.1:$localPort"',
      'server_address: "${_escape(target)}:$port"',
      'password: "${_escape(password)}"',
      'proxy_type: "${_escape(proxyType)}"',
      'mode: "${_escape(mode)}"',
      '',
    ].join('\n');
  }

  String _escape(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }
}
