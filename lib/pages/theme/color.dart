import 'package:flutter/material.dart';

@immutable
class AppPalette {
  const AppPalette({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.popover,
    required this.popoverForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.border,
    required this.input,
    required this.ring,
    required this.selection,
    required this.scannerBackground,
    required this.header,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarPrimary,
    required this.sidebarPrimaryForeground,
    required this.sidebarAccent,
    required this.sidebarAccentForeground,
    required this.sidebarBorder,
    required this.sidebarRing,
    required this.selectedSurface,
    required this.running,
    required this.runningText,
    required this.runningBadge,
    required this.runningBadgeForeground,
    required this.runningForeground,
    required this.runningSurface,
    required this.restarting,
    required this.restartingText,
    required this.destructiveSurface,
    required this.chart1,
    required this.chart2,
    required this.chart3,
    required this.chart4,
    required this.chart5,
  });

  // HYPER CLIENT — космическая тема.
  // Голубой ведёт интерактив (ссылки, кнопки, фокус), жёлтый — бренд и
  // состояние «подключено». Жёлтый используется заливками с тёмным текстом,
  // а не как цвет текста: на светлом фоне он нечитаем.
  static const light = AppPalette(
    background: Color(0xFFF6F9FE),
    foreground: Color(0xFF0B1220),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF0B1220),
    popover: Color(0xFFFFFFFF),
    popoverForeground: Color(0xFF0B1220),
    primary: Color(0xFF0A84C7),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFFEDF3FA),
    secondaryForeground: Color(0xFF16202E),
    muted: Color(0xFFEDF3FA),
    mutedForeground: Color(0xFF5A6779),
    accent: Color(0xFFE2F1FB),
    accentForeground: Color(0xFF0C3550),
    destructive: Color(0xFFDC2B33),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFFD6DFEA),
    input: Color(0xFFD6DFEA),
    ring: Color(0xFF0A84C7),
    selection: Color(0xFFCBE7F8),
    scannerBackground: Color(0xFF05080F),
    header: Color(0xFFF9FBFE),
    sidebar: Color(0xFFF2F7FC),
    sidebarForeground: Color(0xFF16202E),
    sidebarPrimary: Color(0xFF0A84C7),
    sidebarPrimaryForeground: Color(0xFFFFFFFF),
    sidebarAccent: Color(0xFFDFEEF9),
    sidebarAccentForeground: Color(0xFF0C3550),
    sidebarBorder: Color(0xFFD6DFEA),
    sidebarRing: Color(0xFF0A84C7),
    selectedSurface: Color(0xFFEFF7FE),
    running: Color(0xFFE0A400),
    runningText: Color(0xFFA97400),
    runningBadge: Color(0xFFE0A400),
    runningBadgeForeground: Color(0xFF1A1200),
    runningForeground: Color(0xFF0B1220),
    runningSurface: Color(0xFFFDF8E8),
    restarting: Color(0xFFE07B18),
    restartingText: Color(0xFFC25E00),
    destructiveSurface: Color(0x1ADC2B33),
    chart1: Color(0xFF0A84C7),
    chart2: Color(0xFFE0A400),
    chart3: Color(0xFF7C5CE0),
    chart4: Color(0xFFE0475A),
    chart5: Color(0xFF14A88A),
  );

  static const dark = AppPalette(
    background: Color(0xFF060A14),
    foreground: Color(0xFFE8EEF7),
    card: Color(0xFF0D1424),
    cardForeground: Color(0xFFE8EEF7),
    popover: Color(0xFF0D1424),
    popoverForeground: Color(0xFFE8EEF7),
    primary: Color(0xFF4CC9F0),
    primaryForeground: Color(0xFF04121B),
    secondary: Color(0xFF182236),
    secondaryForeground: Color(0xFFE3EAF5),
    muted: Color(0xFF141C2C),
    mutedForeground: Color(0xFF93A3BC),
    accent: Color(0xFF1B2942),
    accentForeground: Color(0xFFCFE6FF),
    destructive: Color(0xFFFF5F6D),
    destructiveForeground: Color(0xFF170406),
    border: Color(0x1FFFFFFF),
    input: Color(0x29FFFFFF),
    ring: Color(0xFF4CC9F0),
    selection: Color(0xFF1C3450),
    scannerBackground: Color(0xFF05080F),
    header: Color(0xFF070C16),
    sidebar: Color(0xFF0A1020),
    sidebarForeground: Color(0xFFE3EAF5),
    sidebarPrimary: Color(0xFF4CC9F0),
    sidebarPrimaryForeground: Color(0xFF04121B),
    sidebarAccent: Color(0xFF16233A),
    sidebarAccentForeground: Color(0xFFCFE6FF),
    sidebarBorder: Color(0x1AFFFFFF),
    sidebarRing: Color(0xFF4CC9F0),
    selectedSurface: Color(0xFF121D30),
    running: Color(0xFFFFC93C),
    runningText: Color(0xFFFFD75E),
    runningBadge: Color(0xFFFFC93C),
    runningBadgeForeground: Color(0xFF1A1200),
    runningForeground: Color(0xFF04121B),
    runningSurface: Color(0xFF1E1A0C),
    restarting: Color(0xFFFF9F43),
    restartingText: Color(0xFFFFB067),
    destructiveSurface: Color(0x33FF5F6D),
    chart1: Color(0xFF4CC9F0),
    chart2: Color(0xFFFFC93C),
    chart3: Color(0xFF9D7BFF),
    chart4: Color(0xFFFF7B8A),
    chart5: Color(0xFF57E0C0),
  );

  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color popover;
  final Color popoverForeground;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color accentForeground;
  final Color destructive;
  final Color destructiveForeground;
  final Color border;
  final Color input;
  final Color ring;
  final Color selection;
  final Color scannerBackground;
  final Color header;
  final Color sidebar;
  final Color sidebarForeground;
  final Color sidebarPrimary;
  final Color sidebarPrimaryForeground;
  final Color sidebarAccent;
  final Color sidebarAccentForeground;
  final Color sidebarBorder;
  final Color sidebarRing;
  final Color selectedSurface;
  final Color running;
  final Color runningText;
  final Color runningBadge;
  final Color runningBadgeForeground;
  final Color runningForeground;
  final Color runningSurface;
  final Color restarting;
  final Color restartingText;
  final Color destructiveSurface;
  final Color chart1;
  final Color chart2;
  final Color chart3;
  final Color chart4;
  final Color chart5;

  static AppPalette lerp(AppPalette begin, AppPalette end, double t) {
    Color color(Color a, Color b) => Color.lerp(a, b, t) ?? b;

    return AppPalette(
      background: color(begin.background, end.background),
      foreground: color(begin.foreground, end.foreground),
      card: color(begin.card, end.card),
      cardForeground: color(begin.cardForeground, end.cardForeground),
      popover: color(begin.popover, end.popover),
      popoverForeground: color(begin.popoverForeground, end.popoverForeground),
      primary: color(begin.primary, end.primary),
      primaryForeground: color(begin.primaryForeground, end.primaryForeground),
      secondary: color(begin.secondary, end.secondary),
      secondaryForeground: color(
        begin.secondaryForeground,
        end.secondaryForeground,
      ),
      muted: color(begin.muted, end.muted),
      mutedForeground: color(begin.mutedForeground, end.mutedForeground),
      accent: color(begin.accent, end.accent),
      accentForeground: color(begin.accentForeground, end.accentForeground),
      destructive: color(begin.destructive, end.destructive),
      destructiveForeground: color(
        begin.destructiveForeground,
        end.destructiveForeground,
      ),
      border: color(begin.border, end.border),
      input: color(begin.input, end.input),
      ring: color(begin.ring, end.ring),
      selection: color(begin.selection, end.selection),
      scannerBackground: color(begin.scannerBackground, end.scannerBackground),
      header: color(begin.header, end.header),
      sidebar: color(begin.sidebar, end.sidebar),
      sidebarForeground: color(begin.sidebarForeground, end.sidebarForeground),
      sidebarPrimary: color(begin.sidebarPrimary, end.sidebarPrimary),
      sidebarPrimaryForeground: color(
        begin.sidebarPrimaryForeground,
        end.sidebarPrimaryForeground,
      ),
      sidebarAccent: color(begin.sidebarAccent, end.sidebarAccent),
      sidebarAccentForeground: color(
        begin.sidebarAccentForeground,
        end.sidebarAccentForeground,
      ),
      sidebarBorder: color(begin.sidebarBorder, end.sidebarBorder),
      sidebarRing: color(begin.sidebarRing, end.sidebarRing),
      selectedSurface: color(begin.selectedSurface, end.selectedSurface),
      running: color(begin.running, end.running),
      runningText: color(begin.runningText, end.runningText),
      runningBadge: color(begin.runningBadge, end.runningBadge),
      runningBadgeForeground: color(
        begin.runningBadgeForeground,
        end.runningBadgeForeground,
      ),
      runningForeground: color(begin.runningForeground, end.runningForeground),
      runningSurface: color(begin.runningSurface, end.runningSurface),
      restarting: color(begin.restarting, end.restarting),
      restartingText: color(begin.restartingText, end.restartingText),
      destructiveSurface: color(
        begin.destructiveSurface,
        end.destructiveSurface,
      ),
      chart1: color(begin.chart1, end.chart1),
      chart2: color(begin.chart2, end.chart2),
      chart3: color(begin.chart3, end.chart3),
      chart4: color(begin.chart4, end.chart4),
      chart5: color(begin.chart5, end.chart5),
    );
  }
}

