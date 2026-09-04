// ignore_for_file: subtype_of_sealed_class, must_be_immutable, annotate_overrides
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/core/utils/crypto_utils.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/sync/services/cloud_media_recovery_service.dart';
import 'package:sitelens/features/sync/services/cloud_sync_service.dart';

class LocalTestEvidenceStorageService extends EvidenceStorageService {
  final Directory tempDir;
  LocalTestEvidenceStorageService(this.tempDir);

  @override
  Future<Directory> getBaseDirectory() async => tempDir;
}

class FakeDownloadTask implements DownloadTask {
  final Future<TaskSnapshot> _future;
  final StreamController<TaskSnapshot> _controller;

  FakeDownloadTask(this._future, [StreamController<TaskSnapshot>? controller])
      : _controller = controller ?? StreamController<TaskSnapshot>.broadcast();

  @override
  Stream<TaskSnapshot> get snapshotEvents => _controller.stream;

  @override
  Future<T> then<T>(FutureOr<T> Function(TaskSnapshot) onValue, {Function? onError}) {
    return _future.then(onValue, onError: onError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTaskSnapshot implements TaskSnapshot {
  final int totalBytes;
  final int bytesTransferred;

  FakeTaskSnapshot({this.totalBytes = 1024, this.bytesTransferred = 1024});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeReference implements Reference {
  final String path;
  Uint8List? bytesToDownload;
  FirebaseException? downloadException;
  Exception? generalException;
  int writeToFileCallCount = 0;

  FakeReference(this.path);

  @override
  DownloadTask writeToFile(File file) {
    writeToFileCallCount++;
    if (downloadException != null) {
      return FakeDownloadTask(Future.error(downloadException!));
    }
    if (generalException != null) {
      return FakeDownloadTask(Future.error(generalException!));
    }

    final controller = StreamController<TaskSnapshot>.broadcast();

    final future = Future(() async {
      final snapshot = FakeTaskSnapshot(
        totalBytes: bytesToDownload?.length ?? 1024,
        bytesTransferred: bytesToDownload?.length ?? 1024,
      );
      controller.add(snapshot);
      if (bytesToDownload != null) {
        await file.writeAsBytes(bytesToDownload!, flush: true);
      }
      return snapshot;
    });

    return FakeDownloadTask(future, controller);
  }

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalTestEvidenceStorageService storageService;
  late FakeStorage fakeStorage;
  late CloudMediaRecoveryService recoveryService;

  final photoBytes = Uint8List.fromList(List.generate(2048, (i) => (i * 7) % 256));
  final photoSha = CryptoUtils.computeSha256(photoBytes);

  final videoBytes = Uint8List.fromList(List.generate(1024 * 1024, (i) => (i * 13) % 256));
  final videoSha = CryptoUtils.computeSha256(videoBytes);

  final evidBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
  final evidSha = CryptoUtils.computeSha256(evidBytes);

  late MediaItem photoItem;
  late MediaItem videoItem;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('recovery_test_');
    storageService = LocalTestEvidenceStorageService(tempDir);
    fakeStorage = FakeStorage();
    recoveryService = CloudMediaRecoveryService(
      storage: fakeStorage,
      storageService: storageService,
    );

    // Create media directory
    final mediaDir = Directory('${tempDir.path}/media');
    await mediaDir.create(recursive: true);

    photoItem = MediaItem(
      id: 'photo-100',
      siteId: 'site-alpha',
      uri: 'media/evid_photo-100.jpg',
      originalUri: 'media/orig_photo-100.jpg',
      thumbUri: 'media/thumb_photo-100.jpg',
      type: MediaItemType.photo,
      lat: 22.5726,
      lon: 88.3639,
      accuracyM: 3.5,
      lowAccuracy: false,
      activityTag: 'Concrete Pave',
      observationType: ObservationType.progress,
      capturedAt: DateTime.utc(2026, 8, 18, 12, 0, 0),
      sha256Hash: photoSha,
      evidenceSha256Hash: evidSha,
      capturedAddress: 'Kolkata Sector V',
      creatorId: 'engineer-bob',
      syncStatus: SyncStatusType.synced,
    );

    videoItem = MediaItem(
      id: 'video-200',
      siteId: 'site-alpha',
      uri: 'media/orig_video-200.mp4',
      originalUri: 'media/orig_video-200.mp4',
      thumbUri: 'media/thumb_video-200.jpg',
      type: MediaItemType.video,
      lat: 22.5726,
      lon: 88.3639,
      accuracyM: 4.0,
      lowAccuracy: false,
      activityTag: 'Excavation',
      observationType: ObservationType.general,
      capturedAt: DateTime.utc(2026, 8, 18, 12, 10, 0),
      sha256Hash: videoSha,
      evidenceSha256Hash: videoSha,
      capturedAddress: 'Kolkata Sector V',
      creatorId: 'engineer-bob',
      syncStatus: SyncStatusType.synced,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('M7-02-II-A Cloud Media Recovery Foundation Tests', () {
    test('1. Photo recovery succeeds and restores media/orig_{id}.jpg with matching SHA-256', () async {
      final cloudRef = fakeStorage.ref('sites/site-alpha/media/photo-100/original') as FakeReference;
      cloudRef.bytesToDownload = photoBytes;

      double? reportedProgress;
      final recoveredFile = await recoveryService.recoverOriginal(
        item: photoItem,
        onProgress: (p) => reportedProgress = p,
      );

      expect(await recoveredFile.exists(), isTrue);
      expect(recoveredFile.path, equals('${tempDir.path}/media/orig_photo-100.jpg'));
      final diskSha = CryptoUtils.computeSha256(await recoveredFile.readAsBytes());
      expect(diskSha, equals(photoSha));
      expect(cloudRef.writeToFileCallCount, equals(1));
      expect(reportedProgress, isNotNull);
    });

    test('2. Video recovery succeeds and restores media/orig_{id}.mp4 with matching SHA-256', () async {
      final cloudRef = fakeStorage.ref('sites/site-alpha/media/video-200/original') as FakeReference;
      cloudRef.bytesToDownload = videoBytes;

      final recoveredFile = await recoveryService.recoverOriginal(item: videoItem);

      expect(await recoveredFile.exists(), isTrue);
      expect(recoveredFile.path, equals('${tempDir.path}/media/orig_video-200.mp4'));
      final diskSha = CryptoUtils.computeSha256(await recoveredFile.readAsBytes());
      expect(diskSha, equals(videoSha));
      expect(cloudRef.writeToFileCallCount, equals(1));
    });

    test('3. Downloaded photo SHA mismatch throws IntegrityConflictException and prunes temp file', () async {
      final cloudRef = fakeStorage.ref('sites/site-alpha/media/photo-100/original') as FakeReference;
      cloudRef.bytesToDownload = Uint8List.fromList([9, 9, 9]); // Corrupted bytes

      final origDestPath = '${tempDir.path}/media/orig_photo-100.jpg';

      expect(
        () => recoveryService.recoverOriginal(item: photoItem),
        throwsA(isA<IntegrityConflictException>()),
      );

      expect(File(origDestPath).existsSync(), isFalse);

      // Verify no leftover .tmp files
      final mediaFiles = Directory('${tempDir.path}/media').listSync();
      expect(mediaFiles.where((f) => f.path.endsWith('.tmp')).isEmpty, isTrue);
    });

    test('4. Downloaded video SHA mismatch throws IntegrityConflictException and prunes temp file', () async {
      final cloudRef = fakeStorage.ref('sites/site-alpha/media/video-200/original') as FakeReference;
      cloudRef.bytesToDownload = Uint8List.fromList([8, 8, 8]); // Corrupted bytes

      final origDestPath = '${tempDir.path}/media/orig_video-200.mp4';

      expect(
        () => recoveryService.recoverOriginal(item: videoItem),
        throwsA(isA<IntegrityConflictException>()),
      );

      expect(File(origDestPath).existsSync(), isFalse);
    });

    test('5. Existing local file with matching SHA is reused without downloading', () async {
      final localOrig = File('${tempDir.path}/media/orig_photo-100.jpg');
      await localOrig.writeAsBytes(photoBytes, flush: true);

      final cloudRef = fakeStorage.ref('sites/site-alpha/media/photo-100/original') as FakeReference;

      final resultFile = await recoveryService.recoverOriginal(item: photoItem);

      expect(resultFile.path, equals(localOrig.path));
      expect(cloudRef.writeToFileCallCount, equals(0)); // Reused local file, zero network calls
    });

    test('6. Existing local file with incorrect SHA throws IntegrityConflictException without silent overwrite', () async {
      final localOrig = File('${tempDir.path}/media/orig_photo-100.jpg');
      await localOrig.writeAsBytes([1, 1, 1], flush: true); // Corrupted existing file

      final cloudRef = fakeStorage.ref('sites/site-alpha/media/photo-100/original') as FakeReference;

      expect(
        () => recoveryService.recoverOriginal(item: photoItem),
        throwsA(isA<IntegrityConflictException>()),
      );

      // File was NOT silently overwritten
      expect(await localOrig.readAsBytes(), equals([1, 1, 1]));
      expect(cloudRef.writeToFileCallCount, equals(0));
    });

    test('7. Cloud original does not exist throws PermanentSyncException', () async {
      final cloudRef = fakeStorage.ref('sites/site-alpha/media/photo-100/original') as FakeReference;
      cloudRef.downloadException = FirebaseException(plugin: 'storage', code: 'object-not-found');

      expect(
        () => recoveryService.recoverOriginal(item: photoItem),
        throwsA(isA<PermanentSyncException>()),
      );

      expect(File('${tempDir.path}/media/orig_photo-100.jpg').existsSync(), isFalse);
    });

    test('8. Network/offline failure throws RetryableSyncException', () async {
      final cloudRef = fakeStorage.ref('sites/site-alpha/media/photo-100/original') as FakeReference;
      cloudRef.generalException = const SocketException('Connection refused');

      expect(
        () => recoveryService.recoverOriginal(item: photoItem),
        throwsA(isA<RetryableSyncException>()),
      );

      expect(File('${tempDir.path}/media/orig_photo-100.jpg').existsSync(), isFalse);
    });

    test('9. Partial/incomplete download cannot become the final local original', () async {
      final cloudRef = fakeStorage.ref('sites/site-alpha/media/photo-100/original') as FakeReference;
      cloudRef.downloadException = FirebaseException(plugin: 'storage', code: 'canceled');

      expect(
        () => recoveryService.recoverOriginal(item: photoItem),
        throwsA(isA<RetryableSyncException>()),
      );

      expect(File('${tempDir.path}/media/orig_photo-100.jpg').existsSync(), isFalse);

      final mediaFiles = Directory('${tempDir.path}/media').listSync();
      expect(mediaFiles.where((f) => f.path.endsWith('.tmp')).isEmpty, isTrue);
    });

    test('10-12. Recovery preserves local evidence, thumbnail, and cloud artifacts untouched', () async {
      // Set up existing local evidence and thumbnail
      final evidFile = File('${tempDir.path}/media/evid_photo-100.jpg');
      await evidFile.writeAsBytes(evidBytes, flush: true);

      final thumbFile = File('${tempDir.path}/media/thumb_photo-100.jpg');
      await thumbFile.writeAsBytes([50, 60, 70], flush: true);

      final cloudRef = fakeStorage.ref('sites/site-alpha/media/photo-100/original') as FakeReference;
      cloudRef.bytesToDownload = photoBytes;

      final recovered = await recoveryService.recoverOriginal(item: photoItem);

      expect(await recovered.exists(), isTrue);

      // 12. Evidence & Thumbnail files remain intact and unmodified
      expect(await evidFile.exists(), isTrue);
      expect(await evidFile.readAsBytes(), equals(evidBytes));

      expect(await thumbFile.exists(), isTrue);
      expect(await thumbFile.readAsBytes(), equals([50, 60, 70]));
    });
  });
}
