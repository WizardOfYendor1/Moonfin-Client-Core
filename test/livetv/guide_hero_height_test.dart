import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/livetv/epg/widgets/epg_hero_preview.dart';

void main() {
  testWidgets('compact standalone hero keeps a fixed height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EpgHeroPreview(
          title: 'Programme',
          timeLabel: '7:00 - 8:00',
          genreLabel: 'Drama',
          synopsis: 'A synopsis that continues onto a second line for context.',
          channelLogoUrl: null,
          channelName: 'Channel One',
          channelNumber: '1',
          isLive: false,
          apple: false,
          compact: true,
        ),
      ),
    );

    expect(tester.getSize(find.byType(EpgHeroPreview)).height, 110);
  });
}