class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens(this.palette);

  static const light = AppColorTokens(AppPalette.light);
  static const dark = AppColorTokens(AppPalette.dark);

  final AppPalette palette;

  Color get pageBackground => palette.background;
  Color get surface => palette.card;
  Color get surfaceBorder => palette.border;
  Color get primaryText => palette.foreground;
  Color get secondaryText => palette.mutedForeground;
  Color get tagBackground => palette.muted;
  Color get selectedBackground => palette.selectedSurface;
  Color get runningBackground => palette.runningSurface;
  Color get stopButtonBackground => palette.destructiveSurface;
  Color get stopButtonForeground => palette.destructive;
  Color get sectionTitle => palette.mutedForeground;
  Color get interactiveText => palette.primary;
  Color get secondaryButtonBackground => palette.secondary;
  Color get secondaryButtonForeground => palette.secondaryForeground;

  static AppColorTokens fallback(Brightness brightness) {
    return brightness == Brightness.light ? light : dark;
  }

  @override
  AppColorTokens copyWith({AppPalette? palette}) {
    return AppColorTokens(palette ?? this.palette);
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) {
      return this;
    }
    return AppColorTokens(AppPalette.lerp(palette, other.palette, t));
  }
}

class ColorManager {
  static AppColorTokens tokens(BuildContext context) {
    return Theme.of(context).extension<AppColorTokens>() ??
        AppColorTokens.fallback(Theme.of(context).brightness);
  }

