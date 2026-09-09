// Pure indexing math for the circular channel carousel: no Flutter imports.

/// Recentre once the raw index drifts this many lineups away from the seed;
/// callers seed deep inside a `channelCount * N` space (N in the hundreds)
/// so this threshold is reached only after long, sustained scrolling.
const int _driftThresholdMultiplier = 200;

/// Maps a raw builder index onto a real channel index, wrapping both ways.
int channelIndexFor(int rawIndex, int channelCount) {
  return ((rawIndex % channelCount) + channelCount) % channelCount;
}

/// How many channels a held LEFT/RIGHT press advances per repeat.
int pageStep({required int channelCount, required int visibleCards}) {
  if (channelCount <= 1) return 0;
  if (channelCount <= visibleCards) return 1;
  return visibleCards;
}

/// Whether `rawIndex` has drifted far enough from `seedIndex` to recentre.
bool needsRecentre(int rawIndex, int channelCount, int seedIndex) {
  final threshold = channelCount * _driftThresholdMultiplier;
  return (rawIndex - seedIndex).abs() >= threshold;
}

/// Shifts `rawIndex` back near `seedIndex` by a whole multiple of
/// `channelCount`, so `channelIndexFor` is unchanged and the jump is
/// invisible to the viewer.
int recentre(int rawIndex, int channelCount, int seedIndex) {
  final lineups = ((rawIndex - seedIndex) / channelCount).round();
  return rawIndex - (lineups * channelCount);
}
