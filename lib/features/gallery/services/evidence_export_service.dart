import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/utils/gps_utils.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../../camera/hud/hud_formatter.dart';
import '../../camera/services/evidence_storage_service.dart';

/// Report presentation mode for PDF generation.
enum EvidenceReportMode {
  /// Standard client-facing inspection note focusing on site, observations, telemetry, photo & remarks.
  standardInspectionNote,

  /// Dedicated forensic & legal audit report exposing cryptographic hashes, chain-of-custody, and file URIs.
  forensicAudit,
}

bool _present(String? value) => value != null && value.trim().isNotEmpty;

/// R21 — immutable, truthful export attribution.
///
/// Evidence creator attribution is bound to the persisted `media.creator_id` of
/// the exported record. The exporter (the authenticated user triggering the
/// export) is tracked separately and can never overwrite the creator. A
/// human-readable identity is surfaced ONLY when it actually exists; otherwise
/// it stays explicitly unknown — no inspector/engineer name is ever fabricated.
class ExportAttribution {
  /// Persisted `creator_id` of the evidence being exported (authoritative).
  final String? evidenceCreatorId;

  /// Identity of the authenticated user performing the export.
  final String? exporterUid;
  final String? exporterEmail;

  const ExportAttribution({
    required this.evidenceCreatorId,
    this.exporterUid,
    this.exporterEmail,
  });

  /// Evidence creator attribution for display. Never substitutes the exporter.
  String get creatorLabel =>
      _present(evidenceCreatorId) ? evidenceCreatorId!.trim() : 'Unknown';

  /// Exporter attribution for display; unknown stays explicitly unknown.
  String get exporterLabel =>
      _present(exporterEmail) ? exporterEmail!.trim() : 'Unknown';

  /// Authoritative exporter UID for display; unknown stays explicitly unknown.
  String get exporterUidLabel =>
      _present(exporterUid) ? exporterUid!.trim() : 'Unknown';

  /// Optional authoritative human identity of the exporter, or null when the
  /// trusted session did not establish one. Never fabricated.
  String? get exporterHumanIdentity => _present(exporterEmail)
      ? exporterEmail!.trim()
      : null;
}

final evidenceExportServiceProvider = Provider<EvidenceExportService>((ref) {
  final storageService = ref.watch(evidenceStorageServiceProvider);
  return EvidenceExportService(storageService);
});

class EvidenceExportService {
  final EvidenceStorageService _storageService;

  EvidenceExportService(this._storageService);

  // ==========================================
  // SINGLE EVIDENCE EXPORTS
  // ==========================================

  /// Shares a single evidence file (JPEG photo or MP4 video) via native OS share sheet.
  Future<void> shareSingleFile(String absolutePath, {String? text}) async {
    final file = File(absolutePath);
    if (!await file.exists()) {
      throw Exception('Evidence file not found on disk: $absolutePath');
    }
    await Share.shareXFiles(
      [XFile(absolutePath)],
      text: text,
    );
  }

  /// Builds a one-page client-facing PDF inspection note (or forensic audit report) for a single MediaItem.
  Future<Uint8List> buildInspectionNotePdf({
    required MediaItem item,
    String? siteCode,
    String? siteName,
    String? exporterEmail,
    String? exporterUid,
    Uint8List? imageBytes,
    EvidenceReportMode mode = EvidenceReportMode.standardInspectionNote,
  }) async {
    final doc = pw.Document();

    Uint8List? resolvedImageBytes = imageBytes;
    if (resolvedImageBytes == null) {
      try {
        final targetUri = item.uri;
        final absPath = await _storageService.resolveAbsolutePath(targetUri);
        final file = File(absPath);
        if (await file.exists()) {
          resolvedImageBytes = await file.readAsBytes();
        }
      } catch (_) {}
    }

    doc.addPage(
      _buildSingleReportPage(
        item: item,
        siteCode: siteCode,
        siteName: siteName,
        exporterEmail: exporterEmail,
        exporterUid: exporterUid,
        imageBytes: resolvedImageBytes,
        pageIndex: 1,
        totalPages: 1,
        mode: mode,
      ),
    );

    return doc.save();
  }

  /// Alias for [buildInspectionNotePdf] supporting legacy or explicit forensic invocation.
  Future<Uint8List> buildAuditPdf({
    required MediaItem item,
    String? siteCode,
    String? siteName,
    String? exporterEmail,
    String? exporterUid,
    Uint8List? imageBytes,
    EvidenceReportMode mode = EvidenceReportMode.standardInspectionNote,
  }) =>
      buildInspectionNotePdf(
        item: item,
        siteCode: siteCode,
        siteName: siteName,
        exporterEmail: exporterEmail,
        exporterUid: exporterUid,
        imageBytes: imageBytes,
        mode: mode,
      );

