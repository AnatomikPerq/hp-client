import 'package:flutter/foundation.dart';
import 'package:onexray/pages/shared/widgets/twemoji_keys.dart';

const _regionalA = 0x1F1E6;
const _regionalZ = 0x1F1FF;
const _variation = 0xFE0F;
const _joiner = 0x200D;

bool _regional(int rune) => rune >= _regionalA && rune <= _regionalZ;

/// Parts of an emoji that may follow a matched image without one of their
/// own: the variation selector, keycap, skin tones and flag tags.
bool _trailing(int rune) =>
    rune == _variation ||
    rune == 0x20E3 ||
    (rune >= 0x1F3FB && rune <= 0x1F3FF) ||
    (rune >= 0xE0020 && rune <= 0xE007F);

/// Below U+2000 only keycap bases, © and ® start an emoji.
bool _mayStart(int rune) =>
    rune >= 0x2000 ||
    rune == 0x23 ||
    rune == 0x2A ||
    (rune >= 0x30 && rune <= 0x39) ||
    rune == 0xA9 ||
    rune == 0xAE;

/// BMP symbols drawn as emoji even without U+FE0F (`Emoji_Presentation`).
/// Others, such as © or ☢, are text unless U+FE0F follows them, so a name
/// like "© Provider" keeps its characters.
const _presentationRanges = <(int, int)>[
  (0x231A, 0x231B),
  (0x23E9, 0x23EC),
  (0x23F0, 0x23F0),
  (0x23F3, 0x23F3),
  (0x25FD, 0x25FE),
  (0x2614, 0x2615),
  (0x2648, 0x2653),
  (0x267F, 0x267F),
  (0x2693, 0x2693),
  (0x26A1, 0x26A1),
  (0x26AA, 0x26AB),
  (0x26BD, 0x26BE),
  (0x26C4, 0x26C5),
  (0x26CE, 0x26CE),
  (0x26D4, 0x26D4),
  (0x26EA, 0x26EA),
  (0x26F2, 0x26F3),
  (0x26F5, 0x26F5),
  (0x26FA, 0x26FA),
  (0x26FD, 0x26FD),
  (0x2705, 0x2705),
  (0x270A, 0x270B),
  (0x2728, 0x2728),
  (0x274C, 0x274C),
  (0x274E, 0x274E),
  (0x2753, 0x2755),
  (0x2757, 0x2757),
  (0x2795, 0x2797),
  (0x27B0, 0x27B0),
  (0x27BF, 0x27BF),
  (0x2B1B, 0x2B1C),
  (0x2B50, 0x2B50),
  (0x2B55, 0x2B55),
];

bool _emojiByDefault(int rune) =>
    rune > 0xFFFF ||
    _presentationRanges.any((range) => rune >= range.$1 && rune <= range.$2);

final Set<String> _keys = twemojiKeys.split(' ').toSet();

/// An emoji from a name, drawn from the bundled Twemoji images.
@immutable
final class NameEmoji {
  /// A country flag, by its two-letter code in upper case.
  const NameEmoji.flag(String this.country) : key = null;

  /// Any other emoji, by its key in [twemojiKeys].
  const NameEmoji.image(String this.key) : country = null;

  final String? country;
  final String? key;

  /// `null` for a flag; `CountryFlag` draws those by [country].
  String? get asset => key == null ? null : 'assets/emoji/$key.png';

  @override
  bool operator ==(Object other) =>
      other is NameEmoji && other.country == country && other.key == key;

  @override
  int get hashCode => Object.hash(country, key);

  @override
  String toString() => 'NameEmoji(${country ?? key})';
}

typedef NameEmojiSplit = ({NameEmoji? emoji, String name});

final _cache = <String, NameEmojiSplit>{};

/// A name with its first emoji taken out, to draw that emoji as the icon.
///
/// Providers mark servers with an emoji ("🏳️‍🌈 Reserve", "🇳🇱 Main").
/// Country flags elsewhere in the name are dropped as well: Windows has no
/// glyphs for them and prints the letters of the code ("NL"). Other emoji
/// stay in the text. [NameEmojiSplit.name] is empty when the name was only
/// emoji; callers fall back to something else then.
NameEmojiSplit splitNameEmoji(String value) {
  final cached = _cache[value];
  if (cached != null) return cached;
  // Lists rebuild often with the same names; the bound only guards against
  // unbounded growth across subscription updates.
  if (_cache.length >= 2048) _cache.clear();
  return _cache[value] = _split(value);
}

NameEmojiSplit _split(String value) {
  final runes = value.runes.toList();
  NameEmoji? emoji;
  final kept = <int>[];
  var index = 0;
  while (index < runes.length) {
    final rune = runes[index];
    if (_regional(rune) &&
        index + 1 < runes.length &&
        _regional(runes[index + 1])) {
      emoji ??= NameEmoji.flag(
        String.fromCharCodes([
          rune - _regionalA + 0x41,
          runes[index + 1] - _regionalA + 0x41,
        ]),
      );
      index += 2;
      continue;
    }
    if (emoji == null) {
      final match = _matchAt(runes, index);
      if (match != null) {
        emoji = NameEmoji.image(match.key);
        index = match.end;
        continue;
      }
    }
    kept.add(rune);
    index++;
  }
  if (emoji == null) return (emoji: null, name: value);
  final name = String.fromCharCodes(kept).replaceAll(RegExp(r'\s{2,}'), ' ');
  return (emoji: emoji, name: name.trim());
}

/// The longest bundled emoji starting at [start], ignoring U+FE0F.
({String key, int end})? _matchAt(List<int> runes, int start) {
  final first = runes[start];
  if (!_mayStart(first) || first == _variation || first == _joiner) {
    return null;
  }
  final buffer = StringBuffer();
  var count = 0;
  String? key;
  var end = start;
  for (
    var index = start;
    index < runes.length && count < twemojiMaxLength;
    index++
  ) {
    final rune = runes[index];
    if (rune == _variation) continue;
    if (count > 0) buffer.write('-');
    buffer.write(rune.toRadixString(16));
    count++;
    final candidate = buffer.toString();
    if (_keys.contains(candidate)) {
      key = candidate;
      end = index + 1;
    }
  }
  if (key == null) return null;
  final presented = end < runes.length && runes[end] == _variation;
  if (!key.contains('-') && !presented && !_emojiByDefault(first)) {
    return null;
  }
  // A sequence newer than the bundled set still leaves the text whole: its
  // remaining joined parts go with the image of its first part.
  while (end < runes.length) {
    final rune = runes[end];
    if (_trailing(rune)) {
      end++;
    } else if (rune == _joiner && end + 1 < runes.length) {
      end += 2;
    } else {
      break;
    }
  }
  return (key: key, end: end);
}
