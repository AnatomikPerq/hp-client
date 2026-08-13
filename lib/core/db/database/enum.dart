import 'package:collection/collection.dart';

enum CoreConfigType {
  outbound("outbound"),
  // Legacy persisted value. Product/code terminology is Xray Profile.
  profile("setting"),
  raw("raw"),
  full("full"),
  // Узел minewire. Хранится отдельным типом, потому что в момент импорта
  // ещё неизвестен локальный порт sidecar-процесса — outbound для Xray
  // собирается уже при подключении.
  minewire("minewire");

  const CoreConfigType(this.name);

  final String name;

  @override
  String toString() => name;

  static CoreConfigType? fromString(String name) =>
      CoreConfigType.values.firstWhereOrNull((value) => value.name == name);

  static List<String> get names {
    return CoreConfigType.values.map((e) => e.name).toList();
  }
}
