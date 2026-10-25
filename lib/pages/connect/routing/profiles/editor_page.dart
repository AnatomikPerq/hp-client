import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/profiles/controller.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/connect/routing/profiles/editor.dart';
import 'package:onexray/service/connect/routing/profiles/profile.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadInput;

const _unchanged = Object();

class TrafficProfileEditorState {
  final TrafficProfileAction action;
  final String? error;

  const TrafficProfileEditorState({required this.action, this.error});

  TrafficProfileEditorState copyWith({
    TrafficProfileAction? action,
    Object? error = _unchanged,
  }) => TrafficProfileEditorState(
    action: action ?? this.action,
    error: identical(error, _unchanged) ? this.error : error as String?,
  );
}

class TrafficProfileEditorController
    extends PageCubit<TrafficProfileEditorState> {
  final TrafficProfile original;

  TrafficProfileEditorController(this.original)
    : super(TrafficProfileEditorState(action: original.action));

  void setAction(TrafficProfileAction action) =>
      emit(state.copyWith(action: action, error: null));

  /// Null with an error shown when the form cannot become a profile.
  TrafficProfile? build(
    AppLocalizations l, {
    required String name,
    required String sites,
    required String addresses,
    required String programs,
    required List<String> apps,
  }) {
    final profile = original.copyWith(
      name: name.trim(),
      action: state.action,
      domains: TrafficProfile.lines(sites, TrafficProfile.normalizeDomain),
      ips: TrafficProfile.lines(addresses, (value) => value.trim()),
      processes: TrafficProfile.lines(
        programs,
        TrafficProfile.normalizeProcess,
      ),
      apps: apps,
    );
    final trimmed = profile.name;
    if (trimmed.isEmpty || trimmed.length > TrafficProfile.maxNameLength) {
      emit(state.copyWith(error: l.trafficProfileNameError));
      return null;
    }
    if (profile.isEmpty) {
      emit(state.copyWith(error: l.trafficProfileEmptyError));
      return null;
    }
    try {
      profile.validate();
    } on FormatException catch (error) {
      emit(state.copyWith(error: error.message));
      return null;
    }
    return profile;
  }
}

/// Fork: one custom traffic profile. Returns the edited profile to the
/// profiles page draft; nothing is saved until that page is saved.
///
/// [openApps] (Android) picks the profile's apps in place of programs.
class TrafficProfileEditorPage extends StatefulWidget {
  final TrafficProfile profile;
  final Future<List<String>?> Function(
    BuildContext context,
    List<String> selected,
  )?
  openApps;
  const TrafficProfileEditorPage({
    super.key,
    required this.profile,
    this.openApps,
  });

  @override
  State<TrafficProfileEditorPage> createState() =>
      _TrafficProfileEditorPageState();
}

class _TrafficProfileEditorPageState extends State<TrafficProfileEditorPage> {
  late final controller = TrafficProfileEditorController(widget.profile);
  late final name = TextEditingController(text: widget.profile.name);
  late final sites = TextEditingController(
    text: [
      for (final value in widget.profile.domains)
        value.startsWith('domain:') ? value.substring(7) : value,
    ].join('\n'),
  );
  late final addresses = TextEditingController(
    text: widget.profile.ips.join('\n'),
  );
  late final programs = TextEditingController(
    text: widget.profile.processes.join('\n'),
  );
  late List<String> apps = widget.profile.apps;
  Map<String, String> appNames = const {};

