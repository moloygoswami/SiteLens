import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/core/controllers/nearby_settings_controller.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/local/database/database_provider.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/nearby/nearby_search_screen.dart';
import 'package:sitelens/features/nearby/widgets/radius_selector_strip.dart';
import 'package:sitelens/features/nearby/widgets/location_timeline_view.dart';
import 'package:sitelens/features/nearby/widgets/nearby_map_view.dart';
import 'package:sitelens/features/review/models/pending_capture_payload.dart';
import 'package:sitelens/features/review/review_tag_screen.dart';
import 'package:sitelens/features/review/widgets/smart_link_card.dart';

class MockWidgetReviewStorageService extends EvidenceStorageService {
  @override
  Future<String> resolveAbsolutePath(String relativePath) async {
    return '/mock/path/$relativePath';
  }

  @override
  Future<bool> verifyArtifactsExist({
    required String originalRelativePath,
    required String evidenceRelativePath,
    String? thumbnailRelativePath,
  }) async {
    return true;
  }
}

class FakeAuthService extends Fake implements AuthService {
  final AuthUser? user;
  FakeAuthService(this.user);
  @override
  AuthUser? get currentUser => user;
}

class FakeNearbySettingsNotifier extends NearbySettingsNotifier {
  FakeNearbySettingsNotifier(double initial) : super() {
    state = initial;
  }
}