  /// Exports the single item PDF inspection note and opens the native OS share dialog.
  Future<void> exportSingleInspectionNotePdf({
    required MediaItem item,
    String? siteCode,
    String? siteName,
    String? exporterEmail,
    String? exporterUid,
    Uint8List? imageBytes,
    EvidenceReportMode mode = EvidenceReportMode.standardInspectionNote,
  }) async {
    final pdfBytes = await buildInspectionNotePdf(
      item: item,
      siteCode: siteCode,
      siteName: siteName,
      exporterEmail: exporterEmail,
      exporterUid: exporterUid,
      imageBytes: imageBytes,
      mode: mode,
    );

    final filename = mode == EvidenceReportMode.forensicAudit
        ? 'SiteLens_Audit_${item.id}.pdf'
        : 'SiteLens_Inspection_Note_${item.id}.pdf';

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: filename,
    );
  }

  /// Alias for [exportSingleInspectionNotePdf] supporting legacy or explicit forensic invocation.
  Future<void> exportSingleAuditPdf({
    required MediaItem item,
    String? siteCode,
    String? siteName,
    String? exporterEmail,
    String? exporterUid,
    Uint8List? imageBytes,
    EvidenceReportMode mode = EvidenceReportMode.standardInspectionNote,
  }) =>
      exportSingleInspectionNotePdf(
        item: item,
        siteCode: siteCode,
        siteName: siteName,
        exporterEmail: exporterEmail,
        exporterUid: exporterUid,
        imageBytes: imageBytes,
        mode: mode,
      );

  // ==========================================
  // BATCH / BULK EVIDENCE EXPORTS
  // ==========================================

  /// Shares multiple evidence files directly via native OS share sheet.
  Future<void> shareBatchFiles(List<MediaItem> items, {String? text}) async {
    if (items.isEmpty) return;

    final xFiles = <XFile>[];
    for (final item in items) {
      try {
        final targetUri = item.uri;
        final absPath = await _storageService.resolveAbsolutePath(targetUri);
        if (await File(absPath).exists()) {
          xFiles.add(XFile(absPath));
        }
      } catch (_) {}
    }

    if (xFiles.isEmpty) {
      throw Exception(
          'None of the selected evidence files could be located on disk.');
    }

    await Share.shareXFiles(
      xFiles,
      text: text ?? 'SiteLens Batch Export (${xFiles.length} evidence files)',
    );
  }

  /// Assembles a multi-page PDF report with one page per selected MediaItem.
  Future<Uint8List> buildBatchPdf(
    List<MediaItem> items, {
    String? siteCode,
    String? siteName,
    String? exporterEmail,
    String? exporterUid,
    EvidenceReportMode mode = EvidenceReportMode.standardInspectionNote,
  }) async {
    final doc = pw.Document();
    final totalPages = items.length;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      Uint8List? resolvedImageBytes;
      try {
        final targetUri = item.uri;
        final absPath = await _storageService.resolveAbsolutePath(targetUri);
        final file = File(absPath);
        if (await file.exists()) {
          resolvedImageBytes = await file.readAsBytes();
        }
      } catch (_) {}

      doc.addPage(
        _buildSingleReportPage(
          item: item,
          siteCode: siteCode,
          siteName: siteName,
          exporterEmail: exporterEmail,
          exporterUid: exporterUid,
          imageBytes: resolvedImageBytes,
          pageIndex: i + 1,
          totalPages: totalPages,
          mode: mode,
        ),
      );
    }

    return doc.save();
  }

  /// Exports the multi-page batch PDF report and triggers the native OS share sheet.
  Future<void> exportBatchPdf(
    List<MediaItem> items, {
    String? siteCode,
    String? siteName,
    String? exporterEmail,
    String? exporterUid,
    EvidenceReportMode mode = EvidenceReportMode.standardInspectionNote,
  }) async {
    if (items.isEmpty) return;

    final pdfBytes = await buildBatchPdf(
      items,
      siteCode: siteCode,
      siteName: siteName,
      exporterEmail: exporterEmail,
      exporterUid: exporterUid,
      mode: mode,
    );

    final filename = mode == EvidenceReportMode.forensicAudit
        ? 'SiteLens_Audit_Report_${DateTime.now().millisecondsSinceEpoch}.pdf'
        : 'SiteLens_Inspection_Notes_${DateTime.now().millisecondsSinceEpoch}.pdf';

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: filename,
    );
  }

  /// Packages all selected evidence files, a generated manifest.json index, and the batch PDF report into a ZIP archive.
  Future<String> buildZipPackage(
    List<MediaItem> items, {
    String? siteCode,
    String? siteName,
    String? exporterEmail,
    String? exporterUid,
    EvidenceReportMode mode = EvidenceReportMode.standardInspectionNote,
  }) async {
    if (items.isEmpty) {
      throw Exception('Cannot generate ZIP package for empty selection.');
    }

    final archive = Archive();
    final nowUtc = DateTime.now().toUtc();
    final nowUtcIso = nowUtc.toIso8601String();

    // 1. Build manifest.json with full cryptographic hashes & provenance.
    // R21: each record is attributed to its persisted evidence creator, and the
    // exporter is recorded separately. The exporting user never substitutes the
    // creator, and an absent human identity stays null rather than defaulted.
    final evidenceCreatorIds = items
        .map((item) => item.creatorId)
        .where(_present)
        .cast<String>()
        .toSet()
        .toList();
    final manifestMap = {
      'export_generated_at': nowUtcIso,
      // R20/R21: canonical human-facing site code via the shared resolver.
      'site_code': HudFormatter.resolveSiteIdentifier(siteCode),
      'site_name': siteName ?? 'Inspection Site',
      'evidence_creator_ids': evidenceCreatorIds,
      'exporter_uid': _present(exporterUid) ? exporterUid!.trim() : null,
      'exporter_email':
          _present(exporterEmail) ? exporterEmail!.trim() : null,
      'item_count': items.length,
      'items': items.map((item) {
        final origFileName = item.originalUri.split('/').last;
        final evidFileName = item.uri.split('/').last;
        return {
          'id': item.id,
          'type': item.type.name,
          'creator_id': _present(item.creatorId) ? item.creatorId!.trim() : null,
          'captured_at': item.capturedAt.toUtc().toIso8601String(),
          'lat': item.lat,
          'lon': item.lon,
          'accuracy_m': item.accuracyM,
          'observation_type': item.observationType.name,
          'activity': item.activityTag,
          'note': item.note,
          'linked_media_id': item.linkedMediaId,
          'sha256_original': item.sha256Hash,
          'sha256_evidence': item.evidenceSha256Hash,
          'captured_address': item.capturedAddress,
          'original_file': origFileName,
          'evidence_file': evidFileName,
        };
      }).toList(),
    };

    final manifestBytes =
        utf8.encode(const JsonEncoder.withIndent('  ').convert(manifestMap));
    archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    // 2. Generate and embed full inspection PDF report
    final pdfBytes = await buildBatchPdf(
      items,
      siteCode: siteCode,
      siteName: siteName,
      exporterEmail: exporterEmail,
      exporterUid: exporterUid,
      mode: mode,
    );
    archive.addFile(
        ArchiveFile('inspection_report.pdf', pdfBytes.length, pdfBytes));

    // 3. Embed evidence and original files
    for (final item in items) {
      try {
        final evidAbs = await _storageService.resolveAbsolutePath(item.uri);
        final evidFile = File(evidAbs);
        if (await evidFile.exists()) {
          final bytes = await evidFile.readAsBytes();
          final filename = item.uri.split('/').last;
          archive
              .addFile(ArchiveFile('evidence/$filename', bytes.length, bytes));
        }

        if (item.originalUri.isNotEmpty) {
          final origAbs =
              await _storageService.resolveAbsolutePath(item.originalUri);
          final origFile = File(origAbs);
          if (await origFile.exists()) {
            final bytes = await origFile.readAsBytes();
            final filename = item.originalUri.split('/').last;
            archive.addFile(
                ArchiveFile('originals/$filename', bytes.length, bytes));
          }
        }
      } catch (_) {}
    }

    // 4. Encode ZIP
    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);
    if (zipBytes == null) {
      throw Exception('Failed to encode ZIP archive.');
    }

    final tempDir = await getTemporaryDirectory();
    final zipPath =
        '${tempDir.path}/SiteLens_Export_${DateTime.now().millisecondsSinceEpoch}.zip';
    final zipFile = File(zipPath);

    try {
      await zipFile.writeAsBytes(zipBytes, flush: true);
      return zipPath;
    } catch (e) {
      // Defensively clean up any partial or abandoned ZIP file created by this operation (vuln-0003)
      try {
        if (await zipFile.exists()) {
          await zipFile.delete();
        }
      } catch (cleanupErr) {
        debugPrint('[EvidenceExportService] Partial ZIP cleanup error: $cleanupErr');
      }
      rethrow;
    }
  }

  /// Exports the packaged ZIP archive via native OS share sheet and cleans up temporary file (vuln-0005).
  Future<void> exportBatchZip(
    List<MediaItem> items, {
    String? siteCode,
    String? siteName,
    String? exporterEmail,
    String? exporterUid,
    EvidenceReportMode mode = EvidenceReportMode.standardInspectionNote,
  }) async {
    final zipPath = await buildZipPackage(
      items,
      siteCode: siteCode,
      siteName: siteName,
      exporterEmail: exporterEmail,
      exporterUid: exporterUid,
      mode: mode,
    );

    try {
      await Share.shareXFiles(
        [XFile(zipPath)],
        text:
            'SiteLens Evidence Archive (${items.length} items with manifest & inspection report)',
      );
    } finally {
      // Best-effort cleanup of temporary exported ZIP archive
      try {
        final zipFile = File(zipPath);
        if (await zipFile.exists()) {
          await zipFile.delete();
        }
      } catch (e) {
        debugPrint('[EvidenceExportService] Temporary export ZIP cleanup: $e');
      }
    }
  }

  // ==========================================
  // PAGE TEMPLATE GENERATOR
  // ==========================================

  static pw.Page _buildSingleReportPage({
    required MediaItem item,
    String? siteCode,
    String? siteName,
    String? exporterEmail,
    String? exporterUid,
    Uint8List? imageBytes,
    required int pageIndex,
    required int totalPages,
    EvidenceReportMode mode = EvidenceReportMode.standardInspectionNote,
  }) {
    final capturedUtc = item.capturedAt.toUtc();
    final capturedUtcFormatted =
        '${DateFormat("yyyy-MM-dd HH:mm:ss").format(capturedUtc)} UTC';
    final generatedUtcFormatted =
        '${DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now().toUtc())} UTC';

    final coordFormatted = GPSUtils.formatCoordinates(item.lat, item.lon);
    final actualAlt = GPSUtils.formatAltitude(item.altitude, isMsl: item.isAltitudeMsl);
    final precisionFormatted = item.accuracyM != null
        ? '±${item.accuracyM!.toStringAsFixed(1)}m (${item.lowAccuracy ? "Degraded" : "High Precision"})'
        : 'Unknown Fix';

    final fullOrigSha = item.sha256Hash ?? 'UNKNOWN';
    final fullEvidSha = item.evidenceSha256Hash ?? 'UNKNOWN';
    // R20: the canonical human-facing site code is the only identifier emitted;
    // the internal database site id is never substituted into export metadata.
    final effectiveSiteCode = HudFormatter.resolveSiteIdentifier(siteCode);
    final effectiveSiteName = (siteName != null && siteName.isNotEmpty)
        ? siteName
        : 'Inspection Site';
    final effectiveAddress =
        (item.capturedAddress != null && item.capturedAddress!.isNotEmpty)
            ? item.capturedAddress!
            : '$effectiveSiteCode VICINITY';

    // R21: creator and exporter are distinct, non-interchangeable attributions.
    final attribution = ExportAttribution(
      evidenceCreatorId: item.creatorId,
      exporterUid: exporterUid,
      exporterEmail: exporterEmail,
    );

    final isForensic = mode == EvidenceReportMode.forensicAudit;
    final reportTitle =
        isForensic ? 'FORENSIC EVIDENCE AUDIT REPORT' : 'INSPECTION NOTE';
    final reportIdPrefix = isForensic ? 'AUDIT ID' : 'NOTE ID';
    final footerTitle = isForensic
        ? 'SiteLens Forensic Evidence System • Immutable Pixel Integrity Verified'
        : 'SiteLens Inspection System • Official Field Inspection Note';

    pw.MemoryImage? pdfImage;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      try {
        pdfImage = pw.MemoryImage(imageBytes);
      } catch (_) {}
    }

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // 1. Header Banner
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const pw.BoxDecoration(
                color: PdfColors.orange800,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'SITELENS',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      pw.Text(
                        reportTitle,
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        '$reportIdPrefix: ${item.id.length > 12 ? item.id.substring(0, 12).toUpperCase() : item.id.toUpperCase()}',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.Text(
                        'GENERATED: $generatedUtcFormatted',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 14),

            // 2. Middle Body: Telemetry & Image Preview
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left side: Metadata Table
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('SITE CONTEXT & OBSERVATION'),
                      _buildDataRow('Site Code & Name',
                          '$effectiveSiteCode • $effectiveSiteName'),
                      _buildDataRow('Captured Address', effectiveAddress,
                          isEmphasized: true),
                      _buildDataRow('Activity / Work Stage',
                          item.activityTag ?? 'Not Specified'),
                      _buildDataRow('Observation Type',
                          item.observationType.label.toUpperCase()),
                      if (item.linkedMediaId != null)
                        _buildDataRow('Linked BEFORE ID', item.linkedMediaId!),
                      _buildDataRow(
                          'Evidence Creator (UID)', attribution.creatorLabel),
                      _buildDataRow('Exported By', attribution.exporterLabel),
                      pw.SizedBox(height: 10),
                      _buildSectionHeader('CALIBRATED GPS TELEMETRY'),
                      _buildDataRow('Capture Timestamp', capturedUtcFormatted),
                      _buildDataRow('Capture Coordinates', coordFormatted),
                      _buildDataRow('Altitude', actualAlt),
                      _buildDataRow('GPS Precision', precisionFormatted),
                      _buildDataRow(
                          'Media Type',
                          item.type == MediaItemType.video
                              ? 'Video (MP4)'
                              : 'Photo (JPEG)'),
                    ],
                  ),
                ),

                pw.SizedBox(width: 14),

                // Right side: Image Box Preview
                pw.Expanded(
                  flex: 2,
                  child: pw.Container(
                    height: isForensic ? 200 : 250,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400, width: 1),
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(6)),
                      color: PdfColors.grey100,
                    ),
                    child: pdfImage != null
                        ? pw.ClipRRect(
                            horizontalRadius: 6,
                            verticalRadius: 6,
                            child: pw.Center(
                              child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
                            ),
                          )
                        : pw.Center(
                            child: pw.Text(
                              item.type == MediaItemType.video
                                  ? '[ Video Media Record ]\n${item.uri}'
                                  : '[ Evidence Photo ]',
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(
                                fontSize: 10,
                                color: PdfColors.grey600,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 10),

            // 3. Notes & Context Section
            _buildSectionHeader('INSPECTION NOTES & REMARKS'),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                color: PdfColors.grey50,
              ),
              child: pw.Text(
                (item.note != null && item.note!.trim().isNotEmpty)
                    ? item.note!
                    : 'No additional textual notes recorded at capture time.',
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
              ),
            ),

            if (isForensic) ...[
              pw.SizedBox(height: 10),

              // 4. Cryptographic Provenance & File Integrity Block (ONLY IN FORENSIC MODE)
              _buildSectionHeader('CRYPTOGRAPHIC INTEGRITY & CHAIN-OF-CUSTODY'),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                  color: PdfColors.grey100,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildCryptoRow('Original File URI', item.originalUri),
                    _buildCryptoRow('Evidence File URI', item.uri),
                    _buildCryptoRow('Thumbnail URI', item.thumbUri ?? '—'),
                    pw.Divider(color: PdfColors.grey300, height: 8),
                    _buildCryptoRow('Original SHA-256', fullOrigSha,
                        isHash: true),
                    _buildCryptoRow('Evidence SHA-256', fullEvidSha,
                        isHash: true),
                    pw.Divider(color: PdfColors.grey300, height: 8),
                    _buildCryptoRow(
                        'Exported By (UID)', attribution.exporterUidLabel),
                  ],
                ),
              ),
            ],

            pw.Spacer(),

            // 5. Footer
            pw.Divider(color: PdfColors.grey400, height: 1),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  footerTitle,
                  style: const pw.TextStyle(
                      fontSize: 7.5, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Page $pageIndex of $totalPages',
                  style: const pw.TextStyle(
                      fontSize: 7.5, color: PdfColors.grey600),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static pw.Widget _buildSectionHeader(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4, top: 2),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.orange900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static pw.Widget _buildDataRow(String label, String value,
      {bool isEmphasized = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight:
                    isEmphasized ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: isEmphasized ? PdfColors.black : PdfColors.grey900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCryptoRow(String label, String value,
      {bool isHash = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 100,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 7.5,
                font: isHash ? pw.Font.courier() : null,
                fontWeight: isHash ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: isHash ? PdfColors.grey900 : PdfColors.grey800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
