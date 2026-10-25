import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/ffi/windows/update_installer.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/app_log.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppUpdateCheckStatus { available, upToDate, failed }

enum AppUpdateDestination { appStore, googlePlay, githubRelease }

enum AppUpdatePackageKind { windowsInstaller, androidApk }

/// A release asset the App can download and install itself.
class AppUpdatePackage {
  final String name;
  final Uri downloadUri;
  final int size;

  /// Lowercase hex, from the asset's `digest` in the GitHub API.
  final String sha256;
  final AppUpdatePackageKind kind;

  const AppUpdatePackage({
    required this.name,
    required this.downloadUri,
    required this.size,
    required this.sha256,
    required this.kind,
  });
}

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final Uri releaseUri;
  final Uri updateUri;
  final AppUpdateDestination destination;

  /// Null where the update is only a page to open: a ZIP build, a platform
  /// without its asset in the release, or a release without digests.
  final AppUpdatePackage? package;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.releaseUri,
    required this.updateUri,
    required this.destination,
    this.package,
  });
}

class AppUpdateCheckResult {
  final AppUpdateCheckStatus status;
  final AppUpdateInfo? updateInfo;
  final Object? error;

  const AppUpdateCheckResult._(this.status, this.updateInfo, [this.error]);

  const AppUpdateCheckResult.available(AppUpdateInfo updateInfo)
    : this._(AppUpdateCheckStatus.available, updateInfo);

  const AppUpdateCheckResult.upToDate()
    : this._(AppUpdateCheckStatus.upToDate, null);

  const AppUpdateCheckResult.failed([Object? error])
    : this._(AppUpdateCheckStatus.failed, null, error);
}

enum AppUpdateTransferPhase { idle, downloading, ready, installing, failed }

/// The one-click update's download, kept by the service so that closing the
/// dialog does not lose it.
class AppUpdateTransfer {
  final AppUpdateTransferPhase phase;
  final String? version;
  final int received;
  final int total;
  final Object? error;

  const AppUpdateTransfer._(
    this.phase, {
    this.version,
    this.received = 0,
    this.total = 0,
    this.error,
  });

  const AppUpdateTransfer.idle() : this._(AppUpdateTransferPhase.idle);

  bool isFor(AppUpdateInfo info) => version == info.latestVersion;
}

/// Platform part of a one-click update; replaced in tests.
abstract interface class AppUpdateInstallHost {
  /// Runs the verified [package] at [path]; on Windows this does not return
  /// when the installer took over (the App exits).
  Future<void> install(String path, AppUpdatePackage package);
}

class AppUpdateService {
  static final AppUpdateService _singleton = AppUpdateService._internal();

  factory AppUpdateService() => _singleton;

  AppUpdateService._internal();

  // Релизы берём у форка, а не у апстрима. С версией 0.1.0-beta проверка
  // против OneXray всегда сообщала бы о «новой версии» и предлагала
  // поставить чужое приложение поверх этого.
  static const _githubLatestReleaseApi =
      "https://api.github.com/repos/AnatomikPerq/hp-client/releases/latest";
  static const _githubLatestReleaseUrl =
      "https://github.com/AnatomikPerq/hp-client/releases/latest";
  static const _appStoreUrl =
      "https://apps.apple.com/us/app/onexray/id6745748773";
  static const _automaticCheckInterval = Duration(days: 1);

  /// Test builds only (`--dart-define`): a release JSON served elsewhere,
  /// whose assets may live on the same origin. Release builds never set it.
  static const _testFeed = String.fromEnvironment('HC_APP_UPDATE_FEED');

  /// Installers are about 45 MB, split APKs about 60 MB.
  static const maxPackageBytes = 512 * 1024 * 1024;

  final transfer = ValueNotifier(const AppUpdateTransfer.idle());
  CancelToken? _cancel;

  @visibleForTesting
  AppUpdateInstallHost? installHost;

  /// Replaces the App data directory the `update` folder lives in.
  @visibleForTesting
  String? rootOverride;

  Future<AppUpdateCheckResult> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = _parseVersion(packageInfo.version);
      if (currentVersion == null) {
        ygLogger(
          "checkForUpdate invalid current version: ${packageInfo.version}",
        );
        return const AppUpdateCheckResult.failed();
      }

      final releaseJson = await AppEventBus.instance.trackDownload(
        () => NetClient().getJson(
          _testFeed.isEmpty ? _githubLatestReleaseApi : _testFeed,
        ),
      );
      if (releaseJson == null) {
        return const AppUpdateCheckResult.failed();
      }

