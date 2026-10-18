import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/policy_editor.dart';

class LanProxyController extends PolicyEditorController {
  LanProxyController({
    super.draft,
    PolicyEditorService? service,
    Future<void> Function(String text)? copy,
  }) : _copy = copy ?? ((text) => Clipboard.setData(ClipboardData(text: text))),
       super(
         service: service ?? PolicyEditorService(validateInterface: false),
       ) {
    if (draft != null) _readDraft();
  }

  final Future<void> Function(String text) _copy;
  final portController = TextEditingController();

  String get user => group('lanProxy')['user'] as String;
  String get password => group('lanProxy')['password'] as String;

  void _readDraft() {
    portController.text = '${group('lanProxy')['port']}';
  }

  @override
  Future<void> load(BuildContext context) async {
    await super.load(context);
    if (isPageActive && draft != null) _readDraft();
  }

  Future<void> copy(BuildContext context, String text) async {
    if (text.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    try {
      await _copy(text);
      if (context.mounted) ContextAlert.showToast(context, l.lanProxyCopied);
    } catch (_) {
      if (isPageActive) emit(state.copyWith(error: l.prototypeCopyFailed));
    }
  }

  @override
  String saveLabel(AppLocalizations l) => l.prototypeSave;

  @override
  Future<bool> save(BuildContext context, {bool pop = true}) {
    if (blocked || runtimeBusy || draft == null) return Future.value(false);
    final port = int.tryParse(portController.text.trim());
    if (port == null || port < 1024 || port > 65535) {
      emit(
        state.copyWith(
          error: AppLocalizations.of(context)!.localApiPortInvalid,
        ),
      );
      return Future.value(false);
    }
    update('port', port, section: 'lanProxy');
    // Turning sharing on makes the account; a policy saved here first gets
    // it now, so sharing never starts without one.
    if (password.isEmpty) {
      update('user', PlatformPolicy.defaultLanProxyUser, section: 'lanProxy');
      update(
        'password',
        PlatformPolicy.generateLanProxyPassword(),
        section: 'lanProxy',
      );
    }
    return super.save(context, pop: pop);
  }

  @override
  void disposePageResources() {
    portController.dispose();
    super.disposePageResources();
  }
}
