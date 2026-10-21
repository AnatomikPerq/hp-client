import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/tools/traffic_format.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/connect/view.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_empty_state.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/health.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/traffic.dart';
import 'package:onexray/service/settings/backup/service.dart';

void main() {
  test('connection traffic keeps byte conversion and prototype precision', () {
    expect(formatTraffic(0, connection: true), '0 B');
    expect(formatTraffic(1024, connection: true), '1 KB');
    expect(formatTraffic(1536, connection: true), '1.5 KB');
    expect(
      formatTraffic((2.34 * 1024 * 1024).round(), connection: true),
      '2.34 MB',
    );
    expect(formatTraffic(1536), '1.5 KiB');
  });

  Widget screen({
    ConnectionView view = const ConnectionView(),
    bool hasServers = true,
    bool expert = false,
    String? runningPath,
    List<CoreConfigData> raws = const [],
    VoidCallback? onAddServers,
    VoidCallback? onExpert,
    Widget? servers,
    ConnectionHealth health = ConnectionHealth.none,
    bool killSwitchBlocking = false,
    VoidCallback? onUnblock,
  }) => ConnectView(
    view: view,
    hasServers: hasServers,
    expert: expert,
    raws: raws,
    activeRawId: null,
    location: 'Automatic selection',
    runningPath: runningPath,
    method: 'Smart Routing',
    onConnection: () {},
    onAddServers: onAddServers ?? () {},
    onExpert: (_) => onExpert?.call(),
    onServer: () {},
    onMethod: () {},
    onWhy: () {},
    onRawAdd: () {},
    onRawSelect: (_) {},
    onRawActions: (_) {},
    servers: servers,
    health: health,
    killSwitchBlocking: killSwitchBlocking,
    onUnblock: onUnblock,
  );

  Widget app(
    Widget child, {
    Locale locale = const Locale('en'),
    double scale = 1,
  }) => MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalePolicy.localizationsDelegates,
    builder: (context, child) => LayoutBuilder(
      builder: (context, constraints) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: constraints.biggest,
          textScaler: TextScaler.linear(scale),
        ),
        child: ShadTheme(data: AppTheme.shad(Brightness.light), child: child!),
      ),
    ),
    home: Scaffold(body: child),
  );

  testWidgets(
    'connection traffic is read-only with complete values and units',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final view = ConnectionView(
        phase: ConnectionPhase.connected,
        metricsAvailable: true,
        downloadSpeed: (248.72 * 1024).round(),
        uploadSpeed: (32.8 * 1024).round(),
        traffic: ConnectionTraffic(
          uplink: (158.91 * 1024).round(),
          downlink: (999.99 * 1024 * 1024).round(),
          sampledAtMs: 0,
        ),
      );
      for (final (width, scale, locale) in [
        (1160.0, 1.0, const Locale('en')),
        (901.0, 1.0, const Locale('en')),
        (390.0, 1.0, const Locale('en')),
        (320.0, 1.0, const Locale('en')),
        (1160.0, 1.3, const Locale('ru')),
        (390.0, 1.3, const Locale('fa')),
      ]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpWidget(
          app(
            width > AppLayout.mobileBreakpoint
                ? Row(
                    children: [
                      const SizedBox(width: AppLayout.desktopSidebarWidth),
                      Expanded(child: screen(view: view)),
                    ],
                  )
                : screen(view: view),
            locale: locale,
            scale: scale,
          ),
        );
        await tester.pump();
        final readout = find.byType(TrafficReadout);
        expect(readout, findsOneWidget);
        // Read-only: the speeds and totals open nothing.
        expect(
          find.ancestor(of: readout, matching: find.byType(InkWell)),
          findsNothing,
        );
        for (final value in [
          find.text('248.72 KB/s'),
          find.text('32.8 KB/s'),
          find.textContaining('158.91 KB'),
          find.textContaining('999.99 MB'),
        ]) {
          expect(value, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(value);
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '$value must not be truncated at $width / $scale / $locale',
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final expert in [false, true]) {
    testWidgets('home keeps one column, expert=$expert', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1160, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app(screen(expert: expert, servers: const Text('server-list'))),
      );
      await tester.pump();
      final panel = find.byKey(const ValueKey('home-connection-panel'));
      expect(tester.getSize(panel).width, AppLayout.homeMaxWidth);
      expect(
        find.descendant(of: panel, matching: find.text('Disconnected')),
        findsOneWidget,
      );
      expect(find.text('Expert mode'), findsOneWidget);
      expect(
        tester.widget<TrafficReadout>(find.byType(TrafficReadout)).desktop,
        isTrue,
      );
      // Quick actions sit below the orb, the node list below them.
      final add = tester.getRect(find.byKey(const ValueKey('home-add')));
      expect(add.top, greaterThan(tester.getRect(panel).bottom));
      expect(
        tester.getRect(find.byKey(const ValueKey('home-paste'))).top,
        add.top,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('home-all-servers'))).top,
        add.top,
      );
      expect(find.text('server-list'), expert ? findsNothing : findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == 'Why this connection?',
        ),
        expert ? findsNothing : findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-routing')),
        expert ? findsNothing : findsOneWidget,
      );
      expect(find.text('Add Raw JSON'), expert ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mobile home keeps the same order without desktop sizing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(screen(servers: const Text('server-list'))));
    await tester.pump();
    final panel = find.byKey(const ValueKey('home-connection-panel'));
    expect(tester.getSize(panel).width, 390 - AppSpacing.mobilePage * 2);
    expect(
      tester.widget<TrafficReadout>(find.byType(TrafficReadout)).desktop,
      isFalse,
    );
    expect(
      tester.getRect(find.text('server-list')).top,
      greaterThan(tester.getRect(find.byKey(const ValueKey('home-add'))).top),
    );
    expect(tester.takeException(), isNull);
  });

  for (final locale in [
    const Locale('en'),
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    const Locale('ru'),
    const Locale('fa'),
  ]) {
    for (final width in [390.0, 1160.0]) {
      testWidgets('connection layout ${locale.toLanguageTag()} at $width', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(app(screen(), locale: locale, scale: 1.3));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final context = tester.element(find.byType(ConnectView));
        final l = AppLocalizations.of(context)!;
        expect(find.text(l.homeCheckConnection), findsOneWidget);
        expect(find.text(l.prototypeAdd), findsOneWidget);
        expect(find.text(l.homePaste), findsOneWidget);
        expect(
          Directionality.of(context),
          locale.languageCode == 'fa' ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }
    testWidgets(
      'connected path and selection reset notice ${locale.toLanguageTag()}',
      (tester) async {
        const path = 'Singapore 03 + Japan 02 → United States 01';
        await tester.pumpWidget(
          app(
            screen(
              view: const ConnectionView(
                phase: ConnectionPhase.connected,
                issue: 'selectionReset',
              ),
              runningPath: path,
            ),
            locale: locale,
          ),
        );
        final l = AppLocalizations.of(
          tester.element(find.byType(ConnectView)),
        )!;
        expect(find.text(path), findsOneWidget);
        expect(
          find.text(l.prototypeNameActive(l.prototypeAutomaticSelection)),
          findsOneWidget,
        );
        expect(find.text(l.prototypeConnectionFailed), findsNothing);
        expect(find.text(l.prototypeCheckNetwork), findsNothing);
        expect(find.text(l.prototypeConnected), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty normal state still offers expert configuration', (
    tester,
  ) async {
    var switched = false;
    await tester.pumpWidget(
      app(screen(hasServers: false, onExpert: () => switched = true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use a complete Raw JSON configuration'));
    expect(switched, isTrue);
  });

  testWidgets('connection empty state uses the server page layout', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final (size, locale) in [
      (const Size(1160, 800), const Locale('zh')),
      (const Size(760, 600), const Locale('ru')),
      (const Size(1160, 800), const Locale('fa')),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        app(
          Scaffold(
            appBar: AppBar(title: const Text('Connect')),
            body: screen(hasServers: false),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PageEmptyState), findsOneWidget);
      final l = AppLocalizations.of(
        tester.element(find.byType(PageEmptyState)),
      )!;
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
      final bodyTop = tester.getBottomLeft(find.byType(AppBar)).dy;
      expect(card.center.dx, closeTo(size.width / 2, .5));
      expect(card.top, bodyTop + AppSpacing.desktopPageTop);
      expect(
        card.width,
        size.width.clamp(0.0, AppLayout.standardMaxWidth) - AppSpacing.page * 2,
      );
      expect(card.height, AppLayout.emptyStateDesktopMinHeight);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'empty state actions stay reachable in short and mobile windows',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final size in [const Size(760, 240), const Size(390, 600)]) {
        var added = false;
        var switched = false;
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          app(
            screen(
              hasServers: false,
              onAddServers: () => added = true,
              onExpert: () => switched = true,
            ),
            scale: 1.5,
          ),
        );
        await tester.pumpAndSettle();
        for (final action in [
          find.widgetWithText(FilledButton, 'Add servers'),
          find.widgetWithText(
            TextButton,
            'Use a complete Raw JSON configuration',
          ),
        ]) {
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          await tester.tap(action);
        }
        expect(added, isTrue);
        expect(switched, isTrue);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('platform errors are not presented as permission requests', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        screen(
          view: ConnectionView(
            phase: ConnectionPhase.failed,
            issue: 'nativeStatusFailed',
            permission: PlatformPermissionResult(
              kind: PlatformPermissionKind.appleVpn,
              state: PlatformPermissionState.failed,
            ),
          ),
        ),
      ),
    );
    final l = AppLocalizations.of(tester.element(find.byType(ConnectView)))!;

    expect(find.text(l.prototypeTemporarilyUnavailable), findsOneWidget);
    expect(find.text(l.prototypeVpnPermissionRequired), findsNothing);
  });

  testWidgets('a kill switch block says so and offers to unblock', (
    tester,
  ) async {
    var unblocked = 0;
    await tester.pumpWidget(
      app(screen(killSwitchBlocking: true, onUnblock: () => unblocked++)),
    );
    final l = AppLocalizations.of(tester.element(find.byType(ConnectView)))!;
    expect(find.text(l.killSwitchBlocked), findsOneWidget);
    expect(find.text(l.killSwitchBlockedDetail), findsOneWidget);
    expect(find.text(l.prototypeDisconnected), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-unblock')));
    expect(unblocked, 1);

    // Connecting again hides the block at once.
    await tester.pumpWidget(
      app(
        screen(
          view: const ConnectionView(phase: ConnectionPhase.connecting),
          killSwitchBlocking: true,
          onUnblock: () {},
        ),
      ),
    );
    expect(find.text(l.killSwitchBlocked), findsNothing);
    expect(find.byKey(const ValueKey('home-unblock')), findsNothing);
  });

  testWidgets('a connection that carries nothing says so, not connected', (
    tester,
  ) async {
    final runtime = ConnectionRuntime.create(
      configuration: ConnectionConfiguration(),
      compiled: CompiledConnection(
        xrayJson: '{}',
        entries: [
          ResolvedServer(id: 1, sourceId: 1, outbound: {'tag': 'Main'}),
        ],
        finalExit: null,
        nodeTags: const {'app-entry-0': 1},
      ),
      platform: ConnectionPlatform.windows,
      request: StartVpnRequest(null, '10820', '18003', '{}'),
      minewirePorts: const {1: 41000},
    );
    final view = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: runtime,
    );
    final key = ConnectionHealth.keyOf(runtime);
    for (final (health, minewire) in [
      (
        ConnectionHealth(key: key, status: ConnectionHealthStatus.unreachable),
        false,
      ),
      (
        ConnectionHealth(
          key: key,
          status: ConnectionHealthStatus.unreachable,
          minewireDown: true,
        ),
        true,
      ),
    ]) {
      await tester.pumpWidget(app(screen(view: view, health: health)));
      final l = AppLocalizations.of(tester.element(find.byType(ConnectView)))!;
      expect(find.text(l.connectionHealthLost), findsOneWidget);
      expect(find.text(l.prototypeConnected), findsNothing);
      expect(
        find.text(
          minewire
              ? l.connectionHealthMinewireDetail
              : l.connectionHealthLostDetail,
        ),
        findsOneWidget,
      );
    }

    // A verdict about another session or node does not apply.
    await tester.pumpWidget(
      app(
        screen(
          view: view,
          health: const ConnectionHealth(
            key: 'other',
            status: ConnectionHealthStatus.unreachable,
          ),
        ),
      ),
    );
    final l = AppLocalizations.of(tester.element(find.byType(ConnectView)))!;
    expect(find.text(l.connectionHealthLost), findsNothing);
    expect(find.text(l.prototypeConnected), findsOneWidget);
  });

  testWidgets('missing desktop interface shows the interface prompt', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        screen(
          view: const ConnectionView(
            phase: ConnectionPhase.disconnected,
            issue: 'interfaceRequired',
          ),
        ),
      ),
    );
    final l = AppLocalizations.of(tester.element(find.byType(ConnectView)))!;

    expect(find.text(l.prototypeChooseInterfaceNotice), findsOneWidget);
    expect(find.text(l.prototypeCheckNetwork), findsNothing);
  });

  testWidgets(
    'connection status shows resolver counts instead of a network error',
    (tester) async {
      await tester.pumpWidget(
        app(
          screen(
            view: const ConnectionView(
              issue: 'insufficientHealthyServers',
              error: ConnectionResolutionException(
                ConnectionResolutionFailure.insufficientHealthyServers,
                requiredCount: 3,
                availableCount: 1,
              ),
            ),
          ),
        ),
      );
      final l = AppLocalizations.of(tester.element(find.byType(ConnectView)))!;
      expect(find.text('${l.prototypeNotEnoughServers} (1/3)'), findsOneWidget);
      expect(find.text(l.prototypeCheckNetwork), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all legacy Raw configurations remain visible; add hidden at 3+',
    (tester) async {
      final raws = List.generate(
        4,
        (index) => CoreConfigData(
          id: index + 1,
          name: 'Legacy ${index + 1}',
          type: 'raw',
          tags: '',
          delay: -1,
          subId: 0,
          favorite: false,
        ),
      );
      await tester.pumpWidget(app(screen(expert: true, raws: raws)));
      await tester.pumpAndSettle();
      for (final row in raws) {
        expect(find.text(row.name), findsOneWidget);
      }
      expect(find.text('Add Raw JSON'), findsNothing);
      expect(find.text('Why this connection?'), findsNothing);
    },
  );

  testWidgets('page footer stays compact and fixed while content scrolls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: List.generate(40, (i) => ListTile(title: Text('Row $i'))),
          ),
          bottomNavigationBar: PageActionBar(
            children: [
              TextButton(onPressed: () {}, child: const Text('Cancel')),
              FilledButton(onPressed: () {}, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
    final before = tester.getRect(find.text('Save'));
    expect(before.top, greaterThan(650));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Save')), before);
    expect(
      tester.getSize(find.byType(PageActionBar)).height,
      greaterThanOrEqualTo(AppLayout.mobilePageActionMinHeight),
    );
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(AppLayout.pageActionButtonMinHeight),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(FilledButton)).width,
      greaterThanOrEqualTo(AppLayout.pageActionButtonMinWidth),
    );
    expect(
      tester.getSize(find.byType(PageActionBar)).height,
      greaterThanOrEqualTo(AppLayout.pageActionMinHeight),
    );
    expect(tester.takeException(), isNull);
  });
}
