import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/constants.dart';

@immutable
class AppPalette {
  // The confirmation overlay is shared by both prototype themes.
  static const restoreOverlay = Color.fromRGBO(5, 12, 30, 0.4);

  const AppPalette({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.popover,
    required this.popoverForeground,
    required this.primary,
    required this.primaryHover,
    required this.primarySolid,
    required this.primarySolidHover,
    required this.primaryForeground,
    required this.surfaceHover,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.mutedStrong,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.destructiveSolid,
    required this.destructiveSolidHover,
    required this.destructiveForeground,
    required this.border,
    required this.borderStrong,
    required this.input,
    required this.ring,
    required this.selection,
    required this.scannerBackground,
    required this.overlay,
    required this.header,
    required this.brand,
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
    required this.warningSurface,
    required this.destructiveSurface,
    required this.chart1,
    required this.chart2,
    required this.chart3,
    required this.chart4,
    required this.chart5,
  });

  // HYPER CLIENT space palette. Cyan leads interaction (links, buttons,
  // focus); yellow is the brand and the "connected" state. Yellow is used as
  // a fill with dark text, never as text on the light background.
  static const light = AppPalette(
    background: Color(0xFFF6F9FE),
    foreground: Color(0xFF0B1220),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF0B1220),
    popover: Color(0xFFFFFFFF),
    popoverForeground: Color(0xFF0B1220),
    primary: Color(0xFF0877B5),
    primaryHover: Color(0xFF066497),
    primarySolid: Color(0xFF0877B5),
    primarySolidHover: Color(0xFF066497),
    primaryForeground: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFEEF4FB),
    secondary: Color(0xFFEDF3FA),
    secondaryForeground: Color(0xFF16202E),
    muted: Color(0xFFEDF3FA),
    mutedForeground: Color(0xFF5A6779),
    mutedStrong: Color(0xFF465366),
    accent: Color(0xFFE2F1FB),
    accentForeground: Color(0xFF0A6FA8),
    destructive: Color(0xFFDC2B33),
    destructiveSolid: Color(0xFFDC2B33),
    destructiveSolidHover: Color(0xFFC0222A),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFFD6DFEA),
    borderStrong: Color(0xFFC4D0DE),
    input: Color(0xFFD6DFEA),
    ring: Color(0xFF0877B5),
    selection: Color(0xFFCBE7F8),
    scannerBackground: Color(0xFF05080F),
    overlay: Color.fromRGBO(5, 8, 15, 0.48),
    header: Color(0xFFF9FBFE),
    brand: Color(0xFF0B2A4A),
    sidebar: Color(0xFFF2F7FC),
    sidebarForeground: Color(0xFF16202E),
    sidebarPrimary: Color(0xFF0877B5),
    sidebarPrimaryForeground: Color(0xFFFFFFFF),
    sidebarAccent: Color(0xFFDFEEF9),
    sidebarAccentForeground: Color(0xFF0C3550),
    sidebarBorder: Color(0xFFD6DFEA),
    sidebarRing: Color(0xFF0877B5),
    selectedSurface: Color(0xFFEFF7FE),
    running: Color(0xFFE0A400),
    runningText: Color(0xFF8F6200),
    runningBadge: Color(0xFF8F6200),
    runningBadgeForeground: Color(0xFFFFFFFF),
    runningForeground: Color(0xFF0B1220),
    runningSurface: Color(0xFFFDF8E8),
    restarting: Color(0xFFE07B18),
    restartingText: Color(0xFFA34F00),
    warningSurface: Color(0xFFFFF4E5),
    destructiveSurface: Color(0xFFFDEDEE),
    chart1: Color(0xFF0877B5),
    chart2: Color(0xFFE0A400),
    chart3: Color(0xFF7C5CE0),
    chart4: Color(0xFFE0475A),
    chart5: Color(0xFF14A88A),
  );

  // The dark theme is the primary one: deep navy with a cyan accent.
  static const dark = AppPalette(
    background: Color(0xFF060A14),
    foreground: Color(0xFFE8EEF7),
    card: Color(0xFF0D1424),
    cardForeground: Color(0xFFE8EEF7),
    popover: Color(0xFF0D1424),
    popoverForeground: Color(0xFFE8EEF7),
    primary: Color(0xFF4CC9F0),
    primaryHover: Color(0xFF7AD8F5),
    primarySolid: Color(0xFF0A75B0),
    primarySolidHover: Color(0xFF08689C),
    primaryForeground: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFF16203A),
    secondary: Color(0xFF182236),
    secondaryForeground: Color(0xFFE3EAF5),
    muted: Color(0xFF141C2C),
    mutedForeground: Color(0xFF93A3BC),
    mutedStrong: Color(0xFFB9C6D8),
    accent: Color(0xFF1B2942),
    accentForeground: Color(0xFF7AD8F5),
    destructive: Color(0xFFFF5F6D),
    destructiveSolid: Color(0xFFDC2B33),
    destructiveSolidHover: Color(0xFFC0222A),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFF25324A),
    borderStrong: Color(0xFF2C3A52),
    input: Color(0xFF25324A),
    ring: Color(0xFF4CC9F0),
    selection: Color(0xFF1C3450),
    scannerBackground: Color(0xFF05080F),
    overlay: Color.fromRGBO(2, 5, 12, 0.56),
    header: Color(0xFF070C16),
    brand: Color(0xFFFFC93C),
    sidebar: Color(0xFF0A1020),
    sidebarForeground: Color(0xFFE3EAF5),
    sidebarPrimary: Color(0xFF4CC9F0),
    sidebarPrimaryForeground: Color(0xFF04121B),
    sidebarAccent: Color(0xFF16233A),
    sidebarAccentForeground: Color(0xFFCFE6FF),
    sidebarBorder: Color(0xFF25324A),
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
    warningSurface: Color(0xFF2E2112),
    destructiveSurface: Color(0xFF3A1A22),
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
  final Color primaryHover;
  final Color primarySolid;
  final Color primarySolidHover;
  // Foregrounds pair with solid fills, not the dark theme's interactive colors.
  final Color primaryForeground;
  final Color surfaceHover;
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color mutedStrong;
  final Color accent;
  final Color accentForeground;
  final Color destructive;
  final Color destructiveSolid;
  final Color destructiveSolidHover;
  final Color destructiveForeground;
  final Color border;
  final Color borderStrong;
  final Color input;
  final Color ring;
  final Color selection;
  final Color scannerBackground;
  final Color overlay;
  final Color header;
  final Color sidebar;
  final Color brand;
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
  final Color warningSurface;
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
      primaryHover: color(begin.primaryHover, end.primaryHover),
      primarySolid: color(begin.primarySolid, end.primarySolid),
      primarySolidHover: color(begin.primarySolidHover, end.primarySolidHover),
      primaryForeground: color(begin.primaryForeground, end.primaryForeground),
      surfaceHover: color(begin.surfaceHover, end.surfaceHover),
      secondary: color(begin.secondary, end.secondary),
      secondaryForeground: color(
        begin.secondaryForeground,
        end.secondaryForeground,
      ),
      muted: color(begin.muted, end.muted),
      mutedForeground: color(begin.mutedForeground, end.mutedForeground),
      mutedStrong: color(begin.mutedStrong, end.mutedStrong),
      accent: color(begin.accent, end.accent),
      accentForeground: color(begin.accentForeground, end.accentForeground),
      destructive: color(begin.destructive, end.destructive),
      destructiveSolid: color(begin.destructiveSolid, end.destructiveSolid),
      destructiveSolidHover: color(
        begin.destructiveSolidHover,
        end.destructiveSolidHover,
      ),
      destructiveForeground: color(
        begin.destructiveForeground,
        end.destructiveForeground,
      ),
      border: color(begin.border, end.border),
      borderStrong: color(begin.borderStrong, end.borderStrong),
      input: color(begin.input, end.input),
      ring: color(begin.ring, end.ring),
      selection: color(begin.selection, end.selection),
      scannerBackground: color(begin.scannerBackground, end.scannerBackground),
      overlay: color(begin.overlay, end.overlay),
      header: color(begin.header, end.header),
      sidebar: color(begin.sidebar, end.sidebar),
      brand: color(begin.brand, end.brand),
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
      warningSurface: color(begin.warningSurface, end.warningSurface),
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

  Color get surface => palette.card;
  Color get surfaceBorder => palette.border;
  Color get primaryText => palette.foreground;
  Color get secondaryText => palette.mutedForeground;
  Color get tagBackground => palette.muted;
  Color get selectedBackground => palette.selectedSurface;

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

  static Color surface(BuildContext context) => tokens(context).surface;

  static Color primaryText(BuildContext context) => tokens(context).primaryText;

  static Color secondaryText(BuildContext context) {
    return tokens(context).secondaryText;
  }

  static Color nodeLatency(BuildContext context, int delay) {
    final colors = palette(context);
    if (!PingDelayConstants.isSuccessful(delay)) return colors.mutedForeground;
    // These tones remain legible as small text on normal and selected cards.
    return delay <= 500
        ? colors.runningBadge
        : delay <= 1000
        ? colors.restartingText
        : colors.primaryHover;
  }

  static Color tagBackground(BuildContext context) {
    return tokens(context).tagBackground;
  }

  static Color border(BuildContext context) => tokens(context).surfaceBorder;

  static Color selected(BuildContext context) {
    return tokens(context).selectedBackground;
  }
}
