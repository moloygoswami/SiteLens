import 'package:flutter/material.dart';
import '../../app/theme.dart';

enum EvidencePhase {
  before,
  after,
  none;

  bool get isBefore => this == EvidencePhase.before;
  bool get isAfter => this == EvidencePhase.after;
}

enum ObservationType {
  progress,
  nonConformity,
  closed,
  material,
  general;

  String get label {
    switch (this) {
      case ObservationType.progress:
        return 'Progress';
      case ObservationType.nonConformity:
        return 'Non-Conformity';
      case ObservationType.closed:
        return 'Closed';
      case ObservationType.material:
        return 'Material';
      case ObservationType.general:
        return 'General';
    }
  }

  Color get color {
    switch (this) {
      case ObservationType.nonConformity:
        return AppColors.statusRed;
      case ObservationType.closed:
        return AppColors.statusGreen;
      case ObservationType.progress:
        return AppColors.primary;
      case ObservationType.material:
        return const Color(0xFF0288D1);
      case ObservationType.general:
        return AppColors.textSecondary;
    }
  }

  IconData get icon {
    switch (this) {
      case ObservationType.nonConformity:
        return Icons.report_problem_rounded;
      case ObservationType.closed:
        return Icons.check_circle_rounded;
      case ObservationType.progress:
        return Icons.trending_up_rounded;
      case ObservationType.material:
        return Icons.inventory_2_rounded;
      case ObservationType.general:
        return Icons.photo_camera_rounded;
    }
  }

  /// Explicit semantic role mapping:
  /// Non-Conformity -> BEFORE
  /// Closed -> AFTER
  /// Progress, Material, General -> NONE
  EvidencePhase get phase {
    switch (this) {
      case ObservationType.nonConformity:
        return EvidencePhase.before;
      case ObservationType.closed:
        return EvidencePhase.after;
      case ObservationType.progress:
      case ObservationType.material:
      case ObservationType.general:
        return EvidencePhase.none;
    }
  }

  /// Silently treated as "Before" in smart-link resolution workflows
  bool get isBeforeRole => phase == EvidencePhase.before;

  /// Silently treated as "After" in smart-link resolution workflows
  bool get isAfterRole => phase == EvidencePhase.after;

  static ObservationType fromString(String? val) {
    if (val == null) return ObservationType.general;
    final normalized = val.toLowerCase().replaceAll('-', '').replaceAll('_', '');
    if (normalized == 'nonconformity' || normalized == 'before') {
      return ObservationType.nonConformity;
    }
    if (normalized == 'closed' || normalized == 'after') {
      return ObservationType.closed;
    }
    return ObservationType.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse: () => ObservationType.general,
    );
  }
}

enum MediaItemType {
  photo,
  video;

  static MediaItemType fromString(String? val) {
    if (val == null) return MediaItemType.photo;
    return MediaItemType.values.firstWhere(
      (e) => e.name.toLowerCase() == val.toLowerCase(),
      orElse: () => MediaItemType.photo,
    );
  }
}

enum SyncStatusType {
  pending,
  syncing,
  synced,
  failed;

  static SyncStatusType fromInt(int? val) {
    switch (val) {
      case 1:
        return SyncStatusType.synced;
      case 2:
        return SyncStatusType.syncing;
      case 3:
        return SyncStatusType.failed;
      default:
        return SyncStatusType.pending;
    }
  }

  int toInt() {
    switch (this) {
      case SyncStatusType.synced:
        return 1;
      case SyncStatusType.syncing:
        return 2;
      case SyncStatusType.failed:
        return 3;
      case SyncStatusType.pending:
        return 0;
    }
  }
}

enum AppMapType {
  normal('Default', 'roadmap'),
  satellite('Satellite', 'satellite');

  final String label;
  final String staticMapParam;

  const AppMapType(this.label, this.staticMapParam);

  static AppMapType fromString(String? val) {
    if (val == null) return AppMapType.satellite;
    final normalized = val.toLowerCase().trim();
    if (normalized == 'normal' || normalized == 'roadmap') return AppMapType.normal;
    return AppMapType.satellite;
  }
}

enum IntegrityVerificationResult {
  verified,
  unverified,
  unavailable;

  String get label => name.toUpperCase();
}

