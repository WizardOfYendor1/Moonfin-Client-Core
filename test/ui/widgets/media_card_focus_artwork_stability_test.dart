import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:moonfin/ui/widgets/media_card.dart';

/// Lives inside the artwork subtree and counts how often it is created, so a
/// teardown of that subtree shows up as an extra [initState].
class _InitCounter extends StatefulWidget {
  const _InitCounter({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_InitCounter> createState() => _InitCounterState();
}

class _InitCounterState extends State<_InitCounter> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  // Only a theme with a focus glow inserts the extra glow layer, which is what
  // used to shift the artwork's slot in the Stack.
  setUp(() => ThemeRegistry.setActiveById('neon_pulse'));
  tearDown(() => ThemeRegistry.setActiveById('moonfin'));

  testWidgets('focus changes keep the artwork subtree alive', (tester) async {
    expect(ThemeRegistry.active.borders.focusGlow, isNotEmpty);

    var inits = 0;
    final overlay = _InitCounter(onInit: () => inits++);

    Widget card(bool focused) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: MediaCard(
            title: 'Movie',
            width: 150,
            itemType: 'Movie',
            externalIsFocused: focused,
            imageOverlays: [overlay],
            onTap: () {},
          ),
        ),
      ),
    );

    await tester.pumpWidget(card(false));
    await tester.pumpAndSettle();
    expect(inits, 1);

    for (final focused in [true, false, true, false]) {
      await tester.pumpWidget(card(focused));
      await tester.pumpAndSettle();
    }

    expect(inits, 1);
  });
}
