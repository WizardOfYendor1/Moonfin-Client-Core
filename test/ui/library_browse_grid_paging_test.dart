import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/browse/library_browse_screen.dart';

void main() {
  const GridGeometry tall = (
    perLine: 6,
    lineExtent: 180,
    lineSpacing: 20,
    leadingPad: 20,
  );

  test('a page forward moves as many lines as the viewport shows whole', () {
    final page = gridPageTarget(
      tall,
      fromIndex: 8,
      direction: 1,
      itemCount: 600,
      scrollOffset: 0,
      viewportExtent: 1000,
      maxScrollExtent: 20000,
    )!;
    expect(page.index, 8 + 5 * 6);
    expect(page.offset, 5 * 200);
  });

  test('a page back keeps the column and the place on screen', () {
    final page = gridPageTarget(
      tall,
      fromIndex: 63,
      direction: -1,
      itemCount: 600,
      scrollOffset: 2000,
      viewportExtent: 1000,
      maxScrollExtent: 20000,
    )!;
    expect(page.index % 6, 63 % 6);
    expect(page.index, 63 - 5 * 6);
    expect(page.offset, 1000);
  });

  test('bigger cards page fewer lines', () {
    const GridGeometry big = (
      perLine: 4,
      lineExtent: 380,
      lineSpacing: 20,
      leadingPad: 20,
    );
    final page = gridPageTarget(
      big,
      fromIndex: 1,
      direction: 1,
      itemCount: 200,
      scrollOffset: 0,
      viewportExtent: 1000,
      maxScrollExtent: 20000,
    )!;
    expect(page.index, 1 + 2 * 4);
  });

  test('a card too big to show whole still pages a line', () {
    const GridGeometry huge = (
      perLine: 2,
      lineExtent: 1200,
      lineSpacing: 20,
      leadingPad: 20,
    );
    final page = gridPageTarget(
      huge,
      fromIndex: 0,
      direction: 1,
      itemCount: 20,
      scrollOffset: 0,
      viewportExtent: 1000,
      maxScrollExtent: 20000,
    )!;
    expect(page.index, 2);
  });

  test('a horizontal grid pages columns and keeps the row', () {
    const GridGeometry wide = (
      perLine: 3,
      lineExtent: 138,
      lineSpacing: 12,
      leadingPad: 60,
    );
    final page = gridPageTarget(
      wide,
      fromIndex: 4,
      direction: 1,
      itemCount: 300,
      scrollOffset: 0,
      viewportExtent: 1800,
      maxScrollExtent: 20000,
    )!;
    expect(page.index, 4 + 11 * 3);
    expect(page.index % 3, 1);
  });

  test('stops at the ends of what has loaded', () {
    final last = gridPageTarget(
      tall,
      fromIndex: 50,
      direction: 1,
      itemCount: 56,
      scrollOffset: 0,
      viewportExtent: 1000,
      maxScrollExtent: 900,
    )!;
    expect(last.index, 55);
    expect(last.offset, 200);

    final first = gridPageTarget(
      tall,
      fromIndex: 9,
      direction: -1,
      itemCount: 56,
      scrollOffset: 200,
      viewportExtent: 1000,
      maxScrollExtent: 900,
    )!;
    expect(first.index, 3);
    expect(first.offset, 0);

    expect(
      gridPageTarget(
        tall,
        fromIndex: 2,
        direction: -1,
        itemCount: 56,
        scrollOffset: 0,
        viewportExtent: 1000,
        maxScrollExtent: 900,
      ),
      isNull,
    );
  });
}
