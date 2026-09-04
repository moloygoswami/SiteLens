import 'evidence_metadata_snapshot.dart';

class ProcessedEvidencePayload {
  final bool isSuccess;
  final String mediaId;
  final String originalFilePath;
  final String? evidenceFilePath;
  final String? thumbnailFilePath;
  final String originalSha256;
  final String? evidenceSha256;
  final int originalFileSizeBytes;
  final int? evidenceFileSizeBytes;
  final int? thumbnailFileSizeBytes;
  final int thumbnailWidth;
  final int thumbnailHeight;
  final EvidenceMetadataSnapshot metadataSnapshot;
  final String? errorMessage;

  const ProcessedEvidencePayload({
    required this.isSuccess,
    required this.mediaId,
    required this.originalFilePath,
    this.evidenceFilePath,
    this.thumbnailFilePath,
    required this.originalSha256,
    this.evidenceSha256,
    required this.originalFileSizeBytes,
    this.evidenceFileSizeBytes,
    this.thumbnailFileSizeBytes,
    this.thumbnailWidth = 0,
    this.thumbnailHeight = 0,
    required this.metadataSnapshot,
    this.errorMessage,
  });

  factory ProcessedEvidencePayload.failure({
    required String mediaId,
    required String originalFilePath,
    required String originalSha256,
    required int originalFileSizeBytes,
    required EvidenceMetadataSnapshot metadataSnapshot,
    required String errorMessage,
  }) {
    return ProcessedEvidencePayload(
      isSuccess: false,
      mediaId: mediaId,
      originalFilePath: originalFilePath,
      originalSha256: originalSha256,
      originalFileSizeBytes: originalFileSizeBytes,
      metadataSnapshot: metadataSnapshot,
      errorMessage: errorMessage,
    );
  }
}
