import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/tools/file.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/minewire/link.dart';
import 'package:path/path.dart' as p;

/// Что нужно знать Xray о поднятом sidecar.
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

/// Sidecar-процесс minewire.
///
/// В отличие от ядра Xray, minewire не трогает сетевой стек и запускается
/// без прав администратора — обычного `Process.start` достаточно, UAC не
/// нужен. Он поднимает локальный SOCKS5, который дальше подключается к
/// Xray как обычный outbound.
final class MinewireService {
  factory MinewireService() => _singleton;

  MinewireService._internal();

  static final MinewireService _singleton = MinewireService._internal();

  static const _exeName = "minewire.exe";
  static const _configName = "minewire.yaml";
  static const _pidName = "minewire.pid";
  static const _readyTimeout = Duration(seconds: 8);

  Process? _process;
  int? _localPort;
  StreamSubscription<String>? _stdout;
  StreamSubscription<String>? _stderr;

  bool get running => _process != null;

  /// Порт локального SOCKS5, пока процесс жив.
  int? get localPort => _localPort;

  /// Лежит рядом с ядром: `<каталог приложения>/bin/minewire.exe`.
  String get exePath {
    final bundleDir = p.dirname(Platform.resolvedExecutable);
    return p.join(bundleDir, "bin", _exeName);
  }

  bool get supported => Platform.isWindows || Platform.isLinux;

  /// Поднимает minewire и возвращает локальный порт и адреса сервера.
  ///
  /// Всегда перезапускает процесс: параметры узла могли поменяться, а
  /// проверять их дешевле перезапуском, чем сравнением конфигов.
  Future<MinewireEndpoint> start(MinewireLink link) async {
    await stop();
    if (!supported) {
      throw const MinewireException(
        "minewire is not supported on this platform",
      );
    }
    final exe = File(exePath);
    if (!exe.existsSync()) {
      throw MinewireException("minewire executable is missing: $exePath");
    }

    // Адрес сервера разрешаем ДО поднятия туннеля: потом DNS может уйти
    // в тот самый туннель, который ещё не работает. Эти же адреса нужны
    // для правила обхода.
    final serverIps = await _resolve(link.host);
    final port = await _reserveLocalPort();
    final runDir = VpnConstants.runDir;
    await FileTool.checkDir(runDir);
    final configPath = p.join(runDir, _configName);
    await File(configPath).writeAsString(
      link.yaml(port, serverHost: serverIps.isEmpty ? null : serverIps.first),
    );

    final Process process;
    try {
      process = await Process.start(exePath, <String>[
        "-config",
        configPath,
      ], workingDirectory: runDir);
    } catch (error) {
      throw MinewireException("start minewire failed: $error");
    }
    _process = process;
    _localPort = port;
    await _writePid(process.pid);
    _pipeLogs(process);
    unawaited(
      process.exitCode.then((code) {
        ygLogger("minewire exited with code $code");
        if (identical(_process, process)) {
          _process = null;
          _localPort = null;
        }
      }),
    );

    if (!await _waitUntilListening(port)) {
      await stop();
      throw const MinewireException("minewire did not open its local port");
    }
    ygLogger("minewire is listening on 127.0.0.1:$port");
    return MinewireEndpoint(localPort: port, serverIps: serverIps);
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

  Future<void> stop() async {
    final process = _process;
    _process = null;
    _localPort = null;
    await _stdout?.cancel();
    await _stderr?.cancel();
    _stdout = null;
    _stderr = null;
    if (process == null) {
      await _clearPid();
      return;
    }
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
    await _clearPid();
  }

  /// Добивает sidecar, оставшийся от аварийно закрытого клиента.
  ///
  /// Иначе тоннель продолжает работать без интерфейса, который о нём знает.
  /// Убиваем строго по сохранённому pid и только если под ним действительно
  /// minewire: пользователь запускает его и руками, чужой процесс не наш.
  Future<void> cleanupStale() async {
    if (!supported || running) {
      return;
    }
    final pid = await _readPid();
    if (pid == null) {
      return;
    }
    await _clearPid();
    if (!await _pidIsMinewire(pid)) {
      return;
    }
    try {
      await Process.run('taskkill.exe', <String>['/F', '/PID', '$pid']);
      ygLogger("stale minewire (pid $pid) terminated");
    } catch (error) {
      ygLogger("stop stale minewire failed: $error");
    }
  }

  Future<bool> _pidIsMinewire(int pid) async {
    try {
      final result = await Process.run('tasklist.exe', <String>[
        '/FI',
        'PID eq $pid',
        '/FI',
        'IMAGENAME eq $_exeName',
        '/NH',
      ]);
      return result.stdout.toString().toLowerCase().contains(
        _exeName.toLowerCase(),
      );
    } catch (error) {
      ygLogger("check stale minewire failed: $error");
      return false;
    }
  }

  File get _pidFile => File(p.join(VpnConstants.runDir, _pidName));

  Future<void> _writePid(int pid) async {
    try {
      await FileTool.checkDir(VpnConstants.runDir);
      await _pidFile.writeAsString("$pid");
    } catch (error) {
      ygLogger("save minewire pid failed: $error");
    }
  }

  Future<int?> _readPid() async {
    try {
      final file = _pidFile;
      if (!file.existsSync()) {
        return null;
      }
      return int.tryParse((await file.readAsString()).trim());
    } catch (error) {
      ygLogger("read minewire pid failed: $error");
      return null;
    }
  }

  Future<void> _clearPid() async {
    try {
      await FileTool.deleteFileIfExists(_pidFile.path);
    } catch (error) {
      ygLogger("clear minewire pid failed: $error");
    }
  }

  void _pipeLogs(Process process) {
    _stdout = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => ygLogger("minewire: $line"));
    _stderr = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => ygLogger("minewire!: $line"));
  }

  /// Занимает свободный порт и сразу освобождает его.
  ///
  /// Гонка тут теоретически возможна, но окно в миллисекунды, а
  /// альтернатива — фиксированный 1080, который занят чаще, чем свободен.
  Future<int> _reserveLocalPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<bool> _waitUntilListening(int port) async {
    final deadline = DateTime.now().add(_readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_process == null) {
        return false;
      }
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 400),
        );
        socket.destroy();
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    return false;
  }
}
