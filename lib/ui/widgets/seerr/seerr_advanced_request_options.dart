import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../l10n/app_localizations.dart';

/// Holds the Radarr/Sonarr server, profile, and root folder selection for a
/// request, including the saved-preference and anime defaults. Shared by the
/// single request dialog and the collection request sheet.
class SeerrAdvancedRequestController extends ChangeNotifier {
  final bool isTv;
  final bool isAnime;

  List<SeerrServiceServerDetails>? servers;
  bool loading = false;

  int? selectedServerId;
  int? selectedProfileId;
  int? selectedRootFolderId;

  String? _savedServerId;
  String? _savedProfileId;
  String? _savedRootFolderId;

  SeerrAdvancedRequestController({required this.isTv, this.isAnime = false});

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      if (isTv) {
        final sonarrServers = await repo.getSonarrServers();
        servers = await Future.wait(
          sonarrServers.map((s) => repo.getSonarrServerDetails(s.id)),
        );
      } else {
        final radarrServers = await repo.getRadarrServers();
        servers = await Future.wait(
          radarrServers.map((s) => repo.getRadarrServerDetails(s.id)),
        );
      }
      _applySavedPreferences();
    } catch (_) {
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Called on init and whenever the 4K toggle flips, with the saved defaults
  /// for the now-active flavor.
  void applySavedPreferences({
    String? serverId,
    String? profileId,
    String? rootFolderId,
    bool resetSelection = false,
  }) {
    _savedServerId = serverId;
    _savedProfileId = profileId;
    _savedRootFolderId = rootFolderId;
    if (resetSelection) {
      selectedProfileId = null;
      selectedRootFolderId = null;
    }
    _applySavedPreferences();
    notifyListeners();
  }

  void _applySavedPreferences() {
    if (_savedServerId != null && _savedServerId!.isNotEmpty) {
      selectedServerId ??= int.tryParse(_savedServerId!);
    }
    if (_savedProfileId != null && _savedProfileId!.isNotEmpty) {
      selectedProfileId ??= int.tryParse(_savedProfileId!);
    }
    if (_savedRootFolderId != null && _savedRootFolderId!.isNotEmpty) {
      selectedRootFolderId ??= int.tryParse(_savedRootFolderId!);
    }
    _applyServerDefaults();
  }

  void _applyServerDefaults() {
    final server = activeServer;
    if (server == null) return;
    selectedServerId ??= server.server.id;

    final int? animeProfileId = server.server.activeAnimeProfileId;
    final String? animeDir = server.server.activeAnimeDirectory;

    if (isAnime && animeProfileId != null) {
      selectedProfileId ??= animeProfileId;
    } else {
      selectedProfileId ??= server.server.activeProfileId;
    }

    final String dir;
    if (isAnime && animeDir != null && animeDir.isNotEmpty) {
      dir = animeDir;
    } else {
      dir = server.server.activeDirectory;
    }

    if (selectedRootFolderId == null && dir.isNotEmpty) {
      final match = server.rootFolders.where((f) => f.path == dir).firstOrNull;
      if (match != null) selectedRootFolderId = match.id;
    }
  }

  SeerrServiceServerDetails? get activeServer {
    if (servers == null || servers!.isEmpty) return null;
    if (selectedServerId == null) return servers!.first;
    return servers!
            .where((s) => s.server.id == selectedServerId)
            .firstOrNull ??
        servers!.first;
  }

  int? get effectiveServerId =>
      selectedServerId ?? servers?.firstOrNull?.server.id;

  int? get effectiveProfileId {
    if (selectedProfileId != null) return selectedProfileId;
    final server = activeServer;
    if (server == null) return null;
    final int? animeProfileId = server.server.activeAnimeProfileId;
    if (isAnime && animeProfileId != null) return animeProfileId;
    return server.server.activeProfileId;
  }

  String? get effectiveRootFolderPath {
    final server = activeServer;
    if (server == null) return null;

    if (selectedRootFolderId != null) {
      return server.rootFolders
          .where((f) => f.id == selectedRootFolderId)
          .firstOrNull
          ?.path;
    }

    final String? animeDir = server.server.activeAnimeDirectory;
    final String dir;
    if (isAnime && animeDir != null && animeDir.isNotEmpty) {
      dir = animeDir;
    } else {
      dir = server.server.activeDirectory;
    }

    if (dir.isNotEmpty) {
      final match = server.rootFolders.where((f) => f.path == dir).firstOrNull;
      if (match != null) return match.path;
    }

    return server.rootFolders.firstOrNull?.path;
  }

  void onServerChanged(int? value) {
    selectedServerId = value;
    selectedProfileId = null;
    selectedRootFolderId = null;
    _applyServerDefaults();
    notifyListeners();
  }

  void onProfileChanged(int? value) {
    selectedProfileId = value;
    notifyListeners();
  }

  void onRootFolderChanged(int? value) {
    selectedRootFolderId = value;
    notifyListeners();
  }
}

