// ignore_for_file: subtype_of_sealed_class, must_be_immutable, annotate_overrides
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:sitelens/core/utils/crypto_utils.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/domain/models/site_model.dart';
import 'package:sitelens/features/camera/hud/hud_data.dart';
import 'package:sitelens/features/sync/services/cloud_sync_service.dart';

class FakeFullMetadata implements FullMetadata {
  @override
  final Map<String, String>? customMetadata;

  FakeFullMetadata({this.customMetadata});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeReference implements Reference {
  final String path;
  FullMetadata? metadataToReturn;
  FirebaseException? getMetadataException;
  int putFileCallCount = 0;
  SettableMetadata? lastSettableMetadata;

  /// When set, the uploaded object reports this SHA instead of the one supplied
  /// at upload time — models a corrupted/divergent replicated artifact.
  String? postUploadShaOverride;

  FakeReference(this.path);

  @override
  Future<FullMetadata> getMetadata() async {
    if (getMetadataException != null) {
      throw getMetadataException!;
    }
    if (metadataToReturn != null) {
      return metadataToReturn!;
    }
    throw FirebaseException(plugin: 'storage', code: 'object-not-found');
  }

  @override
  UploadTask putFile(File file, [SettableMetadata? metadata]) {
    putFileCallCount++;
    lastSettableMetadata = metadata;
    // Mirror real Cloud Storage: the uploaded object carries the metadata that
    // was supplied at upload time, so a post-upload getMetadata() reflects it.
    if (metadata != null) {
      final custom = Map<String, String>.from(metadata.customMetadata ?? const {});
      if (postUploadShaOverride != null) {
        custom['x-sitelens-evidence-sha256'] = postUploadShaOverride!;
      }
      metadataToReturn = FakeFullMetadata(customMetadata: custom);
    }
    return FakeUploadTask();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUploadTask implements UploadTask {
  @override
  Future<T> then<T>(FutureOr<T> Function(TaskSnapshot) onValue, {Function? onError}) async {
    return onValue(FakeTaskSnapshot());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTaskSnapshot implements TaskSnapshot {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeStorage implements FirebaseStorage {
  final Map<String, FakeReference> refs = {};

  @override
  Reference ref([String? path]) {
    return refs.putIfAbsent(path ?? '', () => FakeReference(path ?? ''));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  final bool exists;
  final Map<String, dynamic>? _data;

  FakeDocumentSnapshot({required this.exists, Map<String, dynamic>? data}) : _data = data;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDocumentReference implements DocumentReference<Map<String, dynamic>> {
  final String path;
  final FakeFirestore firestore;
  FakeDocumentSnapshot? snapshotToReturn;
  Map<String, dynamic>? lastSetData;
  Map<Object, Object?>? lastUpdateData;
  int getCallCount = 0;
  Object? getExceptionToThrow;

  FakeDocumentReference(this.path, this.firestore);

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return FakeCollectionReference('$path/$collectionPath', firestore);
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    getCallCount++;
    final toThrow = getExceptionToThrow;
    if (toThrow != null) {
      throw toThrow;
    }
    return snapshotToReturn ?? FakeDocumentSnapshot(exists: false);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    lastSetData = data;
    snapshotToReturn = FakeDocumentSnapshot(
      exists: true,
      data: data,
    );
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    lastUpdateData = data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCollectionReference implements CollectionReference<Map<String, dynamic>> {
  final String path;
  final FakeFirestore firestore;

  FakeCollectionReference(this.path, this.firestore);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final fullPath = '${this.path}/$path';
    return firestore.doc(fullPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeWriteBatch implements WriteBatch {
  final Map<DocumentReference, Map<String, dynamic>> sets = {};
  int commitCount = 0;

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    if (data is Map<String, dynamic>) {
      sets[document] = data;
    }
    final dynamic doc = document;
    if (doc is FakeDocumentReference) {
      doc.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: data as Map<String, dynamic>?,
      );
    }
  }

  @override
  Future<void> commit() async {
    commitCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSiteRepository implements SiteRepository {
  final Map<String, SiteModel> sites = {};

  @override
  Future<SiteModel?> getSiteById(String id, {String? creatorId}) async => sites[id];

  @override
  Future<void> saveSite(SiteModel site) async => sites[site.id] = site;

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async => sites.values.toList();

  @override
  Future<void> deleteSite(String id, {String? creatorId}) async => sites.remove(id);

  @override
  Future<bool> hasMediaForSite(String siteId, {String? creatorId}) async => false;

  @override
  Future<void> seedDefaultSitesIfEmpty() async {}

  @override
  Future<List<SiteModel>> hydrateRemoteSites(String userId) async => [];
}

class FakeFirestore implements FirebaseFirestore {
  final Map<String, FakeDocumentReference> docs = {};
  FakeWriteBatch? lastBatch;

  @override
  WriteBatch batch() {
    lastBatch = FakeWriteBatch();
    return lastBatch!;
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return FakeCollectionReference(collectionPath, this);
  }

  @override
  DocumentReference<Map<String, dynamic>> doc(String documentPath) {
    return docs.putIfAbsent(documentPath, () => FakeDocumentReference(documentPath, this));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File origFile;
  late File evidFile;
  late File thumbFile;
  late String origSha;
  late String evidSha;
  late String thumbSha;
  late MediaItem baseItem;
  late FakeFirestore fakeFirestore;
  late FakeStorage fakeStorage;
  late CloudSyncService syncService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_sync_test_');

    final origBytes = Uint8List.fromList([10, 20, 30, 40]);
    final evidBytes = Uint8List.fromList([50, 60, 70, 80]);
    final thumbBytes = Uint8List.fromList([90, 100, 110, 120]);

    origSha = CryptoUtils.computeSha256(origBytes);
    evidSha = CryptoUtils.computeSha256(evidBytes);
    thumbSha = CryptoUtils.computeSha256(thumbBytes);

    origFile = File('${tempDir.path}/orig_test.jpg');
    evidFile = File('${tempDir.path}/evid_test.jpg');
    thumbFile = File('${tempDir.path}/thumb_test.jpg');

    await origFile.writeAsBytes(origBytes);
    await evidFile.writeAsBytes(evidBytes);
    await thumbFile.writeAsBytes(thumbBytes);

    baseItem = MediaItem(
      id: 'media-100',
      siteId: 'site-alpha',
      originalUri: 'media/orig_test.jpg',
      uri: 'media/evid_test.jpg',
      thumbUri: 'media/thumb_test.jpg',
      type: MediaItemType.photo,
      lat: 22.5726,
      lon: 88.3639,
      accuracyM: 3.5,
      lowAccuracy: false,
      activityTag: 'Pillar Reinforcement',
      observationType: ObservationType.general,
      linkedMediaId: null,
      note: 'Foundations check',
      capturedAt: DateTime.utc(2026, 8, 18, 10, 30, 0),
      sha256Hash: origSha,
      evidenceSha256Hash: evidSha,
      capturedAddress: 'Sector 4 Metro Station, Kolkata',
      creatorId: 'engineer-bob',
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    );

    fakeFirestore = FakeFirestore();
    fakeStorage = FakeStorage();
    final fakeSiteRepo = FakeSiteRepository();
    await fakeSiteRepo.saveSite(const SiteModel(
      id: 'site-alpha',
      siteCode: '5012',
      name: 'Alpha Construction Site',
      address: 'Sector 4 Metro Station, Kolkata',
      creatorId: 'engineer-bob',
    ));
    (fakeFirestore.doc('sites/site-alpha') as FakeDocumentReference).snapshotToReturn = FakeDocumentSnapshot(
      exists: true,
      data: {'id': 'site-alpha', 'creator_id': 'engineer-bob'},
    );
    syncService = CloudSyncService(
      firestore: fakeFirestore,
      storage: fakeStorage,
      siteRepository: fakeSiteRepo,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Module 1A Secure Cloud Site Provisioning Tests', () {
    test('Provisions unprovisioned local offline site atomically before syncing media', () async {
      final localRepo = FakeSiteRepository();
      const newSiteId = 'newOfflineSite123456';
      await localRepo.saveSite(const SiteModel(
        id: newSiteId,
        siteCode: '8801',
        name: 'New Offline Station',
        address: 'Airport Terminal 2, Kolkata',
        creatorId: 'engineer-bob',
      ));

      final testFirestore = FakeFirestore();
      final testStorage = FakeStorage();
      final testSyncService = CloudSyncService(
        firestore: testFirestore,
        storage: testStorage,
        siteRepository: localRepo,
      );

      final newItem = baseItem.copyWith(siteId: newSiteId);

      await testSyncService.syncMediaItem(
        item: newItem,
        absoluteOriginalPath: origFile.path,
        absoluteEvidencePath: evidFile.path,
        absoluteThumbnailPath: thumbFile.path,
        currentUserId: 'engineer-bob',
      );

      // Verify site doc was created directly (creator-owned v1 model)
      final siteRef = testFirestore.doc('sites/$newSiteId') as FakeDocumentReference;
      expect(siteRef.snapshotToReturn?.exists, isTrue);
      expect(siteRef.snapshotToReturn?.data()?['creator_id'], equals('engineer-bob'));
      expect(siteRef.snapshotToReturn?.data()?['site_code'], equals('8801'));
      expect(siteRef.snapshotToReturn?.data()?['name'], equals('New Offline Station'));
    });

    test('Throws PermanentSyncException if local site creator does not match active session', () async {
      final localRepo = FakeSiteRepository();
      const mismatchedSiteId = 'mismatchedSite12345';
      await localRepo.saveSite(const SiteModel(
        id: mismatchedSiteId,
        siteCode: '8802',
        name: 'Mismatched Creator Station',
        address: 'Park Circus, Kolkata',
        creatorId: 'engineer-alice',
      ));

      final testFirestore = FakeFirestore();
      final testStorage = FakeStorage();
      final testSyncService = CloudSyncService(
        firestore: testFirestore,
        storage: testStorage,
        siteRepository: localRepo,
      );

      final newItem = baseItem.copyWith(siteId: mismatchedSiteId, creatorId: 'engineer-bob');

      expect(
        () => testSyncService.syncMediaItem(
          item: newItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<PermanentSyncException>()),
      );
    });

    test('Throws PermanentSyncException if site is missing from local database', () async {
      final localRepo = FakeSiteRepository();
      const missingSiteId = 'missingSite12345678';

      final testFirestore = FakeFirestore();
      final testStorage = FakeStorage();
      final testSyncService = CloudSyncService(
        firestore: testFirestore,
        storage: testStorage,
        siteRepository: localRepo,
      );

      final newItem = baseItem.copyWith(siteId: missingSiteId, creatorId: 'engineer-bob');

      expect(
        () => testSyncService.syncMediaItem(
          item: newItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<PermanentSyncException>()),
      );
    });
  });

  group('M6-B-01 Firestore Forensic Conflict Verification Tests', () {
    test('Test A — Matching immutable fields allows sync and updates mutable fields', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'id': 'media-100',
          'site_id': 'site-alpha',
          'creator_id': 'engineer-bob',
          'storage_original_path': 'sites/site-alpha/media/media-100/original',
          'storage_thumbnail_path': 'sites/site-alpha/media/media-100/thumbnail',
          'type': 'photo',
          'lat': 22.5726,
          'lon': 88.3639,
          'accuracy_m': 3.5,
          'low_accuracy': false,
          'activity_tag': 'Old Activity Tag', // Mutable delta
          'observation_type': 'general',
          'linked_media_id': null,
          'note': 'Old Note', // Mutable delta
          'captured_at': '2026-08-18T10:30:00.000Z',
          'sha256_hash': origSha,
          'evidence_sha256_hash': evidSha,
          'captured_address': 'Sector 4 Metro Station, Kolkata',
          'is_deleted': false,
        },
      );

      // Pre-seed storage refs so storage checks pass idempotently
      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      origRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {
          'x-sitelens-original-sha256': origSha,
          'x-sitelens-evidence-sha256': evidSha,
          'x-sitelens-captured-address': 'Sector 4 Metro Station, Kolkata',
        },
      );
      final thumbRef = fakeStorage.ref('sites/site-alpha/media/media-100/thumbnail') as FakeReference;
      thumbRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {'x-sitelens-thumbnail-sha256': thumbSha},
      );

      await syncService.syncMediaItem(
        item: baseItem,
        absoluteOriginalPath: origFile.path,
        absoluteEvidencePath: evidFile.path,
        absoluteThumbnailPath: thumbFile.path,
        currentUserId: 'engineer-bob',
      );

      // Verify mutable fields were updated
      expect(docRef.lastUpdateData, isNotNull);
      expect(docRef.lastUpdateData!['activity_tag'], equals('Pillar Reinforcement'));
      expect(docRef.lastUpdateData!['note'], equals('Foundations check'));
    });

    test('Test B — Conflicting evidence SHA-256 throws IntegrityConflictException', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'sha256_hash': origSha,
          'evidence_sha256_hash': 'conflicting-evidence-sha-hash',
          'captured_address': 'Sector 4 Metro Station, Kolkata',
          'captured_at': '2026-08-18T10:30:00.000Z',
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
    });

    test('Test C — Conflicting captured address throws IntegrityConflictException', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'sha256_hash': origSha,
          'evidence_sha256_hash': evidSha,
          'captured_address': 'Wrong Address Line 99',
          'captured_at': '2026-08-18T10:30:00.000Z',
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
    });

    test('Test D — Conflicting captured timestamp (different year) throws IntegrityConflictException', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'sha256_hash': origSha,
          'evidence_sha256_hash': evidSha,
          'captured_address': 'Sector 4 Metro Station, Kolkata',
          'captured_at': '2025-01-01T00:00:00.000Z', // Different year/time
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
    });

    test('Test D.1 — Timestamp Case A: Same instant with sub-second precision (Timestamp vs ISO string) matches without conflict', () async {
      final preciseInstant = DateTime.utc(2026, 8, 18, 10, 0, 0, 123);
      final itemWithMs = baseItem.copyWith(capturedAt: preciseInstant);

      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'id': 'media-100',
          'site_id': 'site-alpha',
          'creator_id': 'engineer-bob',
          'storage_original_path': 'sites/site-alpha/media/media-100/original',
          'storage_thumbnail_path': 'sites/site-alpha/media/media-100/thumbnail',
          'type': 'photo',
          'lat': 22.5726,
          'lon': 88.3639,
          'accuracy_m': 3.5,
          'low_accuracy': false,
          'activity_tag': 'Pillar Reinforcement',
          'observation_type': 'general',
          'note': 'Foundations check',
          'captured_at': Timestamp.fromDate(preciseInstant), // Firestore Timestamp representation
          'sha256_hash': origSha,
          'evidence_sha256_hash': evidSha,
          'captured_address': 'Sector 4 Metro Station, Kolkata',
          'is_deleted': false,
        },
      );

      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      origRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {
          'x-sitelens-original-sha256': origSha,
          'x-sitelens-evidence-sha256': evidSha,
          'x-sitelens-captured-address': 'Sector 4 Metro Station, Kolkata',
        },
      );
      final thumbRef = fakeStorage.ref('sites/site-alpha/media/media-100/thumbnail') as FakeReference;
      thumbRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {'x-sitelens-thumbnail-sha256': thumbSha},
      );

      await syncService.syncMediaItem(
        item: itemWithMs,
        absoluteOriginalPath: origFile.path,
        absoluteEvidencePath: evidFile.path,
        absoluteThumbnailPath: thumbFile.path,
        currentUserId: 'engineer-bob',
      );
    });

    test('Test D.2 — Timestamp Case B: 1 ms difference throws IntegrityConflictException', () async {
      final localInstant = DateTime.utc(2026, 8, 18, 10, 0, 0, 123);
      final remoteInstant = DateTime.utc(2026, 8, 18, 10, 0, 0, 124); // 1 ms difference
      final itemWithMs = baseItem.copyWith(capturedAt: localInstant);

      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'sha256_hash': origSha,
          'evidence_sha256_hash': evidSha,
          'captured_address': 'Sector 4 Metro Station, Kolkata',
          'captured_at': remoteInstant.toIso8601String(),
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: itemWithMs,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
    });

    test('Test D.3 — Timestamp Case C: 500 ms difference throws IntegrityConflictException', () async {
      final localInstant = DateTime.utc(2026, 8, 18, 10, 0, 0, 123);
      final remoteInstant = DateTime.utc(2026, 8, 18, 10, 0, 0, 623); // 500 ms difference
      final itemWithMs = baseItem.copyWith(capturedAt: localInstant);

      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'sha256_hash': origSha,
          'evidence_sha256_hash': evidSha,
          'captured_address': 'Sector 4 Metro Station, Kolkata',
          'captured_at': remoteInstant.toIso8601String(),
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: itemWithMs,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
    });

    test('Test E — Conflicting creator ID throws IntegrityConflictException', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'sha256_hash': origSha,
          'evidence_sha256_hash': evidSha,
          'captured_address': 'Sector 4 Metro Station, Kolkata',
          'captured_at': '2026-08-18T10:30:00.000Z',
          'creator_id': 'different-creator-user-999',
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
    });

