import '../../../data/repositories/media_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';

class ReviewTagState {
  final String activityTag;
  final ObservationType observationType;
  final String note;
  final String? linkedMediaId;

  /// The candidate the user has explicitly linked as BEFORE evidence. Authoritative
  /// until the user explicitly replaces or unlinks it. Distinct from
  /// [suggestedBeforeMatch], which is only a Smart-Link suggestion.
  final MediaItem? linkedCandidate;
  final MediaItem? suggestedBeforeMatch;
  final double? suggestedDistanceMeters;
  final bool isSearchingSmartLink;
  final bool isSaving;
  final String? errorMessage;
  final bool hasSiteOpenNonConformities;
  final List<NearbyMediaResult> siteWideCandidates;
  final bool isSiteWideSearchExpanded;

  const ReviewTagState({
    this.activityTag = '',
    this.observationType = ObservationType.general,
    this.note = '',
    this.linkedMediaId,
    this.linkedCandidate,
    this.suggestedBeforeMatch,
    this.suggestedDistanceMeters,
    this.isSearchingSmartLink = false,
    this.isSaving = false,
    this.errorMessage,
    this.hasSiteOpenNonConformities = true,
    this.siteWideCandidates = const [],
    this.isSiteWideSearchExpanded = false,
  });

  bool get isLinked =>
      linkedMediaId != null &&
      linkedCandidate != null &&
      linkedMediaId == linkedCandidate!.id;

  ReviewTagState copyWith({
    String? activityTag,
    ObservationType? observationType,
    String? note,
    String? linkedMediaId,
    MediaItem? linkedCandidate,
    bool clearLinkedMediaId = false,
    MediaItem? suggestedBeforeMatch,
    bool clearSuggestedBeforeMatch = false,
    double? suggestedDistanceMeters,
    bool isSearchingSmartLink = false,
    bool? isSaving,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? hasSiteOpenNonConformities,
    List<NearbyMediaResult>? siteWideCandidates,
    bool? isSiteWideSearchExpanded,
  }) {
    return ReviewTagState(
      activityTag: activityTag ?? this.activityTag,
      observationType: observationType ?? this.observationType,
      note: note ?? this.note,
      linkedMediaId: clearLinkedMediaId ? null : (linkedMediaId ?? this.linkedMediaId),
      linkedCandidate: clearLinkedMediaId
          ? null
          : (linkedCandidate ?? this.linkedCandidate),
      suggestedBeforeMatch: clearSuggestedBeforeMatch
          ? null
          : (suggestedBeforeMatch ?? this.suggestedBeforeMatch),
      suggestedDistanceMeters: clearSuggestedBeforeMatch
          ? null
          : (suggestedDistanceMeters ?? this.suggestedDistanceMeters),
      isSearchingSmartLink: isSearchingSmartLink,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      hasSiteOpenNonConformities:
          hasSiteOpenNonConformities ?? this.hasSiteOpenNonConformities,
      siteWideCandidates: siteWideCandidates ?? this.siteWideCandidates,
      isSiteWideSearchExpanded:
          isSiteWideSearchExpanded ?? this.isSiteWideSearchExpanded,
    );
  }
}
