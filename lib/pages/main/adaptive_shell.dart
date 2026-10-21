import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:onexray/gen/assets.gen.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/main/desktop_window.dart';
import 'package:onexray/pages/main/menu_actions.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';
import 'package:onexray/service/manager.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/service/shared/menu/short_cut/service.dart';
import 'package:onexray/service/shared/menu/tray/service.dart';
import 'package:onexray/service/shared/share/service.dart';

class AdaptiveMainShell extends StatefulWidget {
  const AdaptiveMainShell({
    super.key,
    required this.navigationShell,
    this.initializeServices,
  });

  final StatefulNavigationShell navigationShell;
  final Future<void> Function(BuildContext context)? initializeServices;

  @override
  State<AdaptiveMainShell> createState() => _AdaptiveMainShellState();
}

class _AdaptiveMainShellState extends State<AdaptiveMainShell> {
  Future<void>? _servicesReady;
  bool _menusAttached = false;
  bool _sidebarCollapsed = false;

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _servicesReady ??= _initializeServices();
    if (_menusAttached) _refreshQuickActions();
  }

  Future<void> _initializeServices() {
    ShareService().onIncomingShare = (text) async {
      if (mounted) {
        await context.pushScoped(AppPageDestination.serversImport, extra: text);
      }
    };
    return (widget.initializeServices ?? ServiceManager.serviceInit)(context);
  }

  void _refreshQuickActions() {
    unawaited(ShortCutService().refresh(AppLocalizations.of(context)!));
  }

  void _attachMenus() {
    if (_menusAttached) return;
    _menusAttached = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      TrayService().onConfigurationChange = (values, label, validate) =>
          applyTrayConfiguration(context, values, label, validate);
      TrayService().onSubscriptionFormatConfirmation = (name) =>
          confirmTraySubscriptionFormat(context, name);
      ShortCutService().attach(
        (action) => handleMobileQuickAction(context, action),
      );
      _refreshQuickActions();
    });
  }

  @override
  void dispose() {
    ShortCutService().detach();
    TrayService().onConfigurationChange = null;
    TrayService().onSubscriptionFormatConfirmation = null;
    super.dispose();
  }

  void _retry() {
    final servicesReady = _initializeServices();
    setState(() {
      _servicesReady = servicesReady;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _servicesReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(
                      appFailureMessage(
                        AppLocalizations.of(context)!,
                        snapshot.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('service-initialization-retry'),
                      onPressed: _retry,
                      child: Text(AppLocalizations.of(context)!.buttonRetry),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        _attachMenus();
        return BlocSelector<AppEventBus, AppEventBusState, AppUpdateInfo?>(
          selector: (state) => state.appUpdateInfo,
          builder: (context, appUpdateInfo) => LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > AppLayout.mobileBreakpoint) {
                return _railScaffold(
                  context,
                  constraints.maxWidth,
                  appUpdateInfo,
                );
              }
              return _bottomNavigationScaffold(context, appUpdateInfo != null);
            },
          ),
        );
      },
    );
  }

  Widget _bottomNavigationScaffold(
    BuildContext context,
    bool appUpdateAvailable,
  ) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar:
          navigationShell
                  .shellRouteContext
                  .match
                  .matches
                  .last
                  .matchedLocation !=
              AppPrimaryDestination
                  .values[navigationShell.currentIndex]
                  .rootPath
          ? null
          : DecoratedBox(
              key: const ValueKey('primary-mobile-navigation'),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: ColorManager.palette(context).border),
                ),
              ),
              child: NavigationBar(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: (index) => context.goPrimary(
                  navigationShell,
                  AppPrimaryDestination.values[index],
                ),
                destinations: [
                  for (final primary in AppPrimaryDestination.values)
                    NavigationDestination(
                      key: ValueKey('primary-navigation-${primary.name}'),
                      icon: _navigationIcon(
                        context,
                        primary,
                        appUpdateAvailable,
                      ),
                      label: _label(context, primary),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _railScaffold(
    BuildContext context,
    double width,
    AppUpdateInfo? appUpdateInfo,
  ) {
    final compact = width <= AppLayout.compactDesktopBreakpoint;
    final collapsed = _sidebarCollapsed;
    final sidebarWidth = collapsed
        ? AppLayout.collapsedSidebarWidth
        : !compact
        ? AppLayout.desktopSidebarWidth
        : AppLayout.compactSidebarWidth;
    final palette = ColorManager.palette(context);
    final nativeSidebar = DesktopWindowFrame.hasNativeSidebar(context);
    final l = AppLocalizations.of(context)!;
    final toggle = IconButton(
      key: const ValueKey('primary-sidebar-toggle'),
      tooltip: collapsed ? l.sidebarExpand : l.sidebarCollapse,
      onPressed: () => setState(() => _sidebarCollapsed = !collapsed),
      style: IconButton.styleFrom(
        foregroundColor: palette.mutedForeground,
        minimumSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(
        collapsed ? LucideIcons.panelLeftOpen : LucideIcons.panelLeftClose,
        size: 18,
      ),
    );
    return Scaffold(
      backgroundColor: nativeSidebar ? Colors.transparent : null,
      body: Row(
        children: [
          Container(
            key: const ValueKey('primary-desktop-navigation'),
            width: sidebarWidth,
            decoration: BoxDecoration(
              color: nativeSidebar ? Colors.transparent : palette.sidebar,
              border: BorderDirectional(
                end: BorderSide(color: palette.sidebarBorder),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: collapsed
                      ? AppSpacing.sidebarCollapsedHorizontal
                      : AppSpacing.sidebarHorizontal,
                  vertical: nativeSidebar
                      ? AppSpacing.macOSSidebarVertical
                      : AppSpacing.sidebarVertical,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: collapsed ? 0 : AppSpacing.sidebarBrandStart / 2,
                        top: AppSpacing.sidebarBrandTop,
                        bottom: nativeSidebar
                            ? AppSpacing.macOSSidebarBrandBottom
                            : AppSpacing.sidebarBrandBottom,
                      ),
                      child: collapsed
                          ? Column(
                              children: [
                                const _BrandMark(),
                                const SizedBox(height: 12),
                                toggle,
                              ],
                            )
                          : Row(
                              children: [
                                const _BrandMark(),
                                const SizedBox(width: 10),
                                // One line at any sidebar width; the name is
                                // longer than the upstream brand.
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(
                                      'HYPER CLIENT',
                                      maxLines: 1,
                                      style: AppTypography.desktopBrand
                                          .copyWith(color: palette.brand),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                toggle,
                              ],
                            ),
                    ),
                    for (final primary in AppPrimaryDestination.values) ...[
                      if (primary.index > 0)
                        const SizedBox(height: AppSpacing.sidebarRowGap),
                      _desktopDestination(
                        context,
                        primary,
                        collapsed: collapsed,
                        updateAvailable: appUpdateInfo != null,
                      ),
                    ],
                    const Spacer(),
                    if (appUpdateInfo != null)
                      _DesktopUpdateReminder(
                        collapsed: collapsed,
                        onTap: () => _showDesktopUpdate(context, appUpdateInfo),
                      ),
                    // Windows and Linux show the version in the caption.
                    if (!DesktopWindowFrame.hasCaption(context)) ...[
                      const SizedBox(height: 10),
                      const _SidebarVersion(),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child:
                nativeSidebar && Directionality.of(context) == TextDirection.ltr
                ? MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: navigationShell,
                  )
                // In RTL the content, not the sidebar, is below the native
                // controls on the physical left. Keep its local top inset.
                : navigationShell,
          ),
        ],
      ),
    );
  }

  Widget _desktopDestination(
    BuildContext context,
    AppPrimaryDestination primary, {
    required bool collapsed,
    required bool updateAvailable,
  }) {
    final palette = ColorManager.palette(context);
    final selected = primary.index == navigationShell.currentIndex;
    final label = _label(context, primary);
    final color = selected ? palette.primary : palette.mutedStrong;
    final icon = Icon(_icon(primary), size: 21, color: color);
    final item = Semantics(
      key: ValueKey('primary-navigation-${primary.name}'),
      label: label,
      selected: selected,
      button: true,
      child: Material(
        color: selected ? palette.selectedSurface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(
            color: selected
                ? Color.lerp(palette.border, palette.primary, .2)!
                : Colors.transparent,
          ),
        ),
        child: InkWell(
          onTap: () => context.goPrimary(navigationShell, primary),
          borderRadius: BorderRadius.circular(AppRadii.card),
          hoverColor: palette.surfaceHover,
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSpacing.sidebarRowHeight,
              ),
              child: collapsed
                  ? Center(
                      child:
                          primary == AppPrimaryDestination.settings &&
                              updateAvailable
                          ? _UpdateBadge(child: icon)
                          : icon,
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          icon,
                          const SizedBox(width: 13),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (selected
                                          ? AppTypography
                                                .selectedNavigationLabel
                                          : AppTypography.navigationLabel)
                                      .copyWith(color: color),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
    return collapsed ? Tooltip(message: label, child: item) : item;
  }

  void _showDesktopUpdate(BuildContext context, AppUpdateInfo updateInfo) {
    context.pushAppUpdateDialog(updateInfo);
  }

  Widget _navigationIcon(
    BuildContext context,
    AppPrimaryDestination primary,
    bool appUpdateAvailable,
  ) {
    final icon = Icon(_icon(primary));
    if (primary != AppPrimaryDestination.settings || !appUpdateAvailable) {
      return icon;
    }
    return _UpdateBadge(child: icon);
  }

  IconData _icon(AppPrimaryDestination primary) {
    return switch (primary) {
      AppPrimaryDestination.connect => LucideIcons.shieldCheck,
      AppPrimaryDestination.servers => LucideIcons.server,
      AppPrimaryDestination.settings => LucideIcons.settings,
    };
  }

  String _label(BuildContext context, AppPrimaryDestination primary) {
    final localizations = AppLocalizations.of(context)!;
    return switch (primary) {
      AppPrimaryDestination.connect => localizations.navHome,
      AppPrimaryDestination.servers => localizations.prototypeServers,
      AppPrimaryDestination.settings => localizations.prototypeSettings,
    };
  }
}

class _DesktopUpdateReminder extends StatelessWidget {
  const _DesktopUpdateReminder({required this.onTap, this.collapsed = false});

  final VoidCallback onTap;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context)!.appUpdateAvailable;
    final palette = ColorManager.palette(context);
    const icon = _UpdateBadge(child: Icon(LucideIcons.download, size: 19));
    return Tooltip(
      message: label,
      child: Material(
        color: palette.sidebarAccent,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: collapsed
                ? const Center(child: icon)
                : Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.controlHorizontal,
                    ),
                    child: Row(
                      children: [
                        icon,
                        const SizedBox(width: AppSpacing.actionGap),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.desktopUpdateLabel.copyWith(
                              color: palette.sidebarAccentForeground,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The app logo, the sidebar's only mark when it is collapsed.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Assets.logo.image(width: 32, height: 32),
    ),
  );
}

class _SidebarVersion extends StatelessWidget {
  const _SidebarVersion();

  static final Future<String> _version = PackageInfo.fromPlatform()
      .then((info) => info.version)
      .catchError((_) => '');

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _version,
    builder: (context, snapshot) {
      final version = snapshot.data ?? '';
      if (version.isEmpty) return const SizedBox.shrink();
      return Text(
        'v$version',
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        textAlign: TextAlign.center,
        style: AppTypography.sidebarVersion.copyWith(
          color: ColorManager.palette(context).mutedForeground,
        ),
      );
    },
  );
}

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Badge(
      smallSize: 8,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: child,
    );
  }
}
