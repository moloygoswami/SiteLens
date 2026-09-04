import 'package:flutter/foundation.dart';
import '../../../data/repositories/media_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';

enum NearbyViewMode {
  grouped,
  timeline,
  map,
}

@immutable
class NearbySearchFilters {
  final bool sameSiteOnly;
  final String? activityTag;
  final ObservationType? observationType;
  final DateTime? startDate;
  final DateTime? endDate;

  const NearbySearchFilters({
    this.sameSiteOnly = true,
    this.activityTag,
    this.observationType,
    this.startDate,
    this.endDate,
  });

  NearbySearchFilters copyWith({
    bool? sameSiteOnly,
    String? activityTag,
    ObservationType? observationType,
    DateTime? startDate,
    DateTime? endDate,
    bool clearActivityTag = false,
    bool clearObservationType = false,
    bool clearStartDate = false,
    bool clearEndDate = false,
  }) {
    return NearbySearchFilters(
      sameSiteOnly: sameSiteOnly ?? this.sameSiteOnly,
      activityTag: clearActivityTag ? null : (activityTag ?? this.activityTag),
      observationType: clearObservationType ? null : (observationType ?? this.observationType),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
    );
  }

  int get activeFilterCount {
    int count = 0;
    if (!sameSiteOnly) count++;
    if (activityTag != null && activityTag!.trim().isNotEmpty) count++;
    if (observationType != null) count++;
    if (startDate != null || endDate != null) count++;
    return count;
  }

  bool get hasActiveFilters => activeFilterCount > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NearbySearchFilters &&
          runtimeType == other.runtimeType &&
          sameSiteOnly == other.sameSiteOnly &&
          activityTag == other.activityTag &&
          observationType == other.observationType &&
          startDate == other.startDate &&
          endDate == other.endDate;

  @override
  int get hashCode =>
      sameSiteOnly.hashCode ^
      activityTag.hashCode ^
      observationType.hashCode ^
      startDate.hashCode ^
      endDate.hashCode;
}

@immutable
class NearbySearchState {
  final MediaItem? sourceMedia;
  final double centerLat;
  final double centerLon;
  final double radiusMeters;
  final NearbyViewMode viewMode;
  final NearbySearchFilters filters;
  final bool isLoading;
  final String? errorMessage;
  final List<NearbyMediaResult> results;

  const NearbySearchState({
    this.sourceMedia,
    required this.centerLat,
    required this.centerLon,
    this.radiusMeters = 25.0,
    this.viewMode = NearbyViewMode.grouped,
    this.filters = const NearbySearchFilters(),
    this.isLoading = false,
    this.errorMessage,
    this.results = const [],
  });

  // Grouped accessors per PRD Section 11.3
  List<NearbyMediaResult> get beforeResults => results
      .where((r) => r.item.observationType == ObservationType.nonConformity)
      .toList();

  List<NearbyMediaResult> get afterResults => results
      .where((r) => r.item.observationType == ObservationType.closed)
      .toList();

  List<NearbyMediaResult> get progressResults => results
      .where((r) => r.item.observationType == ObservationType.progress)
      .toList();

  List<NearbyMediaResult> get otherResults => results
      .where((r) =>
          r.item.observationType != ObservationType.nonConformity &&
          r.item.observationType != ObservationType.closed &&
          r.item.observationType != ObservationType.progress)
      .toList();

  /// Chronological timeline accessors per PRD Section 11.6
  /// Displays all items from oldest to newest regardless of observation type.
  List<NearbyMediaResult> get chronologicalResults {
    final list = List<NearbyMediaResult>.from(results);
    list.sort((a, b) => a.item.capturedAt.compareTo(b.item.capturedAt));
    return list;
  }

  int get totalCount => results.length;

  NearbySearchState copyWith({
    MediaItem? sourceMedia,
    double? centerLat,
    double? centerLon,
    double? radiusMeters,
    NearbyViewMode? viewMode,
    NearbySearchFilters? filters,
    bool? isLoading,
    String? errorMessage,
    List<NearbyMediaResult>? results,
    bool clearErrorMessage = false,
  }) {
    return NearbySearchState(
      sourceMedia: sourceMedia ?? this.sourceMedia,
      centerLat: centerLat ?? this.centerLat,
      centerLon: centerLon ?? this.centerLon,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      viewMode: viewMode ?? this.viewMode,
      filters: filters ?? this.filters,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      results: results ?? this.results,
    );
  }
}
