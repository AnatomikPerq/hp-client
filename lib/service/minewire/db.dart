import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/minewire/link.dart';

/// Хранение узла minewire в той же таблице, что и остальные узлы.
///
/// В `data` лежит не конфиг Xray, а параметры подключения: outbound
/// собирается на лету при старте, когда становится известен порт sidecar.
extension MinewireLinkDb on MinewireLink {
  CoreConfigCompanion get configCompanion {
    final payload = JsonTool.encoder.convert(<String, dynamic>{
      "minewire": toJson(),
    });
    final base64Data = base64Encode(utf8.encode(payload));
    return CoreConfigCompanion.insert(
      name: name,
      type: CoreConfigType.minewire.name,
      // Первый тег рисуется на карточке как значок протокола.
      tags: [CoreConfigType.minewire.name, mode, proxyType].join(","),
      data: Value<String>(base64Data),
      delay: PingDelayConstants.unknown,
      subId: DBConstants.defaultId,
    );
  }
}

abstract final class MinewireConfigReader {
  /// Разбирает строку узла обратно в параметры подключения.
  ///
  /// `null` означает, что строка не минуайровская или повреждена — вызов
  /// должен деградировать в понятную ошибку, а не в исключение.
  static MinewireLink? read(CoreConfigData config) {
    if (CoreConfigType.fromString(config.type) != CoreConfigType.minewire) {
      return null;
    }
    final data = config.data;
    if (data == null || data.isEmpty) {
      return null;
    }
    try {
      final text = utf8.decode(base64Decode(data));
      final decoded = JsonTool.decoder.convert(text);
      if (decoded is! Map) {
        return null;
      }
      final payload = decoded["minewire"];
      if (payload is! Map) {
        return null;
      }
      final link = MinewireLink.fromJson(
        payload.map((key, value) => MapEntry("$key", value)),
      );
      if (link == null) {
        return null;
      }
      // Имя узла показывается из колонки name — она могла быть
      // переименована пользователем уже после импорта.
      return MinewireLink(
        password: link.password,
        host: link.host,
        port: link.port,
        name: config.name.isEmpty ? link.name : config.name,
        mode: link.mode,
        proxyType: link.proxyType,
      );
    } catch (error) {
      ygLogger("read minewire config failed: $error");
      return null;
    }
  }
}
