import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/enquiry_model.dart';
import '../services/enquiry_service.dart';

enum EnquiryStatus {
  initial,
  submitting,
  success,
  error,
}

class EnquiryState {
  final EnquiryStatus status;
  final EnquirySubmissionResult? result;
  final String? errorMessage;

  const EnquiryState({
    this.status = EnquiryStatus.initial,
    this.result,
    this.errorMessage,
  });

  bool get isSubmitting => status == EnquiryStatus.submitting;
  bool get isSuccess => status == EnquiryStatus.success;
  bool get isError => status == EnquiryStatus.error;

  EnquiryState copyWith({
    EnquiryStatus? status,
    EnquirySubmissionResult? result,
    String? errorMessage,
  }) {
    return EnquiryState(
      status: status ?? this.status,
      result: result ?? this.result,
      errorMessage: errorMessage,
    );
  }
}

class EnquiryController extends StateNotifier<EnquiryState> {
  final IEnquiryService _enquiryService;

  EnquiryController(this._enquiryService) : super(const EnquiryState());

  Future<bool> submitEnquiry({
    required String name,
    required String email,
    required EnquiryCategory category,
    required String message,
  }) async {
    if (state.isSubmitting) return false;

    state = state.copyWith(
      status: EnquiryStatus.submitting,
      errorMessage: null,
    );

    final enquiry = UserEnquiry(
      name: name,
      email: email,
      category: category,
      message: message,
    );

    final result = await _enquiryService.submitEnquiry(enquiry);

    if (result.isSuccess) {
      state = state.copyWith(
        status: EnquiryStatus.success,
        result: result,
      );
      return true;
    } else {
      state = state.copyWith(
        status: EnquiryStatus.error,
        result: result,
        errorMessage: result.errorMessage ?? 'Submission failed.',
      );
      return false;
    }
  }

  void reset() {
    state = const EnquiryState();
  }
}

final enquiryControllerProvider =
    StateNotifierProvider.autoDispose<EnquiryController, EnquiryState>((ref) {
  final service = ref.watch(enquiryServiceProvider);
  return EnquiryController(service);
});
