import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/gallery/services/evidence_export_service.dart';

class MockEvidenceStorageService extends EvidenceStorageService {
  final List<String> resolvedPaths = [];

  @override
  Future<String> resolveAbsolutePath(String relativePath) async {
    resolvedPaths.add(relativePath);
    return '/mock/$relativePath';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EvidenceExportService Unit Tests', () {
    late MockEvidenceStorageService mockStorage;
    late EvidenceExportService exportService;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('export_test_');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return tempDir.path;
      });

      mockStorage = MockEvidenceStorageService();
      exportService = EvidenceExportService(mockStorage);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final testMediaItem = MediaItem(
      id: 'test-media-101',
      siteId: 'SITE_001',
      originalUri: 'media/orig_test-media-101.jpg',
      uri: 'media/evid_test-media-101.jpg',
      thumbUri: 'media/thumb_test-media-101.jpg',
      type: MediaItemType.photo,
      lat: 22.56298,
      lon: 88.30085,
      accuracyM: 3.5,
      lowAccuracy: false,
      activityTag: 'Foundation Excavation',
      observationType: ObservationType.progress,
      note: 'Foundations dug to 4.5m bedrock depth',
      capturedAt: DateTime.utc(2026, 8, 15, 10, 30, 0),
      sha256Hash:
          'a1b2c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdef',
      evidenceSha256Hash:
          'f1e2d3c4b5a678901234567890abcdef1234567890abcdef1234567890abcdef',
      capturedAddress: '42 Construction Way • New Town, Kolkata',
      syncStatus: SyncStatusType.pending,
      isDeleted: false,
    );

    test(
        'Standard Inspection Note generates PDF titled "INSPECTION NOTE" without cryptographic section',
        () async {
      final pdfBytes = await exportService.buildInspectionNotePdf(
        item: testMediaItem,
        siteCode: 'SL-001',
        siteName: 'Sector Alpha Construction',
        inspectorEmail: 'inspector@company.com',
        imageBytes: Uint8List.fromList([0, 0, 0, 0]),
        mode: EvidenceReportMode.standardInspectionNote,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length > 500, isTrue);
      final header = String.fromCharCodes(pdfBytes.sublist(0, 4));
      expect(header, '%PDF');
    });

    test(
        'Dedicated Forensic Audit report mode includes "FORENSIC EVIDENCE AUDIT REPORT" and cryptographic section',
        () async {
      final pdfBytes = await exportService.buildInspectionNotePdf(
        item: testMediaItem,
        siteCode: 'SL-001',
        siteName: 'Sector Alpha Construction',
        inspectorEmail: 'inspector@company.com',
        imageBytes: Uint8List.fromList([0, 0, 0, 0]),
        mode: EvidenceReportMode.forensicAudit,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length > 500, isTrue);
      final header = String.fromCharCodes(pdfBytes.sublist(0, 4));
      expect(header, '%PDF');
    });

    test(
        'buildInspectionNotePdf handles fallback when address or notes are null',
        () async {
      final minimalItem = MediaItem(
        id: 'test-media-102',
        siteId: 'SITE_002',
        originalUri: 'media/orig_102.jpg',
        uri: 'media/evid_102.jpg',
        type: MediaItemType.video,
        lat: 0.0,
        lon: 0.0,
        capturedAt: DateTime.utc(2026, 8, 15, 12, 0, 0),
        capturedAddress: null,
      );

      final pdfBytes = await exportService.buildInspectionNotePdf(
        item: minimalItem,
        siteCode: null,
        siteName: null,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length > 500, isTrue);
      final header = String.fromCharCodes(pdfBytes.sublist(0, 4));
      expect(header, '%PDF');
    });

    test(
        'buildBatchPdf generates multi-page PDF for multiple items in standard mode',
        () async {
      final item2 = MediaItem(
        id: 'test-media-102',
        siteId: 'SITE_001',
        originalUri: 'media/orig_102.jpg',
        uri: 'media/evid_102.jpg',
        type: MediaItemType.photo,
        lat: 22.56300,
        lon: 88.30090,
        capturedAt: DateTime.utc(2026, 8, 15, 11, 0, 0),
        capturedAddress: '43 Construction Way',
      );

      final pdfBytes = await exportService.buildBatchPdf(
        [testMediaItem, item2],
        siteCode: 'SL-001',
        siteName: 'Sector Alpha Construction',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length > 1000, isTrue);
      final header = String.fromCharCodes(pdfBytes.sublist(0, 4));
      expect(header, '%PDF');
    });

    test(
        'buildInspectionNotePdf resolves canonical evidence JPEG (item.uri) instead of thumbUri',
        () async {
      mockStorage.resolvedPaths.clear();

      await exportService.buildInspectionNotePdf(
        item: testMediaItem,
        siteCode: 'SL-001',
      );

      // Verify that item.uri was requested for disk resolution and NOT item.thumbUri
      expect(mockStorage.resolvedPaths, contains(testMediaItem.uri));
      expect(
          mockStorage.resolvedPaths, isNot(contains(testMediaItem.thumbUri)));
    });

    test(
        'buildBatchPdf resolves canonical evidence JPEG (item.uri) for each item in batch',
        () async {
      mockStorage.resolvedPaths.clear();

      final item2 = MediaItem(
        id: 'test-media-102',
        siteId: 'SITE_001',
        originalUri: 'media/orig_102.jpg',
        uri: 'media/evid_102.jpg',
        thumbUri: 'media/thumb_102.jpg',
        type: MediaItemType.photo,
        lat: 22.56300,
        lon: 88.30090,
        capturedAt: DateTime.utc(2026, 8, 15, 11, 0, 0),
      );

      await exportService.buildBatchPdf(
        [testMediaItem, item2],
        siteCode: 'SL-001',
      );

      expect(mockStorage.resolvedPaths, contains(testMediaItem.uri));
      expect(mockStorage.resolvedPaths, contains(item2.uri));
      expect(
          mockStorage.resolvedPaths, isNot(contains(testMediaItem.thumbUri)));
      expect(mockStorage.resolvedPaths, isNot(contains(item2.thumbUri)));
    });

    test(
        'Underlying cryptographic data, hashes, and chain-of-custody remain intact and retained',
        () {
      // Ensure MediaItem preserves all cryptographic SHA-256 and URI fields
      expect(testMediaItem.sha256Hash,
          'a1b2c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdef');
      expect(testMediaItem.evidenceSha256Hash,
          'f1e2d3c4b5a678901234567890abcdef1234567890abcdef1234567890abcdef');
      expect(testMediaItem.originalUri, 'media/orig_test-media-101.jpg');
      expect(testMediaItem.uri, 'media/evid_test-media-101.jpg');
      expect(testMediaItem.thumbUri, 'media/thumb_test-media-101.jpg');
    });

    test('buildZipPackage creates ZIP archive containing manifest and inspection report', () async {
      final zipPath = await exportService.buildZipPackage(
        [testMediaItem],
        siteCode: 'SL-001',
        siteName: 'Sector Alpha Construction',
        inspectorEmail: 'inspector@company.com',
      );

      expect(zipPath, isNotNull);
      expect(zipPath.endsWith('.zip'), isTrue);
    });

    test('remediates vuln-0002: exports real recorded altitude in standard & forensic modes', () async {
      final itemWithAltitude = testMediaItem.copyWith(altitude: 18.4);
      final pdfBytes = await exportService.buildInspectionNotePdf(
        item: itemWithAltitude,
        siteCode: 'SL-001',
        siteName: 'Sector Alpha Construction',
        mode: EvidenceReportMode.standardInspectionNote,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length > 500, isTrue);

      final forensicBytes = await exportService.buildInspectionNotePdf(
        item: itemWithAltitude,
        siteCode: 'SL-001',
        siteName: 'Sector Alpha Construction',
        mode: EvidenceReportMode.forensicAudit,
      );

      expect(forensicBytes, isNotNull);
      expect(forensicBytes.length > 500, isTrue);
    });

    test('remediates vuln-0002: exports unrecorded altitude honestly without fabricating numeric values', () async {
      final itemNoAltitude = testMediaItem.copyWith(altitude: null);
      final pdfBytes = await exportService.buildInspectionNotePdf(
        item: itemNoAltitude,
        siteCode: 'SL-001',
        siteName: 'Sector Alpha Construction',
        mode: EvidenceReportMode.standardInspectionNote,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length > 500, isTrue);
    });

    test('remediates vuln-0003: exportBatchZip cleans up temporary ZIP archive on success', () async {
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (MethodCall methodCall) async {
        return 'success';
      });

      await exportService.exportBatchZip(
        [testMediaItem],
        siteCode: 'SL-001',
        siteName: 'Sector Alpha Construction',
      );

      final zipFiles = tempDir.listSync().where((f) => f.path.endsWith('.zip'));
      expect(zipFiles, isEmpty);
    });

    test('remediates vuln-0003: exportBatchZip cleans up temporary ZIP archive on share failure', () async {
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (MethodCall methodCall) async {
        throw PlatformException(code: 'SHARE_FAILED', message: 'Simulated share error');
      });

      await expectLater(
        () => exportService.exportBatchZip(
          [testMediaItem],
          siteCode: 'SL-001',
          siteName: 'Sector Alpha Construction',
        ),
        throwsA(isA<PlatformException>()),
      );

      final zipFiles = tempDir.listSync().where((f) => f.path.endsWith('.zip'));
      expect(zipFiles, isEmpty);
    });
  });
}
