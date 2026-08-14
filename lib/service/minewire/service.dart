import 'dart:io';

import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/minewire/link.dart';

/// Что нужно знать Xray о поднятом туннеле.
class MinewireEndpoint {
  const MinewireEndpoint({required this.localPort, required this.serverIps});

  /// Локальный SOCKS5, к которому подключается outbound.
  final int localPort;

  /// Адреса сервера — для правила обхода туннеля.
  final List<String> serverIps;
}

class MinewireException implements Exception {
  const MinewireException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Туннель minewire.
///
/// Движок скомпилирован ВНУТРЬ libXray — той же библиотеки, которую
/// приложение и так загружает. Отдельного процесса больше нет, и это не
/// косметика: на Android и iOS запустить сторонний исполняемый файл нельзя
/// в принципе, так что sidecar не имел пути на телефон. Заодно пароль
/// остаётся в памяти вместо конфигурационного файла на диске.
///
/// Движок по-прежнему открывает локальный SOCKS5, и Xray подключается к нему
/// обычным socks-outbound — исчезла только граница процессов.
final class MinewireService {
  factory MinewireService() => _singleton;

  MinewireService._internal();

  static final MinewireService _singleton = MinewireService._internal();

  int? _localPort;

  bool get running => _localPort != null;

  /// Порт локального SOCKS5, пока туннель поднят.
  int? get localPort => _localPort;

  /// Поднимает туннель и возвращает локальный порт и адреса сервера.
  ///
  /// Всегда перезапускает движок: параметры узла могли поменяться, а
  /// проверять их дешевле перезапуском, чем сравнением конфигов.
  Future<MinewireEndpoint> start(MinewireLink link) async {
    // Адрес сервера разрешаем ДО поднятия туннеля: потом DNS может уйти
    // в тот самый туннель, который ещё не работает. Эти же адреса нужны
    // для правила обхода.
    final serverIps = await _resolve(link.host);
    final target = serverIps.isEmpty ? link.host : serverIps.first;
    try {
      final port = await AppHostApi().startMinewire(
        serverAddress: "$target:${link.port}",
        password: link.password,
        mode: link.mode,
      );
      _localPort = port;
      // Движок открывает локальный порт сразу, а соединяется с сервером
      // фоном. Без ожидания Xray успевает пойти в ещё не готовый туннель, и
      // первые соединения отваливаются на пустом месте.
      if (!await _waitUntilConnected()) {
        await stop();
        throw const MinewireException("minewire did not reach the server");
      }
      ygLogger("minewire is listening on 127.0.0.1:$port");
      return MinewireEndpoint(localPort: port, serverIps: serverIps);
    } catch (error) {
      _localPort = null;
      throw MinewireException("$error");
    }
  }

  Future<void> stop() async {
    if (_localPort == null) {
      return;
    }
    _localPort = null;
    await AppHostApi().stopMinewire();
  }

  /// Подчистить туннель, оставшийся от прошлого запуска приложения.
  ///
  /// Движок живёт внутри процесса приложения, поэтому вместе с ним и
  /// умирает — осиротеть он не может. Вызов оставлен, чтобы снять состояние
  /// внутри libXray, если библиотека почему-то пережила перезапуск.
  Future<void> cleanupStale() async {
    final state = await AppHostApi().minewireState();
    if (state?.running == true) {
      ygLogger("stopping a minewire tunnel left from a previous run");
      await AppHostApi().stopMinewire();
    }
    _localPort = null;
  }

  static const _connectTimeout = Duration(seconds: 12);

  /// Ждёт, пока движок доложит об установленном соединении с сервером.
  Future<bool> _waitUntilConnected() async {
    final deadline = DateTime.now().add(_connectTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final state = await AppHostApi().minewireState();
      if (state?.connected == true) {
        return true;
      }
      if (state?.running != true) {
        // Движок сам себя погасил — дальше ждать нечего.
        final error = state?.lastError;
        if (error != null && error.isNotEmpty) {
          ygLogger("minewire stopped while connecting: $error");
        }
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  /// Адреса сервера minewire. Пустой список — не смогли разрешить имя.
  Future<List<String>> _resolve(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      return <String>[literal.address];
    }
    try {
      final records = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 6));
      return records.map((record) => record.address).toSet().toList();
    } catch (error) {
      ygLogger("resolve minewire host failed: $error");
      return const <String>[];
    }
  }
}
