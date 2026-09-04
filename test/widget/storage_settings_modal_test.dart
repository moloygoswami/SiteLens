import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/core/models/storage_cleanup_models.dart';
import 'package:sitelens/core/services/storage_cleanup_service.dart';
import 'package:sitelens/features/settings/widgets/storage_settings_modal.dart';

class FakeStorageCleanupService implements StorageCleanupService {
  StorageCleanupSummary summary;
  StorageCleanupResult? cleanupResult;
  bool wasCleanCalled = false;

  FakeStorageCleanupService({
    this.summary = const StorageCleanupSummary(
      eligiblePhotosCount: 5,
      reclaimableBytes: 15 * 1024 * 1024,
      totalPhotosCount: 10,
      totalVideosCount: 3,
      syncedPhotosCount: 5,
    ),
    this.cleanupResult,
  });

  @override
  Future<StorageCleanupSummary> getCleanupSummary({
    Set<String>? activeSyncingIds,
    String? creatorId,
  }) async {
    if (wasCleanCalled) {
      return const StorageCleanupSummary(
        eligiblePhotosCount: 0,
        reclaimableBytes: 0,
        totalPhotosCount: 10,
        totalVideosCount: 3,
        syncedPhotosCount: 5,
      );
    }
    return summary;
  }

  @override
  Future<StorageCleanupResult> clearSyncedPhotoOriginals({
    Set<String>? activeSyncingIds,
    String? creatorId,
  }) async {
    wasCleanCalled = true;
    return cleanupResult ??
        const StorageCleanupResult(
          eligibleCount: 5,
          successfullyDeletedCount: 5,
          skippedCount: 0,
          failedCount: 0,
          bytesReclaimed: 15 * 1024 * 1024,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createTestWidget(FakeStorageCleanupService fakeService) {
    return ProviderScope(
      overrides: [
        storageCleanupServiceProvider.overrideWithValue(fakeService),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: StorageSettingsModal(),
        ),
      ),
    );
  }

  group('StorageSettingsModal Widget Tests', () {
    testWidgets('19-21. Displays eligible count, reclaimable size, and video retention notice', (tester) async {
      final fakeService = FakeStorageCleanupService();
      await tester.pumpWidget(createTestWidget(fakeService));
      await tester.pumpAndSettle();

      // Modal title
      expect(find.text('Storage Management'), findsOneWidget);

      // Eligible count & reclaimable MB
      expect(find.text('5 Photos Eligible'), findsOneWidget);
      expect(find.text('15.0 MB'), findsOneWidget);

      // Video retention notice (21)
      expect(find.textContaining('3 Videos retained locally'), findsOneWidget);
      expect(find.textContaining('offline playback preserved'), findsOneWidget);

      // Button is enabled
      expect(find.text('Clear Synced Photo Originals (15.0 MB)'), findsOneWidget);
    });

    testWidgets('20 & 22. Tapping Clear Originals opens confirmation dialog; Cancel dismisses without deletion', (tester) async {
      final fakeService = FakeStorageCleanupService();
      await tester.pumpWidget(createTestWidget(fakeService));
      await tester.pumpAndSettle();

      // Tap action button
      await tester.tap(find.text('Clear Synced Photo Originals (15.0 MB)'));
      await tester.pumpAndSettle();

      // Verify confirmation dialog
      expect(find.text('Clear Synced Originals'), findsOneWidget);
      expect(find.textContaining('This will locally delete 5 synced raw camera original files'), findsOneWidget);
      expect(find.textContaining('Videos (orig_*.mp4) are NOT deleted.'), findsOneWidget);
      expect(find.textContaining('Watermarked evidence (evid_*.jpg) is retained.'), findsOneWidget);

      // Tap Cancel button (22)
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog closed, no cleanup called
      expect(find.text('Clear Synced Originals'), findsNothing);
      expect(fakeService.wasCleanCalled, isFalse);
    });

    testWidgets('23. Confirming dialog triggers cleanup and updates UI state', (tester) async {
      final fakeService = FakeStorageCleanupService();
      await tester.pumpWidget(createTestWidget(fakeService));
      await tester.pumpAndSettle();

      // Tap action button
      await tester.tap(find.text('Clear Synced Photo Originals (15.0 MB)'));
      await tester.pumpAndSettle();

      // Tap Clear Originals in dialog (23)
      await tester.tap(find.widgetWithText(ElevatedButton, 'Clear Originals'));
      await tester.pumpAndSettle();

      expect(fakeService.wasCleanCalled, isTrue);

      // State updated to 0 eligible
      expect(find.text('0 Photos Eligible'), findsOneWidget);
      expect(find.text('No Synced Originals to Clear'), findsOneWidget);
    });
  });
}
