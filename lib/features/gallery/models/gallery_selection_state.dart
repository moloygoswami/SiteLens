import 'package:flutter_riverpod/flutter_riverpod.dart';

class GallerySelectionState {
  final bool isSelectMode;
  final Set<String> selectedIds;

  const GallerySelectionState({
    this.isSelectMode = false,
    this.selectedIds = const {},
  });

  int get selectedCount => selectedIds.length;
  bool isSelected(String id) => selectedIds.contains(id);

  GallerySelectionState copyWith({
    bool? isSelectMode,
    Set<String>? selectedIds,
  }) {
    return GallerySelectionState(
      isSelectMode: isSelectMode ?? this.isSelectMode,
      selectedIds: selectedIds ?? this.selectedIds,
    );
  }
}

class GallerySelectionNotifier extends StateNotifier<GallerySelectionState> {
  GallerySelectionNotifier() : super(const GallerySelectionState());

  void enterSelectMode([String? initialId]) {
    state = GallerySelectionState(
      isSelectMode: true,
      selectedIds: initialId != null ? {initialId} : {},
    );
  }

  void exitSelectMode() {
    state = const GallerySelectionState(
      isSelectMode: false,
      selectedIds: {},
    );
  }

  void toggleSelection(String id) {
    if (!state.isSelectMode) {
      enterSelectMode(id);
      return;
    }

    final updated = Set<String>.from(state.selectedIds);
    if (updated.contains(id)) {
      updated.remove(id);
    } else {
      updated.add(id);
    }

    state = state.copyWith(selectedIds: updated);
  }

  void selectAll(List<String> allIds) {
    state = state.copyWith(
      isSelectMode: true,
      selectedIds: Set<String>.from(allIds),
    );
  }

  void clearSelection() {
    state = state.copyWith(selectedIds: {});
  }
}

final gallerySelectionProvider =
    StateNotifierProvider<GallerySelectionNotifier, GallerySelectionState>((ref) {
  return GallerySelectionNotifier();
});
