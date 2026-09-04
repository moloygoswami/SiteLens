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

  FakeDocumentReference(this.path, this.firestore);

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return FakeCollectionReference('$path/$collectionPath', firestore);
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    return snapshotToReturn ?? FakeDocumentSnapshot(exists: false);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    lastSetData = data;
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
  Future<SiteModel?> getSiteById(String id) async => sites[id];

  @override
  Future<void> saveSite(SiteModel site) async => sites[site.id] = site;

  @override
  Future<List<SiteModel>> getAllSites({String? creatorId}) async => sites.values.toList();

  @override
  Future<void> deleteSite(String id) async => sites.remove(id);

  @override
  Future<void> seedDefaultSitesIfEmpty() async {}
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

      // Verify atomic batch was committed
      expect(testFirestore.lastBatch, isNotNull);
      expect(testFirestore.lastBatch!.commitCount, equals(1));

      // Verify site doc was created
      final siteRef = testFirestore.doc('sites/$newSiteId') as FakeDocumentReference;
      expect(siteRef.snapshotToReturn?.exists, isTrue);
      expect(siteRef.snapshotToReturn?.data()?['creator_id'], equals('engineer-bob'));
      expect(siteRef.snapshotToReturn?.data()?['site_code'], equals('8801'));

      // Verify member doc was created
      final memberRef = testFirestore.doc('sites/$newSiteId/members/engineer-bob') as FakeDocumentReference;
      expect(memberRef.snapshotToReturn?.exists, isTrue);
      expect(memberRef.snapshotToReturn?.data()?['role'], equals('admin'));
      expect(memberRef.snapshotToReturn?.data()?['status'], equals('active'));
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
}
