import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/diagnostics/settings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class NetworkReportSettingsState {
  final bool loaded;
  final NetworkReportSettings settings;

  const NetworkReportSettingsState({
    this.loaded = false,
    this.settings = const NetworkReportSettings(),
  });
}

/// Every change is saved at once: these settings never touch a connection.
class NetworkReportSettingsController
    extends PageCubit<NetworkReportSettingsState> {
  NetworkReportSettingsController({
    Future<NetworkReportSettings> Function()? read,
    Future<void> Function(NetworkReportSettings)? save,
  }) : _read = read ?? NetworkReportSettings.read,
       _save = save ?? ((settings) => settings.save()),
       super(const NetworkReportSettingsState()) {
    _load();
  }

  final Future<NetworkReportSettings> Function() _read;
  final Future<void> Function(NetworkReportSettings) _save;
  final sitesController = TextEditingController();

  Future<void> _load() async {
    final settings = await _read();
    if (!isPageActive) return;
    sitesController.text = settings.extraSites.join('\n');
    emit(NetworkReportSettingsState(loaded: true, settings: settings));
  }

  Future<void> update(NetworkReportSettings settings) async {
    emit(NetworkReportSettingsState(loaded: true, settings: settings));
    await _save(settings);
  }

  Future<void> saveSites() {
    final sites = NetworkReportSettings.normalizeSites([sitesController.text]);
    return update(state.settings.copyWith(extraSites: sites));
  }

  @override
  Future<void> disposePageResources() async {
    if (state.loaded) {
      final sites = NetworkReportSettings.normalizeSites([
        sitesController.text,
      ]);
      if (sites.join('\n') != state.settings.extraSites.join('\n')) {
        await _save(state.settings.copyWith(extraSites: sites));
      }
    }
    sitesController.dispose();
  }
}

class NetworkReportSettingsPage extends StatelessWidget {
  const NetworkReportSettingsPage({super.key, this.createController});