    test('Test F — Conflicting location coordinates throw IntegrityConflictException', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'sha256_hash': origSha,
          'evidence_sha256_hash': evidSha,
          'lat': 51.5074, // Conflicting London latitude
          'lon': 88.3639,
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
    });

    test('Test G — Conflicting storage paths throw IntegrityConflictException', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'sha256_hash': origSha,
          'evidence_sha256_hash': evidSha,
          'storage_original_path': 'sites/site-WRONG/media/media-100/original',
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
    });
  });

  group('M6-B-01 Storage Metadata Verification Tests', () {
    test('Test H — Matching original metadata results in idempotent pass with no upload', () async {
      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      origRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {
          'x-sitelens-original-sha256': origSha,
          'x-sitelens-evidence-sha256': evidSha,
          'x-sitelens-captured-address': 'Sector 4 Metro Station, Kolkata',
        },
      );

      final thumbRef = fakeStorage.ref('sites/site-alpha/media/media-100/thumbnail') as FakeReference;
      thumbRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {'x-sitelens-thumbnail-sha256': thumbSha},
      );

      await syncService.syncMediaItem(
        item: baseItem,
        absoluteOriginalPath: origFile.path,
        absoluteEvidencePath: evidFile.path,
        absoluteThumbnailPath: thumbFile.path,
        currentUserId: 'engineer-bob',
      );

      // Verify zero upload calls were made to storage
      expect(origRef.putFileCallCount, equals(0));
      expect(thumbRef.putFileCallCount, equals(0));
    });

    test('Test I — Conflicting evidence SHA in storage metadata throws IntegrityConflictException without upload', () async {
      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      origRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {
          'x-sitelens-original-sha256': origSha,
          'x-sitelens-evidence-sha256': 'tampered-evidence-sha',
          'x-sitelens-captured-address': 'Sector 4 Metro Station, Kolkata',
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
      expect(origRef.putFileCallCount, equals(0));
    });

    test('Test J — Conflicting captured address in storage metadata throws IntegrityConflictException without upload', () async {
      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      origRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {
          'x-sitelens-original-sha256': origSha,
          'x-sitelens-evidence-sha256': evidSha,
          'x-sitelens-captured-address': 'Tampered Street Address 123',
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
      expect(origRef.putFileCallCount, equals(0));
    });

    test('Test K — Missing required original metadata field throws IntegrityConflictException without upload', () async {
      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      origRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {
          'x-sitelens-original-sha256': origSha,
          // Missing x-sitelens-evidence-sha256 and x-sitelens-captured-address
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
      expect(origRef.putFileCallCount, equals(0));
    });

    test('Test L — Missing required thumbnail metadata throws IntegrityConflictException without upload', () async {
      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      origRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {
          'x-sitelens-original-sha256': origSha,
          'x-sitelens-evidence-sha256': evidSha,
          'x-sitelens-captured-address': 'Sector 4 Metro Station, Kolkata',
        },
      );

      final thumbRef = fakeStorage.ref('sites/site-alpha/media/media-100/thumbnail') as FakeReference;
      thumbRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {}, // Missing x-sitelens-thumbnail-sha256
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
      expect(thumbRef.putFileCallCount, equals(0));
    });

    test('Test M — New capture with missing local original and no cloud artifact throws PermanentSyncException', () async {
      final nonExistentOrigPath = '${tempDir.path}/non_existent_orig.jpg';

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: nonExistentOrigPath,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<PermanentSyncException>()),
      );
    });

    test('Test N — Synced photo with cleared local original and edited tags syncs metadata successfully without re-upload', () async {
      // 1. Delete the local original file (simulating post-sync storage cleanup)
      if (await origFile.exists()) {
        await origFile.delete();
      }
      expect(await origFile.exists(), isFalse);

      // 2. Set up cloud original artifact with matching forensic metadata
      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      origRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {
          'x-sitelens-original-sha256': origSha,
          'x-sitelens-evidence-sha256': evidSha,
          'x-sitelens-captured-address': 'Sector 4 Metro Station, Kolkata',
        },
      );

      // 3. Set up existing Firestore document with original note
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'id': 'media-100',
          'site_id': 'site-alpha',
          'creator_id': 'engineer-bob',
          'storage_original_path': 'sites/site-alpha/media/media-100/original',
          'storage_thumbnail_path': 'sites/site-alpha/media/media-100/thumbnail',
          'type': 'photo',
          'lat': 22.5726,
          'lon': 88.3639,
          'accuracy_m': 3.5,
          'low_accuracy': false,
          'activity_tag': 'Rebar Inspection',
          'observation_type': 'progress',
          'note': 'Initial note',
          'captured_at': '2026-08-18T10:30:00.000Z',
          'sha256_hash': origSha,
          'evidence_sha256_hash': evidSha,
          'captured_address': 'Sector 4 Metro Station, Kolkata',
          'is_deleted': false,
        },
      );

      // 4. Update the item's mutable fields (note & activity tag)
      final updatedItem = baseItem.copyWith(
        note: 'Updated observation after inspection',
        activityTag: 'Poured Concrete',
      );

      // 5. Execute synchronization
      await syncService.syncMediaItem(
        item: updatedItem,
        absoluteOriginalPath: origFile.path,
        absoluteEvidencePath: evidFile.path,
        absoluteThumbnailPath: thumbFile.path,
        currentUserId: 'engineer-bob',
      );

      // 6. Verify: Storage putFile was NOT called (no re-upload)
      expect(origRef.putFileCallCount, equals(0));

      // 7. Verify: Firestore document received update with mutable fields
      expect(docRef.lastUpdateData, isNotNull);
      expect(docRef.lastUpdateData!['note'], equals('Updated observation after inspection'));
      expect(docRef.lastUpdateData!['activity_tag'], equals('Poured Concrete'));

      // 8. Verify: Evidence file and missing original remain intact
      expect(await evidFile.exists(), isTrue);
      expect(await origFile.exists(), isFalse);
    });

    test('Test O — Synced photo with cleared local original and corrupted cloud metadata throws IntegrityConflictException', () async {
      if (await origFile.exists()) {
        await origFile.delete();
      }

      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      origRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {
          'x-sitelens-original-sha256': 'corrupted-cloud-sha',
          'x-sitelens-evidence-sha256': evidSha,
          'x-sitelens-captured-address': 'Sector 4 Metro Station, Kolkata',
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
    });

    test('Test P — Synced photo with cleared local original and missing local evidence throws PermanentSyncException', () async {
      if (await origFile.exists()) {
        await origFile.delete();
      }
      if (await evidFile.exists()) {
        await evidFile.delete();
      }

      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      origRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {
          'x-sitelens-original-sha256': origSha,
          'x-sitelens-evidence-sha256': evidSha,
          'x-sitelens-captured-address': 'Sector 4 Metro Station, Kolkata',
        },
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<PermanentSyncException>()),
      );
    });
  });

  group('F2 v8 Forensic Metadata Persistence Tests', () {
    MediaItem forensicItem() => baseItem.copyWith(
          altitude: 18.4,
          isAltitudeMsl: true,
          verificationStatus: HudStatus.verified,
          gnssSatelliteCount: 24,
          gnssSatellitesUsedInFix: 18,
          gnssFixTimestampUtc: DateTime.utc(2026, 8, 18, 10, 29, 30),
        );

    Map<String, dynamic> matchingCloudDoc({Map<String, dynamic>? overrides}) {
      return {
        'id': 'media-100',
        'site_id': 'site-alpha',
        'creator_id': 'engineer-bob',
        'storage_original_path': 'sites/site-alpha/media/media-100/original',
        'storage_thumbnail_path': 'sites/site-alpha/media/media-100/thumbnail',
        'type': 'photo',
        'lat': 22.5726,
        'lon': 88.3639,
        'accuracy_m': 3.5,
        'low_accuracy': false,
        'altitude': 18.4,
        'is_altitude_msl': true,
        'verification_status': 'verified',
        'gnss_satellite_count': 24,
        'gnss_satellites_used_in_fix': 18,
        'gnss_fix_timestamp': '2026-08-18T10:29:30.000Z',
        'activity_tag': 'Pillar Reinforcement',
        'observation_type': 'general',
        'note': 'Foundations check',
        'captured_at': '2026-08-18T10:30:00.000Z',
        'sha256_hash': origSha,
        'evidence_sha256_hash': evidSha,
        'captured_address': 'Sector 4 Metro Station, Kolkata',
        'is_deleted': false,
        ...?overrides,
      };
    }

    void seedStorageRefs() {
      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      origRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {
          'x-sitelens-original-sha256': origSha,
          'x-sitelens-evidence-sha256': evidSha,
          'x-sitelens-captured-address': 'Sector 4 Metro Station, Kolkata',
        },
      );
      final thumbRef = fakeStorage.ref('sites/site-alpha/media/media-100/thumbnail') as FakeReference;
      thumbRef.metadataToReturn = FakeFullMetadata(
        customMetadata: {'x-sitelens-thumbnail-sha256': thumbSha},
      );
    }

    test('Create path persists altitude, datum, verification status and GNSS telemetry', () async {
      await syncService.syncMediaItem(
        item: forensicItem(),
        absoluteOriginalPath: origFile.path,
        absoluteEvidencePath: evidFile.path,
        absoluteThumbnailPath: thumbFile.path,
        currentUserId: 'engineer-bob',
      );

      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      final payload = docRef.lastSetData!;
      expect(payload['altitude'], equals(18.4));
      expect(payload['is_altitude_msl'], isTrue);
      expect(payload['verification_status'], equals('verified'));
      expect(payload['gnss_satellite_count'], equals(24));
      expect(payload['gnss_satellites_used_in_fix'], equals(18));
      expect(payload['gnss_fix_timestamp'], equals('2026-08-18T10:29:30.000Z'));
    });

    test('Reconcile path: matching v8 fields pass without conflict or re-upload', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: matchingCloudDoc(),
      );
      seedStorageRefs();

      await syncService.syncMediaItem(
        item: forensicItem(),
        absoluteOriginalPath: origFile.path,
        absoluteEvidencePath: evidFile.path,
        absoluteThumbnailPath: thumbFile.path,
        currentUserId: 'engineer-bob',
      );

      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      expect(origRef.putFileCallCount, equals(0));
    });

    test('Reconcile path: conflicting altitude throws IntegrityConflictException', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: matchingCloudDoc(overrides: {'altitude': 999.9}),
      );
      seedStorageRefs();

      expect(
        () => syncService.syncMediaItem(
          item: forensicItem(),
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
    });

    test('Reconcile path: conflicting verification status throws IntegrityConflictException', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: matchingCloudDoc(overrides: {'verification_status': 'pending'}),
      );
      seedStorageRefs();

      expect(
        () => syncService.syncMediaItem(
          item: forensicItem(),
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
    });

    test('Reconcile path: conflicting GNSS telemetry throws IntegrityConflictException', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: matchingCloudDoc(overrides: {'gnss_satellite_count': 7}),
      );
      seedStorageRefs();

      expect(
        () => syncService.syncMediaItem(
          item: forensicItem(),
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );
    });
  });

  group('B-1 Cloud Tombstone Synchronization Tests', () {
    MediaItem tombstonedItem() => baseItem.copyWith(
          isDeleted: true,
          syncStatus: SyncStatusType.synced,
        );

    FakeDocumentReference seedExistingDoc({bool isDeleted = false}) {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'id': 'media-100',
          'site_id': 'site-alpha',
          'creator_id': 'engineer-bob',
          'storage_original_path': 'sites/site-alpha/media/media-100/original',
          'storage_thumbnail_path': 'sites/site-alpha/media/media-100/thumbnail',
          'type': 'photo',
          'lat': 22.5726,
          'lon': 88.3639,
          'accuracy_m': 3.5,
          'low_accuracy': false,
          'activity_tag': 'Pillar Reinforcement',
          'observation_type': 'general',
          'note': 'Foundations check',
          'captured_at': '2026-08-18T10:30:00.000Z',
          'sha256_hash': origSha,
          'evidence_sha256_hash': evidSha,
          'captured_address': 'Sector 4 Metro Station, Kolkata',
          'is_deleted': isDeleted,
        },
      );
      return docRef;
    }

    test('Propagates is_deleted: true to the existing document without touching Storage artifacts', () async {
      final docRef = seedExistingDoc();

      await syncService.syncTombstone(item: tombstonedItem(), currentUserId: 'engineer-bob');

      expect(docRef.lastUpdateData, isNotNull);
      expect(docRef.lastUpdateData!['is_deleted'], isTrue);

      // The tombstone is a ledger state only: original and thumbnail are never
      // uploaded, replaced, or deleted (write-once artifacts stay intact).
      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      final thumbRef = fakeStorage.ref('sites/site-alpha/media/media-100/thumbnail') as FakeReference;
      expect(origRef.putFileCallCount, equals(0));
      expect(thumbRef.putFileCallCount, equals(0));
    });

    test('Idempotent: an already-tombstoned cloud document receives no further update', () async {
      final docRef = seedExistingDoc(isDeleted: true);

      await syncService.syncTombstone(item: tombstonedItem(), currentUserId: 'engineer-bob');

      expect(docRef.lastUpdateData, isNull);
    });

    test('No-op for a never-published item: no cloud record is created and no deletion is claimed', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-never-synced') as FakeDocumentReference;

      await syncService.syncTombstone(
        item: baseItem.copyWith(
          id: 'media-never-synced',
          isDeleted: true,
          syncStatus: SyncStatusType.pending,
        ),
        currentUserId: 'engineer-bob',
      );

      // R22: the never-published path must not probe the cloud at all. A get()
      // on a non-existent media document is denied by the read rule
      // (`resource != null`), which would surface a spurious permission-denied.
      expect(docRef.getCallCount, equals(0));

      // Nothing was created or updated in Firestore: a nonexistent cloud record
      // cannot gain a deletion ledger entry (rules forbid is_deleted at create).
      expect(docRef.lastSetData, isNull);
      expect(docRef.lastUpdateData, isNull);
      expect(docRef.snapshotToReturn?.exists, isNot(isTrue));

      final origRef = fakeStorage.ref('sites/site-alpha/media/media-never-synced/original') as FakeReference;
      expect(origRef.putFileCallCount, equals(0));
    });

    test('Creator mismatch throws PermanentSyncException', () async {
      expect(
        () => syncService.syncTombstone(item: tombstonedItem(), currentUserId: 'someone-else'),
        throwsA(isA<PermanentSyncException>()),
      );
    });

    test('Immutable forensic conflict is detected, never overwritten by tombstone reconciliation', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(
        exists: true,
        data: {
          'sha256_hash': 'f' * 64, // Conflicting original SHA
          'captured_at': '2026-08-18T10:30:00.000Z',
          'is_deleted': false,
        },
      );

      expect(
        () => syncService.syncTombstone(item: tombstonedItem(), currentUserId: 'engineer-bob'),
        throwsA(isA<IntegrityConflictException>()),
      );
      expect(docRef.lastUpdateData, isNull);
    });

    test('C-2: permanently-deleted failed item reconciles the ledger without touching Storage artifacts', () async {
      final docRef = seedExistingDoc();

      // A permanently-deleted locally-failed item: the ledger document was
      // already published before the artifact uploads failed.
      await syncService.syncTombstone(
        item: baseItem.copyWith(isDeleted: true, syncStatus: SyncStatusType.failed),
        currentUserId: 'engineer-bob',
      );

      expect(docRef.lastUpdateData, isNotNull);
      expect(docRef.lastUpdateData!['is_deleted'], isTrue);

      // Tombstone propagation never uploads, replaces, or deletes artifacts.
      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      final thumbRef = fakeStorage.ref('sites/site-alpha/media/media-100/thumbnail') as FakeReference;
      expect(origRef.putFileCallCount, equals(0));
      expect(thumbRef.putFileCallCount, equals(0));
    });

    test('R22: published tombstone with a genuinely missing cloud record is a no-op (read attempted, nothing written)', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-published-missing') as FakeDocumentReference;
      docRef.snapshotToReturn = FakeDocumentSnapshot(exists: false);

      await syncService.syncTombstone(
        item: baseItem.copyWith(
          id: 'media-published-missing',
          isDeleted: true,
          syncStatus: SyncStatusType.synced,
        ),
        currentUserId: 'engineer-bob',
      );

      expect(docRef.getCallCount, equals(1));
      expect(docRef.lastSetData, isNull);
      expect(docRef.lastUpdateData, isNull);
    });

    test('R22: permission-denied on a published tombstone remains a real failure (never converted to not-found)', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      docRef.getExceptionToThrow = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );

      await expectLater(
        syncService.syncTombstone(item: tombstonedItem(), currentUserId: 'engineer-bob'),
        throwsA(isA<FirebaseException>()),
      );

      expect(docRef.getCallCount, equals(1));
      expect(docRef.lastSetData, isNull);
      expect(docRef.lastUpdateData, isNull);
    });

    test('R22: creator mismatch throws even for a never-published (pending) tombstone', () async {
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-never-other') as FakeDocumentReference;

      await expectLater(
        syncService.syncTombstone(
          item: baseItem.copyWith(
            id: 'media-never-other',
            isDeleted: true,
            syncStatus: SyncStatusType.pending,
          ),
          currentUserId: 'someone-else',
        ),
        throwsA(isA<PermanentSyncException>()),
      );

      // The authorization guard runs before the never-published short-circuit:
      // another user's tombstone is never treated as a local-only no-op.
      expect(docRef.getCallCount, equals(0));
    });
  });

  group('R16 Cloud Evidence Artifact Replication (Option A)', () {
    FakeReference evidenceRef() =>
        fakeStorage.ref('sites/site-alpha/media/media-100/evidence') as FakeReference;

    test('replicates the canonical evidence artifact and records its ledger path', () async {
      await syncService.syncMediaItem(
        item: baseItem,
        absoluteOriginalPath: origFile.path,
        absoluteEvidencePath: evidFile.path,
        absoluteThumbnailPath: thumbFile.path,
        currentUserId: 'engineer-bob',
      );

      final evidRef = evidenceRef();
      expect(evidRef.putFileCallCount, equals(1));
      expect(
        evidRef.lastSettableMetadata?.customMetadata?['x-sitelens-evidence-sha256'],
        equals(evidSha),
      );
      expect(evidRef.lastSettableMetadata?.contentType, equals('image/jpeg'));

      // Publication order: ledger -> original -> evidence -> thumbnail.
      final origRef = fakeStorage.ref('sites/site-alpha/media/media-100/original') as FakeReference;
      final thumbRef = fakeStorage.ref('sites/site-alpha/media/media-100/thumbnail') as FakeReference;
      expect(origRef.putFileCallCount, equals(1));
      expect(thumbRef.putFileCallCount, equals(1));

      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      expect(
        docRef.lastSetData?['storage_evidence_path'],
        equals('sites/site-alpha/media/media-100/evidence'),
      );
    });

    test('is idempotent when the replicated evidence artifact already matches', () async {
      evidenceRef().metadataToReturn = FakeFullMetadata(
        customMetadata: {'x-sitelens-evidence-sha256': evidSha},
      );

      await syncService.syncMediaItem(
        item: baseItem,
        absoluteOriginalPath: origFile.path,
        absoluteEvidencePath: evidFile.path,
        absoluteThumbnailPath: thumbFile.path,
        currentUserId: 'engineer-bob',
      );

      expect(evidenceRef().putFileCallCount, equals(0));
    });

    test('a conflicting cloud evidence SHA aborts without uploading', () async {
      evidenceRef().metadataToReturn = FakeFullMetadata(
        customMetadata: {'x-sitelens-evidence-sha256': 'f' * 64},
      );

      expect(
        () => syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );

      expect(evidenceRef().putFileCallCount, equals(0));
    });

    test('a divergent replicated artifact fails post-upload verification', () async {
      evidenceRef().postUploadShaOverride = 'a' * 64;

      await expectLater(
        syncService.syncMediaItem(
          item: baseItem,
          absoluteOriginalPath: origFile.path,
          absoluteEvidencePath: evidFile.path,
          absoluteThumbnailPath: thumbFile.path,
          currentUserId: 'engineer-bob',
        ),
        throwsA(isA<IntegrityConflictException>()),
      );

      // The upload was attempted, but the artifact is never accepted as synced.
      expect(evidenceRef().putFileCallCount, equals(1));
    });

    test('video items do not replicate a separate evidence artifact', () async {
      final videoItem = baseItem.copyWith(type: MediaItemType.video);

      await syncService.syncMediaItem(
        item: videoItem,
        absoluteOriginalPath: origFile.path,
        absoluteEvidencePath: evidFile.path,
        absoluteThumbnailPath: thumbFile.path,
        currentUserId: 'engineer-bob',
      );

      expect(evidenceRef().putFileCallCount, equals(0));
      final docRef = fakeFirestore.doc('sites/site-alpha/media/media-100') as FakeDocumentReference;
      expect(docRef.lastSetData?.containsKey('storage_evidence_path'), isFalse);
    });
  });
}
