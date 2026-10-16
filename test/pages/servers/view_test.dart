import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/menus.dart';
import 'package:onexray/pages/servers/node_tile.dart';
import 'package:onexray/pages/servers/subscription/user_info.dart';
import 'package:onexray/pages/servers/view.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/shared/widgets/page_empty_state.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/settings/backup/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadTheme, ShadToaster, ShadToast;

class _Controller extends ServersController {
  _Controller({
    required super.database,
    required super.coordinator,
    super.ping,
  });

  bool? browsedOnMobile;
  bool helpOpened = false;
  bool addOpened = false;

  @override
  Future<void> browse(
    BuildContext context,
    ServerGroup group, {
    required bool mobile,
  }) async {
    browsedOnMobile = mobile;
    activeGroupId = group.id;
  }

  @override
  Future<void> openServerHelp(BuildContext context) async {
    helpOpened = true;
  }

  @override
  Future<void> addServers(BuildContext context) async {
    addOpened = true;
  }
}

CoreConfigData _server(
  int id,
  String country, {
  bool favorite = false,
  String protocol = 'vless',
}) => CoreConfigData(
  id: id,
  name: 'Node $id',
  type: 'outbound',
  tags: '$protocol,xhttp,tls',
  data: outboundCompanion({
    'tag': 'Node $id',
    'protocol': protocol,
    'streamSettings': {'network': 'xhttp', 'security': 'tls'},
  }).data.value,
  delay: id * 20,
  subId: 0,
  countryCode: country,
  favorite: favorite,
);

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late _Controller controller;
  late ScrollController scroll;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(database: db);
    controller = _Controller(database: db, coordinator: coordinator)
      ..servers = [_server(1, 'JP', favorite: true), _server(2, 'SG')];
    scroll = ScrollController();
  });

  tearDown(() async {
    scroll.dispose();
    await controller.close();
    coordinator.dispose();
    await db.close();
  });

  Future<void> pumpBrowser(
    WidgetTester tester,
    double width, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    bool groupPage = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final mobile = width <= AppLayout.mobileBreakpoint;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.material(brightness, mobile: mobile),
        locale: locale,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ShadTheme(
          data: AppTheme.shad(brightness),
          child: ShadToaster(child: child!),
        ),
        home: Scaffold(
          body: Row(
            children: [
              if (!mobile)
                SizedBox(
                  width: width <= AppLayout.compactDesktopBreakpoint
                      ? AppLayout.compactSidebarWidth
                      : AppLayout.desktopSidebarWidth,
                ),
              Expanded(
                child: ResponsiveContent(
                  child: BlocBuilder<_Controller, ServersPageState>(
                    bloc: controller,
                    builder: (context, _) => groupPage
                        ? ServerGroupView(
                            controller: controller,
                            group: controller
                                .groups(AppLocalizations.of(context)!)
                                .first,
                          )
                        : ServerBrowser(controller: controller, scroll: scroll),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder iconButton(String tooltip) => find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == tooltip,
  );

  for (final locale in const [
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ru'),
    Locale('fa'),
  ]) {
    for (final width in [390.0, 1160.0]) {
      testWidgets(
        'subscription package fits the group header ($locale, $width)',
        (tester) async {
          controller.sources = [
            SubscriptionData(
              id: 1,
              name: 'Provider subscription with a long descriptive name',
              url: 'https://example.test/subscription',
              hwidEnabled: false,
              timestamp: DateTime(2026, 9, 1),
              uploadBytes: 1024,
              downloadBytes: 2048,
              totalBytes: 0x7fffffffffffffff,
              expireTimestamp: 253402214400,
              userInfoUpdatedAt: DateTime(2026, 9, 1),
            ),
          ];
          controller.servers = [_server(1, 'JP').copyWith(subId: 1)];
          for (final groupPage in [false, true]) {
            await pumpBrowser(
              tester,
              width,
              locale: locale,
              groupPage: groupPage,
            );
            final meta = find.byKey(
              const ValueKey('server-group-meta:subscription:1'),
            );
            expect(meta, findsOneWidget);
            expect(find.byType(SourceMenu), findsOneWidget);
            expect(tester.takeException(), isNull);
            // The summary line opens the provider's full package details.
            await tester.tap(meta);
            await tester.pumpAndSettle();
            expect(find.byType(SubscriptionPackageDetails), findsOneWidget);
            expect(tester.takeException(), isNull);
            Navigator.of(
              tester.element(find.byType(SubscriptionPackageDetails)),
            ).pop();
            await tester.pumpAndSettle();
          }
          controller.groupBy(ServerGrouping.location);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('server-group-meta:subscription:1')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('source updates refresh package UI without restricting use', (
    tester,
  ) async {
    final source = SubscriptionData(
      id: 1,
      name: 'Provider',
      url: 'https://example.test/subscription',
      hwidEnabled: false,
      timestamp: DateTime(2026, 9, 1),
    );
    controller.sources = [source];
    controller.servers = [_server(1, 'JP').copyWith(subId: 1)];
    await pumpBrowser(tester, 390, groupPage: true);
    final l = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    VoidCallback? use() => tester
        .widget<OutlinedButton>(
          find.descendant(
            of: find.byType(ServerUseButton),
            matching: find.byType(OutlinedButton),
          ),
        )
        .onPressed;
    expect(find.textContaining(l.subscriptionPackageExpired), findsNothing);
    expect(use(), isNotNull);
    controller.sources = [
      source.copyWith(
        uploadBytes: const Value(1024),
        downloadBytes: const Value(2048),
        totalBytes: const Value(1024),
        expireTimestamp: const Value(1),
        userInfoUpdatedAt: Value(DateTime(2026, 9, 2)),
      ),
    ];
    await tester.pumpAndSettle();
    expect(find.textContaining(l.subscriptionPackageExpired), findsOneWidget);
    expect(use(), isNotNull);
    controller.sources = [source];
    await tester.pumpAndSettle();
    expect(find.textContaining(l.subscriptionPackageExpired), findsNothing);
    expect(find.byType(ServerNodeRow), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final width in [427.0, 1160.0]) {
      testWidgets('node latency colors stay readable ($brightness, $width)', (
        tester,
      ) async {
        final palette = AppColorTokens.fallback(brightness).palette;
        final samples = [
          (0, palette.runningBadge),
          (500, palette.runningBadge),
          (501, palette.restartingText),
          (1000, palette.restartingText),
          (1001, palette.primaryHover),
          (PingDelayConstants.unknown, null),
          (PingDelayConstants.error, palette.mutedForeground),
          (PingDelayConstants.timeout, palette.mutedForeground),
        ];
        controller.servers = [
          for (final (index, (delay, _)) in samples.indexed)
            _server(index + 1, 'JP').copyWith(delay: delay),
        ];
        await pumpBrowser(
          tester,
          width,
          brightness: brightness,
          groupPage: true,
        );
        final l = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
        for (final (index, (delay, color)) in samples.indexed) {
          final latency = find.descendant(
            of: find.byKey(ValueKey(index + 1)),
            matching: find.byType(NodeLatency),
          );
          final text = find.descendant(
            of: latency,
            matching: find.byType(Text),
          );
          if (color == null) {
            // Never probed: no label at all.
            expect(text, findsNothing);
            continue;
          }
          final label = tester.widget<Text>(text);
          expect(
            label.data,
            PingDelayConstants.isSuccessful(delay)
                ? l.livePingResult(delay)
                : l.livePingFailed,
          );
          expect(label.style!.color, color);
          if (PingDelayConstants.isSuccessful(delay)) {
            for (final background in [palette.card, palette.selectedSurface]) {
              final foregroundLuminance = color.computeLuminance() + 0.05;
              final backgroundLuminance = background.computeLuminance() + 0.05;
              final contrast = foregroundLuminance > backgroundLuminance
                  ? foregroundLuminance / backgroundLuminance
                  : backgroundLuminance / foregroundLuminance;
              expect(contrast, greaterThanOrEqualTo(4.5));
            }
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [427.0, 1160.0]) {
    for (final grouping in ServerGrouping.values) {
      testWidgets(
        'group test can be cancelled without locking menus: $grouping at $width',
        (tester) async {
          controller.groupBy(grouping);
          controller.sources = [
            SubscriptionData(
              id: 4,
              name: 'Source',
              hwidEnabled: false,
              url: 'https://example.test/sub',
              timestamp: DateTime(2026),
            ),
          ];
          controller.servers = [_server(1, 'JP').copyWith(subId: 4)];
          await pumpBrowser(tester, width, groupPage: true);
          final l = AppLocalizations.of(
            tester.element(find.byType(ServerGroupView)),
          )!;
          final group = controller.groups(l).single;
          controller.emit(
            controller.state.copyWith(
              serverTests: {
                Object(): (groupId: group.id, cancelling: false),
                Object(): (groupId: null, cancelling: false),
              },
            ),
          );
          AppEventBus.instance.updatePinging(true);
          expect(controller.testingGroup(group), isTrue);
          await tester.pump();
          await tester.pump();

          for (final menu in [
            find.byType(ServerMenu),
            find.byType(SourceMenu),
          ]) {
            for (final element in menu.evaluate()) {
              final button = tester.widget<IconButton>(
                find.descendant(
                  of: find.byWidget(element.widget),
                  matching: find.byType(IconButton),
                ),
              );
              expect(button.onPressed, isNotNull);
              expect(button.icon, isA<Icon>());
              expect((button.icon as Icon).icon, LucideIcons.ellipsis);
            }
          }
          // The group's test button spins while its test runs.
          expect(find.byType(ButtonProgressIndicator), findsOneWidget);
          await tester.tap(iconButton(l.prototypeCancel));
          await tester.pump();
          await tester.pump();
          expect(controller.cancellingGroup(group), isTrue);
          expect(controller.state.serverTests.values.last.cancelling, isFalse);
          expect(
            tester
                .widget<IconButton>(iconButton(l.prototypePleaseWait))
                .onPressed,
            isNull,
          );

          controller.emit(controller.state.copyWith(serverTests: {}));
          AppEventBus.instance.updatePinging(false);
          await tester.pumpAndSettle();
          expect(iconButton(l.prototypeTestServers), findsOneWidget);
          expect(find.byType(ButtonProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final (width, groupPage) in [
    (427.0, false),
    (427.0, true),
    (1160.0, false),
    (1160.0, true),
  ]) {
    testWidgets('automatic probing shows loading ($width, group: $groupPage)', (
      tester,
    ) async {
      late Completer<void> started;
      late Completer<void> release;
      late PingService ping;
      var batches = 0;
      final row = await tester.runAsync(() async {
        started = Completer<void>();
        release = Completer<void>();
        ping = PingService.forTesting(
          database: db,
          runBatch: (_, _) async {
            batches++;
            if (!started.isCompleted) started.complete();
            await release.future;
            return const [PingBatchResult(true, 20, '', countryCode: 'JP')];
          },
        );
        final id = await db.coreConfigDao.insertRow(
          outboundCompanion({'tag': 'Imported', 'protocol': 'socks'}),
        );
        return db.coreConfigDao.searchRow(id);
      });
      await controller.close();
      controller = _Controller(
        database: db,
        coordinator: coordinator,
        ping: ping,
      )..servers = [row!];
      await pumpBrowser(tester, width, groupPage: groupPage);
      final l = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      try {
        await tester.runAsync(() async {
          ping.schedulePingConfigIds([row.id]);
          await started.future.timeout(const Duration(seconds: 5));
        });
        await tester.pump();
        await tester.pump();
        expect(ping.isPinging, isTrue);
        expect(AppEventBus.instance.state.pinging, isTrue);
        expect(controller.state.serverTests, isEmpty);
        // Background probes show on the automatic choice, which only the
        // full list has.
        expect(
          find.byType(ButtonProgressIndicator),
          groupPage ? findsNothing : findsOneWidget,
        );
        expect(
          tester
              .widget<IconButton>(
                find.descendant(
                  of: find.byType(ServerMenu),
                  matching: find.byType(IconButton),
                ),
              )
              .onPressed,
          isNotNull,
        );
        await tester.runAsync(() async {
          await tester.tap(iconButton(l.prototypeTestServers));
        });
        await tester.pump();
        expect(find.byType(ShadToast), findsNothing);
        expect(controller.state.serverTests, hasLength(1));
        expect(batches, 1);
        if (groupPage) {
          // A queued group must not reject single-node requests. Cancelling
          // that group must leave both node requests queued and independent.
          for (var index = 0; index < 2; index++) {
            await tester.runAsync(() async {
              await tester.tap(
                find.byTooltip('${l.prototypeMoreActions}: Imported'),
              );
            });
            // The menu's entrance starts on the first frame after opening.
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            await tester.runAsync(() async {
              await tester.tap(find.text(l.prototypeTestAgain));
            });
            await tester.pump(const Duration(seconds: 1));
          }
          expect(controller.state.serverTests, hasLength(3));
          expect(find.byType(ShadToast), findsNothing);
          expect(batches, 1);
          await tester.tap(iconButton(l.prototypeCancel));
          await tester.pump();
          expect(
            controller.state.serverTests.values.map((test) => test.cancelling),
            [true, false, false],
          );
        }
      } finally {
        await tester.runAsync(() async {
          release.complete();
          // Wait for the scheduled task's database write and event update.
          await ping
              .pingConfigIds([row.id])
              .timeout(const Duration(seconds: 5));
        });
      }
      await tester.pumpAndSettle();
      expect(batches, groupPage ? 3 : 2);
      expect(controller.state.serverTests, isEmpty);
      expect(find.byType(ButtonProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in const [Locale('en'), Locale('ru'), Locale('fa')]) {
    testWidgets('every group sits in one scrolling list: $locale', (
      tester,
    ) async {
      await pumpBrowser(tester, 1160, locale: locale);
      final browser = find.byType(ServerBrowser);
      // Favorites first, then the manual group: no master/detail panes.
      expect(find.byType(ServerGroupSliver), findsNWidgets(2));
      expect(
        find.descendant(
          of: browser,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        ),
        findsOneWidget,
      );
      expect(find.byType(ServerNodeRow), findsNWidgets(3));
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(PopupMenuButton<ServerAction>), findsNothing);

      controller.groupBy(ServerGrouping.location);
      await tester.pumpAndSettle();
      expect(find.byType(ServerGroupSliver), findsNWidgets(3));
      expect(find.byType(ServerNodeRow), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a group header collapses its nodes, collapse all hides all', (
    tester,
  ) async {
    controller.groupBy(ServerGrouping.location);
    await pumpBrowser(tester, 1160);
    final l = AppLocalizations.of(tester.element(find.byType(ServerBrowser)))!;
    expect(find.byKey(const ValueKey(2)), findsOneWidget);
    await tester.tap(find.text(l.countryRegionName('SG')));
    await tester.pumpAndSettle();
    expect(controller.collapsed('location:SG'), isTrue);
    expect(find.byKey(const ValueKey(2)), findsNothing);
    // The favorite JP node stays in both the favorites and the JP group.
    expect(find.byKey(const ValueKey(1)), findsNWidgets(2));
    final groups = controller.groups(l, filter: false);
    controller.setAllCollapsed(groups, true);
    await tester.pumpAndSettle();
    expect(controller.allCollapsed(groups), isTrue);
    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    controller.setAllCollapsed(groups, false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(2)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter chips narrow nodes by favorites and protocol', (
    tester,
  ) async {
    controller.servers = [
      _server(1, 'JP', favorite: true),
      _server(2, 'SG'),
      _server(3, 'DE', protocol: 'trojan'),
    ];
    await pumpBrowser(tester, 1160);
    final l = AppLocalizations.of(tester.element(find.byType(ServerBrowser)))!;
    Finder chip(String label) => find.descendant(
      of: find.byType(ServerToolbar),
      matching: find.text(label),
    );
    expect(controller.protocols(), ['VLESS', 'TROJAN']);
    await tester.tap(chip('TROJAN'));
    await tester.pumpAndSettle();
    expect(controller.protocolFilter, 'TROJAN');
    expect(find.byKey(const ValueKey(3)), findsOneWidget);
    expect(find.byKey(const ValueKey(2)), findsNothing);
    await tester.tap(chip('TROJAN'));
    await tester.pumpAndSettle();
    expect(controller.protocolFilter, isNull);
    await tester.tap(chip(l.prototypeFavorites));
    await tester.pumpAndSettle();
    expect(controller.favoritesOnly, isTrue);
    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    expect(find.byKey(const ValueKey(2)), findsNothing);
    await tester.tap(chip(l.serversFilterAll));
    await tester.pumpAndSettle();
    expect(controller.filtering, isFalse);
    expect(find.byKey(const ValueKey(2)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the grouping toggle switches to locations on mobile', (
    tester,
  ) async {
    await pumpBrowser(tester, 427);
    final l = AppLocalizations.of(tester.element(find.byType(ServerBrowser)))!;
    expect(controller.grouping, ServerGrouping.subscription);
    expect(find.byType(TabBar), findsNothing);
    await tester.tap(find.text(l.prototypeByNodeLocation));
    await tester.pumpAndSettle();
    expect(controller.grouping, ServerGrouping.location);
    expect(find.text(l.countryRegionName('SG')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [427.0, 900.0, 1160.0]) {
    testWidgets('node lists build lazily at $width', (tester) async {
      controller.groupBy(ServerGrouping.location);
      controller.servers = [
        for (var id = 1; id <= 200; id++) _server(id, 'JP'),
        for (final (index, country) in [
          'AR',
          'AT',
          'AU',
          'BE',
          'BR',
          'CA',
          'CH',
          'DE',
          'DK',
          'ES',
          'FI',
          'FR',
          'GB',
          'HK',
          'IE',
          'IN',
          'IT',
          'KR',
          'NL',
          'SG',
        ].indexed)
          _server(201 + index, country),
      ];
      await pumpBrowser(tester, width);
      final rows = find.byType(ServerNodeRow);
      expect(rows.evaluate().length, inInclusiveRange(1, 30));
      expect(find.byKey(const ValueKey(200)), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey(200)),
        1000,
        scrollable: find
            .descendant(
              of: find.byType(ServerBrowser),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first,
        maxScrolls: 60,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(200)), findsOneWidget);
      expect(rows.evaluate().length, lessThan(30));
      expect(scroll.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty server browser replaces browsing controls with actions', (
    tester,
  ) async {
    controller.servers = [];
    await pumpBrowser(tester, 1160);
    final l = AppLocalizations.of(tester.element(find.byType(ServerBrowser)))!;

    expect(find.byType(PageEmptyState), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, l.backupRestoreFrom),
      BackupService.supported ? findsOneWidget : findsNothing,
    );
    final emptyCard = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is ShapeDecoration &&
          (widget.decoration as ShapeDecoration).shape is AppDashedBorder,
    );
    final card = tester.getRect(emptyCard);
    expect(card.top, AppSpacing.desktopPageTop);
    expect(card.left, AppLayout.desktopSidebarWidth + AppSpacing.page);
    expect(
      card.width,
      1160 - AppLayout.desktopSidebarWidth - AppSpacing.page * 2,
    );
    expect(card.height, AppLayout.emptyStateDesktopMinHeight);
    expect(find.text(l.prototypeNoServersYet), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ServerGroupView), findsNothing);
    expect(find.text(l.prototypeAutomaticRecommended), findsNothing);

    await tester.tap(find.text(l.prototypeHowGetServers));
    await tester.pump();
    expect(controller.helpOpened, isTrue);
    await tester.tap(find.text(l.prototypeAddServer));
    await tester.pump();
    expect(controller.addOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final width in [427.0, 1160.0]) {
    testWidgets('the node menu closes without a mutation at $width', (
      tester,
    ) async {
      await pumpBrowser(tester, width);
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerBrowser)),
      )!;
      await tester.tap(
        find.byTooltip('${l.prototypeMoreActions}: Node 2').first,
      );
      await tester.pumpAndSettle();
      // Phones get the sheet with hints, desktops a popup at the button.
      if (width <= AppLayout.mobileBreakpoint) {
        expect(find.byType(ServerActionsMenu), findsOneWidget);
        await tester.tap(find.byTooltip(l.prototypeCloseDialog));
      } else {
        expect(find.byType(ServerActionsMenu), findsNothing);
        expect(find.text(l.prototypeEditServer), findsOneWidget);
        expect(find.text(l.prototypeAddFavorite), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pumpAndSettle();
      expect(find.text(l.prototypeEditServer), findsNothing);
      expect(controller.servers, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }
}
