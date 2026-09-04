import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/shared/widgets/app_drawer_icon.dart';

void main() {
  group('AppDrawerIcon Widget Tests', () {
    testWidgets('Renders AppDrawerIcon with custom size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppDrawerIcon(
                size: 96,
                tooltip: 'SiteLens Aperture',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AppDrawerIcon), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('Triggers onTap callback on tap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppDrawerIcon(
                size: 64,
                onTap: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AppDrawerIcon));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('Handles hover gesture gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppDrawerIcon(size: 80),
            ),
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.byType(AppDrawerIcon)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(AppDrawerIcon), findsOneWidget);
    });
  });
}
