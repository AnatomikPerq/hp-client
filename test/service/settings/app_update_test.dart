import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/ffi/windows/update_installer.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

const _sha = 'eaef8474d02878a59a153f7d140d99553fdd5f5e9279ef0bbad1e3313c05d977';

Map<String, dynamic> _asset(
  String name, {
  String? digest = 'sha256:$_sha',
  int size = 42605544,
  String? url,
}) => {
  'name': name,
  'size': size,
  'digest': ?digest,
  'browser_download_url':
      url ??
      'https://github.com/AnatomikPerq/hp-client/releases/download/v1.0.0/$name',
};

class _RecordingHost implements AppUpdateInstallHost {
  final calls = <String>[];
  Object? failure;

  @override
  Future<void> install(String path, AppUpdatePackage package) async {
    calls.add(path);
    if (failure case final error?) throw error;
  }
}

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'HYPER CLIENT',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('release assets', () {
    final release = GitHubRelease.fromJson({
      'tag_name': 'v1.0.0',
      'html_url': 'https://github.com/AnatomikPerq/hp-client/releases/tag/v1',
      'body': '',
      'assets': [
        _asset('HyperClient-1.0.0-windows-x64.zip'),
        _asset('HyperClient-1.0.0-windows-x64-setup.exe'),
        _asset('HyperClient-1.0.0-android-arm64-v8a.apk', size: 60000000),
        _asset('HyperClient-1.0.0-android-x86_64.apk', digest: null),
        'not an asset',
      ],
    })!;

    test('the installer and the APK of the running ABI are picked', () {
      final windows = AppUpdateService.selectPackage(
        release.assets,
        target: AppUpdatePackageTarget.windowsX64,
      );
      expect(windows?.name, 'HyperClient-1.0.0-windows-x64-setup.exe');
      expect(windows?.sha256, _sha);
      expect(windows?.kind, AppUpdatePackageKind.windowsInstaller);
      final android = AppUpdateService.selectPackage(
        release.assets,
        target: AppUpdatePackageTarget.androidArm64,
      );
      expect(android?.name, 'HyperClient-1.0.0-android-arm64-v8a.apk');
      expect(android?.size, 60000000);
    });

    test('no package without a target, an asset or its digest', () {
      expect(
        AppUpdateService.selectPackage(release.assets, target: null),
        isNull,
      );
      expect(
        AppUpdateService.selectPackage(
          release.assets,
          target: AppUpdatePackageTarget.windowsArm64,
        ),
        isNull,
      );
      expect(
        AppUpdateService.selectPackage(
          release.assets,
          target: AppUpdatePackageTarget.androidX64,
        ),
        isNull,
      );
    });

    test('assets outside this repository or oversized are refused', () {
      for (final asset in [
        _asset(
          'HyperClient-1.0.0-windows-x64-setup.exe',
          url: 'https://github.com/someone/else/releases/download/v1/x.exe',
        ),
        _asset(
          'HyperClient-1.0.0-windows-x64-setup.exe',
          url: 'https://attacker.test/AnatomikPerq/hp-client/releases/download/x',
        ),
        _asset(
          'HyperClient-1.0.0-windows-x64-setup.exe',
          url: 'https://github.com/AnatomikPerq/hp-client/releases/tag/v1',
        ),
        _asset(
          'HyperClient-1.0.0-windows-x64-setup.exe',
          size: AppUpdateService.maxPackageBytes + 1,
        ),
        _asset(
          'HyperClient-1.0.0-windows-x64-setup.exe',
          digest: 'sha512:$_sha',
        ),
      ]) {
        expect(
          AppUpdateService.selectPackage([
            GitHubReleaseAsset.fromJson(asset)!,
          ], target: AppUpdatePackageTarget.windowsX64),
          isNull,
          reason: '$asset',
        );
      }
    });
  });

  group('download and install', () {
    late Directory root;
    late _RecordingHost host;
    final service = AppUpdateService();

    setUp(() async {
      final bus = AppEventBus();
      addTearDown(bus.close);
      root = await Directory.systemTemp.createTemp('hc-update-');
      host = _RecordingHost();
      service
        ..rootOverride = root.path
        ..installHost = host
        ..transfer.value = const AppUpdateTransfer.idle();
    });

    tearDown(() async {
      service
        ..rootOverride = null
        ..installHost = null
        ..transfer.value = const AppUpdateTransfer.idle();
      await root.delete(recursive: true);
    });

    Future<Uri> serve(List<int> body, {Completer<void>? hold}) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.contentLength = body.length;
        request.response.add(body.sublist(0, body.length ~/ 2));
        await request.response.flush();
        await hold?.future;
        request.response.add(body.sublist(body.length ~/ 2));
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      return Uri.parse('http://127.0.0.1:${server.port}/package.exe');
    }

    AppUpdateInfo info(Uri uri, List<int> body, {String? hash}) =>
        AppUpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '1.1.0',
          releaseNotes: '',
          releaseUri: Uri.parse('https://example.com/release'),
          updateUri: Uri.parse('https://example.com/release'),
          destination: AppUpdateDestination.githubRelease,
          package: AppUpdatePackage(
            name: 'HyperClient-1.1.0-windows-x64-setup.exe',
            downloadUri: uri,
            size: body.length,
            sha256: hash ?? sha256.convert(body).toString(),
            kind: AppUpdatePackageKind.windowsInstaller,
          ),
        );

    test('a verified package is installed from the update folder', () async {
      final body = List<int>.generate(300000, (index) => index % 251);
      final update = info(await serve(body), body);
      final phases = <AppUpdateTransferPhase>{};
      void record() => phases.add(service.transfer.value.phase);
      service.transfer.addListener(record);
      addTearDown(() => service.transfer.removeListener(record));

      await service.download(update);

      expect(service.transfer.value.phase, AppUpdateTransferPhase.ready);
      expect(phases, contains(AppUpdateTransferPhase.downloading));
      final file = File(p.join(root.path, 'update', update.package!.name));
      expect(await file.readAsBytes(), body);
      expect(await File('${file.path}.part').exists(), isFalse);

      // Downloading again is a no-op; installing hands over the file.
      await service.download(update);
      await service.install(update);
      expect(host.calls, [file.path]);
      expect(service.transfer.value.phase, AppUpdateTransferPhase.ready);
    });

    test('a file that does not match the release digest fails', () async {
      final body = List<int>.filled(1000, 7);
      final update = info(await serve(body), body, hash: _sha);

      await service.download(update);

      expect(service.transfer.value.phase, AppUpdateTransferPhase.failed);
      expect(
        service.transfer.value.error,
        isA<AppFailure>().having((e) => e.code, 'code', 'updateHashMismatch'),
      );
      await expectLater(service.install(update), throwsA(isA<AppFailure>()));
      expect(host.calls, isEmpty);
    });

    test('a declined installer leaves the download ready', () async {
      final body = List<int>.filled(1000, 9);
      final update = info(await serve(body), body);
      await service.download(update);
      host.failure = const AppFailure(
        FailureCategory.runtime,
        'updateInstallerExited',
      );

      await expectLater(service.install(update), throwsA(isA<AppFailure>()));
      expect(service.transfer.value.phase, AppUpdateTransferPhase.ready);
    });

    test('cancelling a download goes back to idle', () async {
      final hold = Completer<void>();
      final body = List<int>.filled(200000, 3);
      final update = info(await serve(body, hold: hold), body);

      final running = service.download(update);
      // A second click joins the running download.
      final joined = service.download(update);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      service.cancelDownload();
      hold.complete();
      await running;
      await joined;

      expect(service.transfer.value.phase, AppUpdateTransferPhase.idle);
    });
  });

  test('the Windows file lock keeps writers and deleters out', () async {
    final directory = await Directory.systemTemp.createTemp('hc-lock-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'setup.exe'))
      ..writeAsBytesSync([1, 2, 3]);

    final lock = WindowsFileLock.open(file.path);
    try {
      expect(await file.readAsBytes(), [1, 2, 3]);
      expect(
        () => file.writeAsBytesSync([4]),
        throwsA(isA<FileSystemException>()),
      );
      expect(file.deleteSync, throwsA(isA<FileSystemException>()));
      expect(
        () => file.renameSync(p.join(directory.path, 'other.exe')),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      lock.release();
    }
    file.deleteSync();
    expect(windowsMutexExists('HyperClientTest-$pid-absent'), isFalse);
  }, skip: !Platform.isWindows);
}
