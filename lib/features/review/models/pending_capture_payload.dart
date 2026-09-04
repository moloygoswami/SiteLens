import 'dart:typed_data';
import '../../../domain/models/enums.dart';
import '../../camera/models/evidence_metadata_snapshot.dart';
import '../../camera/models/processed_evidence_payload.dart';

class PendingCapturePayload {
  final String mediaId;
  final MediaItemType mediaType;
  final String originalFilePath;
  final String? evidenceFilePath;
  final String? thumbnailFilePath;
  final String sha256Hash;
  final int fileSizeBytes;
  final Duration? videoDuration;
  final EvidenceMetadataSnapshot metadataSnapshot;
  final ProcessedEvidencePayload? photoPayload;
  final Uint8List? previewBytes;
  final Future<ProcessedEvidencePayload>? processingFuture;
  bool isCancelled;

  PendingCapturePayload({
    required this.mediaId,
    required this.mediaType,
    required this.originalFilePath,
    this.evidenceFilePath,
    this.thumbnailFilePath,
    required this.sha256Hash,
    required this.fileSizeBytes,
    this.videoDuration,
    required this.metadataSnapshot,
    this.photoPayload,
    this.previewBytes,
    this.processingFuture,
    this.isCancelled = false,
  });

  bool get isPhoto => mediaType == MediaItemType.photo;
  bool get isVideo => mediaType == MediaItemType.video;

  void cancelProcessing() {
    isCancelled = true;
  }

  String get formattedFileSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  PendingCapturePayload copyWith({
    String? mediaId,
    MediaItemType? mediaType,
    String? originalFilePath,
    String? evidenceFilePath,
    String? thumbnailFilePath,
    String? sha256Hash,
    int? fileSizeBytes,
    Duration? videoDuration,
    EvidenceMetadataSnapshot? metadataSnapshot,
    ProcessedEvidencePayload? photoPayload,
    Uint8List? previewBytes,
    Future<ProcessedEvidencePayload>? processingFuture,
    bool? isCancelled,
  }) {
    return PendingCapturePayload(
      mediaId: mediaId ?? this.mediaId,
      mediaType: mediaType ?? this.mediaType,
      originalFilePath: originalFilePath ?? this.originalFilePath,
      evidenceFilePath: evidenceFilePath ?? this.evidenceFilePath,
      thumbnailFilePath: thumbnailFilePath ?? this.thumbnailFilePath,
      sha256Hash: sha256Hash ?? this.sha256Hash,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      videoDuration: videoDuration ?? this.videoDuration,
      metadataSnapshot: metadataSnapshot ?? this.metadataSnapshot,
      photoPayload: photoPayload ?? this.photoPayload,
      previewBytes: previewBytes ?? this.previewBytes,
      processingFuture: processingFuture ?? this.processingFuture,
      isCancelled: isCancelled ?? this.isCancelled,
    );
  }

  factory PendingCapturePayload.fromPhotoPayload(
    ProcessedEvidencePayload photoPayload, {
    Uint8List? previewBytes,
    Future<ProcessedEvidencePayload>? processingFuture,
  }) {
    return PendingCapturePayload(
      mediaId: photoPayload.mediaId,
      mediaType: MediaItemType.photo,
      originalFilePath: photoPayload.originalFilePath,
      evidenceFilePath: photoPayload.evidenceFilePath ?? photoPayload.originalFilePath,
      thumbnailFilePath: photoPayload.thumbnailFilePath,
      sha256Hash: photoPayload.originalSha256,
      fileSizeBytes: photoPayload.originalFileSizeBytes,
      metadataSnapshot: photoPayload.metadataSnapshot,
      photoPayload: photoPayload,
      previewBytes: previewBytes,
      processingFuture: processingFuture,
    );
  }
}
