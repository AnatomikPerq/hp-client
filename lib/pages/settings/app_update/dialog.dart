import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:onexray/core/tools/traffic_format.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/app_update/controller.dart';
import 'package:onexray/pages/settings/app_update/params.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AppUpdateDialog extends StatelessWidget {
  final AppUpdateDialogParams params;

  const AppUpdateDialog({super.key, required this.params});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppUpdateDialogController(params.updateInfo),
      child: BlocBuilder<AppUpdateDialogController, AppUpdateDialogAction?>(
        builder: (context, action) {
          final controller = context.read<AppUpdateDialogController>();
          return ValueListenableBuilder(
            valueListenable: controller.transfer,
            builder: (context, transfer, _) => AppUpdateDialogView(
              updateInfo: params.updateInfo,
              action: action,
              transfer: transfer.isFor(params.updateInfo)
                  ? transfer
                  : const AppUpdateTransfer.idle(),
              onLater: () => controller.later(context),
              onSkip: () => controller.skip(context),
              onUpdate: () => controller.update(context),
              onCancelDownload: controller.cancelDownload,
              onOpenLink: (href) => controller.openLink(context, href),
            ),
          );
        },
      ),
    );
  }
}

class AppUpdateDialogView extends StatelessWidget {
  final AppUpdateInfo updateInfo;
  final AppUpdateDialogAction? action;
  final AppUpdateTransfer transfer;
  final VoidCallback onLater;
  final VoidCallback onSkip;
  final VoidCallback onUpdate;
  final VoidCallback? onCancelDownload;
  final ValueChanged<String?> onOpenLink;

  const AppUpdateDialogView({
    super.key,
    required this.updateInfo,
    this.action,
    this.transfer = const AppUpdateTransfer.idle(),
    required this.onLater,
    required this.onSkip,
    required this.onUpdate,
    this.onCancelDownload,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final notes = updateInfo.releaseNotes.trim();
    final screenSize = MediaQuery.sizeOf(context);
    final notesHeight = (screenSize.height * 0.42).clamp(160.0, 420.0);
    return Dialog(
      // Match the prototype dialog's effective UA max-width (viewport - 38).
      insetPadding: const EdgeInsets.symmetric(horizontal: 19, vertical: 16),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ShadCard(
          width: double.infinity,
          padding: EdgeInsets.zero,
          radius: const BorderRadius.all(Radius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.appUpdateDialogTitle,
                      style: AppTypography.updateTitle,
                    ),
                    const SizedBox(height: 14),
                    _VersionGrid(updateInfo: updateInfo),
                  ],
                ),
              ),
              if (notes.isNotEmpty) ...[
                Divider(height: 1, color: ColorManager.border(context)),
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: notesHeight),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.prototypeReleaseNotes,
                            style: AppTypography.updateNotesHeading,
                          ),
                          const SizedBox(height: 10),
                          // flutter_markdown_plus still uses SDK Material.
                          // ignore: deprecated_member_use
                          MaterialUiCompatibilityBridge(
                            child: MarkdownBody(
                              data: notes,
                              selectable: true,
                              styleSheet: MarkdownStyleSheet(
                                p: AppTypography.updateNotes,
                                listBullet: AppTypography.updateNotes,
                                listIndent: 20,
                                listBulletPadding:
                                    const EdgeInsetsDirectional.only(end: 4)
                                        .resolve(Directionality.of(context)),
                                blockSpacing: 6,
                              ),
                              onTapLink: (_, href, _) => onOpenLink(href),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (_status(l10n) case final status?) ...[
                Divider(height: 1, color: ColorManager.border(context)),
                _UpdateStatus(transfer: transfer, text: status),
              ],
              Divider(height: 1, color: ColorManager.border(context)),
              _UpdateActions(
                updateInfo: updateInfo,
                transfer: transfer,
                action: action,
                onLater: onLater,
                onSkip: onSkip,
                onUpdate: onUpdate,
                onCancelDownload: onCancelDownload,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on AppUpdateDialogView {
  String? _status(AppLocalizations l10n) => switch (transfer.phase) {
    AppUpdateTransferPhase.idle || AppUpdateTransferPhase.ready => null,
    AppUpdateTransferPhase.downloading => l10n.appUpdateDownloading(
      formatTraffic(transfer.received, connection: true),
      formatTraffic(transfer.total, connection: true),
    ),
    AppUpdateTransferPhase.installing =>
      updateInfo.package?.kind == AppUpdatePackageKind.androidApk
          ? l10n.appUpdateWaitingAndroid
          : l10n.appUpdateWaitingWindows,
    AppUpdateTransferPhase.failed => updateFailureMessage(l10n, transfer.error),
  };
}

class _UpdateStatus extends StatelessWidget {
  final AppUpdateTransfer transfer;
  final String text;

  const _UpdateStatus({required this.transfer, required this.text});

  @override
  Widget build(BuildContext context) {
    final downloading = transfer.phase == AppUpdateTransferPhase.downloading;
    final failed = transfer.phase == AppUpdateTransferPhase.failed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            text,
            style: failed
                ? AppTypography.updateNotes.copyWith(
                    color: ColorManager.palette(context).destructive,
                  )
                : AppTypography.updateNotes,
          ),
          if (downloading ||
              transfer.phase == AppUpdateTransferPhase.installing) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: downloading && transfer.total > 0
                    ? transfer.received / transfer.total
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VersionGrid extends StatelessWidget {
  final AppUpdateInfo updateInfo;

  const _VersionGrid({required this.updateInfo});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _row(context, l10n.appUpdateCurrentVersion, updateInfo.currentVersion),
        const SizedBox(height: 10),
        _row(context, l10n.appUpdateLatestVersion, updateInfo.latestVersion),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String version) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.updateVersionLabel)),
        Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: ColorManager.palette(context).surfaceHover,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(version, style: AppTypography.updateVersion),
        ),
      ],
    );
  }
}