  static AppPalette palette(BuildContext context) => tokens(context).palette;

  static Color scaffoldBackground(Brightness brightness) {
    return AppColorTokens.fallback(brightness).pageBackground;
  }

  static Color surface(BuildContext context) => tokens(context).surface;

  static Color primaryText(BuildContext context) => tokens(context).primaryText;

  static Color secondaryText(BuildContext context) {
    return tokens(context).secondaryText;
  }

  static Color tagBackground(BuildContext context) {
    return tokens(context).tagBackground;
  }

  static Color border(BuildContext context) => tokens(context).surfaceBorder;

  static Color selected(BuildContext context) {
    return tokens(context).selectedBackground;
  }

  static Color running(BuildContext context) {
    return tokens(context).runningBackground;
  }

  static Color buttonStop(BuildContext context) {
    return tokens(context).stopButtonBackground;
  }

  static Color buttonStopForeground(BuildContext context) {
    return tokens(context).stopButtonForeground;
  }

  static Color sectionTitle(BuildContext context) {
    return tokens(context).sectionTitle;
  }

  static Color interactiveText(BuildContext context) {
    return tokens(context).interactiveText;
  }

  static Color formTitle(BuildContext context) {
    return interactiveText(context);
  }

  static Color secondaryButtonBackground(BuildContext context) {
    return tokens(context).secondaryButtonBackground;
  }

  static Color secondaryButtonForeground(BuildContext context) {
    return tokens(context).secondaryButtonForeground;
  }
}
