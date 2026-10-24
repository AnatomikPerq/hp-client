import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/manual_group_dialogs.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';

Future<ServerAction?> showServerActionsMenu(
  BuildContext context, {
  required String name,
  required String source,
  bool favorite = false,
  bool provider = false,
  bool canMove = false,
}) => showAppDialog<ServerAction>(
  context,
  (_) => ServerActionsMenu(
    name: name,
    source: source,
    favorite: favorite,
    provider: provider,
    canMove: canMove,
  ),
);

/// Desktop: the same actions as a popup next to the button that opened it.
Future<ServerAction?> showServerActionsPopup(
  BuildContext anchor, {
  bool favorite = false,
  bool provider = false,
  bool canMove = false,
}) {
  final l = AppLocalizations.of(anchor)!;
  return _popup<ServerAction>(anchor, [
    _popupItem(
      anchor,
      ServerAction.favorite,
      favorite ? LucideIcons.starOff : LucideIcons.star,
      favorite ? l.prototypeRemoveFavorite : l.prototypeAddFavorite,
    ),
    if (!provider)
      _popupItem(
        anchor,
        ServerAction.test,
        LucideIcons.gauge,
        l.prototypeTestAgain,
      ),
    _popupItem(
      anchor,
      ServerAction.edit,
      provider ? LucideIcons.fileJson : LucideIcons.pencil,
      provider ? l.providerViewConfiguration : l.prototypeEditServer,
    ),
    _popupItem(
      anchor,
      ServerAction.copy,
      LucideIcons.copy,
      provider ? l.providerCopyAsRaw : l.prototypeSaveAsLocalServer,
    ),
    _popupItem(
      anchor,
      ServerAction.share,
      LucideIcons.share2,
      provider ? l.prototypeShare : l.prototypeShareServer,
    ),
    if (canMove)
      _popupItem(
        anchor,
        ServerAction.move,
        LucideIcons.folderInput,
        l.manualGroupMove,
      ),
    const PopupMenuDivider(),
    _popupItem(
      anchor,
      ServerAction.delete,
      LucideIcons.trash2,
      l.prototypeDelete,
      destructive: true,
    ),
  ]);
}

Future<SourceAction?> showSourceActionsPopup(
  BuildContext anchor, {
  bool provider = false,
}) {
  final l = AppLocalizations.of(anchor)!;
  return _popup<SourceAction>(anchor, [
    _popupItem(
      anchor,
      SourceAction.update,
      LucideIcons.refreshCw,
      l.prototypeCheckForUpdates,
    ),
    if (!provider)
      _popupItem(
        anchor,
        SourceAction.test,
        LucideIcons.gauge,
        l.prototypeTestServers,
      ),
    _popupItem(
      anchor,
      SourceAction.edit,
      LucideIcons.pencil,
      l.prototypeEditSubscription,
    ),
    _popupItem(
      anchor,
      SourceAction.share,
      LucideIcons.share2,
      l.prototypeShareSubscription,
    ),
    const PopupMenuDivider(),
    _popupItem(
      anchor,
      SourceAction.delete,
      LucideIcons.trash2,
      l.prototypeDelete,
      destructive: true,
    ),
  ]);
}

/// Desktop: a section of the manual card, as a popup at its button.
Future<ManualGroupAction?> showManualGroupActionsPopup(
  BuildContext anchor, {
  required bool custom,
  required bool order,
}) {
  final l = AppLocalizations.of(anchor)!;
  return _popup<ManualGroupAction>(anchor, [
    if (order)
      _popupItem(
        anchor,
        ManualGroupAction.order,
        LucideIcons.listOrdered,
        l.manualServerOrder,
      ),
    if (custom) ...[
      _popupItem(
        anchor,
        ManualGroupAction.rename,
        LucideIcons.pencil,
        l.manualGroupRename,
      ),
      _popupItem(
        anchor,
        ManualGroupAction.dissolve,
        LucideIcons.folderMinus,
        l.manualGroupDissolve,
      ),
      const PopupMenuDivider(),
      _popupItem(
        anchor,
        ManualGroupAction.delete,
        LucideIcons.trash2,
        l.manualGroupDelete,
        destructive: true,
      ),
    ],
  ]);
}

Future<T?> _popup<T>(BuildContext anchor, List<PopupMenuEntry<T>> items) {
  final button = anchor.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(
        button.size.bottomLeft(Offset.zero),
        ancestor: overlay,
      ),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    ),
    Offset.zero & overlay.size,
  );
  final palette = ColorManager.palette(anchor);
  return showMenu<T>(
    context: anchor,
    position: position,
    color: palette.popover,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: BorderSide(color: palette.border),
    ),
    items: items,
  );
}