class _UpdateActions extends StatelessWidget {
  final AppUpdateInfo updateInfo;
  final AppUpdateTransfer transfer;
  final AppUpdateDialogAction? action;
  final VoidCallback onLater;
  final VoidCallback onSkip;
  final VoidCallback onUpdate;
  final VoidCallback? onCancelDownload;

  const _UpdateActions({
    required this.updateInfo,
    required this.transfer,
    required this.action,
    required this.onLater,
    required this.onSkip,
    required this.onUpdate,
    required this.onCancelDownload,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final package = updateInfo.package;
    final phase = transfer.phase;
    final skipping = action == AppUpdateDialogAction.skip;
    final later = ShadButton.outline(
      height: 40,
      onPressed: onLater,
      child: Text(l10n.appUpdateLater),
    );
    final actions = switch (phase) {
      AppUpdateTransferPhase.downloading => [
        later,
        ShadButton.outline(
          height: 40,
          onPressed: onCancelDownload,
          child: Text(l10n.buttonCancel),
        ),
      ],
      AppUpdateTransferPhase.installing => [
        later,
        ShadButton(
          enabled: false,
          child: ButtonProgress(
            busy: true,
            child: Text(_installLabel(l10n, package)),
          ),
        ),
      ],
      AppUpdateTransferPhase.ready => [
        later,
        ShadButton(
          onPressed: onUpdate,
          child: Text(_installLabel(l10n, package)),
        ),
      ],
      AppUpdateTransferPhase.idle || AppUpdateTransferPhase.failed => [
        later,
        ShadButton.outline(
          height: 40,
          enabled: !skipping,
          onPressed: skipping ? null : onSkip,
          child: ButtonProgress(
            busy: skipping,
            child: Text(l10n.appUpdateSkipVersion),
          ),
        ),
        ShadButton(
          onPressed: onUpdate,
          child: Text(
            package == null
                ? l10n.appUpdateOpen
                : phase == AppUpdateTransferPhase.failed
                ? l10n.buttonRetry
                : l10n.appUpdateInstall,
          ),
        ),
      ],
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      color: ColorManager.palette(context).muted,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 460) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < actions.length; index++) ...[
                  if (index > 0) const SizedBox(height: 8),
                  actions[index],
                ],
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                actions[index],
              ],
            ],
          );
        },
      ),
    );
  }

  static String _installLabel(AppLocalizations l10n, AppUpdatePackage? p) =>
      p?.kind == AppUpdatePackageKind.androidApk
      ? l10n.appUpdateInstallNow
      : l10n.appUpdateInstallRestart;
}
