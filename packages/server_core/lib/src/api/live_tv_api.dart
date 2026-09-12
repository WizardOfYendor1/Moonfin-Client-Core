abstract class LiveTvApi {
  Future<Map<String, dynamic>> getChannels({
    int? startIndex,
    int? limit,
    String? sortBy,
    String? sortOrder,
    String? fields,
    bool? enableTotalRecordCount,
    String? userId,
  });

  /// A genre flag ([isMovie], [isSeries], [isSports], [isNews], [isKids]) makes
  /// the server return only that genre's programs for the given [channelIds],
  /// so the guide's category chips can walk the lineup in large batches
  /// without pulling every program. Omitting [channelIds] searches every
  /// channel; the guide does not use that form.
  Future<Map<String, dynamic>> getGuide({
    DateTime? startDate,
    DateTime? endDate,
    List<String>? channelIds,
    bool? isMovie,
    bool? isSeries,
    bool? isSports,
    bool? isNews,
    bool? isKids,
    String? fields,
    bool? enableTotalRecordCount,
    bool? enableImages,
    bool? enableUserData,
    String? userId,
  });

  /// [isAiring] has to be true for the server to recommend anything. Without
  /// it the endpoint falls back to a plain guide listing sorted by start date,
  /// which is neither filtered to what is on right now nor ranked.
  Future<Map<String, dynamic>> getRecommendedPrograms({
    int? limit,
    bool? isAiring,
  });

  Future<Map<String, dynamic>> getRecordings({
    int? limit,
    String? fields,
    bool? enableImages,
    bool? isSeries,
    bool? isMovie,
    bool? isSports,
    bool? isKids,
  });

  Future<Map<String, dynamic>> getTimers();

  Future<Map<String, dynamic>> getSeriesTimers();

  Future<void> createTimer(String programId);

  /// Records every showing of a program's series, not just this one.
  Future<void> createSeriesTimer(String programId);

  Future<void> cancelTimer(String timerId);

  Future<void> cancelSeriesTimer(String seriesTimerId);
}
