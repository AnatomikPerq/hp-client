import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/country_flag.dart';
import 'package:onexray/pages/theme/theme.dart';

void main() {
  group('splitFlagEmoji', () {
    test('takes a leading flag out of the name', () {
      expect(splitFlagEmoji('🇳🇱 Основной (REALITY + XHTTP)'), (
        code: 'NL',
        name: 'Основной (REALITY + XHTTP)',
      ));
    });

    test('keeps the first flag and drops every flag from the text', () {
      expect(splitFlagEmoji('Fast 🇩🇪 via 🇳🇱 hop'), (
        code: 'DE',
        name: 'Fast via hop',
      ));
    });

    test('leaves names without regional indicators alone', () {
      const name = '🏳️‍🌈 Резервный (XHTTP) ⭐';
      expect(splitFlagEmoji(name), (code: null, name: name));
    });

    test('a lone regional indicator is not a flag', () {
      const name = '🇳 single';
      expect(splitFlagEmoji(name), (code: null, name: name));
    });

    test('a name that is only a flag leaves an empty name', () {
      expect(splitFlagEmoji(' 🇯🇵 '), (code: 'JP', name: ''));
    });
  });

  group('CountryFlag', () {
    Future<void> pump(WidgetTester tester, String? code) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Center(child: CountryFlag(code: code)),
      ),
    );

    testWidgets('draws the bundled image for a country code', (tester) async {
      await pump(tester, 'NL');
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, 'assets/flags/nl.png');
    });

    testWidgets('falls back to a globe without a valid code', (tester) async {
      for (final code in [null, '', 'N1', 'NLD']) {
        await pump(tester, code);
        expect(find.byType(Image), findsNothing);
        expect(find.byIcon(LucideIcons.globe), findsOneWidget);
      }
    });

    testWidgets('is decorative for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, 'DE');
      expect(
        find.descendant(
          of: find.byType(CountryFlag),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });
}
