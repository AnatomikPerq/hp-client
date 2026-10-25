import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/connect/routing/profiles/catalog.dart';
import 'package:onexray/service/connect/routing/profiles/editor.dart';
import 'package:onexray/service/connect/routing/profiles/profile.dart';
import 'package:onexray/service/connect/routing/profiles/ru_blocked.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/failure.dart';

/// The custom profile editor returns the edited profile, or a null profile
/// to delete it; a null result is a cancel.
typedef TrafficProfileEditResult = ({TrafficProfile? profile});
typedef OpenTrafficProfile = Future<TrafficProfileEditResult?> Function(
  BuildContext context,
  TrafficProfile profile,
);

const _unchanged = Object();

class TrafficProfilesState {
  final TrafficProfilesDraft? original;
  final TrafficProfileSettings draft;
  final RuBlockedStatus? ruBlocked;
  final bool updatingList;
  final String? error;
  final bool busy;

  const TrafficProfilesState({
    this.original,
    this.draft = const TrafficProfileSettings(),
    this.ruBlocked,
    this.updatingList = false,
    this.error,
    this.busy = true,
  });

  TrafficProfilesState copyWith({
    TrafficProfilesDraft? original,
    TrafficProfileSettings? draft,
    Object? ruBlocked = _unchanged,
    bool? updatingList,
    Object? error = _unchanged,
    bool? busy,
  }) => TrafficProfilesState(
    original: original ?? this.original,
    draft: draft ?? this.draft,
    ruBlocked: identical(ruBlocked, _unchanged)
        ? this.ruBlocked
        : ruBlocked as RuBlockedStatus?,
    updatingList: updatingList ?? this.updatingList,
    error: identical(error, _unchanged) ? this.error : error as String?,
    busy: busy ?? this.busy,
  );
}

class TrafficProfilesController extends PageCubit<TrafficProfilesState> {
  final TrafficProfilesEditorService service;

  TrafficProfilesController({TrafficProfilesEditorService? service})
    : service = service ?? TrafficProfilesEditorService(),
      super(const TrafficProfilesState());

