import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// One line of the grid, across whichever axis it scrolls.
typedef GridGeometry = ({
  int perLine,
  double lineExtent,
  double lineSpacing,
  double leadingPad,
});

/// Leading edge of the line holding [index], in the scroll view's own
/// coordinates.
double gridLineStart(GridGeometry geometry, int index) =>
    geometry.leadingPad +
    (index ~/ geometry.perLine) *
        (geometry.lineExtent + geometry.lineSpacing);

/// Card and scroll offset one page away, a page being the whole lines in view.
/// A line only counts as in view with its leading pad showing, which is the
/// room a focused card zooms into.
({int index, double offset})? gridPageTarget(
  GridGeometry geometry, {
  required int fromIndex,
  required int direction,
  required int itemCount,
  required double scrollOffset,
  required double viewportExtent,
  required double maxScrollExtent,
}) {
  if (itemCount <= 0 || direction == 0) return null;
  final stride = geometry.lineExtent + geometry.lineSpacing;
  if (stride <= 0) return null;
  final perLine = math.max(1, geometry.perLine);
  final firstWhole = ((scrollOffset - 0.5) / stride).ceil();
  final lastWhole = ((scrollOffset +
                  viewportExtent +
                  0.5 -
                  geometry.leadingPad -
                  geometry.lineExtent) /
              stride)
          .floor();
  final lines = math.max(1, lastWhole - firstWhole + 1);
  final lastLine = (itemCount - 1) ~/ perLine;
  final fromLine = fromIndex ~/ perLine;
  final targetLine = (fromLine + direction * lines).clamp(0, lastLine);
  final index = (targetLine * perLine + fromIndex % perLine).clamp(
    0,
    itemCount - 1,
  );
  if (index == fromIndex) return null;
  final topLine = (firstWhole + direction * lines).clamp(0, lastLine);
  final offset = (topLine * stride)
      .clamp(0.0, math.max(0.0, maxScrollExtent))
      .toDouble();
  return (index: index, offset: offset);
}

/// Pages [controller]'s grid from the card at [fromIndex] and focuses the card
/// it lands on. False when there was nowhere to go.
bool pageGrid(
  BuildContext context, {
  required ScrollController controller,
  required GridGeometry geometry,
  required int fromIndex,
  required int direction,
  required int itemCount,
  required FocusNode Function(int index) focusNodeFor,
}) {
  if (!controller.hasClients || controller.positions.length != 1) return false;
  final position = controller.position;
  if (!position.hasPixels || !position.hasContentDimensions) return false;
  final page = gridPageTarget(
    geometry,
    fromIndex: fromIndex,
    direction: direction,
    itemCount: itemCount,
    scrollOffset: position.pixels,
    viewportExtent: position.viewportDimension,
    maxScrollExtent: position.maxScrollExtent,
  );
  if (page == null) return false;
  controller.jumpTo(page.offset);
  // Wait for the target card to be built at the new offset.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) focusNodeFor(page.index).requestFocus();
  });
  return true;
}
