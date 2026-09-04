import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';

class ReviewTagState {
  final String activityTag;
  final ObservationType observationType;
  final String note;
  final String? linkedMediaId;
  final MediaItem? suggestedBeforeMatch;
  final double? suggestedDistanceMeters;
  final bool isSearchingSmartLink;
  final bool isSaving;
  final String? errorMessage;

  const ReviewTagState({
    this.activityTag = '',
    this.observationType = ObservationType.general,
    this.note = '',
    this.linkedMediaId,
    this.suggestedBeforeMatch,
    this.suggestedDistanceMeters,
    this.isSearchingSmartLink = false,
    this.isSaving = false,
    this.errorMessage,
  });

  bool get isLinked => linkedMediaId != null;

  ReviewTagState copyWith({
    String? activityTag,
    ObservationType? observationType,
    String? note,
    String? linkedMediaId,
    bool clearLinkedMediaId = false,
    MediaItem? suggestedBeforeMatch,
    bool clearSuggestedBeforeMatch = false,
    double? suggestedDistanceMeters,
    bool isSearchingSmartLink = false,
    bool? isSaving,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ReviewTagState(
      activityTag: activityTag ?? this.activityTag,
      observationType: observationType ?? this.observationType,
      note: note ?? this.note,
      linkedMediaId: clearLinkedMediaId ? null : (linkedMediaId ?? this.linkedMediaId),
      suggestedBeforeMatch: clearSuggestedBeforeMatch
          ? null
          : (suggestedBeforeMatch ?? this.suggestedBeforeMatch),
      suggestedDistanceMeters: clearSuggestedBeforeMatch
          ? null
          : (suggestedDistanceMeters ?? this.suggestedDistanceMeters),
      isSearchingSmartLink: isSearchingSmartLink,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
