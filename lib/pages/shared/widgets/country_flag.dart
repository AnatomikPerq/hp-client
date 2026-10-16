import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';

const _regionalA = 0x1F1E6;
const _regionalZ = 0x1F1FF;

bool _regional(int rune) => rune >= _regionalA && rune <= _regionalZ;

/// A server name with its emoji flags taken out.
///
/// Windows has no glyphs for regional-indicator flags and prints the letters
/// of the code instead ("NL"), so lists draw the first flag as an image and
/// drop every flag from the text. [name] is empty when the name was only a
/// flag; callers fall back to the country name then.
({String? code, String name}) splitFlagEmoji(String value) {
  String? code;
  final kept = <int>[];
  final runes = value.runes.toList();
  for (var index = 0; index < runes.length; index++) {
    final rune = runes[index];
    if (_regional(rune) &&
        index + 1 < runes.length &&
        _regional(runes[index + 1])) {
      code ??= String.fromCharCodes([
        rune - _regionalA + 0x41,
        runes[index + 1] - _regionalA + 0x41,
      ]);
      index++;
      continue;
    }
    kept.add(rune);
  }
  if (code == null) return (code: null, name: value);
  final name = String.fromCharCodes(kept).replaceAll(RegExp(r'\s{2,}'), ' ');
  return (code: code, name: name.trim());
}

/// A country flag from the bundled Twemoji set, or a globe when unknown.
///
/// Decorative: the row text already names the server or country.
class CountryFlag extends StatelessWidget {
  const CountryFlag({super.key, required this.code, this.size = 22});

  final String? code;
  final double size;

  static final _valid = RegExp(r'^[A-Za-z]{2}$');

  @override
  Widget build(BuildContext context) {
    final value = code;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: value == null || !_valid.hasMatch(value)
            ? _globe(context)
            : Image.asset(
                'assets/flags/${value.toLowerCase()}.png',
                width: size,
                height: size,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, _, _) => _letters(context, value),
              ),
      ),
    );
  }

  Widget _globe(BuildContext context) => Center(
    child: Icon(
      LucideIcons.globe,
      size: size * .72,
      color: ColorManager.palette(context).mutedForeground,
    ),
  );

  Widget _letters(BuildContext context, String value) => Center(
    child: FittedBox(
      child: Text(
        value.toUpperCase(),
        textDirection: TextDirection.ltr,
        style: AppTypography.badge.copyWith(
          color: ColorManager.palette(context).mutedStrong,
        ),
      ),
    ),
  );
}