PopupMenuItem<T> _popupItem<T>(
  BuildContext context,
  T value,
  IconData icon,
  String title, {
  bool destructive = false,
}) {
  final palette = ColorManager.palette(context);
  final color = destructive ? palette.destructive : palette.foreground;
  return PopupMenuItem<T>(
    value: value,
    height: 40,
    child: Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: destructive ? palette.destructive : palette.mutedStrong,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            title,
            style: AppTypography.serverMenuTitle.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

Future<SourceAction?> showSourceActionsMenu(
  BuildContext context, {
  required String name,
  required int count,
  bool provider = false,
}) => showAppDialog<SourceAction>(
  context,
  (_) => SourceActionsMenu(name: name, count: count, provider: provider),
);

/// Selects an action only; the caller keeps the controller's existing workflow.
class ServerActionsMenu extends StatelessWidget {
  const ServerActionsMenu({
    super.key,
    required this.name,
    required this.source,
    this.favorite = false,
    this.provider = false,
    this.canMove = false,
  });

  final String name;
  final String source;
  final bool favorite;
  final bool provider;
  final bool canMove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      title: name,
      subtitle: source,
      body: Column(
        children: [
          _menuRow(
            context,
            ServerAction.favorite,
            favorite ? LucideIcons.starOff : LucideIcons.star,
            favorite ? l.prototypeRemoveFavorite : l.prototypeAddFavorite,
          ),
          _menuRow(
            context,
            ServerAction.edit,
            provider ? LucideIcons.fileJson : LucideIcons.pencil,
            provider ? l.providerViewConfiguration : l.prototypeEditServer,
          ),
          if (!provider)
            _menuRow(
              context,
              ServerAction.test,
              LucideIcons.refreshCw,
              l.prototypeTestAgain,
            ),
          _menuRow(
            context,
            ServerAction.copy,
            LucideIcons.copy,
            provider ? l.providerCopyAsRaw : l.prototypeSaveAsLocalServer,
            hint: provider ? l.providerCopyAsRawHint : l.prototypeLocalCopyHint,
          ),
          if (canMove)
            _menuRow(
              context,
              ServerAction.move,
              LucideIcons.folderInput,
              l.manualGroupMove,
            ),
          _menuRow(
            context,
            ServerAction.share,
            LucideIcons.share2,
            provider ? l.prototypeShare : l.prototypeShareServer,
          ),
          _menuRow(
            context,
            ServerAction.delete,
            LucideIcons.trash2,
            l.prototypeDelete,
            destructive: true,
          ),
        ],
      ),
    );
  }
}

class SourceActionsMenu extends StatelessWidget {
  const SourceActionsMenu({
    super.key,
    required this.name,
    required this.count,
    this.provider = false,
  });

  final String name;
  final int count;
  final bool provider;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      title: name,
      subtitle: provider
          ? l.providerConfigurationCount(count)
          : l.prototypeServerCount(count),
      body: Column(
        children: [
          _menuRow(
            context,
            SourceAction.update,
            LucideIcons.refreshCw,
            l.prototypeCheckForUpdates,
          ),
          if (!provider)
            _menuRow(
              context,
              SourceAction.test,
              LucideIcons.refreshCw,
              l.prototypeTestServers,
            ),
          _menuRow(
            context,
            SourceAction.edit,
            LucideIcons.pencil,
            l.prototypeEditSubscription,
          ),
          _menuRow(
            context,
            SourceAction.share,
            LucideIcons.share2,
            l.prototypeShareSubscription,
          ),
          _menuRow(
            context,
            SourceAction.delete,
            LucideIcons.trash2,
            l.prototypeDelete,
            destructive: true,
          ),
        ],
      ),
    );
  }
}

Widget _menuRow<T>(
  BuildContext context,
  T action,
  IconData icon,
  String title, {
  String? hint,
  bool destructive = false,
}) {
  final palette = ColorManager.palette(context);
  final textColor = destructive ? palette.destructive : palette.foreground;
  return Semantics(
    button: true,
    child: InkWell(
      onTap: () => Navigator.of(context).pop(action),
      hoverColor: palette.surfaceHover,
      child: Container(
        constraints: BoxConstraints(minHeight: hint == null ? 52 : 68),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          border: destructive
              ? null
              : Border(bottom: BorderSide(color: palette.border)),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: destructive ? palette.destructive : palette.primary,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(
                    title,
                    style: AppTypography.serverMenuTitle.copyWith(
                      color: textColor,
                    ),
                  ),
                  if (hint != null)
                    Text(
                      hint,
                      style: AppTypography.serverMenuHint.copyWith(
                        color: palette.mutedForeground,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 13),
            Icon(LucideIcons.arrowRightDir, size: 18, color: textColor),
          ],
        ),
      ),
    ),
  );
}
