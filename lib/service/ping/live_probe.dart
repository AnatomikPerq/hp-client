import 'dart:async';
import 'dart:io';

import 'package:onexray/core/tools/logger.dart';

/// Результат проверки живого подключения.
class LivePingResult {
  const LivePingResult.success(this.milliseconds) : reachable = true;

  const LivePingResult.failure() : milliseconds = 0, reachable = false;

  final bool reachable;
  final int milliseconds;
}

/// Проверка того, что подключение РЕАЛЬНО работает.
///
/// Обычный пинг в списке узлов меряет узел в отдельном временном ядре и
/// ничего не говорит о текущем соединении. Здесь запрос уходит из самого
/// приложения — то есть по тому же маршруту, что и весь остальной трафик
/// системы, — и меряется полный путь до внешнего сервера.
final class LivePingProbe {
  /// Эндпоинты, отвечающие пустым 204 — минимум трафика и никакой
  /// зависимости от вёрстки чужих страниц.
  static const targets = <String>[
    "https://cp.cloudflare.com/generate_204",
    "https://www.gstatic.com/generate_204",
  ];

  static const _timeout = Duration(seconds: 8);

  Future<LivePingResult> measure() async {
    for (final target in targets) {
      final result = await _probe(target);
      if (result.reachable) {
        return result;
      }
    }
    return const LivePingResult.failure();
  }

  Future<LivePingResult> _probe(String target) async {
    final client = HttpClient()
      ..connectionTimeout = _timeout
      // Соединение одноразовое: нас интересует полный путь, а не скорость
      // переиспользованного сокета.
      ..userAgent = null;
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client.getUrl(Uri.parse(target)).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      await response.drain<void>().timeout(_timeout);
      stopwatch.stop();
      if (response.statusCode >= 400) {
        return const LivePingResult.failure();
      }
      return LivePingResult.success(stopwatch.elapsedMilliseconds);
    } catch (error) {
      ygLogger("live ping to $target failed: $error");
      return const LivePingResult.failure();
    } finally {
      client.close(force: true);
    }
  }
}
