import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:package_info_plus/package_info_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUpAll(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    PackageInfo.setMockInitialValues(
      appName: 'HYPER CLIENT',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<HttpServer> serve(int bytes, {bool declareLength = true}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      if (declareLength) response.contentLength = bytes;
      const chunk = 64 * 1024;
      final block = List<int>.filled(chunk, 0x41);
      var left = bytes;
      while (left > 0) {
        final size = left < chunk ? left : chunk;
        response.add(size == chunk ? block : block.sublist(0, size));
        left -= size;
      }
      await response.close();
    });
    addTearDown(server.close);
    return server;
  }

  String url(HttpServer server) => 'http://127.0.0.1:${server.port}/sub';

  test('a normal subscription body is read', () async {
    final server = await serve(1024);
    expect(await NetClient().getText(url(server)), 'A' * 1024);
  });

  test('an oversized body is refused before it is buffered', () async {
    for (final declare in [true, false]) {
      final server = await serve(
        NetClient.maxTextDownloadBytes + 1,
        declareLength: declare,
      );
      await expectLater(
        NetClient().getTextResponse(url(server)),
        throwsA(
          isA<AppFailure>().having(
            (error) => error.code,
            'code',
            'downloadTooLarge',
          ),
        ),
        reason: 'declared length: $declare',
      );
    }
  });

  test('only release pages of this repository are opened', () {
    expect(
      AppUpdateService.isReleasePage(
        Uri.parse('https://github.com/AnatomikPerq/hp-client/releases/tag/v1'),
      ),
      isTrue,
    );
    for (final url in [
      'file:///C:/Windows/System32/calc.exe',
      r'\\attacker.test\share\setup.exe',
      'https://github.com/someone/else/releases/tag/v1',
      'https://github.com.attacker.test/AnatomikPerq/hp-client/releases/x',
      'http://github.com/AnatomikPerq/hp-client/releases/x',
      'https://user@github.com/AnatomikPerq/hp-client/releases/x',
    ]) {
      expect(
        AppUpdateService.isReleasePage(Uri.parse(url)),
        isFalse,
        reason: url,
      );
    }
  });
}
