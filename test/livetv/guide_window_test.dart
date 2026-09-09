import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/livetv/guide/guide_window.dart';

void main() {
  test('leftEdge is the previous quarter hour minus fifteen minutes', () {
    expect(guideLeftEdge(DateTime(2026, 9, 8, 19, 26)), DateTime(2026, 9, 8, 19, 0));
    expect(guideLeftEdge(DateTime(2026, 9, 8, 19, 31)), DateTime(2026, 9, 8, 19, 15));
    expect(guideLeftEdge(DateTime(2026, 9, 8, 19, 44)), DateTime(2026, 9, 8, 19, 15));
    expect(guideLeftEdge(DateTime(2026, 9, 8, 19, 46)), DateTime(2026, 9, 8, 19, 30));
  });

  test('the back-slice stays within 15 to 30 minutes for every minute of a day', () {
    var t = DateTime(2026, 9, 8);
    for (var i = 0; i < 24 * 60; i++) {
      final slice = backSlice(t).inMinutes;
      expect(slice, inInclusiveRange(15, 30), reason: 'at $t');
      t = t.add(const Duration(minutes: 1));
    }
  });

  test('leftEdge crosses midnight backwards correctly', () {
    expect(guideLeftEdge(DateTime(2026, 9, 8, 0, 5)), DateTime(2026, 9, 7, 23, 45));
  });
}
