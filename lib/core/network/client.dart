import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/network/model.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

class NetClient {
  static final NetClient _singleton = NetClient._internal();

  factory NetClient() => _singleton;

  NetClient._internal()
    : _downloadClient = Dio(
        BaseOptions(
          connectTimeout: Duration(seconds: 10),
          receiveTimeout: Duration(seconds: 60),
        ),
      );

  @visibleForTesting
  NetClient.forTesting(Dio client)
    : _downloadClient = client,
      _initFuture = Future.value();

  //========================
  final Dio _downloadClient;

  Future<void>? _initFuture;

  String get downloadUserAgent =>
      _downloadClient.options.headers['User-Agent']?.toString() ?? '';

  Future<void> asyncInit() {
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    _downloadClient.options.headers['User-Agent'] = await defaultUserAgent();
  }

  static Future<String> defaultUserAgent() async {
    var version = '0.0.0';
    var userAgent = 'HyperClient (${Platform.operatingSystem})';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      version = packageInfo.version;
      userAgent =
          'HyperClient/$version '
          '(${packageInfo.packageName}; build:${packageInfo.buildNumber}; '
          '${Platform.operatingSystem})';
    } catch (error) {
      ygLogger('Unable to build the HYPER CLIENT User-Agent: $error');
    }
    // Providers can select an Xray JSON template by this leading product:
    // Remnawave's JSON fallback matches /^v2rayN\/\d+\.\d+\.\d+/ with no
    // minimum version, so the fork's 0.1.0-beta.x qualifies.
    return 'v2rayN/$version $userAgent';
  }

  static const geoIPUrl = "https://ip-check-perf.radar.cloudflare.com/";

  static const _maxDownloadRedirects = 8;

  static bool isHttpsDownloadUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      uri.port > 0 &&
      uri.port <= 65535;

  Future<String?> getText(
    String url, {
    DownloadRequestHeaders? requestHeaders,
    bool httpsOnly = false,
  }) async =>
      (await getTextResponse(
        url,
        requestHeaders: requestHeaders,
        httpsOnly: httpsOnly,
      )).data ??
      '';

  Future<Response<String>> getTextResponse(
    String url, {
    DownloadRequestHeaders? requestHeaders,
    bool httpsOnly = false,
  }) async {
    try {
      var uri = Uri.parse(url);
      if (httpsOnly && !isHttpsDownloadUri(uri)) {
        throw const AppFailure(
          FailureCategory.input,
          'downloadUrl',
          cause: 'A valid HTTPS download URL is required',
        );
      }
      await asyncInit();
      final headers = requestHeaders?.toHttpHeaders();
      for (
        var redirectCount = 0;
        redirectCount <= _maxDownloadRedirects;
        redirectCount++
      ) {
        final res = await _downloadClient.getUri<ResponseBody>(
          uri,
          options: Options(
            responseType: ResponseType.stream,
            headers: headers,
            followRedirects: false,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        );
        final status = res.statusCode ?? 0;
        if (status < 300) {
          return Response<String>(
            data: await _readCapped(res),
            headers: res.headers,
            requestOptions: res.requestOptions,
            statusCode: res.statusCode,
            statusMessage: res.statusMessage,
          );
        }
        // Redirect bodies are never read.
        res.data?.stream.listen(null).cancel();
        final location = res.headers.value(HttpHeaders.locationHeader);
        if (location == null ||
            location.isEmpty ||
            redirectCount == _maxDownloadRedirects) {
          throw const AppFailure(
            FailureCategory.network,
            'redirect',
            cause: 'Missing redirect location or too many redirects',
          );
        }
        final next = uri.resolve(location);
        if (next.scheme != uri.scheme ||
            next.host != uri.host ||
            next.port != uri.port) {
          // Consent belongs to the subscription origin, not a redirect target.
          // Do not restore the identifier later in the redirect chain.
          headers?.remove('x-hwid');
        }
        uri = next;
        if (httpsOnly && !isHttpsDownloadUri(uri)) {
          throw const AppFailure(
            FailureCategory.network,
            'redirect',
            cause: 'Download redirected to a non-HTTPS URL',
          );
        }
      }
      throw const AppFailure(
        FailureCategory.network,
        'redirect',
        cause: 'Too many download redirects',
      );
    } catch (e) {
      // Subscription URLs can contain credentials; never log the request URI.
      ygLogger('text download failed: ${failureDetails(e)}');
      rethrow;
    }
  }

  /// Subscriptions and other text downloads are small. A body beyond this
  /// comes from a broken or hostile server and would otherwise be buffered
  /// whole, on every automatic refresh.
  static const maxTextDownloadBytes = 16 * 1024 * 1024;

  static Future<String> _readCapped(Response<ResponseBody> response) async {
    final declared = int.tryParse(
      response.headers.value(Headers.contentLengthHeader) ?? '',
    );
    if (declared != null && declared > maxTextDownloadBytes) {
      throw const AppFailure(
        FailureCategory.network,
        'downloadTooLarge',
        cause: 'The download exceeds 16 MiB',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.data!.stream) {
      bytes.add(chunk);
      if (bytes.length > maxTextDownloadBytes) {
        throw const AppFailure(
          FailureCategory.network,
          'downloadTooLarge',
          cause: 'The download exceeds 16 MiB',
        );
      }
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  Future<Map<String, dynamic>?> getJson(String url) async {
    try {
      await asyncInit();
      final res = await _downloadClient.get<Map<String, dynamic>>(url);
      return res.data;
    } catch (e) {
      ygLogger('JSON download failed: ${failureDetails(e)}');
      rethrow;
    }
  }
}
