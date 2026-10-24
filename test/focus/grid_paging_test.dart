import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/focus/grid_paging.dart';

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

  test('a part-scrolled grid pages onto a line boundary', () {
    final page = gridPageTarget(
      tall,
      fromIndex: 20,
      direction: 1,
      itemCount: 600,
      scrollOffset: 250,
      viewportExtent: 1000,
      maxScrollExtent: 20000,
    )!;
    expect(page.index, 20 + 4 * 6);
    expect(page.offset, 6 * 200);
  });

  test('the paged-to card lands whole in view at any scale and screen', () {
    // Card extents stand in for UI scale and poster size, viewports for 720p
    // to 4K displays and horizontal grids, pads for the focus zoom room.
    for (final extent in [120.0, 180.0, 260.0, 420.0, 700.0]) {
      for (final spacing in [12.0, 30.0]) {
        for (final pad in [8.0, 40.0]) {
          for (final viewport in [600.0, 1000.0, 1500.0, 2100.0]) {
            for (final perLine in [1, 3, 7]) {
              final GridGeometry geometry = (
                perLine: perLine,
                lineExtent: extent,
                lineSpacing: spacing,
                leadingPad: pad,
              );
              final stride = extent + spacing;
              for (var scroll = stride * 3; scroll < stride * 6; scroll += 7) {
                for (var line = 0; line < 12; line++) {
                  for (final direction in [1, -1]) {
                    final from = line * perLine + perLine ~/ 2;
                    final page = gridPageTarget(
                      geometry,
                      fromIndex: from,
                      direction: direction,
                      itemCount: perLine * 200,
                      scrollOffset: scroll,
                      viewportExtent: viewport,
                      maxScrollExtent: 1e9,
                    );
                    if (page == null) continue;
                    final reason =
                        'extent $extent, viewport $viewport, scroll $scroll, '
                        'line $line, direction $direction';
                    expect(page.index % perLine, from % perLine, reason: reason);
                    expect(
                      direction > 0 ? page.index > from : page.index < from,
                      isTrue,
                      reason: reason,
                    );
                    final start = gridLineStart(geometry, page.index);
                    expect(
                      start - pad,
                      greaterThanOrEqualTo(page.offset - 0.5),
                      reason: reason,
                    );
                    // A card taller than the screen can only show its start.
                    if (extent + pad <= viewport) {
                      expect(
                        start + extent,
                        lessThanOrEqualTo(page.offset + viewport + 0.5),
                        reason: reason,
                      );
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
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
    expect(last.offset, 900);

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

  group('pageList', () {
    const cardHeight = 100.0;
    const gap = 8.0;
    const headerHeight = 400.0;

    late List<FocusNode> nodes;
    late ScrollController controller;

    Future<void> pumpList(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      nodes = List.generate(40, (i) => FocusNode(debugLabel: 'card$i'));
      controller = ScrollController();
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: [
                const SizedBox(height: headerHeight),
                for (var i = 0; i < nodes.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: gap),
                    child: Focus(
                      focusNode: nodes[i],
                      child: const SizedBox(height: cardHeight),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    bool page(int from, int direction) => pageList(
      nodes[from].context!,
      fromIndex: from,
      direction: direction,
      itemCount: nodes.length,
      focusNodeFor: (i) => nodes[i],
    );

    testWidgets('pages by the whole cards in view below a header', (
      tester,
    ) async {
      await pumpList(tester);
      nodes[1].requestFocus();
      await tester.pump();

      // Five whole cards show under the header: 400 + 5 * 108 < 1000.
      expect(page(1, 1), isTrue);
      await tester.pump();
      expect(nodes[6].hasFocus, isTrue);
      // The top whole card sits 24 below the viewport top.
      expect(controller.offset, headerHeight + 5 * (cardHeight + gap) - 24);

      expect(page(6, -1), isTrue);
      await tester.pump();
      expect(nodes[0].hasFocus, isTrue);
    });

    testWidgets('a repeat before the next frame pages on from the target', (
      tester,
    ) async {
      await pumpList(tester);
      await tester.pump();
      controller.jumpTo(headerHeight - 24);
      await tester.pump();
      nodes[0].requestFocus();
      await tester.pump();

      expect(page(0, 1), isTrue);
      expect(page(0, 1), isTrue);
      await tester.pump();
      // Nine whole cards per page with no header in view.
      expect(nodes[18].hasFocus, isTrue);
      expect(
        controller.offset,
        headerHeight - 24 + 18 * (cardHeight + gap),
      );
    });

    testWidgets('the paged-to card reports its focus came from paging', (
      tester,
    ) async {
      await pumpList(tester);
      nodes[0].requestFocus();
      await tester.pump();
      page(0, 1);
      await tester.pump();
      expect(takePagedFocus(nodes[5]), isTrue);
      expect(takePagedFocus(nodes[5]), isFalse);
    });
  });
}
