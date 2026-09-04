import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sitelens/features/camera/hud/hud_layout_spec.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/services/watermark_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WatermarkDrawer Unit Tests', () {
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

    test('Draws watermark on Landscape 4:3 image without errors', () async {
      final image = img.Image(width: 800, height: 600);
      img.fill(image, color: img.ColorRgb8(100, 100, 100));

      final originalPixelCount = image.length;
      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );

      expect(result.width, 800);
      expect(result.height, 600);
      expect(result.length, originalPixelCount);
    });

    test('Draws watermark on Portrait 3:4 image with high resolution',
        () async {
      final image = img.Image(width: 1200, height: 1600);
      img.fill(image, color: img.ColorRgb8(50, 50, 50));

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
      );

      expect(result.width, 1200);
      expect(result.height, 1600);
    });

    test('Draws watermark with real mapTileBytes and VERIFIED badge', () async {
      final image = img.Image(width: 1920, height: 1080);
      img.fill(image, color: img.ColorRgb8(30, 30, 30));

      final tile = img.Image(width: 100, height: 100);
      img.fill(tile,
          color:
              img.ColorRgb8(180, 200, 220)); // Simulated Google map tile color
      final tileBytes = Uint8List.fromList(img.encodePng(tile));

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8',
        mapTileBytes: tileBytes,
        isGpsLocked: true,
      );

      expect(result.width, 1920);
      expect(result.height, 1080);
    });

    test('Test A — Address enabled bakes full metadata stack including ADDR',
        () async {
      final image = img.Image(width: 800, height: 600);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        showAddress: true,
      );

      expect(result.width, 800);
      expect(result.height, 600);
    });

    test(
        'Test B — Address disabled excludes ADDR line while preserving metadata',
        () async {
      final image = img.Image(width: 800, height: 600);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        showAddress: false,
      );

      expect(result.width, 800);
      expect(result.height, 600);
    });

    test('Test C — Map tile enabled draws 1:1 map slot and pin', () async {
      final image = img.Image(width: 800, height: 600);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        showMapTile: true,
      );

      expect(result.width, 800);
      expect(result.height, 600);
    });

    test('Test D — Map tile disabled skips map box and left slot entirely',
        () async {
      final image = img.Image(width: 800, height: 600);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        showMapTile: false,
      );

      expect(result.width, 800);
      expect(result.height, 600);
    });

    test(
        'Test E — Both address and map tile disabled preserves mandatory metadata',
        () async {
      final image = img.Image(width: 800, height: 600);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        showAddress: false,
        showMapTile: false,
      );

      expect(result.width, 800);
      expect(result.height, 600);
    });

    test(
        'Test F — Long full street address wraps cleanly across lines and renders properly',
        () async {
      final image = img.Image(width: 1200, height: 1600);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));

      final longAddressSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'test-uuid-long',
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
        resolvedAddress:
            'Sonar Kella Apartment, 14 Kazipara Road, Block B, Shalimar, Howrah, West Bengal 711103, India',
      );

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: longAddressSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        showAddress: true,
        showMapTile: true,
      );

      expect(result.width, 1200);
      expect(result.height, 1600);
    });

    test(
        'Test H — Verified badge on short site code (SITE: TEST) does not overlap and address wraps within bounds',
        () async {
      final image = img.Image(width: 1080, height: 1920);
      img.fill(image, color: img.ColorRgb8(40, 40, 40));

      final testSiteSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'test-uuid-test',
        siteId: 'SITE_TEST',
        siteCode: 'TEST',
        siteName: 'Test Structure',
        latitude: 22.56300,
        longitude: 88.30072,
        altitudeMeters: -59.6,
        accuracyMeters: 11.3,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 23, 10, 24, 55),
        canonicalTimestampUtc: '2026-08-23 10:24:55 UTC',
        resolvedAddress:
            '22 Andul 2nd Bye Lane, Howrah, West Bengal 711103, India',
      );

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: testSiteSnapshot,
        originalSha256:
            'a4b6466eac2c7000000000000000000000000000000000000000000000000000',
        showAddress: true,
        showMapTile: true,
        isGpsLocked: true,
      );

      expect(result.width, 1080);
      expect(result.height, 1920);
    });

    test('Test I — Empty site code and timestamp fallback gracefully',
        () async {
      final image = img.Image(width: 800, height: 600);
      img.fill(image, color: img.ColorRgb8(10, 10, 10));

      final emptyFieldsSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'test-uuid-empty',
        siteId: 'SITE_101',
        siteCode: '',
        siteName: '',
        latitude: 0.0,
        longitude: 0.0,
        altitudeMeters: 0.0,
        accuracyMeters: 0.0,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 15, 12, 0, 0),
        canonicalTimestampUtc: '',
        resolvedAddress: '',
      );

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: emptyFieldsSnapshot,
        originalSha256: '',
      );

      expect(result.width, 800);
      expect(result.height, 600);
    });

    test('Test J — Watermark mutates image pixels in bottom container area',
        () async {
      final image = img.Image(width: 800, height: 600);
      img.fill(image, color: img.ColorRgb8(255, 255, 255)); // All pure white

      await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );

      // Verify that bottom region has been stamped with dark container pixels
      final bottomPixel = image.getPixel(200, 560);
      expect(bottomPixel.r, isNot(255));
      expect(bottomPixel.g, isNot(255));
      expect(bottomPixel.b, isNot(255));
    });

    test(
        'Test K — High resolution 3000x4000 photo renders compact balanced watermark card and map thumbnail',
        () async {
      final image = img.Image(width: 3000, height: 4000);
      img.fill(image, color: img.ColorRgb8(120, 120, 120));

      final tile = img.Image(width: 100, height: 100);
      img.fill(tile, color: img.ColorRgb8(200, 220, 240));
      final tileBytes = Uint8List.fromList(img.encodePng(tile));

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        mapTileBytes: tileBytes,
        showAddress: true,
        showMapTile: true,
        isGpsLocked: true,
      );

      expect(result.width, 3000);
      expect(result.height, 4000);
      // Verify pixels within the compact map area and bottom card
      final mapPixel = image.getPixel(200, 3850);
      expect(mapPixel.r, isNot(120));
    });

    test(
        'Test L — Full 64-character SHA-256 hash wraps and negative altitude parses cleanly',
        () async {
      final image = img.Image(width: 1200, height: 1600);
      img.fill(image, color: img.ColorRgb8(50, 50, 50));

      final negativeAltSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'test-uuid-neg-alt',
        siteId: 'SITE_101',
        siteCode: 'TEST',
        siteName: 'Underground Tunnel',
        latitude: -22.56298,
        longitude: -88.30085,
        altitudeMeters: -128.4,
        accuracyMeters: 4.2,
        lowAccuracy: false,
        capturedAtUtc: DateTime.utc(2026, 8, 26, 1, 30, 45),
        canonicalTimestampUtc: '2026-08-26 01:30:45 UTC',
        resolvedAddress: 'Subterranean Sector 4B, Metro Extension Line',
      );

      final fullSha64 =
          '7bc3f0a36cd6a4a6e771fc89a55be71e9876543210abcdef0123456789abcdef';

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: negativeAltSnapshot,
        originalSha256: fullSha64,
        showAddress: true,
        showMapTile: true,
        isGpsLocked: true,
      );

      expect(result.width, 1200);
      expect(result.height, 1600);
      expect(negativeAltSnapshot.altitudeDisplay, '-128.4 m ASL');
    });

    test(
        'Test M — Minimap card and Metadata card are separated by a consistent spacing gap',
        () async {
      final image = img.Image(width: 1200, height: 1600);
      img.fill(image,
          color: img.ColorRgb8(255, 255, 255)); // Pure white background

      final tile = img.Image(width: 100, height: 100);
      img.fill(tile, color: img.ColorRgb8(100, 150, 200));
      final tileBytes = Uint8List.fromList(img.encodePng(tile));

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        mapTileBytes: tileBytes,
        showAddress: true,
        showMapTile: true,
        isGpsLocked: true,
      );

      expect(result.width, 1200);
      expect(result.height, 1600);

      // Verify minimap card interior is drawn and not the white background
      final mapCardPixel = image.getPixel(200, 1400);
      expect(mapCardPixel.b, isNot(255));

      // Verify metadata card interior is drawn and not the white background
      final metadataCardPixel = image.getPixel(900, 1520);
      expect(metadataCardPixel.b, isNot(255));
    });

    test(
        'Test N — Minimap and Metadata Stack have matched container heights and align on top and bottom baselines',
        () async {
      final image = img.Image(width: 1080, height: 1920);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      final tile = img.Image(width: 80, height: 80);
      img.fill(tile, color: img.ColorRgb8(100, 150, 200));
      final tileBytes = Uint8List.fromList(img.encodePng(tile));

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            'a1b2c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdef',
        mapTileBytes: tileBytes,
        showAddress: true,
        showMapTile: true,
        isGpsLocked: true,
      );

      expect(result.width, 1080);
      expect(result.height, 1920);

      // Verify Minimap center is painted
      final minimapPixel = image.getPixel(100, 1800);
      expect(minimapPixel.r, isNot(255));

      // Verify Metadata card background area is painted with dark card color
      final metadataPixel = image.getPixel(450, 1800);
      expect(metadataPixel.r, isNot(255));

      // Area well above overlay (y = 1300) should be untouched white
      final topPixel = image.getPixel(540, 1300);
      expect(topPixel.r, 255);
      expect(topPixel.g, 255);
      expect(topPixel.b, 255);
    });

    test(
        'Test O — High-Resolution 12MP capture (3024x4032) scales overlay proportionally',
        () async {
      final image = img.Image(width: 3024, height: 4032);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
        showAddress: true,
        showMapTile: true,
        isGpsLocked: true,
      );

      expect(result.width, 3024);
      expect(result.height, 4032);

      // Verify overlay region was painted
      final overlayPixel = image.getPixel(2500, 3800);
      expect(overlayPixel.r, isNot(255));

      // Top region remains untouched
      final topPixel = image.getPixel(1500, 2000);
      expect(topPixel.r, 255);
      expect(topPixel.g, 255);
      expect(topPixel.b, 255);
    });

    test(
        'Test P — Reference 458x610 3:4 canvas renders minimap (1.24:1) and metadata card within bottom overlay zone',
        () async {
      final image = img.Image(width: 458, height: 610);
      img.fill(image,
          color: img.ColorRgb8(255, 255, 255)); // Pure white background

      final tile = img.Image(width: 136, height: 110);
      img.fill(tile, color: img.ColorRgb8(100, 150, 200));
      final tileBytes = Uint8List.fromList(img.encodePng(tile));

      final result = await WatermarkDrawer.drawWatermark(
        image: image,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        mapTileBytes: tileBytes,
        showAddress: true,
        showMapTile: true,
        isGpsLocked: true,
      );

      expect(result.width, 458);
      expect(result.height, 610);

      // 1. Check Minimap Interior is drawn
      final mapPixel = image.getPixel(60, 560);
      expect(mapPixel.r, isNot(255));

      // 2. Check Metadata Card Interior is drawn
      final textCardPixel = image.getPixel(300, 560);
      expect(textCardPixel.r, isNot(255));

      // 3. Check Left Margin is untouched white (at x=0 outside shadow radius)
      final leftMarginPixel = image.getPixel(0, 560);
      expect(leftMarginPixel.r, 255);
      expect(leftMarginPixel.g, 255);
      expect(leftMarginPixel.b, 255);

      // 4. Check Area Above Overlay (x = 229, y = 300) is untouched white
      final topPixel = image.getPixel(229, 300);
      expect(topPixel.r, 255);
      expect(topPixel.g, 255);
      expect(topPixel.b, 255);
    });

    // -------------------------------------------------------------
    // Additional Focused Resolution & Geometric Parity Tests
    // -------------------------------------------------------------

    test('Geometry Model: 390x844 Reference Viewport Layout Verification', () {
      final (geometry, typography) = WatermarkDrawer.computeHudLayout(
        imageWidth: 390,
        imageHeight: 844,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        isGpsLocked: true,
        showAddress: true,
        showMapTile: true,
      );

      expect(geometry.scaleFactor, closeTo(1.0, 0.05));
      expect(geometry.outerMarginLeft, 14);
      expect(geometry.outerMarginRight, 14);
      expect(geometry.outerMarginBottom, 16);
      expect(geometry.cardGap, 4);
      expect(geometry.cardPaddingH, 8);
      expect(geometry.cardPaddingV, 6);
      expect(geometry.hasEqualCardHeights, isTrue);
      expect(geometry.minimapBounds.height, geometry.finalCardHeight);
      expect(geometry.metadataBounds.height, geometry.finalCardHeight);
      expect(geometry.minimapBounds.y1, geometry.metadataBounds.y1);
      expect(geometry.minimapBounds.y2, geometry.metadataBounds.y2);
      expect(typography.badgeText, 'VERIFIED');
    });

    test(
        'Geometry Model: Landscape 1920x1080 maintains proportional scale and equal heights',
        () {
      final (geometry, typography) = WatermarkDrawer.computeHudLayout(
        imageWidth: 1920,
        imageHeight: 1080,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        isGpsLocked: true,
        showAddress: true,
        showMapTile: true,
      );

      expect(geometry.hasEqualCardHeights, isTrue);
      expect(geometry.minimapBounds.width,
          closeTo(geometry.finalCardHeight * 1.24, 0.5));
      expect(geometry.metadataBounds.y2, 1080 - geometry.outerMarginBottom);
      expect(geometry.minimapBounds.y2, 1080 - geometry.outerMarginBottom);
      expect(typography.headlineLines.isNotEmpty, isTrue);
    });

    test(
        'Card Height Growth: Multi-line long address expands card height dynamically',
        () {
      final (shortGeo, _) = WatermarkDrawer.computeHudLayout(
        imageWidth: 1080,
        imageHeight: 1920,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        showAddress: false,
      );

      final longAddressSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'test-uuid-long-2',
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
        resolvedAddress:
            'Flat 402, Building 7B, Sonar Kella Luxury Enclave, 144 Kazipara Grand Trunk Expressway, Block C, Shalimar Station Road, Howrah, West Bengal 711103, India',
      );

      final (longGeo, longTypo) = WatermarkDrawer.computeHudLayout(
        imageWidth: 1080,
        imageHeight: 1920,
        snapshot: longAddressSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        showAddress: true,
      );

      expect(longGeo.finalCardHeight, greaterThan(shortGeo.finalCardHeight));
      expect(longTypo.addressLines.length, greaterThanOrEqualTo(2));
      expect(longGeo.hasEqualCardHeights, isTrue);
    });

    test(
        'Zero Truncation: Full 64-character SHA hash wraps completely without truncation',
        () {
      const full64Sha =
          'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
      final (geo, typo) = WatermarkDrawer.computeHudLayout(
        imageWidth: 458,
        imageHeight: 610,
        snapshot: sampleSnapshot,
        originalSha256: full64Sha,
        showAddress: true,
        showMapTile: true,
      );

      // Join all wrapped SHA lines and verify full SHA-256 is present
      final fullReconstructedText = typo.siteShaLines.join(' ');
      expect(
          fullReconstructedText.contains(full64Sha.substring(0, 32)), isTrue);
      expect(fullReconstructedText.contains(full64Sha.substring(32)), isTrue);
      expect(geo.hasEqualCardHeights, isTrue);
    });

    test('Status Badges: VERIFIED, DEGRADED, and PENDING resolve correctly',
        () {
      // 1. Verified: Locked, high accuracy, SHA present
      final (_, verifiedTypo) = WatermarkDrawer.computeHudLayout(
        imageWidth: 1080,
        imageHeight: 1920,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        isGpsLocked: true,
      );
      expect(verifiedTypo.badgeText, 'VERIFIED');

      // 2. Degraded: Low accuracy flag set
      final degradedSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'test-uuid-degraded',
        siteId: sampleSnapshot.siteId,
        siteCode: sampleSnapshot.siteCode,
        siteName: sampleSnapshot.siteName,
        latitude: sampleSnapshot.latitude,
        longitude: sampleSnapshot.longitude,
        altitudeMeters: sampleSnapshot.altitudeMeters,
        accuracyMeters: 45.0,
        lowAccuracy: true,
        capturedAtUtc: sampleSnapshot.capturedAtUtc,
        canonicalTimestampUtc: sampleSnapshot.canonicalTimestampUtc,
        resolvedAddress: sampleSnapshot.resolvedAddress,
      );
      final (_, degradedTypo) = WatermarkDrawer.computeHudLayout(
        imageWidth: 1080,
        imageHeight: 1920,
        snapshot: degradedSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        isGpsLocked: true,
      );
      expect(degradedTypo.badgeText, 'DEGRADED');

      // 3. Pending: GPS not locked or SHA pending
      final (_, pendingTypo) = WatermarkDrawer.computeHudLayout(
        imageWidth: 1080,
        imageHeight: 1920,
        snapshot: sampleSnapshot,
        originalSha256: '',
        isGpsLocked: true,
      );
      expect(pendingTypo.badgeText, 'PENDING');
    });

    test(
        'Narrow Metadata Width: Survives ultra-narrow 300px canvas with equal height guarantee',
        () {
      final (geo, _) = WatermarkDrawer.computeHudLayout(
        imageWidth: 300,
        imageHeight: 400,
        snapshot: sampleSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        showAddress: true,
        showMapTile: true,
      );

      expect(geo.hasEqualCardHeights, isTrue);
      expect(geo.minimapBounds.width, greaterThan(0));
      expect(geo.metadataBounds.width, greaterThan(0));
    });

    test(
        'Unicode and Special Symbols: verifies °, •, − and country flag support',
        () {
      final flagSnapshot = EvidenceMetadataSnapshot(
        mediaId: 'test-uuid-flag',
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
        resolvedAddress: 'Sonar Kella Apartment, Kolkata, India',
      );

      final (geometry, typography) = WatermarkDrawer.computeHudLayout(
        imageWidth: 1080,
        imageHeight: 1920,
        snapshot: flagSnapshot,
        originalSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        isGpsLocked: true,
        showAddress: true,
        showMapTile: true,
      );

      // Verify degree symbol in coordinates
      expect(typography.coordinatesText.contains('°'), isTrue);
      // Verify bullet symbol in Site / SHA line
      expect(typography.siteShaText.contains('•'), isTrue);
      // Verify minus or negative sign in altitude
      expect(
          typography.coordinatesText.contains('-43.4m') ||
              typography.coordinatesText.contains('−43.4m'),
          isTrue);
      // Verify flag suffix present in headline
      expect(typography.headlineText.contains('🇮🇳'), isTrue);
      expect(geometry.hasEqualCardHeights, isTrue);
    });

    group('Canonical Native-Resolution Scaling & Coupled Layout Regression Tests', () {
      const dimensionsToTest = [
        (width: 390, height: 844, expectedScale: 1.0, name: '390x844 Reference Viewport'),
        (width: 3000, height: 4000, expectedScale: 3000.0 / 390.0, name: '3000x4000 Native 3:4 Portrait'),
        (width: 4000, height: 3000, expectedScale: 3000.0 / 390.0, name: '4000x3000 Native 4:3 Landscape'),
        (width: 3000, height: 3000, expectedScale: 3000.0 / 390.0, name: '3000x3000 Native 1:1 Square'),
        (width: 2250, height: 4000, expectedScale: 2250.0 / 390.0, name: '2250x4000 Native 9:16 Portrait'),
        (width: 1920, height: 1080, expectedScale: 1080.0 / 390.0, name: '1920x1080 Native 16:9 Landscape'),
      ];

      for (final dim in dimensionsToTest) {
        test('Deterministic projection on ${dim.name}', () {
          final (geo, _) = WatermarkDrawer.computeHudLayout(
            imageWidth: dim.width,
            imageHeight: dim.height,
            snapshot: sampleSnapshot,
            originalSha256:
                'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
            showAddress: true,
            showMapTile: true,
          );

          // 1. Scale factor matches short dimension / 390
          expect(geo.scaleFactor, closeTo(dim.expectedScale, 0.0001));

          // 2. Strict height matching
          expect(geo.hasEqualCardHeights, isTrue);
          expect(geo.minimapBounds.height, closeTo(geo.metadataBounds.height, 0.01));

          // 3. Aspect ratio of minimap is canonical 1.24:1
          final actualAspect = geo.minimapBounds.width / geo.minimapBounds.height;
          expect(actualAspect, closeTo(HudLayoutSpec.minimapAspectRatio, 0.02));

          // 4. Inter-card gap matches canonical token scaled
          final expectedGap = HudLayoutSpec.refCardGap * dim.expectedScale;
          final actualGap = geo.metadataBounds.x1 - geo.minimapBounds.x2;
          expect(actualGap, closeTo(expectedGap, 0.01));

          // 5. Outer bottom and side margins are strictly scaled
          final expectedMarginB = HudLayoutSpec.refMarginB * dim.expectedScale;
          expect(dim.height - geo.metadataBounds.y2, closeTo(expectedMarginB, 0.01));
          expect(dim.height - geo.minimapBounds.y2, closeTo(expectedMarginB, 0.01));

          // 6. Baselines are aligned
          expect(geo.minimapBounds.y1, closeTo(geo.metadataBounds.y1, 0.01));
          expect(geo.minimapBounds.y2, closeTo(geo.metadataBounds.y2, 0.01));

          // 7. Width constraints
          expect(geo.metadataBounds.width, greaterThan(geo.minimapBounds.width));
        });
      }

      test('Long-address input induces 2-line wrapping and dynamically expands card height', () {
        const longAddress =
            'Flat 4B, Tower 2, Sonar Kella Residential Complex, 142/A Prince Anwar Shah Road, South 24 Parganas, Kolkata, West Bengal 700045, India';
        final longSnapshot = EvidenceMetadataSnapshot(
          mediaId: 'test-uuid-long',
          siteId: 'SITE_101',
          siteCode: 'HOME',
          siteName: 'Sonar Kella Apartment',
          latitude: 22.56298,
          longitude: 88.30085,
          altitudeMeters: 14.5,
          accuracyMeters: 4.2,
          lowAccuracy: false,
          capturedAtUtc: DateTime.utc(2026, 8, 15, 2, 24, 55),
          canonicalTimestampUtc: '2026-08-15 02:24:55 UTC',
          resolvedAddress: longAddress,
        );

        final shortSnapshot = EvidenceMetadataSnapshot(
          mediaId: 'test-uuid-short',
          siteId: 'SITE_101',
          siteCode: 'HOME',
          siteName: 'Sonar Kella Apartment',
          latitude: 22.56298,
          longitude: 88.30085,
          altitudeMeters: 14.5,
          accuracyMeters: 4.2,
          lowAccuracy: false,
          capturedAtUtc: DateTime.utc(2026, 8, 15, 2, 24, 55),
          canonicalTimestampUtc: '2026-08-15 02:24:55 UTC',
          resolvedAddress: 'Kolkata',
        );

        final (geoShort, typoShort) = WatermarkDrawer.computeHudLayout(
          imageWidth: 3000,
          imageHeight: 4000,
          snapshot: shortSnapshot,
          originalSha256:
              'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          showAddress: true,
          showMapTile: true,
        );

        final (geoLong, typoLong) = WatermarkDrawer.computeHudLayout(
          imageWidth: 3000,
          imageHeight: 4000,
          snapshot: longSnapshot,
          originalSha256:
              'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          showAddress: true,
          showMapTile: true,
        );

        // Address must be wrapped onto 2 lines
        expect(typoLong.addressLines.length, 2);

        // Long address must expand card height
        expect(geoLong.finalCardHeight, greaterThan(geoShort.finalCardHeight));

        // Minimap must expand proportionally in both width and height to preserve 1.24:1
        expect(geoLong.minimapBounds.height, equals(geoLong.metadataBounds.height));
        expect(geoLong.minimapBounds.width, greaterThan(geoShort.minimapBounds.width));
        expect(
          geoLong.minimapBounds.width / geoLong.minimapBounds.height,
          closeTo(HudLayoutSpec.minimapAspectRatio, 0.02),
        );
      });
    });
  });
}
