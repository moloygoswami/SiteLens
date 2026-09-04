import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/features/camera/widgets/gps_settings_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createTestWidget() {
    return const ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: GpsSettingsModal(),
        ),
      ),
    );
  }

  group('GpsSettingsModal Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Renders GPS Accuracy Threshold modal with default 20m', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('GPS Accuracy Threshold'), findsOneWidget);
      expect(find.text('ACTIVE THRESHOLD'), findsOneWidget);
      expect(find.text('±20.0 m'), findsOneWidget);
      expect(find.text('20 m (Default)'), findsOneWidget);
      expect(find.text('10 m'), findsOneWidget);
      expect(find.text('30 m'), findsOneWidget);
    });

    testWidgets('Tapping a preset chip updates the threshold setting', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap 30 m chip
      final chip30 = find.text('30 m');
      await tester.tap(chip30);
      await tester.pumpAndSettle();

      expect(find.text('±30.0 m'), findsOneWidget);
      expect(find.text('Reset (20m)'), findsOneWidget);

      // Tap Reset button
      await tester.tap(find.text('Reset (20m)'));
      await tester.pumpAndSettle();

      expect(find.text('±20.0 m'), findsOneWidget);
    });
  });
}