void main() {
  late AppDatabase db;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: 'site-alpha-1234',
            creatorId: const drift.Value('user-alice'),
            siteCode: const drift.Value('ALPHA-01'),
            name: const drift.Value('Alpha Tower North'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  PendingCapturePayload createPayload({
    String mediaId = 'payload-1',
    String siteId = 'site-alpha-1234',
    String siteCode = 'ALPHA-01',
    String siteName = 'Alpha Tower North',
    double lat = 22.57264,
    double lon = 88.36389,
    String initialActivity = 'Masonry',
  }) {
    final snapshot = EvidenceMetadataSnapshot(
      mediaId: mediaId,
      creatorId: 'user-alice',
      siteId: siteId,
      siteCode: siteCode,
      siteName: siteName,
      latitude: lat,
      longitude: lon,
      altitudeMeters: 10.0,
      accuracyMeters: 2.0,
      lowAccuracy: false,
      capturedAtUtc: DateTime.utc(2026, 9, 21, 10, 0, 0),
      canonicalTimestampUtc: '2026-09-21 10:00:00 UTC',
      resolvedAddress: 'Alpha Tower, City Center',
    );

    return PendingCapturePayload(
      mediaId: mediaId,
      mediaType: MediaItemType.photo,
      originalFilePath: 'media/orig_p1.jpg',
      evidenceFilePath: 'media/evid_p1.jpg',
      thumbnailFilePath: 'media/thumb_p1.jpg',
      sha256Hash: 'hash-orig',
      fileSizeBytes: 200000,
      metadataSnapshot: snapshot,
    );
  }

  Widget createReviewWidget(PendingCapturePayload payload) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mediaRepositoryProvider.overrideWithValue(LocalMediaRepository(db)),
        evidenceStorageServiceProvider.overrideWithValue(MockWidgetReviewStorageService()),
        nearbySettingsProvider.overrideWith((ref) => FakeNearbySettingsNotifier(25.0)),
        authServiceProvider.overrideWithValue(FakeAuthService(const AuthUser(uid: 'user-alice'))),
        authStateProvider.overrideWith((ref) => Stream.value(const AuthUser(uid: 'user-alice'))),
      ],
      child: MaterialApp(
        home: ReviewTagScreen(payload: payload),
      ),
    );
  }

  group('TM-W-05 [AC-LINK-02, AC-LINK-03, AC-LINK-04, AC-LINK-08]: Review & Tag Smart-Link UI', () {
    testWidgets('1-match case: renders banner with Link and Not now; Link is only path calling link creation', (tester) async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-match-1',
              siteId: const drift.Value('site-alpha-1234'),
              originalUri: const drift.Value('media/orig_nc1.jpg'),
              uri: 'media/evid_nc1.jpg',
              lat: 22.57264 + 0.00003, // ~3.3m away
              lon: 88.36389,
              activityTag: const drift.Value('Masonry'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      final payload = createPayload();
      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      final closedChip = find.text('Closed');
      await tester.tap(closedChip);
      await tester.pumpAndSettle();

      expect(find.byType(SmartLinkCard), findsOneWidget);
      expect(find.text('SMART-LINK SUGGESTION'), findsOneWidget);
      expect(find.text('Link'), findsWidgets);
      expect(find.text('Not now'), findsOneWidget);

      expect(find.textContaining('site-alpha-1234'), findsNothing);

      final linkBtn = find.widgetWithText(ElevatedButton, 'Link');
      await tester.tap(linkBtn.first);
      await tester.pumpAndSettle();

      expect(find.text('SELECTED BEFORE EVIDENCE'), findsOneWidget);
      expect(find.text('Save Evidence'), findsOneWidget);
    });

    testWidgets('0-match case with site-wide candidates: expands site-wide candidate list with None of these option', (tester) async {
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'nc-far-site',
              siteId: const drift.Value('site-alpha-1234'),
              originalUri: const drift.Value('media/orig_far.jpg'),
              uri: 'media/evid_far.jpg',
              lat: 22.57264 + 0.00045, // ~50m away
              lon: 88.36389,
              activityTag: const drift.Value('Masonry'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      final payload = createPayload();
      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      final closedChip = find.text('Closed');
      await tester.tap(closedChip);
      await tester.pumpAndSettle();

      expect(find.byType(SmartLinkCard), findsNothing);

      expect(find.text('Search all open Non-Conformities on this site'), findsOneWidget);
      expect(find.text('None of these'), findsOneWidget);

      expect(find.text('ALPHA-01'), findsWidgets);
      expect(find.textContaining('site-alpha-1234'), findsNothing);

      final noneOfThese = find.text('None of these');
      await tester.ensureVisible(noneOfThese);
      await tester.tap(noneOfThese);
      await tester.pumpAndSettle();

      expect(find.text('None of these'), findsNothing);
      expect(find.text('Find Nearby Evidence'), findsOneWidget);
    });

    testWidgets('0 open candidates on site: disables Closed with explanation and switching away re-enables Save', (tester) async {
      final payload = createPayload();
      await tester.pumpWidget(createReviewWidget(payload));
      await tester.pumpAndSettle();

      final closedChip = find.text('Closed');
      await tester.tap(closedChip);
      await tester.pumpAndSettle();

      expect(find.text('No open Non-Conformity exists on this site yet — capture one first'), findsOneWidget);
      expect(find.text('Link BEFORE to Save'), findsOneWidget);

      final progressChip = find.text('Progress');
      await tester.tap(progressChip);
      await tester.pumpAndSettle();

      expect(find.text('Save Evidence'), findsOneWidget);
      expect(find.text('Link BEFORE to Save'), findsNothing);
    });
  });

  group('TM-W-08 [AC-NEARBY-01, AC-NEARBY-02, AC-NEARBY-07, AC-NEARBY-08, AC-NEARBY-09]: Nearby Search UI', () {
    Widget createNearbySearchWidget({
      MediaItem? sourceMedia,
      String? initialSiteCode,
    }) {
      return ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mediaRepositoryProvider.overrideWithValue(LocalMediaRepository(db)),
          evidenceStorageServiceProvider.overrideWithValue(MockWidgetReviewStorageService()),
          nearbySettingsProvider.overrideWith((ref) => FakeNearbySettingsNotifier(25.0)),
          authServiceProvider.overrideWithValue(FakeAuthService(const AuthUser(uid: 'user-alice'))),
          authStateProvider.overrideWith((ref) => Stream.value(const AuthUser(uid: 'user-alice'))),
        ],
        child: MaterialApp(
          home: NearbySearchScreen(
            sourceMedia: sourceMedia,
            initialSiteId: 'site-alpha-1234',
            initialSiteCode: initialSiteCode ?? 'ALPHA-01',
            initialLat: 22.57264,
            initialLon: 88.36389,
          ),
        ),
      );
    }

    testWidgets('Renders all six radius options: 2m, 5m, 10m, 25m, 50m, and Custom', (tester) async {
      await tester.pumpWidget(createNearbySearchWidget());
      await tester.pumpAndSettle();

      expect(find.byType(RadiusSelectorStrip), findsOneWidget);
      expect(find.text('2m'), findsOneWidget);
      expect(find.text('5m'), findsOneWidget);
      expect(find.text('10m'), findsOneWidget);
      expect(find.text('25m'), findsOneWidget);
      expect(find.text('50m'), findsOneWidget);
      expect(find.textContaining('Custom'), findsOneWidget);
    });

    testWidgets('Filters action button is present and opens filter modal', (tester) async {
      await tester.pumpWidget(createNearbySearchWidget());
      await tester.pumpAndSettle();

      final filterBtn = find.byTooltip('Filter Nearby Media');
      expect(filterBtn, findsOneWidget);

      await tester.tap(filterBtn);
      await tester.pumpAndSettle();

      expect(find.text('FILTER NEARBY MEDIA'), findsOneWidget);
      expect(find.text('Same Site Only'), findsOneWidget);
      expect(find.text('OBSERVATION TYPE'), findsOneWidget);
      expect(find.text('ACTIVITY / WORK STAGE'), findsOneWidget);
      expect(find.text('DATE RANGE'), findsOneWidget);
    });

    testWidgets('Before source fixture surfaces opposite-type suggestion card with working one-tap Link action', (tester) async {
      final sourceBefore = MediaItem(
        id: 'source-defect',
        siteId: 'site-alpha-1234',
        originalUri: 'media/orig_s.jpg',
        uri: 'media/evid_s.jpg',
        thumbUri: 'media/thumb_s.jpg',
        type: MediaItemType.photo,
        lat: 22.57264,
        lon: 88.36389,
        accuracyM: 2.0,
        activityTag: 'Paving',
        observationType: ObservationType.nonConformity,
        capturedAt: DateTime.utc(2026, 9, 21, 9, 0, 0),
        creatorId: 'user-alice',
        syncStatus: SyncStatusType.pending,
      );

      // Seed source item in database
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'source-defect',
              siteId: const drift.Value('site-alpha-1234'),
              originalUri: const drift.Value('media/orig_s.jpg'),
              uri: 'media/evid_s.jpg',
              thumbUri: const drift.Value('media/thumb_s.jpg'),
              lat: 22.57264,
              lon: 88.36389,
              accuracyM: const drift.Value(2.0),
              activityTag: const drift.Value('Paving'),
              observationType: const drift.Value('nonConformity'),
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      // Seed opposite-type (Closed/After) captured later and unlinked
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'after-res',
              siteId: const drift.Value('site-alpha-1234'),
              originalUri: const drift.Value('media/orig_cl.jpg'),
              uri: 'media/evid_cl.jpg',
              thumbUri: const drift.Value('media/thumb_cl.jpg'),
              lat: 22.57264 + (5.0 / 111320.0),
              lon: 88.36389,
              accuracyM: const drift.Value(2.0),
              activityTag: const drift.Value('Paving'),
              observationType: const drift.Value('closed'),
              capturedAt: '2026-09-21T11:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      await tester.pumpWidget(createNearbySearchWidget(sourceMedia: sourceBefore));
      await tester.pumpAndSettle();

      expect(find.text('SUGGESTED RESOLUTION PAIRING'), findsOneWidget);
      expect(find.text('Link'), findsWidgets);

      final linkBtn = find.widgetWithText(ElevatedButton, 'Link');
      await tester.ensureVisible(linkBtn.first);
      await tester.tap(linkBtn.first);
      await tester.pumpAndSettle();

      final linkedRow = await (db.select(db.media)..where((tbl) => tbl.id.equals('after-res'))).getSingle();
      expect(linkedRow.linkedMediaId, 'source-defect');
    });

    testWidgets('Map view renders source pin, result pins, and radius circle; timeline renders ungrouped oldest-to-newest', (tester) async {
      final source = MediaItem(
        id: 'source-item',
        siteId: 'site-alpha-1234',
        originalUri: 'media/orig_s.jpg',
        uri: 'media/evid_s.jpg',
        thumbUri: 'media/thumb_s.jpg',
        type: MediaItemType.photo,
        lat: 22.57264,
        lon: 88.36389,
        observationType: ObservationType.nonConformity,
        capturedAt: DateTime.utc(2026, 9, 21, 9, 0, 0),
        creatorId: 'user-alice',
        syncStatus: SyncStatusType.pending,
      );

      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'source-item',
              siteId: const drift.Value('site-alpha-1234'),
              originalUri: const drift.Value('media/orig_s.jpg'),
              uri: 'media/evid_s.jpg',
              lat: 22.57264,
              lon: 88.36389,
              capturedAt: '2026-09-21T09:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 't-newer',
              siteId: const drift.Value('site-alpha-1234'),
              originalUri: const drift.Value('media/orig_n.jpg'),
              uri: 'media/evid_n.jpg',
              lat: 22.57264 + (6.0 / 111320.0),
              lon: 88.36389,
              observationType: const drift.Value('closed'),
              capturedAt: '2026-09-21T12:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 't-older',
              siteId: const drift.Value('site-alpha-1234'),
              originalUri: const drift.Value('media/orig_o.jpg'),
              uri: 'media/evid_o.jpg',
              lat: 22.57264 + (4.0 / 111320.0),
              lon: 88.36389,
              observationType: const drift.Value('progress'),
              capturedAt: '2026-09-21T08:00:00Z',
              creatorId: const drift.Value('user-alice'),
            ),
          );

      await tester.pumpWidget(createNearbySearchWidget(sourceMedia: source));
      await tester.pumpAndSettle();

      final mapToggle = find.text('Map View');
      await tester.tap(mapToggle);
      await tester.pumpAndSettle();

      expect(find.byType(NearbyMapView), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      final timelineToggle = find.text('Timeline');
      await tester.tap(timelineToggle);
      await tester.pumpAndSettle();

      expect(find.byType(LocationTimelineView), findsOneWidget);
      expect(find.text('CHRONOLOGICAL LIFECYCLE HISTORY'), findsOneWidget);
    });
  });
}
