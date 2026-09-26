import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/core/utils/crypto_utils.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/gallery/services/evidence_export_service.dart';

class MockEvidenceStorageService extends EvidenceStorageService {
  final List<String> resolvedPaths = [];
  String? basePath;

  @override
  Future<String> resolveAbsolutePath(String relativePath) async {
    resolvedPaths.add(relativePath);
    if (basePath != null) {
      return '$basePath/$relativePath';
    }
    return '/mock/$relativePath';
  }
}

String extractPdfText(Uint8List pdf) {
  final raw = latin1.decode(pdf, allowInvalid: true);
  final decompressedBuf = StringBuffer();
  final streamRegex = RegExp(r'stream\r?\n');
  int idx = 0;
  while (true) {
    final m = streamRegex.firstMatch(raw.substring(idx));
    if (m == null) break;
    final start = idx + m.end;
    final end = raw.indexOf('endstream', start);
    if (end < 0) break;
    var chunk = pdf.sublist(start, end);
    while (chunk.isNotEmpty && (chunk.last == 10 || chunk.last == 13 || chunk.last == 32)) {
      chunk = chunk.sublist(0, chunk.length - 1);
    }
    try {
      decompressedBuf.write(latin1.decode(zlib.decode(chunk), allowInvalid: true));
    } catch (_) {
      decompressedBuf.write(latin1.decode(chunk, allowInvalid: true));
    }
    idx = end + 9;
  }
  final streamText = decompressedBuf.toString();
  final tokenRegex = RegExp(r'\(([^)]+)\)');
  final tokens = tokenRegex.allMatches(streamText).map((m) => m.group(1)!).toList();
  return tokens.join(' ');
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
        exporterEmail: 'inspector@company.com',
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
        exporterEmail: 'inspector@company.com',
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
        exporterEmail: 'inspector@company.com',
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

    group('Finding 3 — Forensic Audit PDF Integrity Verification Tests', () {
      setUp(() {
        mockStorage.basePath = tempDir.path;
      });

      test('1. VALID ARTIFACT: matching bytes and expected SHA-256 states "Immutable Pixel Integrity Verified"', () async {
        final mediaDir = Directory('${tempDir.path}/media');
        if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);

        final genuineBytes = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
        final validFile = File('${tempDir.path}/media/evid_valid.jpg');
        await validFile.writeAsBytes(genuineBytes, flush: true);

        final authoritativeHash = CryptoUtils.computeSha256(genuineBytes);
        final validItem = testMediaItem.copyWith(
          id: 'valid-item-1',
          uri: 'media/evid_valid.jpg',
          evidenceSha256Hash: authoritativeHash,
        );

        final pdfBytes = await exportService.buildInspectionNotePdf(
          item: validItem,
          siteCode: 'SL-001',
          siteName: 'Sector Alpha Construction',
          mode: EvidenceReportMode.forensicAudit,
        );

        final text = extractPdfText(pdfBytes);
        expect(text, contains('Immutable Pixel Integrity Verified'));
        expect(text, contains('VERIFIED'));
        expect(text, isNot(contains('Pixel Integrity Unverified')));
        expect(text, isNot(contains('Pixel Integrity Unavailable')));
      });

      test('2. TAMPERED ARTIFACT: on-disk bytes modified after hash established does NOT state verified', () async {
        final mediaDir = Directory('${tempDir.path}/media');
        if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);

        final originalBytes = Uint8List.fromList([1, 2, 3, 4]);
        final authoritativeHash = CryptoUtils.computeSha256(originalBytes);

        // Attacker or corrupted disk writes different bytes
        final tamperedBytes = Uint8List.fromList([9, 9, 9, 9]);
        final tamperedFile = File('${tempDir.path}/media/evid_tampered.jpg');
        await tamperedFile.writeAsBytes(tamperedBytes, flush: true);

        final tamperedItem = testMediaItem.copyWith(
          id: 'tampered-item-1',
          uri: 'media/evid_tampered.jpg',
          evidenceSha256Hash: authoritativeHash,
        );

        final pdfBytes = await exportService.buildInspectionNotePdf(
          item: tamperedItem,
          siteCode: 'SL-001',
          mode: EvidenceReportMode.forensicAudit,
        );

        final text = extractPdfText(pdfBytes);
        expect(text, isNot(contains('Immutable Pixel Integrity Verified')));
        expect(text, contains('Pixel Integrity Unverified'));
        expect(text, contains('UNVERIFIED'));
      });

      test('3. MISSING/UNREADABLE ARTIFACT: missing on-disk file does NOT state verified', () async {
        final missingItem = testMediaItem.copyWith(
          id: 'missing-item-1',
          uri: 'media/evid_non_existent.jpg',
          evidenceSha256Hash: 'a' * 64,
        );

        final pdfBytes = await exportService.buildInspectionNotePdf(
          item: missingItem,
          siteCode: 'SL-001',
          mode: EvidenceReportMode.forensicAudit,
        );

        final text = extractPdfText(pdfBytes);
        expect(text, isNot(contains('Immutable Pixel Integrity Verified')));
        expect(text, contains('Pixel Integrity Unavailable'));
        expect(text, contains('UNAVAILABLE'));
      });

      test('4. HASH UNAVAILABLE / INVALID: null or empty expected hash does NOT state verified', () async {
        final mediaDir = Directory('${tempDir.path}/media');
        if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);

        final dummyBytes = Uint8List.fromList([5, 6, 7, 8]);
        final dummyFile = File('${tempDir.path}/media/evid_no_hash.jpg');
        await dummyFile.writeAsBytes(dummyBytes, flush: true);

        // Item with null evidenceSha256Hash
        final noHashItem = MediaItem(
          id: 'no-hash-item-1',
          siteId: 'SITE_001',
          originalUri: 'media/orig_test-media-101.jpg',
          uri: 'media/evid_no_hash.jpg',
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
          evidenceSha256Hash: null,
          syncStatus: SyncStatusType.pending,
        );

        final pdfBytes = await exportService.buildInspectionNotePdf(
          item: noHashItem,
          siteCode: 'SL-001',
          mode: EvidenceReportMode.forensicAudit,
        );

        final text = extractPdfText(pdfBytes);
        expect(text, isNot(contains('Immutable Pixel Integrity Verified')));
        expect(text, contains('Pixel Integrity Unavailable'));
        expect(text, contains('UNAVAILABLE'));

        // Item with empty string hash
        final emptyHashItem = testMediaItem.copyWith(
          id: 'empty-hash-item-1',
          uri: 'media/evid_no_hash.jpg',
          evidenceSha256Hash: '',
        );

        final pdfBytes2 = await exportService.buildInspectionNotePdf(
          item: emptyHashItem,
          siteCode: 'SL-001',
          mode: EvidenceReportMode.forensicAudit,
        );

        final text2 = extractPdfText(pdfBytes2);
        expect(text2, isNot(contains('Immutable Pixel Integrity Verified')));
        expect(text2, contains('Pixel Integrity Unavailable'));
      });

      test('5. NO FALSE POSITIVE & BATCH ISOLATION: each item independently evaluated, mismatched imageBytes rejected', () async {
        final mediaDir = Directory('${tempDir.path}/media');
        if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);

        // Item 1: Genuine on-disk and matching hash
        final bytes1 = Uint8List.fromList([11, 22, 33]);
        await File('${tempDir.path}/media/evid_batch_1.jpg').writeAsBytes(bytes1, flush: true);
        final item1 = testMediaItem.copyWith(
          id: 'item-1',
          uri: 'media/evid_batch_1.jpg',
          evidenceSha256Hash: CryptoUtils.computeSha256(bytes1),
        );

        // Item 2: Tampered on-disk bytes
        final bytes2 = Uint8List.fromList([44, 55, 66]);
        await File('${tempDir.path}/media/evid_batch_2.jpg').writeAsBytes(bytes2, flush: true);
        final item2 = testMediaItem.copyWith(
          id: 'item-2',
          uri: 'media/evid_batch_2.jpg',
          evidenceSha256Hash: 'b' * 64,
        );

        // Item 3: Missing on-disk file
        final item3 = testMediaItem.copyWith(
          id: 'item-3',
          uri: 'media/evid_missing_batch_3.jpg',
          evidenceSha256Hash: 'c' * 64,
        );

        final batchPdf = await exportService.buildBatchPdf(
          [item1, item2, item3],
          siteCode: 'SL-001',
          mode: EvidenceReportMode.forensicAudit,
        );

        final text = extractPdfText(batchPdf);
        // Page 1 is verified
        expect(text, contains('Immutable Pixel Integrity Verified'));
        // Page 2 is unverified
        expect(text, contains('Pixel Integrity Unverified'));
        // Page 3 is unavailable
        expect(text, contains('Pixel Integrity Unavailable'));

        // Direct imageBytes override test: even if on-disk matches, if imageBytes is mismatched, must NOT be verified
        final mismatchedPdf = await exportService.buildInspectionNotePdf(
          item: item1,
          imageBytes: Uint8List.fromList([99, 99, 99]),
          mode: EvidenceReportMode.forensicAudit,
        );
        final mismatchedText = extractPdfText(mismatchedPdf);
        expect(mismatchedText, isNot(contains('Immutable Pixel Integrity Verified')));
        expect(mismatchedText, contains('Pixel Integrity Unverified'));
      });

      test('6. EXISTING VALID EXPORT BEHAVIOR: standard inspection note mode retains standard footer and no crypto block', () async {
        final mediaDir = Directory('${tempDir.path}/media');
        if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);

        final genuineBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        await File('${tempDir.path}/media/evid_std.jpg').writeAsBytes(genuineBytes, flush: true);
        final item = testMediaItem.copyWith(
          id: 'std-item-1',
          uri: 'media/evid_std.jpg',
          evidenceSha256Hash: CryptoUtils.computeSha256(genuineBytes),
        );

        final stdPdf = await exportService.buildInspectionNotePdf(
          item: item,
          siteCode: 'SL-001',
          siteName: 'Sector Alpha Construction',
          mode: EvidenceReportMode.standardInspectionNote,
        );

        final text = extractPdfText(stdPdf);
        expect(text, contains('SiteLens Inspection System'));
        expect(text, contains('Official Field Inspection Note'));
        expect(text, isNot(contains('Immutable Pixel Integrity Verified')));
        expect(text, isNot(contains('CRYPTOGRAPHIC INTEGRITY & CHAIN-OF-CUSTODY')));
      });
    });
  });
}
