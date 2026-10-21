import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/live_tv_recording_state.dart';
import '../../../data/models/series_recording_episodes.dart';
import '../../../l10n/app_localizations.dart';
import '../adaptive/adaptive_dialog.dart';
import '../overlay_sheet.dart';

/// Asks which episodes a series recording takes. Choosing one closes the
/// dialog with it, and Cancel or Back returns null. [current] is the rule's
/// present choice when changing an existing recording, and is marked.
Future<SeriesRecordingEpisodes?> showSeriesRecordingEpisodesDialog({
  required BuildContext context,
  required String seriesName,
  SeriesRecordingEpisodes? current,
}) {
  final l10n = AppLocalizations.of(context);
  final initial = current ?? SeriesRecordingEpisodes.notRecorded;
  final initialFocusNode = FocusNode(debugLabel: 'SeriesRecordingEpisodes');
  var initialFocusRequested = false;

  return showFocusRestoringDialog<SeriesRecordingEpisodes>(
    context: context,
    builder: (dialogContext) {
      if (!initialFocusRequested) {
        initialFocusRequested = true;
        // On TV a navigator observer focuses a new route's first focusable
        // after autofocus resolves, so the initial choice takes it back here.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (initialFocusNode.context?.mounted == true) {
            initialFocusNode.requestFocus();
          }
        });
      }
      void choose(SeriesRecordingEpisodes? choice) =>
          Navigator.of(dialogContext).pop(choice);

      return AlertDialog.adaptive(
        title: Text(seriesName, style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.seriesRecordingEpisodesQuestion,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              for (final option in SeriesRecordingEpisodes.values)
                adaptiveDialogAction(
                  focusNode: option == initial ? initialFocusNode : null,
                  autofocus: option == initial,
                  focusRingColor: AppColorScheme.accent,
                  onPressed: () => choose(option),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _label(l10n, option),
                              style: const TextStyle(color: Colors.white),
                            ),
                            Text(
                              _description(l10n, option),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (option == current) ...[
                        const SizedBox(width: 16),
                        const Icon(Icons.check, color: Colors.white),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          adaptiveDialogAction(
            focusRingColor: AppColorScheme.accent,
            onPressed: () => choose(null),
            child: Text(l10n.cancel),
          ),
        ],
      );
    },
  ).whenComplete(initialFocusNode.dispose);
}

/// Shows an existing rule's choice and saves a different one. Returns whether
/// the rule changed. API errors reach the caller.
Future<bool> changeSeriesRecordingEpisodes({
  required BuildContext context,
  required LiveTvApi liveTvApi,
  required String seriesTimerId,
}) async {
  final timer = await liveTvApi.getSeriesTimer(seriesTimerId);
  if (!context.mounted) return false;
  final current = SeriesRecordingEpisodes.fromSeriesTimer(timer);
  final choice = await showSeriesRecordingEpisodesDialog(
    context: context,
    seriesName: timer['Name']?.toString() ?? '',
    current: current,
  );
  if (choice == null || choice == current) return false;
  await liveTvApi.updateSeriesTimer(seriesTimerId, {
    ...timer,
    ...choice.settings,
  });
  notifyLiveTvRecordingsChanged();
  return true;
}

enum SeriesTimerOption { changeSettings, cancel }

/// What to do with an existing series recording, from a list of rules.
Future<SeriesTimerOption?> showSeriesTimerOptionsDialog({
  required BuildContext context,
  required String name,
  String? subtitle,
}) {
  final l10n = AppLocalizations.of(context);
  return showFocusRestoringDialog<SeriesTimerOption>(
    context: context,
    builder: (ctx) {
      void choose(SeriesTimerOption? option) =>
          Navigator.of(ctx, rootNavigator: true).pop(option);
      return AlertDialog.adaptive(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(name, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null && subtitle.isNotEmpty)
              Text(
                subtitle,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
          ],
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => choose(null),
            child: Text(l10n.close),
          ),
          adaptiveDialogAction(
            onPressed: () => choose(SeriesTimerOption.changeSettings),
            child: Text(l10n.seriesRecordingSettings),
          ),
          TextButton(
            onPressed: () => choose(SeriesTimerOption.cancel),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.cancelSeriesRecording),
          ),
        ],
      );
    },
  );
}

String _label(AppLocalizations l10n, SeriesRecordingEpisodes option) =>
    switch (option) {
      SeriesRecordingEpisodes.all => l10n.seriesRecordingAllEpisodes,
      SeriesRecordingEpisodes.notRecorded =>
        l10n.seriesRecordingNotRecordedEpisodes,
      SeriesRecordingEpisodes.newOnly => l10n.seriesRecordingNewEpisodesOnly,
    };

String _description(AppLocalizations l10n, SeriesRecordingEpisodes option) =>
    switch (option) {
      SeriesRecordingEpisodes.all => l10n.seriesRecordingAllEpisodesDescription,
      SeriesRecordingEpisodes.notRecorded =>
        l10n.seriesRecordingNotRecordedEpisodesDescription,
      SeriesRecordingEpisodes.newOnly =>
        l10n.seriesRecordingNewEpisodesOnlyDescription,
    };
