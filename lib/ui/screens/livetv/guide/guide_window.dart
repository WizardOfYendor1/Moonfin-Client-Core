/// Rounds down to :00, :15, :30 or :45.
DateTime floorToQuarterHour(DateTime t) =>
    DateTime(t.year, t.month, t.day, t.hour, t.minute - (t.minute % 15));

/// Left edge of the guide window: the previous quarter hour, less a fifteen
/// minute back-slice so a still-airing programme keeps width as it ends.
DateTime guideLeftEdge(DateTime now) =>
    floorToQuarterHour(now).subtract(const Duration(minutes: 15));

Duration backSlice(DateTime now) => now.difference(guideLeftEdge(now));
