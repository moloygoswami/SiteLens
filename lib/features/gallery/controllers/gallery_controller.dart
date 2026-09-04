import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/session_service.dart';
import '../../../data/repositories/media_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../../sites/site_controller.dart';
import '../models/gallery_filter_state.dart';
import '../models/gallery_view_mode.dart';

class GalleryFilterNotifier extends StateNotifier<GalleryFilterState> {
  GalleryFilterNotifier() : super(const GalleryFilterState());

  void setSearchQuery(String query) {
    if (query.trim().isEmpty) {
      state = state.copyWith(clearSearchQuery: true);
    } else {
      state = state.copyWith(searchQuery: query.trim());
    }
  }

  void clearSearchQuery() {
    state = state.copyWith(clearSearchQuery: true);
  }

  void setObservationType(ObservationType? type) {
    if (type == null || state.observationType == type) {
      state = state.copyWith(clearObservationType: true);
    } else {
      state = state.copyWith(observationType: type);
    }
  }

  void setActivityTag(String? activity) {
    if (activity == null || activity.trim().isEmpty) {
      state = state.copyWith(clearActivityTag: true);
    } else {
      state = state.copyWith(activityTag: activity.trim());
    }
  }

  void setDateRange(DateTimeRange? range) {
    if (range == null) {
      state = state.copyWith(clearDateRange: true);
    } else {
      state = state.copyWith(dateRange: range);
    }
  }

  void toggleLowAccuracyOnly() {
    state = state.copyWith(lowAccuracyOnly: !state.lowAccuracyOnly);
  }

  void setSyncStatus(SyncStatusType? status) {
    if (status == null || state.syncStatus == status) {
      state = state.copyWith(clearSyncStatus: true);
    } else {
      state = state.copyWith(syncStatus: status);
    }
  }

  void setSiteId(String? siteId) {
    if (siteId == null || siteId.isEmpty) {
      state = state.copyWith(clearSiteId: true);
    } else {
      state = state.copyWith(siteId: siteId);
    }
  }

  void resetFilters() {
    state = state.clearAllFilters();
  }
}

final galleryFilterProvider =
    StateNotifierProvider<GalleryFilterNotifier, GalleryFilterState>((ref) {
  return GalleryFilterNotifier();
});

final galleryViewModeProvider = StateProvider<GalleryViewMode>((ref) {
  return GalleryViewMode.grid3x3;
});

final filteredGalleryMediaProvider = StreamProvider<List<MediaItem>>((ref) {
  final mediaRepo = ref.watch(mediaRepositoryProvider);
  final filter = ref.watch(galleryFilterProvider);
  final activeSite = ref.watch(siteControllerProvider).activeSite;
  String? currentUserId;
  try {
    final session = ref.watch(sessionServiceProvider);
    currentUserId = session.user?.uid;
  } catch (_) {
    currentUserId = null;
  }

  // Use explicit site filter if set, otherwise default to active site (or null for all sites)
  final targetSiteId = filter.siteId ?? activeSite?.id;

  // watchAllMedia strictly excludes is_deleted = 1 and scopes to active user session (vuln-0003)
  return mediaRepo.watchAllMedia(siteId: targetSiteId, creatorId: currentUserId).map((items) {
    return items.where((item) {
      // 1. Metadata Search Filter
      if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
        final q = filter.searchQuery!.toLowerCase();
        final noteMatch = item.note?.toLowerCase().contains(q) ?? false;
        final activityMatch = item.activityTag?.toLowerCase().contains(q) ?? false;
        final obsMatch = item.observationType.label.toLowerCase().contains(q);
        final idMatch = item.id.toLowerCase().contains(q);
        final siteMatch = item.siteId.toLowerCase().contains(q);

        if (!noteMatch && !activityMatch && !obsMatch && !idMatch && !siteMatch) {
          return false;
        }
      }

      // 2. Observation Type Filter
      if (filter.observationType != null) {
        if (item.observationType != filter.observationType) {
          return false;
        }
      }

      // 3. Activity / Work Stage Filter
      if (filter.activityTag != null && filter.activityTag!.isNotEmpty) {
        if (item.activityTag?.toLowerCase() != filter.activityTag!.toLowerCase()) {
          return false;
        }
      }

      // 4. Date Range Filter
      if (filter.dateRange != null) {
        final localCaptured = item.capturedAt.toLocal();
        final start = DateTime(
          filter.dateRange!.start.year,
          filter.dateRange!.start.month,
          filter.dateRange!.start.day,
          0,
          0,
          0,
        );
        final end = DateTime(
          filter.dateRange!.end.year,
          filter.dateRange!.end.month,
          filter.dateRange!.end.day,
          23,
          59,
          59,
          999,
        );

        if (localCaptured.isBefore(start) || localCaptured.isAfter(end)) {
          return false;
        }
      }

      // 5. Low Accuracy (>20m) Filter
      if (filter.lowAccuracyOnly) {
        final isLow = item.lowAccuracy || (item.accuracyM != null && item.accuracyM! > 20.0);
        if (!isLow) {
          return false;
        }
      }

      // 6. Sync Status Filter
      if (filter.syncStatus != null) {
        if (item.syncStatus != filter.syncStatus) {
          return false;
        }
      }

      return true;
    }).toList();
  });
});
