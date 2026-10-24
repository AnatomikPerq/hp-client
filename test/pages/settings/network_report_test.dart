import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/network_report/controller.dart';
import 'package:onexray/pages/settings/network_report/page.dart';
import 'package:onexray/pages/settings/network_report/settings_page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/tunnel/interface.dart';
import 'package:onexray/service/diagnostics/runner.dart';
import 'package:onexray/service/diagnostics/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../service/diagnostics/fixtures.dart';
import '../../service/diagnostics/runner_test.dart' show FakeReportHost;

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: AppTheme.light,
  locale: locale,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (_, child) => ShadTheme(
    data: AppTheme.shad(Brightness.light),
    child: ShadToaster(child: child!),
  ),
  home: child,
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    PackageInfo.setMockInitialValues(
      appName: 'HYPER CLIENT',
      packageName: 'test',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  NetworkReportController controller(FakeReportHost host) =>
      NetworkReportController(
        runner: NetworkReportRunner(
          host: host,
          pollInterval: const Duration(milliseconds: 100),
        ),
        interfaces: () async => const [
          OutboundInterfaceOption('Ethernet', ['192.0.2.5'], true),
          OutboundInterfaceOption('Ethernet 4', ['10.0.0.2'], false),
        ],
      );

  for (final locale in const [Locale('en'), Locale('ru'), Locale('fa')]) {
    testWidgets('a white list report renders in ${locale.languageCode}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final host = FakeReportHost([
        NetworkReportStateResponse(running: false, report: whitelistReport()),
      ]);
      await tester.pumpWidget(
        _app(
          NetworkReportPage(createController: () => controller(host)),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      final l = await AppLocalizations.delegate.load(locale);
      expect(find.text(l.netReportStart), findsOneWidget);
      expect(find.text(l.netReportIntro(8)), findsOneWidget);

      await tester.tap(find.text(l.netReportStart));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      expect(host.requests.single.interfaceName, 'Ethernet');
      expect(
        find.byKey(const ValueKey('network-report-summary')),
        findsOneWidget,
      );
      expect(find.text(l.netReportModeSniWhitelist), findsOneWidget);
      expect(find.text(l.netReportModeSniWhitelistDetail), findsOneWidget);
      expect(find.text(l.netReportWorks), findsOneWidget);
      expect(find.text(l.netReportFails), findsOneWidget);
      expect(find.text(l.netReportRerun), findsOneWidget);

      // Sections start collapsed; a tap shows their rows.
      expect(find.text('ChatGPT'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('network-report-sites')));
      await tester.pumpAndSettle();
      expect(find.text('ChatGPT'), findsOneWidget);
      expect(find.text(l.netReportStatusSniBlocked), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an old libXray says so instead of failing silently', (
    tester,
  ) async {
    final host = FakeReportHost(const [], startError: 'unknown method');
    await tester.pumpWidget(
      _app(NetworkReportPage(createController: () => controller(host))),
    );
    await tester.pumpAndSettle();
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l.netReportStart));
    await tester.pumpAndSettle();
    expect(find.text(l.netReportUnsupported), findsOneWidget);
  });

  testWidgets('report data saves every change and the site list on leave', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final saved = <NetworkReportSettings>[];
    await tester.pumpWidget(
      _app(
        NetworkReportSettingsPage(
          createController: () => NetworkReportSettingsController(
            read: () async => const NetworkReportSettings(),
            save: (settings) async => saved.add(settings),
          ),
        ),
        locale: const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();
    final l = await AppLocalizations.delegate.load(const Locale('ru'));
    await tester.tap(find.text(l.netReportSettingsAdapter));
    await tester.pumpAndSettle();
    expect(saved.last.adapter, isTrue);
    // On by default since the Fragment checks; a tap turns it off.
    await tester.tap(find.text(l.netReportSettingsBypass));
    await tester.pumpAndSettle();
    expect(saved.last.bypass, isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('network-report-sites')),
      'https://Example.org/path\nnews.example.com',
    );
    await tester.pumpWidget(_app(const SizedBox()));
    await tester.pumpAndSettle();
    expect(saved.last.extraSites, ['example.org', 'news.example.com']);
    expect(saved.last.adapter, isTrue);
    expect(tester.takeException(), isNull);
  });
}
