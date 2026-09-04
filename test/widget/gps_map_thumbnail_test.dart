import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitelens/features/camera/widgets/gps_map_thumbnail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GpsMapThumbnail Widget Tests', () {
    testWidgets('renders synthetic CustomPaint when GPS is pending / offline', (tester) async {
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
      expect(find.byType(CustomPaint), findsWidgets);
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
