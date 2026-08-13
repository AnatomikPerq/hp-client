import 'dart:convert';
import 'dart:io';

import 'package:onexray/core/ffi/windows_ffi_api.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/model/xray_standard.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/tools/file.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/service/xray/profile/enum.dart';
import 'package:onexray/service/xray/profile/inbounds_state.dart';
import 'package:path/path.dart' as p;

/// Управляющий интерфейс живого ядра.
///
/// Смена узла раньше означала убить ядро и поднять новое — а на Windows
/// ядро поднимается с правами администратора, поэтому каждое переключение
/// стоило пользователю окна UAC. Здесь outbound подменяется у уже
/// запущенного процесса, и права спрашиваются один раз за запуск программы.
///
/// Клиентом к API служит сам бинарник ядра (`xray api ...`): он запускается
/// БЕЗ повышения прав и общается с ядром по петле, поэтому отдельная
/// gRPC-зависимость в приложении не нужна.
abstract final class XrayCoreApi {
  static const _tag = "api";
  static const _services = <String>["HandlerService", "RoutingService"];
  static const _timeout = Duration(seconds: 10);

  /// Ядро слушает управление только на петле.
  static String _server(String port) => "127.0.0.1:$port";

  static void applyToXrayJson(XrayJson xrayJson, XrayPorts ports) {
    if (!supported) {
      return;
    }
    xrayJson.api = XrayApiStandard.standard
      ..tag = _tag
      ..listen = _server(ports.apiPort)
      ..services = List<String>.from(_services);
  }

  /// Пока реализовано там, где ядро — отдельный элевированный процесс.
  static bool get supported => AppPlatform.isWindows || AppPlatform.isLinux;

  /// Заменить исходящее соединение у живого ядра.
  ///
  /// Возвращает `false`, если что-то пошло не так — вызывающий обязан
  /// откатиться на полный перезапуск, иначе туннель останется в
  /// половинчатом состоянии.
  static Future<bool> replaceProxyOutbound({
    required String apiPort,
    required List<XrayOutbound> outbounds,
    required List<String> removedRuleTags,
    required List<XrayRoutingRule> addedRules,
  }) async {
    if (!supported || outbounds.isEmpty) {
      return false;
    }
    final runDir = VpnConstants.runDir;
    await FileTool.checkDir(runDir);

    for (final tag in removedRuleTags) {
      // Правило могло и не существовать — это не ошибка.
      await _run(apiPort, <String>["rmrules", tag]);
    }

    for (final outbound in outbounds) {
      final tag = outbound.tag;
      if (tag == null || tag.isEmpty) {
        return false;
      }
      // Снятие может не найти outbound, если ядро только поднялось —
      // результат не проверяем, важен успех добавления.
      await _run(apiPort, <String>["rmo", tag]);
    }

    final outboundsPath = p.join(runDir, "api-outbounds.json");
    await File(outboundsPath).writeAsString(
      JsonTool.encoder.convert(<String, dynamic>{
        "outbounds": outbounds.map((outbound) => outbound.toJson()).toList(),
      }),
    );
    if (!await _run(apiPort, <String>["ado", outboundsPath])) {
      return false;
    }

    if (addedRules.isNotEmpty) {
      final rulesPath = p.join(runDir, "api-rules.json");
      await File(rulesPath).writeAsString(
        JsonTool.encoder.convert(<String, dynamic>{
          "routing": <String, dynamic>{
            "rules": addedRules.map((rule) => rule.toJson()).toList(),
          },
        }),
      );
      if (!await _run(apiPort, <String>["adrules", rulesPath])) {
        return false;
      }
    }
    return true;
  }

  static Future<bool> _run(String apiPort, List<String> arguments) async {
    final executable = _corePath;
    if (executable == null) {
      return false;
    }
    final command = <String>[
      "api",
      arguments.first,
      "--server=${_server(apiPort)}",
      ...arguments.skip(1),
    ];
    try {
      final result = await Process.run(
        executable,
        command,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(_timeout);
      if (result.exitCode != 0) {
        ygLogger(
          "core api ${arguments.first} failed: exit=${result.exitCode} "
          "${result.stderr}",
        );
        return false;
      }
      return true;
    } catch (error) {
      ygLogger("core api ${arguments.first} failed: $error");
      return false;
    }
  }

  static String? get _corePath {
    if (AppPlatform.isWindows) {
      return WindowsFfiApi().corePath;
    }
    if (AppPlatform.isLinux) {
      return p.join(
        p.dirname(Platform.resolvedExecutable),
        "bin",
        "HyperClientCore",
      );
    }
    return null;
  }

  /// Тег исходящего соединения, которое подменяется при смене узла.
  static String get proxyTag => RoutingOutboundTag.proxy.name;
}