/// The advanced options expansion tile with server, quality profile, and root
/// folder dropdowns, driven by a [SeerrAdvancedRequestController].
class SeerrAdvancedRequestOptions extends StatelessWidget {
  final SeerrAdvancedRequestController controller;

  const SeerrAdvancedRequestOptions({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ExpansionTile(
        title: Text(
          l10n.advancedOptions,
          style: TextStyle(color: AppColorScheme.onSurface.withValues(alpha: 0.7)),
        ),
        tilePadding: EdgeInsets.zero,
        children: [
          if (controller.loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (controller.servers != null &&
              controller.servers!.isNotEmpty) ...[
            _buildServerDropdown(l10n),
            const SizedBox(height: 16),
            _buildProfileDropdown(l10n),
            const SizedBox(height: 16),
            _buildRootFolderDropdown(l10n),
          ] else
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                l10n.noServiceServersConfigured,
                style: TextStyle(color: AppColorScheme.onSurface.withValues(alpha: 0.54)),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: AppColorScheme.onSurface.withValues(alpha: 0.54)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    border: const OutlineInputBorder(),
    enabledBorder: OutlineInputBorder(
      borderSide: ThemeRegistry.active.borders.chipBorder,
    ),
  );

  Widget _buildServerDropdown(AppLocalizations l10n) {
    final servers = controller.servers;
    return DropdownButtonFormField<int>(
      decoration: _decoration(l10n.server),
      dropdownColor: AppColorScheme.surface,
      initialValue:
          controller.selectedServerId ?? servers?.firstOrNull?.server.id,
      items: servers
          ?.map(
            (s) => DropdownMenuItem(
              value: s.server.id,
              child: Text(
                '${s.server.name}${s.server.is4k ? " (4K)" : ""}',
                style: TextStyle(color: AppColorScheme.onSurface),
              ),
            ),
          )
          .toList(),
      onChanged: controller.onServerChanged,
    );
  }

  Widget _buildProfileDropdown(AppLocalizations l10n) {
    final profiles = controller.activeServer?.profiles ?? [];
    return DropdownButtonFormField<int>(
      decoration: _decoration(l10n.qualityProfile),
      dropdownColor: AppColorScheme.surface,
      initialValue: controller.selectedProfileId ?? profiles.firstOrNull?.id,
      items: profiles
          .map(
            (p) => DropdownMenuItem(
              value: p.id,
              child: Text(p.name, style: TextStyle(color: AppColorScheme.onSurface)),
            ),
          )
          .toList(),
      onChanged: controller.onProfileChanged,
    );
  }

  Widget _buildRootFolderDropdown(AppLocalizations l10n) {
    final folders = controller.activeServer?.rootFolders ?? [];
    return DropdownButtonFormField<int>(
      decoration: _decoration(l10n.rootFolder),
      dropdownColor: AppColorScheme.surface,
      initialValue: controller.selectedRootFolderId ?? folders.firstOrNull?.id,
      items: folders
          .map(
            (f) => DropdownMenuItem(
              value: f.id,
              child: Text(f.path, style: TextStyle(color: AppColorScheme.onSurface)),
            ),
          )
          .toList(),
      onChanged: controller.onRootFolderChanged,
    );
  }
}
