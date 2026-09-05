import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/features/camera/hud/hud_data.dart';
import 'package:sitelens/features/camera/hud/hud_formatter.dart';
import 'package:sitelens/features/camera/hud/hud_layout_spec.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';

void main() {
  group('HudData & HudFormatter Unit Tests', () {
    final sampleSnapshot = EvidenceMetadataSnapshot(
      mediaId: 'test-uuid-1',
      siteId: 'SITE_101',
      siteCode: 'HOME',
      siteName: 'Sonar Kella Apartment',
      latitude: 22.56298,
      longitude: 88.30085,
      altitudeMeters: -43.4,
      accuracyMeters: 7.6,
      lowAccuracy: false,
      capturedAtUtc: DateTime.utc(2026, 8, 15, 2, 24, 55),
      canonicalTimestampUtc: '2026-08-15 02:24:55 UTC',
      resolvedAddress: 'Sonar Kella Apartment, Kolkata',
    );

    const sampleSha =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    test('formatFromSnapshot creates canonical HudData with correct formatting', () {
      final hud = HudFormatter.fromSnapshot(
        snapshot: sampleSnapshot,
        originalSha256: sampleSha,
        isGpsLocked: true,
      );

      expect(hud.headlineText, contains('Sonar Kella Apartment'));
      expect(hud.status, HudStatus.verified);
      expect(hud.statusText, 'VERIFIED');
      expect(hud.addressText, 'Sonar Kella Apartment, Kolkata');
      expect(hud.isAddressResolving, false);
      expect(hud.utcTimestampText, '2026-08-15 02:24:55');
      expect(hud.latitudeText, contains('22.562980° N'));
      expect(hud.longitudeText, contains('88.300850° E'));
      expect(hud.altitudeSuffix, ' (Alt: -43.4m)');
      expect(hud.siteCodeText, 'HOME');
      expect(hud.displaySha256, 'e3b0c442...7852b855');
      expect(hud.isShaPending, false);
    });

    test('formatFromLive handles resolving address and pending hash', () {
      final hud = HudFormatter.fromLive(
        siteCode: 'TEST',
        siteName: 'Test Site',
        resolvedAddress: 'RESOLVING...',
        latitude: 22.5,
        longitude: 88.3,
        altitudeMeters: 10.5,
        accuracyMeters: 3.0,
        isGpsLocked: true,
        isDegraded: false,
        captureTime: DateTime.utc(2026, 8, 15, 12, 0, 0),
      );

      expect(hud.siteCodeText, 'TEST');
      expect(hud.isAddressResolving, true);
      expect(hud.addressText, 'RESOLVING...');
      expect(hud.displaySha256, isNull);
      expect(hud.isShaPending, true);
      expect(hud.status, HudStatus.verified);
      expect(hud.altitudeSuffix, ' (Alt: +10.5m)');
    });

    test('Degraded status resolves correctly', () {
      final hud = HudFormatter.fromLive(
        siteCode: 'TEST',
        resolvedAddress: '123 Main St',
        latitude: 22.5,
        longitude: 88.3,
        isGpsLocked: true,
        isDegraded: true,
      );

      expect(hud.status, HudStatus.degraded);
      expect(hud.statusText, 'DEGRADED');
    });

    test('Pending status resolves when GPS is not locked', () {
      final hud = HudFormatter.fromLive(
        siteCode: 'TEST',
        resolvedAddress: '123 Main St',
        latitude: 0.0,
        longitude: 0.0,
        isGpsLocked: false,
        isDegraded: false,
      );

      expect(hud.status, HudStatus.pending);
      expect(hud.statusText, 'PENDING');
    });

    test('HudLayoutSpec constants adhere to design specification', () {
      expect(HudLayoutSpec.minimapAspectRatio, 1.24);
      expect(HudLayoutSpec.maxMinimapWidthFraction, 0.42);
      expect(HudLayoutSpec.fontScaleMin, 0.82);
      expect(HudLayoutSpec.fontScaleMax, 1.0);
      expect(HudLayoutSpec.refCardGap, 4.0);
      expect(HudLayoutSpec.refCardPaddingH, 8.0);
      expect(HudLayoutSpec.refCardPaddingV, 6.0);

      // Verify font scale helper clamp
      final scale1 = HudLayoutSpec.calculateFontScale(300.0, 1.0);
      expect(scale1, 1.0);

      final scale2 = HudLayoutSpec.calculateFontScale(100.0, 1.0);
      expect(scale2, 0.82);
    });

    test('formatCoordinates formats MSL vs WGS84 truthfully', () {
      final (_, _, mslSuffix) = HudFormatter.formatCoordinates(22.56, 88.30, 14.66, isMsl: true);
      expect(mslSuffix, ' (Alt: +14.7m)');

      final (_, _, wgsSuffix) = HudFormatter.formatCoordinates(22.56, 88.30, -42.41, isMsl: false);
      expect(wgsSuffix, ' (Alt: -42.4m WGS84)');
    });
  });
}
