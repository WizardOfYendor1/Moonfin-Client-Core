import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../models/live_tv_recording_state.dart';

/// What happened to the complete showing of an incomplete recording's episode.
enum CompleteShowingStatus { scheduled, recorded, notFound, none }

CompleteShowingStatus _statusFrom(Object? value) => switch (value) {
  'scheduled' => CompleteShowingStatus.scheduled,
  'recorded' => CompleteShowingStatus.recorded,
  'notFound' => CompleteShowingStatus.notFound,
  _ => CompleteShowingStatus.none,
};

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// A recording the Moonfin plugin judged incomplete.
@immutable
class IncompleteRecording {
  final String itemId;
  final int recordedMinutes;
  final int expectedMinutes;
  final CompleteShowingStatus status;
  final DateTime? scheduledStart;
  final String? channelName;
  final DateTime? recordedAt;

  const IncompleteRecording({
    required this.itemId,
    required this.recordedMinutes,
    required this.expectedMinutes,
    this.status = CompleteShowingStatus.none,
    this.scheduledStart,
    this.channelName,
    this.recordedAt,
  });

  static IncompleteRecording? fromJson(Map<String, dynamic> json) {
    final id = json['itemId']?.toString();
    if (id == null || id.isEmpty) return null;
    return IncompleteRecording(
      itemId: id,
      recordedMinutes: (json['recordedMinutes'] as num?)?.round() ?? 0,
      expectedMinutes: (json['expectedMinutes'] as num?)?.round() ?? 0,
      status: _statusFrom(json['state']),
      scheduledStart: _date(json['scheduledStart']),
      channelName: json['channelName']?.toString(),
      recordedAt: _date(json['recordedAt']),
    );
  }
}

/// The server-wide settings for incomplete recordings.
@immutable
class IncompleteRecordingSettings {
  final bool autoRecordComplete;
  final int thresholdPercent;

  const IncompleteRecordingSettings({
    required this.autoRecordComplete,
    required this.thresholdPercent,
  });
}

/// The incomplete Live TV recordings the Moonfin plugin tracks, for the badge,
/// the detail line, the Record prompt and the settings toggle.
///
/// The whole set is fetched in one call and kept, since it stays small, so a
/// card only checks membership. It is read again when this app changes a
/// recording and every few minutes while something is asking for it.
class IncompleteRecordingsService extends ChangeNotifier {
  static const _maxAge = Duration(minutes: 5);

  final Dio _dio;
  final MediaServerClient? Function() _client;

  Map<String, IncompleteRecording> _byItem = const {};
  bool _supported = false;
  DateTime? _loadedAt;
  Future<void>? _inFlight;

  IncompleteRecordingsService({
    required MediaServerClient? Function() client,
    @visibleForTesting Dio? dio,
  }) : _client = client,
       _dio = dio ?? Dio() {
    if (dio == null) {
      configureServerDio(_dio);
      _dio.interceptors.add(redirectInterceptor(_dio));
    }
    liveTvRecordingRevision.addListener(_onRecordingsChanged);
  }

  @override
  void dispose() {
    liveTvRecordingRevision.removeListener(_onRecordingsChanged);
    super.dispose();
  }

  /// True when the server's plugin has the incomplete recordings endpoints.
  /// Everything in the UI is hidden otherwise, which covers Emby and older
  /// plugins.
  bool get supported => _supported;

  void setSupported(bool value) {
    if (_supported == value) return;
    _supported = value;
    _byItem = const {};
    _loadedAt = null;
    notifyListeners();
    if (value) unawaited(refresh());
  }

  /// The item's incomplete state, or null when it is complete or unknown.
  /// Asking also reads the set again once it has gone stale.
  IncompleteRecording? stateFor(String? itemId) {
    if (!_supported || itemId == null || itemId.isEmpty) return null;
    _refreshIfStale();
    return _byItem[_normalize(itemId)];
  }

  void _refreshIfStale() {
    final loadedAt = _loadedAt;
    if (loadedAt == null || DateTime.now().difference(loadedAt) > _maxAge) {
      unawaited(refresh());
    }
  }

