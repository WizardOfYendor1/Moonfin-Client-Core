import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/playback/device_profile_builder.dart';
import 'package:moonfin/playback/known_defects.dart';

Set<String> _hevcUnsupportedRangeTypes(Map<String, dynamic> profile) {
  final codecProfiles = profile['CodecProfiles'] as List<dynamic>? ?? const [];

  for (final rawProfile in codecProfiles) {
    final codecProfile = rawProfile as Map<dynamic, dynamic>;
    if (codecProfile['Type'] != 'Video' || codecProfile['Codec'] != 'hevc') {
      continue;
    }

    final conditions = codecProfile['Conditions'] as List<dynamic>? ?? const [];
    for (final rawCondition in conditions) {
      final condition = rawCondition as Map<dynamic, dynamic>;
      if (condition['Property'] != 'VideoRangeType') {
        continue;
      }

      final value = condition['Value']?.toString() ?? '';
      return value
          .split('|')
          .map((token) => token.trim())
          .where((token) => token.isNotEmpty)
          .toSet();
    }
  }

  return <String>{};
}

Map<dynamic, dynamic>? _stereoAacFallbackProfile(Map<String, dynamic> profile) {
  final codecProfiles = profile['CodecProfiles'] as List<dynamic>? ?? const [];

  for (final rawProfile in codecProfiles) {
    final codecProfile = rawProfile as Map<dynamic, dynamic>;
    if (codecProfile['Type'] != 'VideoAudio' || codecProfile['Codec'] != 'aac') {
      continue;
    }

    final conditions = codecProfile['Conditions'] as List<dynamic>? ?? const [];
    final hasStereoCondition = conditions.any((rawCondition) {
      final condition = rawCondition as Map<dynamic, dynamic>;
      return condition['Property'] == 'AudioChannels' &&
          condition['Condition'] == 'LessThanEqual' &&
          condition['Value'] == '2';
    });

    if (hasStereoCondition) {
      return codecProfile;
    }
  }

  return null;
}

void main() {
  group('DeviceProfileBuilder HEVC range filtering', () {
    test('does not exclude DoVi HDR10+ only because profile 8 is unsupported', () {
      final profile = DeviceProfileBuilder.build(
        supportsHevc: true,
        supportsHevcMain10: true,
        supportsHevcDolbyVision: true,
        supportsHevcDolbyVisionEl: true,
        supportsHevcHdr10: true,
        supportsHevcHdr10Plus: false,
        supportsDvProfile5: true,
        supportsDvProfile7: true,
        supportsDvProfile8: false,
        knownHevcDoviHdr10PlusBug: false,
      );

      final unsupportedRanges = _hevcUnsupportedRangeTypes(profile);

      expect(unsupportedRanges, contains('DOVI_WITH_HDR10'));
      expect(unsupportedRanges, isNot(contains('DOVI_WITH_HDR10_PLUS')));
    });

    test('excludes DoVi HDR10+ when known buggy model flag is set', () {
      final profile = DeviceProfileBuilder.build(
        supportsHevc: true,
        supportsHevcMain10: true,
        supportsHevcDolbyVision: true,
        supportsHevcDolbyVisionEl: true,
        supportsHevcHdr10: true,
        supportsHevcHdr10Plus: true,
        supportsDvProfile5: true,
        supportsDvProfile7: true,
        supportsDvProfile8: true,
        knownHevcDoviHdr10PlusBug: true,
      );

      final unsupportedRanges = _hevcUnsupportedRangeTypes(profile);

      expect(unsupportedRanges, contains('DOVI_WITH_HDR10_PLUS'));
      expect(unsupportedRanges, contains('DOVI_WITH_ELHDR10_PLUS'));
    });
  });

  group('DeviceProfileBuilder stereo AAC fallback', () {
    test('adds stereo AAC fallback profile when enabled', () {
      final profile = DeviceProfileBuilder.build(
        downMixAudio: false,
        audioFallbackToStereoAac: true,
      );

      expect(_stereoAacFallbackProfile(profile), isNotNull);
    });

    test('does not add stereo AAC fallback profile when disabled', () {
      final profile = DeviceProfileBuilder.build(
        downMixAudio: false,
        audioFallbackToStereoAac: false,
      );

      expect(_stereoAacFallbackProfile(profile), isNull);
    });
  });

  group('KnownDefects model mapping', () {
    test('matches additional Fire TV models for DoVi HDR10+ bug', () {
      expect(KnownDefects.modelHasHevcDoviHdr10PlusBug('AFTKRT'), isTrue);
      expect(KnownDefects.modelHasHevcDoviHdr10PlusBug('aftmm'), isFalse);
    });
  });
}
