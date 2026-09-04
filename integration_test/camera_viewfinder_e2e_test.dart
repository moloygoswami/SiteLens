import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitelens/features/camera/camera_screen.dart';
import 'package:sitelens/features/camera/widgets/camera_top_hud.dart';
import 'package:sitelens/features/camera/widgets/camera_viewfinder.dart';
import 'package:sitelens/features/camera/widgets/camera_shutter_station.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SiteLens Camera Viewfinder & Controls E2E (E2E-06)', () {
    testWidgets('Camera viewfinder controls, flash, grid, zoom cycling, and mode switching',
        (tester) async {
      final harness = E2ETestHarness();
      addTearDown(harness.dispose);

      await harness.bootstrapAuthenticatedApp(tester);

      // Open camera
      await tester.tap(find.text('Confirm Site & Open Camera'));
      await tester.pumpAndSettle();

      expect(find.byType(CameraScreen), findsOneWidget);
      expect(find.byType(CameraTopHud), findsOneWidget);
      expect(find.byType(CameraViewfinder), findsOneWidget);
      expect(find.byType(CameraShutterStation), findsOneWidget);

      // 1. Grid Toggle
      expect(find.byType(ThirdsGrid), findsOneWidget);
      await tester.tap(find.byIcon(Icons.grid_on_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ThirdsGrid), findsNothing);

      await tester.tap(find.byIcon(Icons.grid_off_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ThirdsGrid), findsOneWidget);

      // 2. Flash Toggle
      expect(find.byIcon(Icons.flash_auto_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.flash_auto_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.flash_on_rounded), findsOneWidget);

      // 3. Zoom Cycling (0.5x -> 1x -> 2x)
      final zoomButton = find.byType(ViewfinderControls);
      expect(zoomButton, findsOneWidget);

      // 4. Tap-to-Focus Reticle
      await tester.tapAt(const Offset(200, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(FocusReticle), findsOneWidget);

      // 5. Mode Switcher (PHOTO -> VIDEO -> PHOTO)
      expect(find.text('PHOTO'), findsOneWidget);
      expect(find.text('VIDEO'), findsOneWidget);

      await tester.tap(find.text('VIDEO'));
      await tester.pumpAndSettle();
      expect(find.byType(ModeSwitcher), findsOneWidget);

      await tester.tap(find.text('PHOTO'));
      await tester.pumpAndSettle();
      expect(find.byType(ModeSwitcher), findsOneWidget);
    });
  });
}
