import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitelens/features/camera/camera_screen.dart';
import 'package:sitelens/features/camera/widgets/camera_top_hud.dart';
import 'package:sitelens/features/camera/widgets/camera_viewfinder.dart';
import 'package:sitelens/features/camera/widgets/timestamp_settings_modal.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens GPS Telemetry, Timestamp & Watermark E2E (E2E-07)', () {
    testWidgets('Top HUD GPS pill formatting, timestamp modal, and watermark preview HUD',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);

      // Open camera
      await tester.tap(find.text('Confirm Site & Open Camera'));
      await tester.pumpAndSettle();

      expect(find.byType(CameraScreen), findsOneWidget);
      expect(find.byType(CameraTopHud), findsOneWidget);
      expect(find.byType(GpsStatusPill), findsOneWidget);

      // 1. Watermark Preview HUD exists and displays technical metadata
      expect(find.byType(WatermarkPreview), findsOneWidget);
      expect(find.textContaining('SITE:'), findsOneWidget);
      expect(find.textContaining('LAT:'), findsOneWidget);
      expect(find.textContaining('LON:'), findsOneWidget);

      // 2. Timestamp settings modal
      final timestampStrip = find.byIcon(Icons.schedule_rounded);
      expect(timestampStrip, findsOneWidget);

      await tester.tap(timestampStrip);
      await tester.pumpAndSettle();

      expect(find.text('Overlay Timestamp Settings'), findsOneWidget);
      expect(find.textContaining('Local Time'), findsOneWidget);

      // Close modal
      final closeBtn = find.descendant(
        of: find.byType(TimestampSettingsModal),
        matching: find.byIcon(Icons.close_rounded),
      );
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pumpAndSettle();
      }

      expect(find.text('Overlay Timestamp Settings'), findsNothing);
    });
  });
}
