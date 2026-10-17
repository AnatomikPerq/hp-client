import 'dart:async';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

/// The App's own window caption on Windows and Linux: the brand and version
/// on the left, the window buttons on the right. The empty part moves the
/// window and maximizes it on a double click, like a native caption.
///
/// It sits outside the Navigator, so there is no Overlay for tooltips; the
/// buttons carry semantic labels instead.
class DesktopCaption extends StatefulWidget {
  const DesktopCaption({super.key});

  static final Future<String> _version = PackageInfo.fromPlatform()
      .then((info) => info.version)
      .catchError((_) => '');

  @override
  State<DesktopCaption> createState() => _DesktopCaptionState();
}

class _DesktopCaptionState extends State<DesktopCaption> with WindowListener {
  var _maximized = false;
  var _focused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_readMaximized());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _readMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted && maximized != _maximized) {
        setState(() => _maximized = maximized);
      }
    } catch (_) {
      // No native window (tests); the maximize glyph stays.
    }
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void onWindowFocus() => setState(() => _focused = true);

  @override
  void onWindowBlur() => setState(() => _focused = false);

  Future<void> _toggleMaximized() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final l = AppLocalizations.of(context);
    return Directionality(
      // OS caption buttons stay on the right in RTL languages.
      textDirection: TextDirection.ltr,
      child: Material(
        // Above the Navigator there is no Material yet; without one, text
        // inherits the App's debug "missing Material" style.
        color: palette.header,
        shape: Border(
          bottom: BorderSide(
            color: palette.sidebarBorder.withValues(alpha: .55),
          ),
        ),
        child: AnimatedOpacity(
          // Inactive windows dim their caption, as Windows does.
          opacity: _focused ? 1 : .6,
          duration: const Duration(milliseconds: 120),
          child: Row(
            children: [
              Expanded(
                child: DragToMoveArea(
                  child: SizedBox.expand(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 16),
                      child: Row(
                        children: [
                          Text(
                            'HYPER CLIENT',
                            maxLines: 1,
                            style: AppTypography.windowCaptionBrand.copyWith(
                              color: palette.brand,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(child: _version(palette)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _CaptionButton(
                key: const ValueKey('desktop-caption-minimize'),
                icon: LucideIcons.minus,
                label: l?.windowMinimize,
                onPressed: windowManager.minimize,
              ),
              _CaptionButton(
                key: const ValueKey('desktop-caption-maximize'),
                icon: _maximized ? LucideIcons.copy : LucideIcons.square,
                iconSize: 13,
                label: _maximized ? l?.windowRestore : l?.windowMaximize,
                onPressed: _toggleMaximized,
              ),
              _CaptionButton(
                key: const ValueKey('desktop-caption-close'),
                icon: LucideIcons.x,
                iconSize: 17,
                label: l?.windowClose,
                close: true,
                // The window service hides to the tray instead of quitting.
                onPressed: windowManager.close,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _version(AppPalette palette) => FutureBuilder<String>(
    future: DesktopCaption._version,
    builder: (context, snapshot) {
      final version = snapshot.data ?? '';
      if (version.isEmpty) return const SizedBox.shrink();
      return Text(
        'v$version',
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: AppTypography.windowCaptionVersion.copyWith(
          color: palette.mutedForeground,
        ),
      );
    },
  );
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.label,
    this.iconSize = 16,
    this.close = false,
  });

  final IconData icon;
  final double iconSize;
  final String? label;
  final bool close;
  final Future<void> Function() onPressed;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final active = _hovered || _pressed;
    final background = !active
        ? Colors.transparent
        : widget.close
        ? (_pressed ? palette.destructiveSolidHover : palette.destructiveSolid)
        : (_pressed ? palette.accent : palette.surfaceHover);
    final foreground = widget.close && active
        ? palette.destructiveForeground
        : active
        ? palette.foreground
        : palette.mutedStrong;
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            setState(() => _pressed = false);
            unawaited(widget.onPressed());
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: AppLayout.desktopCaptionButtonWidth,
            height: double.infinity,
            color: background,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: foreground),
          ),
        ),
      ),
    );
  }
}
