import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/file.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/minewire/db.dart';
import 'package:onexray/service/minewire/link.dart';
import 'package:onexray/service/xray/outbound/state.dart';
import 'package:onexray/service/xray/outbound/state_db.dart';
import 'package:onexray/service/xray/outbound/state_normalizer.dart';
import 'package:onexray/service/xray/outbound/state_reader.dart';

class XrayShareReader {
  Future<List<CoreConfigCompanion>> parseShareFile(String filePath) async {
    final file = File(filePath);
    final text = await file.readAsString();
    await FileTool.deleteFileIfExists(filePath);
    return parseShareText(text);
  }

  Future<List<CoreConfigCompanion>> parseOutboundShareText(
    String text, {
    String? ageSecretKey,
  }) async {
    // Ссылки minewire снимаем ДО libXray: ядро их не знает и молча
    // выбрасывает. Трогать libXray нельзя — это превратило бы обновление
    // апстрима в ручное слияние.
    final split = splitMinewireLinks(text);
    final res = <CoreConfigCompanion>[];
    if (split.rest.trim().isNotEmpty) {
      final xrayJson = await AppHostApi().convertShareLinksToXrayJsonStrict(
        split.rest,
        ageSecretKey: ageSecretKey,
      );
      res.addAll(await readXrayJsonOutbounds(xrayJson));
    }
    res.addAll(split.minewire.map((link) => link.configCompanion));
    return res;
  }

  Future<List<CoreConfigCompanion>> parseShareText(String text) async {
    return parseOutboundShareText(text);
  }

  @visibleForTesting
  static ShareTextSplit splitMinewireLinks(String text) {
    final plain = _decodeSubscriptionBody(text);
    if (!plain.contains("${MinewireLink.scheme}://")) {
      // Ничего минуайровского — отдаём исходный текст как есть, чтобы не
      // менять то, что libXray и так разбирает.
      return ShareTextSplit(text, const []);
    }
    final rest = <String>[];
    final minewire = <MinewireLink>[];
    for (final line in const LineSplitter().convert(plain)) {
      if (!MinewireLink.matches(line)) {
        rest.add(line);
        continue;
      }
      final link = MinewireLink.parse(line);
      if (link == null) {
        ygLogger("skipped malformed minewire link");
        continue;
      }
      minewire.add(link);
    }
    return ShareTextSplit(rest.join("\n"), minewire);
  }

  /// Подписка приходит либо списком ссылок, либо одним base64-блоком.
  ///
  /// Декодируем только во втором случае и только если внутри действительно
  /// оказались ссылки: ошибочное «раскодирование» обычного текста испортило
  /// бы вход для libXray.
  static String _decodeSubscriptionBody(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.contains("://")) {
      return text;
    }
    var payload = trimmed.replaceAll('-', '+').replaceAll('_', '/');
    payload = payload.replaceAll(RegExp(r'\s'), '');
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    try {
      final decoded = utf8.decode(base64Decode(payload));
      return decoded.contains("://") ? decoded : text;
    } catch (_) {
      return text;
    }
  }

  @visibleForTesting
  Future<List<CoreConfigCompanion>> readXrayJsonOutbounds(
    XrayJson xrayJson,
  ) async {
    final res = <CoreConfigCompanion>[];
    final outbounds = xrayJson.outbounds;
    if (outbounds == null) {
      return res;
    }

    for (var index = 0; index < outbounds.length; index++) {
      if (index > 0 && index % 64 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final outbound = outbounds[index];
      try {
        final state = OutboundState();
        final success = state.readFromOutbound(outbound);
        if (!success) {
          continue;
        }
        state.removeWhitespace();
        res.add(state.outboundCompanion);
      } catch (error, stackTrace) {
        ygLogger(
          "Failed to read imported outbound (${error.runtimeType})\n$stackTrace",
        );
      }
    }
    return res;
  }
}

/// Текст подписки, разделённый на «понятное libXray» и узлы minewire.
class ShareTextSplit {
  const ShareTextSplit(this.rest, this.minewire);

  final String rest;
  final List<MinewireLink> minewire;
}
