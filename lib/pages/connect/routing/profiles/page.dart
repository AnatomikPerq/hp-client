import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/profiles/controller.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/connect/routing/profiles/catalog.dart';
import 'package:onexray/service/connect/routing/profiles/profile.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSwitch;

/// Fork: the profiles chosen on top of the routing mode.
class TrafficProfilesPage extends StatefulWidget {
  final OpenTrafficProfile openProfile;
  const TrafficProfilesPage({super.key, required this.openProfile});

  @override
  State<TrafficProfilesPage> createState() => _TrafficProfilesPageState();
}

class _TrafficProfilesPageState extends State<TrafficProfilesPage> {
  final controller = TrafficProfilesController();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      controller.load(context);
    }
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  static IconData _icon(String id) => switch (id) {
    TrafficProfiles.ruBlocked => LucideIcons.shieldBan,
    TrafficProfiles.ai => LucideIcons.sparkles,
    TrafficProfiles.discord => LucideIcons.headphones,
    TrafficProfiles.youtube => LucideIcons.tvMinimalPlay,
    TrafficProfiles.messengers => LucideIcons.messagesSquare,
    TrafficProfiles.games => LucideIcons.gamepad2,
    TrafficProfiles.torrents => LucideIcons.arrowDownUp,
    _ => LucideIcons.slidersHorizontal,
  };

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<TrafficProfilesController, TrafficProfilesState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        return Scaffold(
          appBar: PageAppBar(
            title: Text(l.trafficProfiles),
            leading: BackButton(onPressed: () => controller.cancel(context)),
          ),
          body: SafeArea(
            child: state.original == null
                ? Center(
                    child: state.busy
                        ? const CircularProgressIndicator()
                        : TextButton(
                            onPressed: () => controller.load(context),
                            child: Text(l.prototypeRetry),
                          ),
                  )
                : SettingsPageScroll(
                    desktopMaxWidth: AppLayout.routingMaxWidth,
                    padding: EdgeInsetsDirectional.fromSTEB(
                      mobile ? AppSpacing.mobilePage : AppSpacing.page,
                      mobile ? 12 : AppSpacing.desktopPageTop,
                      mobile ? AppSpacing.mobilePage : AppSpacing.page,
                      mobile ? 18 : AppSpacing.desktopPageBottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: mobile ? 12 : 16,
                      children: [
                        _builtIn(context, state),
                        _custom(context, state),
                      ],
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              PageActionBar(
                children: [
                  if (!mobile)
                    OutlinedButton(
                      onPressed: () => controller.cancel(context),
                      child: Text(l.prototypeCancel),
                    ),
                  FilledButton(
                    onPressed: controller.editable
                        ? () => controller.save(context)
                        : null,
                    child: ButtonProgress(
                      busy: state.busy && state.original != null,
                      child: Text(l.prototypeSave),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _builtIn(BuildContext context, TrafficProfilesState state) {
    final l = AppLocalizations.of(context)!;
    final profiles = TrafficProfiles.builtIn;
    return RoutingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoutingCardHeader(
            title: l.trafficProfiles,
            description: controller.headerHint(l),
            help: [l.trafficProfilesPriorityHint, l.trafficProfilesProcessHint],
          ),
          for (final (index, profile) in profiles.indexed)
            _row(
              context,
              state,
              profile,
              title: TrafficProfilesController.builtInName(l, profile.id),
              description: TrafficProfilesController.builtInDescription(
                l,
                profile.id,
              ),
              divider: index < profiles.length - 1,
              below: profile.id == TrafficProfiles.ruBlocked
                  ? _ruBlocked(context, state)
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _ruBlocked(BuildContext context, TrafficProfilesState state) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final status = controller.ruBlockedStatus(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 4,
      children: [
        if (status != null)
          Text(
            status,
            style: AppTypography.routingRowDescription.copyWith(
              color: palette.mutedForeground,
            ),
          ),
        TextButton.icon(
          onPressed: state.updatingList
              ? null
              : () => controller.updateList(context),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: AppTypography.actionHelp,
          ),
          icon: state.updatingList
              ? const ButtonProgressIndicator(size: 14)
              : const Icon(LucideIcons.refreshCw, size: 15),
          label: Text(l.trafficProfileRuBlockedUpdate),
        ),
      ],
    );
  }

  Widget _custom(BuildContext context, TrafficProfilesState state) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final custom = state.draft.custom;
    return RoutingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoutingCardHeader(
            title: l.trafficProfilesCustom,
            description: l.trafficProfileLimit,
          ),
          for (final profile in custom)
            _row(
              context,
              state,
              profile,
              title: profile.name,
              description: TrafficProfilesController.customSummary(profile),
              onTap: () =>
                  controller.edit(context, widget.openProfile, profile),
            ),
          if (custom.length < TrafficProfileSettings.maxCustom)
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: controller.editable
                    ? () => controller.edit(context, widget.openProfile)
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.primary,
                  minimumSize: const Size.fromHeight(42),
                  side: BorderSide(color: palette.borderStrong),
                ),
                icon: const Icon(LucideIcons.plus, size: 17),
                label: Text(l.trafficProfileAdd),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    TrafficProfilesState state,
    TrafficProfile profile, {
    required String title,
    required String description,
    bool divider = true,
    Widget? below,
    VoidCallback? onTap,
  }) => RoutingSettingRow(
    icon: _icon(profile.id),
    title: title,
    description: description,
    enabled: controller.editable,
    divider: divider,
    below: below,
    onTap: onTap,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        TrafficProfileDirectionBadge(action: profile.action),
        Semantics(
          label: title,
          child: ShadSwitch(
            value: state.draft.isEnabled(profile.id),
            enabled: controller.editable,
            onChanged: (value) => controller.toggle(profile.id, value),
          ),
        ),
      ],
    ),
  );
}
