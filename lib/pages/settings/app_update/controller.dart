import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppUpdateDialogAction { skip }

class AppUpdateDialogController extends PageCubit<AppUpdateDialogAction?> {
  final AppUpdateInfo updateInfo;
  final AppUpdateService _service;

  AppUpdateDialogController(this.updateInfo, {AppUpdateService? service})
    : _service = service ?? AppUpdateService(),
      super(null);

  ValueListenable<AppUpdateTransfer> get transfer => _service.transfer;

  void later(BuildContext context) {
    Navigator.pop(context);
  }

  Future<void> skip(BuildContext context) async {
    if (state != null) return;
    emit(AppUpdateDialogAction.skip);
    try {
      await AppUpdateService().skipVersion(updateInfo);
      AppEventBus.instance.updateAppUpdateInfo(null);
      if (context.mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (context.mounted) {
        ContextAlert.showToast(
          context,
          appFailureMessage(
            AppLocalizations.of(context)!,
            error,
            operation: AppLocalizations.of(context)!.buttonSaveFailed,
          ),
        );
      }
    } finally {
      emit(null);
    }
  }

  /// One click: download, check and install. A download the user hid with
  /// "Later" keeps running and waits for the next click to install.
  Future<void> update(BuildContext context) async {
    if (updateInfo.package == null) return _openPage(context);
    final l = AppLocalizations.of(context)!;
    try {
      await _service.download(updateInfo);
      if (!context.mounted ||
          !transfer.value.isFor(updateInfo) ||
          transfer.value.phase != AppUpdateTransferPhase.ready) {
        return;
      }
      await _service.install(updateInfo);
    } catch (error) {
      ygLogger("app update error: $error");
      if (context.mounted) {
        ContextAlert.showToast(context, updateFailureMessage(l, error));
      }
    }
  }

  void cancelDownload() => _service.cancelDownload();

  Future<void> openPage(BuildContext context) => _openPage(context);

  Future<void> _openPage(BuildContext context) async {
    final navigator = Navigator.of(context);
    final feedbackContext = navigator.context;
    final l = AppLocalizations.of(context)!;
    navigator.pop();
    try {
      await AppUpdateService().openUpdate(updateInfo);
    } catch (error) {
      ygLogger("openUpdate error: $error");
      if (feedbackContext.mounted) {
        ContextAlert.showToast(feedbackContext, appFailureMessage(l, error));
      }
    }
  }

  Future<void> openLink(BuildContext context, String? href) async {
    if (href == null || href.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri == null) {
      ygLogger("openUpdateLink invalid url: $href");
      ContextAlert.showToast(
        context,
        AppLocalizations.of(context)!.prototypeTemporarilyUnavailable,
      );
      return;
    }
    try {
      if (!await launchUrl(uri)) {
        throw StateError('Could not open release link');
      }
    } catch (error) {
      ygLogger("openUpdateLink error: $error");
      if (context.mounted) {
        ContextAlert.showToast(
          context,
          appFailureMessage(AppLocalizations.of(context)!, error),
        );
      }
    }
  }
}

String updateFailureMessage(AppLocalizations l, Object? error) =>
    switch (error) {
      AppFailure(code: 'updateHashMismatch') => l.appUpdateHashMismatch,
      AppFailure(code: 'updateInstallerExited' || 'updateTimedOut') =>
        l.appUpdateInstallerCancelled,
      AppFailure(code: 'updateInstallPermission') =>
        l.appUpdateInstallPermission,
      _ => appFailureMessage(l, error, operation: l.appUpdateFailed),
    };