  bool get _existing => widget.profile.name.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.openApps != null && apps.isNotEmpty) unawaited(_loadAppNames());
  }

  /// Labels of the chosen apps; the picker already asked for the right to
  /// list them, so this shows no prompt for a profile with apps.
  Future<void> _loadAppNames() async {
    try {
      final installed = await AppHostApi().getInstalledApps();
      if (!mounted) return;
      setState(() {
        appNames = {for (final app in installed) app.packageName: app.name};
      });
    } catch (_) {
      // Package names stay as they are.
    }
  }

  Future<void> _pickApps() async {
    FocusScope.of(context).unfocus();
    final picked = await widget.openApps!(context, apps);
    if (!mounted) return;
    // The route gives focus back to the field last edited, which brings the
    // keyboard up over the list on the way back.
    FocusScope.of(context).unfocus();
    if (picked == null) return;
    setState(() => apps = List.unmodifiable(picked..sort()));
    unawaited(_loadAppNames());
  }

  @override
  void dispose() {
    name.dispose();
    sites.dispose();
    addresses.dispose();
    programs.dispose();
    unawaited(controller.close());
    super.dispose();
  }

  void _save() {
    final profile = controller.build(
      AppLocalizations.of(context)!,
      name: name.text,
      sites: sites.text,
      addresses: addresses.text,
      programs: programs.text,
      apps: apps,
    );
    if (profile != null) {
      Navigator.of(context).pop<TrafficProfileEditResult>((profile: profile));
    }
  }

  Future<void> _pickProgram() async {
    final file = await TrafficProfilesEditorService.pickProgram();
    if (file == null || !mounted) return;
    final current = programs.text.trimRight();
    programs.text = current.isEmpty ? file : '$current\n$file';
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child:
        BlocBuilder<TrafficProfileEditorController, TrafficProfileEditorState>(
          builder: (context, state) {
            final l = AppLocalizations.of(context)!;
            final palette = ColorManager.palette(context);
            final mobile =
                MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
            final desktop = Platform.isWindows || Platform.isLinux;
            final android = widget.openApps != null;
            return Scaffold(
              appBar: PageAppBar(
                title: Text(
                  _existing ? widget.profile.name : l.trafficProfileNew,
                ),
                leading: BackButton(
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              body: SafeArea(
                child: SettingsPageScroll(
                  desktopMaxWidth: AppLayout.routingMaxWidth,
                  padding: EdgeInsetsDirectional.fromSTEB(
                    mobile ? AppSpacing.mobilePage : AppSpacing.page,
                    mobile ? 12 : AppSpacing.desktopPageTop,
                    mobile ? AppSpacing.mobilePage : AppSpacing.page,
                    mobile ? 18 : AppSpacing.desktopPageBottom,
                  ),
                  child: RoutingCard(
                    padding: EdgeInsets.all(mobile ? 12 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 7,
                      children: [
                        _label(context, l.trafficProfileName),
                        _input(context, name, l.trafficProfileName),
                        const SizedBox(height: 9),
                        _label(context, l.trafficProfileDirection),
                        _direction(context, state),
                        const SizedBox(height: 9),
                        _label(context, l.trafficProfileSites),
                        _input(
                          context,
                          sites,
                          l.trafficProfileSitesHint,
                          lines: 6,
                        ),
                        const SizedBox(height: 9),
                        _label(context, l.trafficProfileAddresses),
                        _input(
                          context,
                          addresses,
                          l.trafficProfileAddressesHint,
                          lines: 4,
                        ),
                        const SizedBox(height: 9),
                        if (android) ...[
                          _label(context, l.trafficProfileApps),
                          _apps(context),
                        ] else ...[
                          _label(context, l.trafficProfilePrograms),
                          _input(
                            context,
                            programs,
                            l.trafficProfileProgramsHint,
                            lines: 4,
                          ),
                        ],
                        if (desktop)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: _pickProgram,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 30),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: AppTypography.actionHelp,
                              ),
                              icon: const Icon(
                                LucideIcons.folderOpen,
                                size: 15,
                              ),
                              label: Text(l.trafficProfilePickProgram),
                            ),
                          ),
                        Text(
                          l.trafficProfilesProcessHint,
                          style: AppTypography.actionHelp.copyWith(
                            color: palette.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              bottomNavigationBar: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.error case final error?)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    ),
                  PageActionBar(
                    children: [
                      if (_existing)
                        OutlinedButton(
                          onPressed: () => Navigator.of(context)
                              .pop<TrafficProfileEditResult>((profile: null)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: palette.destructive,
                          ),
                          child: Text(l.trafficProfileDelete),
                        ),
                      if (!mobile)
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l.prototypeCancel),
                        ),
                      FilledButton(
                        onPressed: _save,
                        child: Text(l.prototypeDone),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
  );

  Widget _apps(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final names = [for (final app in apps) appNames[app] ?? app]..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Text(
          names.isEmpty ? l.trafficProfileAppsNone : names.join(', '),
          style: AppTypography.routingInput.copyWith(
            color: names.isEmpty ? palette.mutedForeground : palette.foreground,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _pickApps,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: AppTypography.actionHelp,
            ),
            icon: const Icon(LucideIcons.layoutGrid, size: 15),
            label: Text(l.trafficProfilePickApps),
          ),
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: AppTypography.routeIdentityLabel.copyWith(
      color: ColorManager.palette(context).mutedStrong,
    ),
  );

  Widget _input(
    BuildContext context,
    TextEditingController controller,
    String hint, {
    int lines = 1,
  }) => ShadInput(
    controller: controller,
    minLines: lines,
    maxLines: lines == 1 ? 1 : null,
    constraints: const BoxConstraints(minHeight: 40),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    style: AppTypography.routingInput,
    placeholder: Text(hint),
    placeholderStyle: AppTypography.routingInput.copyWith(
      color: ColorManager.palette(context).mutedForeground,
    ),
    keyboardType: lines == 1 ? TextInputType.text : TextInputType.multiline,
    autocorrect: false,
    enableSuggestions: false,
  );

  Widget _direction(BuildContext context, TrafficProfileEditorState state) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final actions = {
      TrafficProfileAction.proxy: l.trafficProfileViaVpn,
      TrafficProfileAction.direct: l.trafficProfileDirect,
    };
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (final (index, action) in actions.entries.indexed) ...[
              if (index > 0) const VerticalDivider(width: 1),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: state.action == action.key,
                  child: InkWell(
                    onTap: () => controller.setAction(action.key),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 38),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: state.action == action.key
                            ? palette.selectedSurface
                            : palette.muted,
                        border: state.action == action.key
                            ? Border.all(color: palette.primary)
                            : null,
                      ),
                      child: Text(
                        action.value,
                        textAlign: TextAlign.center,
                        style:
                            (state.action == action.key
                                    ? AppTypography.selectedActionOption
                                    : AppTypography.actionOption)
                                .copyWith(
                                  color: state.action == action.key
                                      ? palette.primary
                                      : palette.foreground,
                                ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
