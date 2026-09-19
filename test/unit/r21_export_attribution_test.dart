import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/domain/models/media_item.dart';
import 'package:sitelens/features/camera/services/evidence_storage_service.dart';
import 'package:sitelens/features/gallery/services/evidence_export_service.dart';

class _MockEvidenceStorageService extends EvidenceStorageService {
  @override
  Future<String> resolveAbsolutePath(String relativePath) async =>
      '/mock/$relativePath';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockEvidenceStorageService mockStorage;
  late EvidenceExportService exportService;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('r21_export_test_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      return tempDir.path;
    });

    mockStorage = _MockEvidenceStorageService();
    exportService = EvidenceExportService(mockStorage);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  MediaItem itemFor({String? creatorId, String id = 'media-1'}) => MediaItem(
        id: id,
        siteId: 'site-doc-id-1',
        creatorId: creatorId,
        originalUri: 'media/orig_$id.jpg',
        uri: 'media/evid_$id.jpg',
        thumbUri: 'media/thumb_$id.jpg',
        type: MediaItemType.photo,
        lat: 22.56298,
        lon: 88.30085,
        accuracyM: 3.5,
        activityTag: 'Foundation Excavation',
        observationType: ObservationType.progress,
        capturedAt: DateTime.utc(2026, 8, 15, 10, 30, 0),
        sha256Hash:
            'a1b2c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdef',
        evidenceSha256Hash:
            'f1e2d3c4b5a678901234567890abcdef1234567890abcdef1234567890abcdef',
        capturedAddress: '42 Construction Way • New Town, Kolkata',
      );

  Future<Map<String, dynamic>> readManifest(
    List<MediaItem> items, {
    String? siteCode,
    String? exporterUid,
    String? exporterEmail,
  }) async {
    final zipPath = await exportService.buildZipPackage(
      items,
      siteCode: siteCode,
      siteName: 'Sector Alpha Construction',
      exporterUid: exporterUid,
      exporterEmail: exporterEmail,
    );
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile =
        archive.files.firstWhere((f) => f.name == 'manifest.json');
    return jsonDecode(utf8.decode(manifestFile.content as List<int>))
        as Map<String, dynamic>;
  }

  group('R21 Export Attribution', () {
    test(
        'R21: exported manifest attributes evidence to the persisted creator, never the exporter',
        () async {
      final manifest = await readManifest(
        [itemFor(creatorId: 'creator-uid-A')],
        siteCode: 'sl-001',
        exporterUid: 'exporter-uid-B',
        exporterEmail: 'exporter@example.com',
      );

      expect(manifest['evidence_creator_ids'], ['creator-uid-A']);

      final items = manifest['items'] as List;
      expect(items.first['creator_id'], 'creator-uid-A');

      // The exporter is recorded separately and is never substituted as creator.
      expect(manifest['exporter_uid'], 'exporter-uid-B');
      expect(manifest['exporter_email'], 'exporter@example.com');
      expect(manifest['exporter_uid'], isNot('creator-uid-A'));
      expect(items.first['creator_id'], isNot(manifest['exporter_uid']));
    });

    test('R21: missing human identity is never fabricated', () async {
      final manifest = await readManifest(
        [itemFor(creatorId: null)],
        exporterUid: null,
        exporterEmail: null,
      );

      expect(manifest['exporter_uid'], isNull);
      expect(manifest['exporter_email'], isNull);
      expect(manifest['evidence_creator_ids'], isEmpty);
      expect((manifest['items'] as List).first['creator_id'], isNull);

      final encoded = jsonEncode(manifest);
      expect(encoded, isNot(contains('Field Inspector')));
      expect(encoded, isNot(contains('Site Inspector')));
      expect(encoded, isNot(contains('Site Engineer')));
    });

    test('R21: canonical site identity is preserved via the shared resolver',
        () async {
      expect(
        (await readManifest([itemFor(creatorId: 'c')], siteCode: 'sl-001'))[
            'site_code'],
        'SL-001',
      );
      expect(
        (await readManifest([itemFor(creatorId: 'c')], siteCode: 'UNASSIGNED'))[
            'site_code'],
        'SITE',
      );
      expect(
        (await readManifest([itemFor(creatorId: 'c')], siteCode: null))[
            'site_code'],
        'SITE',
      );
    });

    test('R21: attribution labels distinguish creator, exporter and unknown',
        () {
      const full = ExportAttribution(
        evidenceCreatorId: 'creator-uid-A',
        exporterUid: 'exporter-uid-B',
        exporterEmail: 'exporter@example.com',
      );
      expect(full.creatorLabel, 'creator-uid-A');
      expect(full.exporterLabel, 'exporter@example.com');
      expect(full.exporterUidLabel, 'exporter-uid-B');
      expect(full.exporterHumanIdentity, 'exporter@example.com');
      expect(full.creatorLabel, isNot(full.exporterLabel));

      const none = ExportAttribution(evidenceCreatorId: null);
      expect(none.creatorLabel, 'Unknown');
      expect(none.exporterLabel, 'Unknown');
      expect(none.exporterUidLabel, 'Unknown');
      expect(none.exporterHumanIdentity, isNull);
    });
  });
}