  final NetworkReportSettingsController Function()? createController;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        createController?.call() ?? NetworkReportSettingsController(),
    child:
        BlocBuilder<
          NetworkReportSettingsController,
          NetworkReportSettingsState
        >(
          builder: (context, state) {
            final l = AppLocalizations.of(context)!;
            final controller = context.read<NetworkReportSettingsController>();
            final palette = ColorManager.palette(context);
            final width = MediaQuery.sizeOf(context).width;
            final mobile = width <= AppLayout.mobileBreakpoint;
            final gutter = mobile
                ? 12.0
                : AppSpacing.advancedDesktopGutter(width);
            final value = state.settings;
            const rowPadding = EdgeInsetsDirectional.symmetric(
              horizontal: 14,
              vertical: 10,
            );
            Widget select<T extends Object>(
              String title,
              T selected,
              Map<T, String> entries,
              NetworkReportSettings Function(T) apply,
            ) => SettingRow(
              title: title,
              titleStyle: AppTypography.settingsRow,
              contentPadding: rowPadding,
              trailing: SettingSelect<T>(
                value: selected,
                entries: entries,
                onChanged: (option) {
                  if (option != null) controller.update(apply(option));
                },
              ),
            );
            Widget toggle(
              String title,
              bool selected,
              NetworkReportSettings Function(bool) apply, {
              String? subtitle,
            }) => SwitchSettingRow(
              title: title,
              subtitle: subtitle,
              value: selected,
              onChanged: (next) => controller.update(apply(next)),
            );
            return Scaffold(
              appBar: PageAppBar(title: Text(l.netReportSettingsTitle)),
              body: SafeArea(
                child: !state.loaded
                    ? const Center(child: CircularProgressIndicator())
                    : SettingsPageScroll(
                        desktopMaxWidth: AppLayout.advancedMaxWidth,
                        padding: EdgeInsets.zero,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            gutter,
                            mobile ? 12 : 40,
                            gutter,
                            mobile ? 24 : 32,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l.netReportSettingsPrivacy,
                                style: AppTypography.settingsNote.copyWith(
                                  color: palette.mutedForeground,
                                ),
                              ),
                              const SizedBox(height: 18),
                              SettingSection(
                                title: l.netReportSettingsContent,
                                icon: LucideIcons.fileText,
                                padding: EdgeInsets.zero,
                                children: [
                                  select<ReportAddressMode>(
                                    l.netReportSettingsAddress,
                                    value.address,
                                    {
                                      ReportAddressMode.hidden:
                                          l.netReportHidden,
                                      ReportAddressMode.network:
                                          l.netReportAddressNetwork,
                                      ReportAddressMode.full:
                                          l.netReportAddressFull,
                                    },
                                    (option) => value.copyWith(address: option),
                                  ),
                                  toggle(
                                    l.netReportSettingsProvider,
                                    value.provider,
                                    (next) => value.copyWith(provider: next),
                                  ),
                                  select<ReportLocationMode>(
                                    l.netReportSettingsLocation,
                                    value.location,
                                    {
                                      ReportLocationMode.hidden:
                                          l.netReportHidden,
                                      ReportLocationMode.country:
                                          l.netReportLocationCountry,
                                      ReportLocationMode.city:
                                          l.netReportLocationCity,
                                    },
                                    (option) =>
                                        value.copyWith(location: option),
                                  ),
                                  toggle(
                                    l.netReportSettingsConnection,
                                    value.connectionType,
                                    (next) =>
                                        value.copyWith(connectionType: next),
                                  ),
                                  toggle(
                                    l.netReportSettingsAdapter,
                                    value.adapter,
                                    (next) => value.copyWith(adapter: next),
                                  ),
                                  toggle(
                                    l.netReportSettingsDns,
                                    value.dnsServers,
                                    (next) => value.copyWith(dnsServers: next),
                                  ),
                                  toggle(
                                    l.netReportSettingsDevice,
                                    value.device,
                                    (next) => value.copyWith(device: next),
                                  ),
                                ],
                              ),
                              SizedBox(height: mobile ? 25 : 28),
                              SettingSection(
                                title: l.netReportSettingsChecks,
                                icon: LucideIcons.listChecks,
                                padding: EdgeInsets.zero,
                                children: [
                                  toggle(
                                    l.netReportSectionDns,
                                    value.checkDns,
                                    (next) => value.copyWith(checkDns: next),
                                  ),
                                  toggle(
                                    l.netReportSectionSites,
                                    value.checkSites,
                                    (next) => value.copyWith(checkSites: next),
                                  ),
                                  toggle(
                                    l.netReportSectionHosting,
                                    value.checkHosting,
                                    (next) =>
                                        value.copyWith(checkHosting: next),
                                  ),
                                  toggle(
                                    l.netReportSectionUdp,
                                    value.checkUdp,
                                    (next) => value.copyWith(checkUdp: next),
                                  ),
                                  toggle(
                                    l.netReportSettingsBypass,
                                    value.bypass,
                                    (next) => value.copyWith(bypass: next),
                                    subtitle: l.netReportSettingsBypassHint,
                                  ),
                                  toggle(
                                    l.netReportSettingsSaveTraffic,
                                    value.saveTraffic,
                                    (next) => value.copyWith(saveTraffic: next),
                                    subtitle:
                                        l.netReportSettingsSaveTrafficHint,
                                  ),
                                ],
                              ),
                              SizedBox(height: mobile ? 25 : 28),
                              SettingSection(
                                title: l.netReportSettingsSites,
                                icon: LucideIcons.globe,
                                padding: EdgeInsets.zero,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          l.netReportSettingsSitesHint(
                                            NetworkReportSettings.maxExtraSites,
                                          ),
                                          style: AppTypography.settingsHint
                                              .copyWith(
                                                color: palette.mutedForeground,
                                              ),
                                        ),
                                        const SizedBox(height: 9),
                                        Focus(
                                          onFocusChange: (focused) {
                                            if (!focused) {
                                              controller.saveSites();
                                            }
                                          },
                                          child: TextField(
                                            key: const ValueKey(
                                              'network-report-sites',
                                            ),
                                            controller:
                                                controller.sitesController,
                                            minLines: 3,
                                            maxLines: 8,
                                            textDirection: TextDirection.ltr,
                                            keyboardType: TextInputType.url,
                                            autocorrect: false,
                                            style: AppTypography.settingsInput
                                                .copyWith(
                                                  color: palette.foreground,
                                                ),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              hintText: 'example.org',
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: mobile ? 25 : 28),
                              SettingSection(
                                title: l.netReportSettingsShow,
                                icon: LucideIcons.eye,
                                padding: EdgeInsets.zero,
                                children: [
                                  toggle(
                                    l.netReportSettingsHidePassed,
                                    value.hidePassed,
                                    (next) => value.copyWith(hidePassed: next),
                                  ),
                                  toggle(
                                    l.netReportSettingsDetails,
                                    value.details,
                                    (next) => value.copyWith(details: next),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            );
          },
        ),
  );
}
