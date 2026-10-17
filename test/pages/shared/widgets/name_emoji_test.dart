import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/country_flag.dart';
import 'package:onexray/pages/shared/widgets/name_emoji.dart';
import 'package:onexray/pages/shared/widgets/twemoji_keys.dart';
import 'package:onexray/pages/theme/theme.dart';

void main() {
  group('splitNameEmoji', () {
    // Server names of a real subscription: each provider emoji is the icon.
    final names = <String, (NameEmoji, String)>{
      '🇳🇱 Основной (REALITY + XHTTP)': (
        const NameEmoji.flag('NL'),
        'Основной (REALITY + XHTTP)',
      ),
      '🏳️‍🌈 Резервный (XHTTP)': (
        const NameEmoji.image('1f3f3-200d-1f308'),
        'Резервный (XHTTP)',
      ),
      '🏳️‍⚧️ Троянский (XHTTP)': (
        const NameEmoji.image('1f3f3-200d-26a7'),
        'Троянский (XHTTP)',
      ),
      '🇪🇺 Живучий (WS + Mux)': (
        const NameEmoji.flag('EU'),
        'Живучий (WS + Mux)',
      ),
      '🏴‍☠️ Быстрый UDP (HYS)': (
        const NameEmoji.image('1f3f4-200d-2620'),
        'Быстрый UDP (HYS)',
      ),
      '🧬 Мутант (AWG 2.0)': (
        const NameEmoji.image('1f9ec'),
        'Мутант (AWG 2.0)',
      ),
      '🚩 Особенный (MINE)': (
        const NameEmoji.image('1f6a9'),
        'Особенный (MINE)',
      ),
      '🏁 Без TLS (PLAIN)': (const NameEmoji.image('1f3c1'), 'Без TLS (PLAIN)'),
      '🛟 Аварийный (только моб.)': (
        const NameEmoji.image('1f6df'),
        'Аварийный (только моб.)',
      ),
      '🌟HYPER VPN💫': (const NameEmoji.image('1f31f'), 'HYPER VPN💫'),
    };
    names.forEach((value, expected) {
      test('takes the icon out of "$value"', () {
        expect(splitNameEmoji(value), (emoji: expected.$1, name: expected.$2));
      });
    });

    test('the first emoji wins and later flags leave the text', () {
      expect(splitNameEmoji('Fast 🔥 via 🇩🇪 hop ⭐'), (
        emoji: const NameEmoji.image('1f525'),
        name: 'Fast via hop ⭐',
      ));
      expect(splitNameEmoji('Main 🇩🇪 🔥'), (
        emoji: const NameEmoji.flag('DE'),
        name: 'Main 🔥',
      ));
    });

    test('works with or without the variation selector', () {
      expect(splitNameEmoji('☢️ Hot').emoji, const NameEmoji.image('2622'));
      expect(
        splitNameEmoji('🏳‍🌈 Pride').emoji,
        const NameEmoji.image('1f3f3-200d-1f308'),
      );
    });

    test('skin tones, keycaps and subdivision flags stay whole', () {
      expect(splitNameEmoji('👍🏽 Ok'), (
        emoji: const NameEmoji.image('1f44d-1f3fd'),
        name: 'Ok',
      ));
      expect(splitNameEmoji('1️⃣ First'), (
        emoji: const NameEmoji.image('31-20e3'),
        name: 'First',
      ));
      expect(splitNameEmoji('🏴󠁧󠁢󠁳󠁣󠁴󠁿 Edinburgh'), (
        emoji: const NameEmoji.image(
          '1f3f4-e0067-e0062-e0073-e0063-e0074-e007f',
        ),
        name: 'Edinburgh',
      ));
    });

    test('text symbols are not emoji without the variation selector', () {
      for (final name in ['© Provider', '#1 Server', '10 Gbit', '★ Premium']) {
        expect(splitNameEmoji(name), (emoji: null, name: name));
      }
    });

    test('an unknown joined part goes with its first image', () {
      // The set has no image for this joined pair; the text must not keep a
      // dangling joiner and its second half.
      expect(splitNameEmoji('🙂\u200D\u{1FAE8} Node'), (
        emoji: const NameEmoji.image('1f642'),
        name: 'Node',
      ));
    });

    test('names without emoji are left alone', () {
      const name = 'Germany Frankfurt';
      expect(splitNameEmoji(name), (emoji: null, name: name));
    });

    test('a name that is only an emoji leaves an empty name', () {
      expect(splitNameEmoji(' 🚀 '), (
        emoji: const NameEmoji.image('1f680'),
        name: '',
      ));
    });

    test('every key has its bundled image', () {
      final keys = twemojiKeys.split(' ');
      expect(keys.toSet(), hasLength(keys.length));
      final missing = keys
          .where((key) => !File('assets/emoji/$key.png').existsSync())
          .toList();
      expect(missing, isEmpty);
      expect(
        Directory('assets/emoji').listSync().whereType<File>(),
        hasLength(keys.length),
      );
    });
  });

  group('NameIcon', () {
    Future<void> pump(WidgetTester tester, Widget icon) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Center(child: icon),
      ),
    );

    String asset(WidgetTester tester) =>
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName;

    testWidgets('draws the emoji image', (tester) async {
      await pump(
        tester,
        const NameIcon(
          emoji: NameEmoji.image('1f3f3-200d-1f308'),
          countryCode: 'NL',
        ),
      );
      expect(asset(tester), 'assets/emoji/1f3f3-200d-1f308.png');
    });

    testWidgets('a flag emoji uses the bundled flag', (tester) async {
      await pump(
        tester,
        const NameIcon(emoji: NameEmoji.flag('EU'), countryCode: 'NL'),
      );
      expect(asset(tester), 'assets/flags/eu.png');
    });

    testWidgets('without an emoji shows the country flag', (tester) async {
      await pump(tester, const NameIcon(countryCode: 'DE'));
      expect(asset(tester), 'assets/flags/de.png');
    });
  });
}
