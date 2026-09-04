import 'package:flutter/material.dart';
import '../../../domain/models/enums.dart';

class GalleryFilterState {
  final String? searchQuery;
  final ObservationType? observationType;
  final String? activityTag;
  final DateTimeRange? dateRange;
  final bool lowAccuracyOnly;
  final SyncStatusType? syncStatus;
  final String? siteId;

  const GalleryFilterState({
    this.searchQuery,
    this.observationType,
    this.activityTag,
    this.dateRange,
    this.lowAccuracyOnly = false,
    this.syncStatus,
    this.siteId,
  });

  bool get hasActiveFilters {
    return (searchQuery != null && searchQuery!.trim().isNotEmpty) ||
        observationType != null ||
        (activityTag != null && activityTag!.trim().isNotEmpty) ||
        dateRange != null ||
        lowAccuracyOnly ||
        syncStatus != null;
  }

  int get activeFilterCount {
    int count = 0;
    if (searchQuery != null && searchQuery!.trim().isNotEmpty) count++;
    if (observationType != null) count++;
    if (activityTag != null && activityTag!.trim().isNotEmpty) count++;
    if (dateRange != null) count++;
    if (lowAccuracyOnly) count++;
    if (syncStatus != null) count++;
    return count;
  }

  GalleryFilterState copyWith({
    String? searchQuery,
    ObservationType? observationType,
    String? activityTag,
    DateTimeRange? dateRange,
    bool? lowAccuracyOnly,
    SyncStatusType? syncStatus,
    String? siteId,
    bool clearSearchQuery = false,
    bool clearObservationType = false,
    bool clearActivityTag = false,
    bool clearDateRange = false,
    bool clearSyncStatus = false,
    bool clearSiteId = false,
  }) {
    return GalleryFilterState(
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      observationType: clearObservationType ? null : (observationType ?? this.observationType),
      activityTag: clearActivityTag ? null : (activityTag ?? this.activityTag),
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      lowAccuracyOnly: lowAccuracyOnly ?? this.lowAccuracyOnly,
      syncStatus: clearSyncStatus ? null : (syncStatus ?? this.syncStatus),
      siteId: clearSiteId ? null : (siteId ?? this.siteId),
    );
  }

  GalleryFilterState clearAllFilters() {
    return GalleryFilterState(
      siteId: siteId, // Preserve active site selection
    );
  }
}