  Future<void> load(BuildContext context) async {
    emit(state.copyWith(busy: true, error: null));
    try {
      final value = await service.load();
      if (!isPageActive) return;
      emit(
        TrafficProfilesState(
          original: value,
          draft: value.configuration.connection.profiles,
          ruBlocked: value.ruBlocked,
          busy: false,
        ),
      );
    } catch (_) {
      if (context.mounted) {
        emit(
          state.copyWith(
            error: AppLocalizations.of(context)!
                .prototypeTemporarilyUnavailable,
          ),
        );
      }
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  bool get editable => state.original != null && !state.busy;

  void toggle(String id, bool on) {
    if (!editable) return;
    emit(state.copyWith(draft: state.draft.toggle(id, on), error: null));
  }

  /// Opens [profile], or a new one, and applies the result to the draft.
  Future<void> edit(
    BuildContext context,
    OpenTrafficProfile open, [
    TrafficProfile? profile,
  ]) async {
    if (!editable) return;
    final creating = profile == null;
    if (creating &&
        state.draft.custom.length >= TrafficProfileSettings.maxCustom) {
      return;
    }
    final result = await open(
      context,
      profile ??
          TrafficProfile(
            id: state.draft.nextCustomId(),
            action: TrafficProfileAction.proxy,
          ),
    );
    if (!isPageActive || result == null) return;
    final edited = result.profile;
    if (edited == null) {
      if (!creating) {
        emit(state.copyWith(draft: state.draft.withoutCustom(profile.id)));
      }
      return;
    }
    var draft = state.draft.withCustom(edited);
    if (creating) draft = draft.toggle(edited.id, true);
    emit(state.copyWith(draft: draft, error: null));
  }

  Future<void> updateList(BuildContext context) async {
    if (state.updatingList) return;
    final l = AppLocalizations.of(context)!;
    emit(state.copyWith(updatingList: true));
    try {
      final result = await service.updateRuBlocked();
      final status = await service.status();
      if (!isPageActive) return;
      emit(state.copyWith(ruBlocked: status));
      if (context.mounted) {
        ContextAlert.showToast(
          context,
          result == RuBlockedUpdate.updated
              ? l.trafficProfileRuBlockedUpdated
              : l.trafficProfileRuBlockedUnchanged,
        );
      }
    } catch (_) {
      if (context.mounted) {
        ContextAlert.showToast(context, l.trafficProfileRuBlockedUpdateFailed);
      }
    } finally {
      emit(state.copyWith(updatingList: false));
    }
  }

  String modeName(AppLocalizations l) =>
      switch (state.original?.configuration.connection.trafficMode) {
        TrafficMode.allVpn => l.prototypeAllViaVpn,
        TrafficMode.custom => l.prototypeCustomRouting,
        TrafficMode.selective => l.trafficSelective,
        _ => l.prototypeSmartRouting,
      };

  String headerHint(AppLocalizations l) {
    final original = state.original;
    if (original == null) return '';
    if (original.scope != TrafficProfilesScope.applied) {
      return l.trafficProfilesNotApplied;
    }
    return original.configuration.connection.trafficMode ==
            TrafficMode.selective
        ? l.trafficProfilesSelectiveHint
        : l.trafficProfilesOverlayHint(modeName(l));
  }

  String? ruBlockedStatus(BuildContext context) {
    final status = state.ruBlocked;
    if (status == null) return null;
    final l = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final number = NumberFormat.decimalPattern(locale);
    return l.trafficProfileRuBlockedStatus(
      number.format(status.domainCount),
      number.format(status.ipCount),
      status.bundled
          ? l.trafficProfileRuBlockedBundled
          : DateFormat.yMMMd(locale).format(status.fetchedAt.toLocal()),
    );
  }

  static String builtInName(AppLocalizations l, String id) => switch (id) {
    TrafficProfiles.ruBlocked => l.trafficProfileRuBlocked,
    TrafficProfiles.ai => l.trafficProfileAi,
    TrafficProfiles.discord => l.trafficProfileDiscord,
    TrafficProfiles.youtube => l.trafficProfileYoutube,
    TrafficProfiles.messengers => l.trafficProfileMessengers,
    TrafficProfiles.games => l.trafficProfileGames,
    TrafficProfiles.torrents => l.trafficProfileTorrents,
    _ => id,
  };

  static String builtInDescription(AppLocalizations l, String id) =>
      switch (id) {
        TrafficProfiles.ruBlocked => l.trafficProfileRuBlockedDescription,
        TrafficProfiles.ai => l.trafficProfileAiDescription,
        TrafficProfiles.discord => l.trafficProfileDiscordDescription,
        TrafficProfiles.youtube => l.trafficProfileYoutubeDescription,
        TrafficProfiles.messengers => l.trafficProfileMessengersDescription,
        TrafficProfiles.games => l.trafficProfileGamesDescription,
        TrafficProfiles.torrents => l.trafficProfileTorrentsDescription,
        _ => '',
      };

  /// What a custom profile holds, shortest first.
  static String customSummary(TrafficProfile profile) {
    String plain(String value) =>
        value.startsWith('domain:') ? value.substring(7) : value;
    final values = [
      ...profile.domains.map(plain),
      ...profile.ips,
      ...profile.processes,
      ...profile.apps,
    ];
    if (values.length <= 3) return values.join(', ');
    return '${values.take(3).join(', ')} +${values.length - 3}';
  }

  Future<void> save(BuildContext context) async {
    if (!editable) return;
    final l = AppLocalizations.of(context)!;
    emit(state.copyWith(busy: true, error: null));
    try {
      final result = await service.save(
        original: state.original!.configuration,
        profiles: state.draft,
        confirmReconnect: () => context.mounted
            ? showApplyAndReconnectDialog(context, label: l.trafficProfiles)
            : Future.value(false),
      );
      if (result == null || !context.mounted) return;
      ContextAlert.showToast(
        context,
        result
            ? l.trafficProfileRuBlockedUpdateFailed
            : l.prototypeSettingsSaved,
      );
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      emit(
        state.copyWith(
          error: appFailureMessage(l, error, operation: l.buttonSaveFailed),
        ),
      );
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  void cancel(BuildContext context) => Navigator.of(context).pop();
}
