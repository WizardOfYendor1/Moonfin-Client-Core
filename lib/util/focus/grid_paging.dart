import 'dart:math' as math;

import 'package:flutter/rendering.dart';
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
  final firstWhole = math.max(0, ((scrollOffset - 0.5) / stride).ceil());
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

/// Page targets whose focus hasn't landed yet, so key repeats arriving before
/// the next frame page on from there instead of from the old card.
final _pendingPageTargets = Expando<int>('pendingPageTarget');

FocusNode? _pagedFocus;

/// True once for a node paging just focused, so its own focus scroll can skip
/// a card paging already put in place.
bool takePagedFocus(FocusNode node) {
  if (!identical(node, _pagedFocus)) return false;
  _pagedFocus = null;
  return true;
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
  return _page(
    context,
    controller.position,
    geometry,
    fromIndex: fromIndex,
    direction: direction,
    itemCount: itemCount,
    focusNodeFor: focusNodeFor,
  );
}

/// [pageGrid] for a column of same-height cards that may sit anywhere in a
/// longer scroll view. Card height, gap and where the list starts are measured
/// from the focused card and its neighbour.
bool pageList(
  BuildContext context, {
  required int fromIndex,
  required int direction,
  required int itemCount,
  required FocusNode Function(int index) focusNodeFor,
  double leadingMargin = 24,
}) {
  final itemContext = focusNodeFor(fromIndex).context;
  final card = itemContext?.findRenderObject();
  if (itemContext == null || card is! RenderBox || !card.hasSize) return false;
  final viewport = RenderAbstractViewport.maybeOf(card);
  final position = Scrollable.maybeOf(itemContext)?.position;
  if (viewport == null || position == null) return false;
  double? topOf(int index) {
    if (index < 0 || index >= itemCount) return null;
    final box = focusNodeFor(index).context?.findRenderObject();
    if (box == null || !box.attached) return null;
    return viewport.getOffsetToReveal(box, 0).offset;
  }

  final top = topOf(fromIndex)!;
  final next = topOf(fromIndex + 1);
  final previous = topOf(fromIndex - 1);
  final stride = next != null
      ? next - top
      : previous != null
      ? top - previous
      : card.size.height;
  if (stride <= 0) return false;
  return _page(
    context,
    position,
    (
      perLine: 1,
      lineExtent: card.size.height,
      lineSpacing: stride - card.size.height,
      leadingPad: leadingMargin,
    ),
    fromIndex: fromIndex,
    direction: direction,
    itemCount: itemCount,
    focusNodeFor: focusNodeFor,
    contentStart: top - fromIndex * stride - leadingMargin,
  );
}

/// [contentStart] is where [geometry] begins in the scroll view.
bool _page(
  BuildContext context,
  ScrollPosition position,
  GridGeometry geometry, {
  required int fromIndex,
  required int direction,
  required int itemCount,
  required FocusNode Function(int index) focusNodeFor,
  double contentStart = 0,
}) {
  if (!position.hasPixels || !position.hasContentDimensions) return false;
  _pagedFocus = null;
  final pending = _pendingPageTargets[position];
  final page = gridPageTarget(
    geometry,
    fromIndex: pending ?? fromIndex,
    direction: direction,
    itemCount: itemCount,
    scrollOffset: position.pixels - contentStart,
    viewportExtent: position.viewportDimension,
    maxScrollExtent: position.maxScrollExtent - contentStart,
  );
  if (page == null) return false;
  position.jumpTo(
    (page.offset + contentStart).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    ),
  );
  _pendingPageTargets[position] = page.index;
  // Wait for the target card to be built at the new offset.
  if (pending == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _pendingPageTargets[position];
      _pendingPageTargets[position] = null;
      if (target != null && context.mounted) {
        final node = focusNodeFor(target);
        _pagedFocus = node;
        node.requestFocus();
      }
    });
  }
  return true;
}