  void _onRecordingsChanged() {
    if (_supported) unawaited(refresh());
  }

  /// Reads the whole set again. Concurrent callers share one request.
  Future<void> refresh() {
    if (!_supported) return Future.value();
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  // An older plugin is told apart by the ping's capability flag, before this
  // runs. Here a refusal means this user may not see Live TV, so nothing is
  // badged; an outage or a server error keeps what was last known.
  Future<void> _load() async {
    _loadedAt = DateTime.now();
    final response = await _raw(
      'GET',
      '/Moonfin/LiveTv/Recordings/Incomplete',
      null,
    );
    final status = response?.statusCode ?? 0;
    if (status == 401 || status == 403) {
      if (_byItem.isNotEmpty) {
        _byItem = const {};
        notifyListeners();
      }
      return;
    }
    final data = response?.data;
    if (data is! List) return;
    final next = <String, IncompleteRecording>{};
    for (final entry in data) {
      if (entry is! Map) continue;
      final parsed = IncompleteRecording.fromJson(
        Map<String, dynamic>.from(entry),
      );
      if (parsed != null) next[_normalize(parsed.itemId)] = parsed;
    }
    _byItem = next;
    notifyListeners();
  }

  /// Keep as Complete. Dismisses the record for everyone on the server.
  Future<bool> dismiss(String itemId) async {
    final ok = await _send(
      'POST',
      '/Moonfin/LiveTv/Recordings/${_normalize(itemId)}/Dismiss',
    );
    if (ok) {
      _byItem = Map.of(_byItem)..remove(_normalize(itemId));
      notifyListeners();
    }
    return ok;
  }

  /// Asks the plugin to record a complete showing of the program's episode
  /// later. Returns false when it couldn't.
  Future<bool> requestCompleteShowing(String programId) =>
      _send('POST', '/Moonfin/LiveTv/CompleteShowing', {'programId': programId});

  Future<IncompleteRecordingSettings?> loadSettings() async {
    final data = await _request(
      'GET',
      '/Moonfin/LiveTv/Settings/IncompleteRecordings',
    );
    if (data is! Map) return null;
    return IncompleteRecordingSettings(
      autoRecordComplete: data['autoRecordComplete'] == true,
      thresholdPercent: (data['thresholdPercent'] as num?)?.round() ?? 90,
    );
  }

  Future<bool> saveSettings(IncompleteRecordingSettings settings) => _send(
    'POST',
    '/Moonfin/LiveTv/Settings/IncompleteRecordings',
    {
      'autoRecordComplete': settings.autoRecordComplete,
      'thresholdPercent': settings.thresholdPercent,
    },
  );

  /// Forgets everything. Called on sign out and server switch.
  void clear() {
    _byItem = const {};
    _loadedAt = null;
    _supported = false;
    notifyListeners();
  }

  // Ids are compared without dashes or case, so either GUID spelling matches.
  static String _normalize(String id) => id.replaceAll('-', '').toLowerCase();

  Future<bool> _send(String method, String path, [Object? body]) async {
    final response = await _raw(method, path, body);
    final status = response?.statusCode ?? 0;
    return status >= 200 && status < 300;
  }

  Future<Object?> _request(String method, String path, [Object? body]) async =>
      (await _raw(method, path, body))?.data;

  Future<Response<Object?>?> _raw(String method, String path, Object? body) async {
    final client = _client();
    final token = client?.accessToken;
    if (client == null || token == null || token.isEmpty) return null;
    try {
      return await _dio.request<Object?>(
        '${client.baseUrl}$path',
        data: body,
        options: Options(
          method: method,
          headers: {
            'Authorization': buildServerAuthorizationHeader(
              scheme: 'MediaBrowser',
              deviceInfo: client.deviceInfo,
              accessToken: token,
            ),
            'Accept': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      // A refusal still has a status worth reading; anything else is an outage.
      return e.response;
    } catch (_) {
      return null;
    }
  }
}
