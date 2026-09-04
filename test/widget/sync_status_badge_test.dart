import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/features/sync/models/sync_state.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';
import 'package:sitelens/features/sync/widgets/sync_status_badge.dart';

class FakeSyncCoordinatorNotifier extends StateNotifier<SyncState> implements SyncCoordinator {
  int manualTriggerCount = 0;
  int autoTriggerCount = 0;

  FakeSyncCoordinatorNotifier(super.state);

  @override
  Future<void> triggerSync({bool isManual = false}) async {
    if (isManual) {
      manualTriggerCount++;
    } else {
      autoTriggerCount++;
    }
  }

  void updateState(SyncState newState) {
    state = newState;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeSyncCoordinatorNotifier fakeCoordinator;

  Widget buildBadgeTestWidget({
    required SyncState initialState,
    bool compact = false,
  }) {
    fakeCoordinator = FakeSyncCoordinatorNotifier(initialState);

    return ProviderScope(
      overrides: [
        syncCoordinatorProvider.overrideWith((ref) => fakeCoordinator),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SyncStatusBadge(compact: compact),
          ),
        ),
      ),
    );
  }

  group('SyncStatusBadge Widget Tests', () {
    testWidgets('1. Fully Synced State: Displays green All synced and cloud_done icon', (tester) async {
      await tester.pumpWidget(
        buildBadgeTestWidget(
          initialState: const SyncState(
            isOnline: true,
            isSyncing: false,
            pendingCount: 0,
            failedCount: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All synced'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);

      // Tap triggers manual sync
      await tester.tap(find.byType(SyncStatusBadge));
      await tester.pumpAndSettle();

      expect(fakeCoordinator.manualTriggerCount, equals(1));
      expect(find.text('Checking cloud synchronization...'), findsOneWidget);
    });

    testWidgets('2. Pending State: Displays blue pending count and cloud_upload icon', (tester) async {
      await tester.pumpWidget(
        buildBadgeTestWidget(
          initialState: const SyncState(
            isOnline: true,
            isSyncing: false,
            pendingCount: 3,
            failedCount: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3 pending'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);

      // Tap triggers manual sync
      await tester.tap(find.byType(SyncStatusBadge));
      await tester.pumpAndSettle();

      expect(fakeCoordinator.manualTriggerCount, equals(1));
      expect(find.text('Checking cloud synchronization...'), findsOneWidget);
    });

    testWidgets('3. Syncing State: Displays primary Syncing text and spinning CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(
        buildBadgeTestWidget(
          initialState: const SyncState(
            isOnline: true,
            isSyncing: true,
            pendingCount: 2,
            failedCount: 0,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Syncing (2)...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Tap is non-interactive while syncing
      await tester.tap(find.byType(SyncStatusBadge));
      await tester.pump();

      expect(fakeCoordinator.manualTriggerCount, equals(0));
    });

    testWidgets('4. Failed State: Displays red failed count with retry affordance', (tester) async {
      await tester.pumpWidget(
        buildBadgeTestWidget(
          initialState: const SyncState(
            isOnline: true,
            isSyncing: false,
            pendingCount: 0,
            failedCount: 4,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('4 failed — Retry'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      // Tap triggers retry
      await tester.tap(find.byType(SyncStatusBadge));
      await tester.pumpAndSettle();

      expect(fakeCoordinator.manualTriggerCount, equals(1));
      expect(find.text('Retrying synchronization...'), findsOneWidget);
    });

    testWidgets('5. Offline State: Displays orange Offline badge and cloud_off icon', (tester) async {
      await tester.pumpWidget(
        buildBadgeTestWidget(
          initialState: const SyncState(
            isOnline: false,
            isSyncing: false,
            pendingCount: 5,
            failedCount: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Offline (5)'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);

      // Tap is non-interactive when offline
      await tester.tap(find.byType(SyncStatusBadge));
      await tester.pump();

      expect(fakeCoordinator.manualTriggerCount, equals(0));
    });

    testWidgets('6. Compact Mode: Renders only icon/spinner without text label', (tester) async {
      await tester.pumpWidget(
        buildBadgeTestWidget(
          initialState: const SyncState(
            isOnline: true,
            isSyncing: false,
            pendingCount: 2,
            failedCount: 0,
          ),
          compact: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 pending'), findsNothing);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    });
  });
}
