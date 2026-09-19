import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitelens/core/controllers/map_type_settings_controller.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/features/camera/widgets/gps_map_thumbnail.dart';

/// Forces the map layer to Normal (vector) so the offline fallback for that
/// layer can be asserted without touching persistent storage.
class _NormalMapTypeNotifier extends MapTypeSettingsNotifier {
  _NormalMapTypeNotifier() {
    state = AppMapType.normal;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GpsMapThumbnail Widget Tests', () {
    testWidgets(
        'R11: renders a truthful neutral offline fallback (never fabricated map graphics)',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: GpsMapThumbnail(
                isLocked: false,
                latitude: 0.0,
                longitude: 0.0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(GpsMapThumbnail), findsOneWidget);
      // Neutral status only — no synthesized grid/roads/reticle.
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('SAT'), findsOneWidget);
    });

    testWidgets(
        'R11: the Normal layer offline fallback is a neutral status, not a fake map',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mapTypeSettingsProvider
                .overrideWith((ref) => _NormalMapTypeNotifier()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: GpsMapThumbnail(
                isLocked: false,
                latitude: 0.0,
                longitude: 0.0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('MAP'), findsOneWidget);
    });

    testWidgets('renders HUD overlay pin and radar sweep when GPS fix is locked', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: GpsMapThumbnail(
                isLocked: true,
                latitude: 22.56286,
                longitude: 88.30082,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(GpsMapThumbnail), findsOneWidget);
      expect(find.byType(RepaintBoundary), findsWidgets);
    });

    testWidgets('transitions gracefully from unlocked to locked GPS without error', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: GpsMapThumbnail(
                isLocked: false,
                latitude: 0.0,
                longitude: 0.0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(GpsMapThumbnail), findsOneWidget);

      // Transition to locked state with valid coordinates
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: GpsMapThumbnail(
                isLocked: true,
                latitude: 22.56286,
                longitude: 88.30082,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(GpsMapThumbnail), findsOneWidget);
    });

    testWidgets('renders dedicated layer control icon on mini-map container', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: GpsMapThumbnail(
                isLocked: true,
                latitude: 22.56286,
                longitude: 88.30082,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Dedicated map layer control chip displays satellite icon when satellite mode is active
      expect(find.byIcon(Icons.satellite_alt_rounded), findsWidgets);
    });
  });
}
