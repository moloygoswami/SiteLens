import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/shared/utils/responsive_layout.dart';

void main() {
  group('ResponsiveBreakpoints Constants', () {
    test('standardizes mobile, tablet, and desktop breakpoints', () {
      expect(ResponsiveBreakpoints.compactMax, 600.0);
      expect(ResponsiveBreakpoints.mediumMax, 840.0);
      expect(ResponsiveBreakpoints.expandedMin, 840.0);
      expect(ResponsiveBreakpoints.maxContentWidth, 1200.0);
      expect(ResponsiveBreakpoints.maxFormWidth, 520.0);
    });
  });

  group('ResponsiveContext Extension on BuildContext', () {
    testWidgets('identifies compact screen (<600dp)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      late bool isCompact;
      late bool isMedium;
      late bool isExpanded;
      late bool isTabletOrDesktop;
      late String responsiveVal;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              isCompact = context.isCompact;
              isMedium = context.isMedium;
              isExpanded = context.isExpanded;
              isTabletOrDesktop = context.isTabletOrDesktop;
              responsiveVal = context.responsiveValue(
                compact: 'mobile',
                medium: 'tablet',
                expanded: 'desktop',
              );
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isCompact, isTrue);
      expect(isMedium, isFalse);
      expect(isExpanded, isFalse);
      expect(isTabletOrDesktop, isFalse);
      expect(responsiveVal, 'mobile');
    });

    testWidgets('identifies medium screen (600-840dp)', (tester) async {
      tester.view.physicalSize = const Size(700, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      late bool isCompact;
      late bool isMedium;
      late bool isExpanded;
      late bool isTabletOrDesktop;
      late String responsiveVal;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              isCompact = context.isCompact;
              isMedium = context.isMedium;
              isExpanded = context.isExpanded;
              isTabletOrDesktop = context.isTabletOrDesktop;
              responsiveVal = context.responsiveValue(
                compact: 'mobile',
                medium: 'tablet',
                expanded: 'desktop',
              );
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isCompact, isFalse);
      expect(isMedium, isTrue);
      expect(isExpanded, isFalse);
      expect(isTabletOrDesktop, isTrue);
      expect(responsiveVal, 'tablet');
    });

    testWidgets('identifies expanded screen (>=840dp)', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      late bool isCompact;
      late bool isMedium;
      late bool isExpanded;
      late bool isTabletOrDesktop;
      late bool isLandscape;
      late String responsiveVal;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              isCompact = context.isCompact;
              isMedium = context.isMedium;
              isExpanded = context.isExpanded;
              isTabletOrDesktop = context.isTabletOrDesktop;
              isLandscape = context.isLandscape;
              responsiveVal = context.responsiveValue(
                compact: 'mobile',
                medium: 'tablet',
                expanded: 'desktop',
              );
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isCompact, isFalse);
      expect(isMedium, isFalse);
      expect(isExpanded, isTrue);
      expect(isTabletOrDesktop, isTrue);
      expect(isLandscape, isTrue);
      expect(responsiveVal, 'desktop');
    });
  });

  group('ResponsiveContainer Widget', () {
    testWidgets('centers and constraints content correctly', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ResponsiveContainer(
              maxWidth: 500,
              child: Text('Constrained Container Content'),
            ),
          ),
        ),
      );

      expect(find.text('Constrained Container Content'), findsOneWidget);
      final constrainedBox = tester.widget<ConstrainedBox>(
        find.descendant(of: find.byType(ResponsiveContainer), matching: find.byType(ConstrainedBox)),
      );
      expect(constrainedBox.constraints.maxWidth, 500.0);
    });
  });

  group('ResponsiveTwoPane Widget', () {
    testWidgets('renders single column stack on compact viewport', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ResponsiveTwoPane(
              pane1: Text('PRIMARY_PANE'),
              pane2: Text('SECONDARY_PANE'),
            ),
          ),
        ),
      );

      expect(find.text('PRIMARY_PANE'), findsOneWidget);
      expect(find.text('SECONDARY_PANE'), findsOneWidget);
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('renders side-by-side Row on tablet viewport', (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ResponsiveTwoPane(
              pane1: Text('PRIMARY_PANE'),
              pane2: Text('SECONDARY_PANE'),
            ),
          ),
        ),
      );

      expect(find.text('PRIMARY_PANE'), findsOneWidget);
      expect(find.text('SECONDARY_PANE'), findsOneWidget);
      expect(find.byType(Row), findsWidgets);
    });
  });
}