      final release = GitHubRelease.fromJson(releaseJson);
      if (release == null) {
        ygLogger("checkForUpdate invalid release json");
        return const AppUpdateCheckResult.failed();
      }

      final latestVersion = _parseVersion(release.tagName);
      if (latestVersion == null) {
        ygLogger("checkForUpdate invalid release tag: ${release.tagName}");
        return const AppUpdateCheckResult.failed();
      }

      if (latestVersion.compareTo(currentVersion) > 0) {
        final updateUri = await _resolveUpdateUri(release.releaseUri);
        return AppUpdateCheckResult.available(
          AppUpdateInfo(
            currentVersion: packageInfo.version,
            latestVersion: latestVersion.toString(),
            releaseNotes: release.body,
            releaseUri: release.releaseUri,
            updateUri: updateUri.item1,
            destination: updateUri.item2,
            package: selectPackage(
              release.assets,
              target: await _packageTarget(),
            ),
          ),
        );
      }
      return const AppUpdateCheckResult.upToDate();
    } catch (e) {
      ygLogger("checkForUpdate error: $e");
      return AppUpdateCheckResult.failed(e);
    }
  }

  Future<bool> shouldRunAutomaticCheck() async {
    final lastCheck = await PreferencesKey().readAppUpdateLastCheckTimestamp();
    if (lastCheck == null) {
      return true;
    }
    return DateTime.now().difference(lastCheck) >= _automaticCheckInterval;
  }

  Future<void> recordAutomaticCheck() async {
    await PreferencesKey().saveAppUpdateLastCheckTimestamp(DateTime.now());
  }

  Future<bool> shouldShowAutomaticReminder(AppUpdateInfo updateInfo) async {
    final skippedVersion = await PreferencesKey().readAppUpdateSkippedVersion();
    return skippedVersion != updateInfo.latestVersion;
  }

  Future<void> skipVersion(AppUpdateInfo updateInfo) async {
    await PreferencesKey().saveAppUpdateSkippedVersion(
      updateInfo.latestVersion,
    );
  }

  static bool isReleasePage(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      uri.path.startsWith('/AnatomikPerq/hp-client/releases/');

  /// Assets are taken only from this repository's releases; GitHub then
  /// redirects to its asset host, and the hash decides.
  static bool isReleaseAsset(Uri uri) =>
      isReleasePage(uri) &&
      uri.path.startsWith('/AnatomikPerq/hp-client/releases/download/');

  Future<void> openUpdate(AppUpdateInfo updateInfo) async {
    if (!await launchUrl(updateInfo.updateUri)) {
      throw StateError('Could not open update page');
    }
  }

  /// The asset this App can install, by the names the release process gives
  /// them (`readme/BUILD.md`): `HyperClient-<version>-windows-x64-setup.exe`,
  /// `HyperClient-<version>-android-<abi>.apk`.
  @visibleForTesting
  static AppUpdatePackage? selectPackage(
    List<GitHubReleaseAsset> assets, {
    required AppUpdatePackageTarget? target,
  }) {
    if (target == null) return null;
    for (final asset in assets) {
      if (!asset.name.startsWith('HyperClient-') ||
          !asset.name.endsWith(target.suffix)) {
        continue;
      }
      final sha256 = asset.sha256;
      if (sha256 == null ||
          asset.size <= 0 ||
          asset.size > maxPackageBytes ||
          !(isReleaseAsset(asset.downloadUri) || _testFeedAsset(asset))) {
        ygLogger("app update asset rejected: ${asset.name}");
        return null;
      }
      return AppUpdatePackage(
        name: asset.name,
        downloadUri: asset.downloadUri,
        size: asset.size,
        sha256: sha256,
        kind: target.kind,
      );
    }
    return null;
  }

  static bool _testFeedAsset(GitHubReleaseAsset asset) {
    if (_testFeed.isEmpty) return false;
    final feed = Uri.parse(_testFeed);
    return asset.downloadUri.scheme == feed.scheme &&
        asset.downloadUri.host == feed.host &&
        asset.downloadUri.port == feed.port;
  }

  Future<AppUpdatePackageTarget?> _packageTarget() async {
    if (AppPlatform.isWindows) {
      // Only an installed App updates itself: the ZIP build lives wherever it
      // was unpacked, and the installer would put a second copy elsewhere.
      final directory = p.dirname(Platform.resolvedExecutable);
      if (!await File(p.join(directory, 'unins000.exe')).exists()) {
        return null;
      }
      return switch (Abi.current()) {
        Abi.windowsX64 => AppUpdatePackageTarget.windowsX64,
        Abi.windowsArm64 => AppUpdatePackageTarget.windowsArm64,
        _ => null,
      };
    }
    if (AppPlatform.isAndroid) {
      return switch (Abi.current()) {
        Abi.androidArm64 => AppUpdatePackageTarget.androidArm64,
        Abi.androidArm => AppUpdatePackageTarget.androidArm,
        Abi.androidX64 => AppUpdatePackageTarget.androidX64,
        _ => null,
      };
    }
    return null;
  }

  /// Downloads and checks the update package. Progress and the result are in
  /// [transfer]; a second call for the same version joins the running
  /// download, and after it finished does nothing.
  Future<void> download(AppUpdateInfo info) {
    final current = transfer.value;
    if (current.isFor(info)) {
      if (current.phase == AppUpdateTransferPhase.downloading) {
        return _downloading ?? Future.value();
      }
      if (current.phase == AppUpdateTransferPhase.ready ||
          current.phase == AppUpdateTransferPhase.installing) {
        return Future.value();
      }
    }
    final running = _downloading = _download(info);
    return running.whenComplete(() {
      if (identical(_downloading, running)) _downloading = null;
    });
  }

  Future<void>? _downloading;

  Future<void> _download(AppUpdateInfo info) async {
    final package = info.package;
    if (package == null) {
      throw const AppFailure(FailureCategory.input, 'updatePackageMissing');
    }
    final cancel = _cancel = CancelToken();
    void report(AppUpdateTransferPhase phase, {int received = 0, Object? e}) {
      transfer.value = AppUpdateTransfer._(
        phase,
        version: info.latestVersion,
        received: received,
        total: package.size,
        error: e,
      );
    }

    report(AppUpdateTransferPhase.downloading);
    try {
      final directory = await _updateDirectory(clean: true);
      final target = File(p.join(directory.path, package.name));
      final part = File('${target.path}.part');
      var reported = 0;
      await AppEventBus.instance.trackDownload(
        () => NetClient().downloadFile(
          package.downloadUri,
          part.path,
          maxBytes: package.size,
          cancelToken: cancel,
          onProgress: (received) {
            // About two hundred updates for the whole file.
            if (received - reported >= package.size ~/ 200 ||
                received == package.size) {
              reported = received;
              report(AppUpdateTransferPhase.downloading, received: received);
            }
          },
        ),
      );
      if (await part.length() != package.size) {
        throw const AppFailure(FailureCategory.network, 'updateIncomplete');
      }
      await part.rename(target.path);
      await verifyPackage(target, package.sha256);
      report(AppUpdateTransferPhase.ready, received: package.size);
    } catch (error) {
      if (error is DioException && CancelToken.isCancel(error)) {
        transfer.value = const AppUpdateTransfer.idle();
        return;
      }
      ygLogger("app update download failed: ${failureDetails(error)}");
      AppLog.warning('update download failed (${AppLog.reason(error)})');
      report(AppUpdateTransferPhase.failed, e: error);
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }

  void cancelDownload() => _cancel?.cancel();

  /// Installs the downloaded package. On Windows a successful call ends with
  /// the App exiting; the installer starts it again.
  Future<void> install(AppUpdateInfo info) async {
    final package = info.package;
    final current = transfer.value;
    if (package == null ||
        !current.isFor(info) ||
        current.phase != AppUpdateTransferPhase.ready) {
      throw const AppFailure(FailureCategory.conflict, 'updateNotReady');
    }
    transfer.value = AppUpdateTransfer._(
      AppUpdateTransferPhase.installing,
      version: current.version,
      received: current.received,
      total: current.total,
    );
    try {
      final directory = await _updateDirectory();
      await (installHost ?? _platformInstallHost()).install(
        p.join(directory.path, package.name),
        package,
      );
    } finally {
      // Back to "ready" when the installer declined or was cancelled; the
      // file stays for the next attempt.
      if (transfer.value.phase == AppUpdateTransferPhase.installing) {
        transfer.value = current;
      }
    }
  }

  AppUpdateInstallHost _platformInstallHost() {
    if (AppPlatform.isWindows) return const _WindowsInstallHost();
    if (AppPlatform.isAndroid) return const _AndroidInstallHost();
    throw const AppFailure(FailureCategory.input, 'updatePackageMissing');
  }

  /// Leftovers of an earlier update; the running download keeps its files.
  Future<void> removeDownloads() async {
    if (transfer.value.phase != AppUpdateTransferPhase.idle) return;
    try {
      await _updateDirectory(clean: true);
    } catch (error) {
      ygLogger("app update cleanup failed: $error");
    }
  }

  Future<Directory> _updateDirectory({bool clean = false}) async {
    final root = rootOverride ?? AppHostApi().tunFilesDir;
    if (root.isEmpty) {
      throw const AppFailure(FailureCategory.storage, 'updateDirectory');
    }
    final directory = Directory(p.join(root, 'update'));
    if (clean && await directory.exists()) {
      await for (final entry in directory.list()) {
        try {
          await entry.delete(recursive: true);
        } on FileSystemException {
          // An installer that still runs keeps its file open.
        }
      }
    }
    await directory.create(recursive: true);
    return directory;
  }

  Future<({Uri item1, AppUpdateDestination item2})> _resolveUpdateUri(
    Uri releaseUri,
  ) async {
    if (AppPlatform.isIOS) {
      return (
        item1: Uri.parse(_appStoreUrl),
        item2: AppUpdateDestination.appStore,
      );
    }
    if (AppPlatform.isMacOS) {
      final useSystemExtension = await AppHostApi().useSystemExtension();
      if (!useSystemExtension) {
        return (
          item1: Uri.parse(_appStoreUrl),
          item2: AppUpdateDestination.appStore,
        );
      }
    }
    // Android included: the fork is not on Google Play, and upstream's
    // listing there is another app.
    return (item1: releaseUri, item2: AppUpdateDestination.githubRelease);
  }

  Version? _parseVersion(String value) {
    var text = value.trim();
    if (text.startsWith("v") || text.startsWith("V")) {
      text = text.substring(1);
    }
    try {
      return Version.parse(text);
    } catch (_) {
      return null;
    }
  }
}

/// Throws unless [file] hashes to [expected] (lowercase hex SHA-256).
Future<void> verifyPackage(File file, String expected) async {
  final digest = await sha256.bind(file.openRead()).first;
  if (digest.toString() != expected) {
    throw const AppFailure(FailureCategory.input, 'updateHashMismatch');
  }
}

enum AppUpdatePackageTarget {
  windowsX64('-windows-x64-setup.exe', AppUpdatePackageKind.windowsInstaller),
  windowsArm64(
    '-windows-arm64-setup.exe',
    AppUpdatePackageKind.windowsInstaller,
  ),
  androidArm64('-android-arm64-v8a.apk', AppUpdatePackageKind.androidApk),
  androidArm('-android-armeabi-v7a.apk', AppUpdatePackageKind.androidApk),
  androidX64('-android-x86_64.apk', AppUpdatePackageKind.androidApk);

  final String suffix;
  final AppUpdatePackageKind kind;

  const AppUpdatePackageTarget(this.suffix, this.kind);
}

class _WindowsInstallHost implements AppUpdateInstallHost {
  const _WindowsInstallHost();

  @override
  Future<void> install(String path, AppUpdatePackage package) async {
    // Locked before the hash is checked, and kept locked while the installer
    // starts: the update folder is writable by every process of the user,
    // and UAC would elevate whatever lies there.
    final lock = WindowsFileLock.open(path);
    var exiting = false;
    try {
      await verifyPackage(File(path), package.sha256);
      final outcome = await const WindowsUpdateInstaller().launch(
        path,
        windowsUpdateArguments(p.join(p.dirname(path), 'setup.log')),
      );
      switch (outcome.state) {
        case WindowsInstallerState.waitingForApp:
          break;
        case WindowsInstallerState.exited:
          // UAC declined, or an installer without the update mode.
          throw AppFailure(
            FailureCategory.runtime,
            'updateInstallerExited',
            cause: 'Installer exit code ${outcome.exitCode}',
          );
        case WindowsInstallerState.timedOut:
          throw const AppFailure(FailureCategory.runtime, 'updateTimedOut');
      }
      // The installer waits up to two minutes for this App to exit; if the
      // Core cannot be stopped it gives up and nothing changes.
      final reconnect = await ConnectionCoordinator.instance.suspendForUpdate();
      if (reconnect) await PreferencesKey().saveAppUpdateReconnect();
      AppLog.info('exiting for the update to ${package.name}');
      // Log lines are written asynchronously; the exit would drop them.
      await AppLog.flush();
      exiting = true;
      await ServicesBinding.instance.exitApplication(AppExitType.required);
    } finally {
      if (!exiting) lock.release();
    }
  }
}

class _AndroidInstallHost implements AppUpdateInstallHost {
  const _AndroidInstallHost();

  @override
  Future<void> install(String path, AppUpdatePackage package) async {
    // App-private storage: no other app can swap the file.
    await verifyPackage(File(path), package.sha256);
    final api = AndroidSystemHostApi();
    if (!await api.canInstallUpdates()) {
      // Opens "install unknown apps" for the App; the tunnel stays up.
      await api.installUpdate(path, false);
      throw const AppFailure(
        FailureCategory.permission,
        'updateInstallPermission',
      );
    }
    final coordinator = ConnectionCoordinator.instance;
    final reconnect =
        coordinator.state.value.phase == ConnectionPhase.connected;
    if (reconnect) {
      // Replacing the package while its VPN runs leaves Android's per-UID
      // ingress rule (bpf IIF_MATCH) on the dead tunnel: the updated App
      // then receives nothing, with or without the VPN, until a reboot
      // (Android 16 emulator, 25.10.2026). The receiver starts it again.
      await coordinator.disconnect();
    }
    final state = await api.installUpdate(path, reconnect);
    if (state == AndroidUpdateInstallState.permissionRequired) {
      if (reconnect) unawaited(coordinator.connect());
      throw const AppFailure(
        FailureCategory.permission,
        'updateInstallPermission',
      );
    }
    if (reconnect) _ReconnectAfterCancel.arm();
  }
}

/// A replaced package kills this process. Coming back to it alive means the
/// user cancelled the installer: the tunnel stopped for the update comes back.
final class _ReconnectAfterCancel {
  static AppLifecycleListener? _listener;

  static void arm() {
    _listener?.dispose();
    _listener = AppLifecycleListener(
      onResume: () {
        _listener?.dispose();
        _listener = null;
        // The installer may still be finishing; a replaced package never
        // gets here.
        Timer(const Duration(seconds: 3), () async {
          try {
            await AndroidSystemHostApi().clearUpdateReconnect();
            await ConnectionCoordinator.instance.connect();
          } catch (error) {
            ygLogger("reconnect after a cancelled update failed: $error");
          }
        });
      },
    );
  }
}

class GitHubReleaseAsset {
  final String name;
  final Uri downloadUri;
  final int size;
  final String? sha256;

  const GitHubReleaseAsset({
    required this.name,
    required this.downloadUri,
    required this.size,
    required this.sha256,
  });

  static final _digest = RegExp(r'^sha256:([0-9a-f]{64})$');

  static GitHubReleaseAsset? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final url = json['browser_download_url'];
    final size = json['size'];
    final digest = json['digest'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (name is! String || uri == null || size is! int) return null;
    final match = digest is String
        ? _digest.firstMatch(digest.toLowerCase())
        : null;
    return GitHubReleaseAsset(
      name: name,
      downloadUri: uri,
      size: size,
      sha256: match?.group(1),
    );
  }
}

class GitHubRelease {
  final String tagName;
  final String body;
  final Uri releaseUri;
  final List<GitHubReleaseAsset> assets;

  const GitHubRelease({
    required this.tagName,
    required this.body,
    required this.releaseUri,
    this.assets = const [],
  });

  static GitHubRelease? fromJson(Map<String, dynamic> json) {
    final tagName = json["tag_name"];
    if (tagName is! String || tagName.isEmpty) {
      return null;
    }
    final htmlUrl = json["html_url"];
    final candidate = htmlUrl is String ? Uri.tryParse(htmlUrl) : null;
    // The page is opened with the OS handler, which accepts any scheme or
    // path; only a release page of this repository is followed.
    final releaseUri =
        candidate != null && AppUpdateService.isReleasePage(candidate)
        ? candidate
        : Uri.tryParse(AppUpdateService._githubLatestReleaseUrl);
    if (releaseUri == null) {
      return null;
    }
    final body = json["body"];
    final assets = json["assets"];
    return GitHubRelease(
      tagName: tagName,
      body: body is String ? body : "",
      releaseUri: releaseUri,
      assets: [
        if (assets is List)
          for (final asset in assets) ?GitHubReleaseAsset.fromJson(asset),
      ],
    );
  }
}
