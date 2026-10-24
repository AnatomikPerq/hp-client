import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/view.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/service/connect/settings.dart';

/// Home's server list: automatic choice, favorites and the subscription that
/// holds the current selection, with the same rows and menus as Servers.
class HomeServerList extends StatelessWidget {
  const HomeServerList({super.key, required this.controller});

  final ServersController controller;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ServersController, ServersPageState>(
        bloc: controller,
        builder: (context, state) {
          if (!state.ready || state.failed || state.servers.isEmpty) {
            return const SizedBox.shrink();
          }
          final l = AppLocalizations.of(context)!;
          final group = controller.homeGroup(l);
          final favorites = state.servers.where((row) => row.favorite).toList();
          return Column(
            key: const ValueKey('home-server-list'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ServerAutomaticTile(controller: controller),
              if (favorites.isNotEmpty) ...[
                const SizedBox(height: 10),
                ServerGroupCard(
                  controller: controller,
                  favorites: true,
                  group: ServerGroup(
                    id: 'favorites',
                    name: l.prototypeFavorites,
                    selection: const ServerSelection.automatic(),
                    rows: favorites,
                    visibleRows: favorites,
                  ),
                ),
              ],
              if (group != null) ...[
                _heading(
                  context,
                  group.source == null
                      ? l.prototypeServers
                      : l.homeCurrentSubscription,
                ),
                ServerGroupCard(
                  controller: controller,
                  group: group,
                  organize: false,
                ),
              ],
            ],
          );
        },
      );

  Widget _heading(BuildContext context, String title) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(4, 16, 4, 8),
    child: Text(
      title.toUpperCase(),
      style: AppTypography.listSection.copyWith(
        color: ColorManager.palette(context).mutedForeground,
      ),
    ),
  );
}
