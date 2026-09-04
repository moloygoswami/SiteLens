import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/features/gallery/models/gallery_selection_state.dart';

void main() {
  group('GallerySelectionNotifier Unit Tests', () {
    late GallerySelectionNotifier notifier;

    setUp(() {
      notifier = GallerySelectionNotifier();
    });

    test('Initial state has selectMode = false and empty set', () {
      expect(notifier.state.isSelectMode, isFalse);
      expect(notifier.state.selectedIds, isEmpty);
      expect(notifier.state.selectedCount, 0);
    });

    test('enterSelectMode activates select mode and adds initial id', () {
      notifier.enterSelectMode('item-1');
      expect(notifier.state.isSelectMode, isTrue);
      expect(notifier.state.selectedIds, contains('item-1'));
      expect(notifier.state.selectedCount, 1);
      expect(notifier.state.isSelected('item-1'), isTrue);
      expect(notifier.state.isSelected('item-2'), isFalse);
    });

    test('toggleSelection adds and removes items properly', () {
      notifier.enterSelectMode();
      notifier.toggleSelection('item-1');
      expect(notifier.state.selectedIds, contains('item-1'));

      notifier.toggleSelection('item-2');
      expect(notifier.state.selectedCount, 2);

      notifier.toggleSelection('item-1');
      expect(notifier.state.selectedIds, isNot(contains('item-1')));
      expect(notifier.state.selectedCount, 1);
    });

    test('selectAll and clearSelection manipulate entire batch', () {
      notifier.selectAll(['id-1', 'id-2', 'id-3']);
      expect(notifier.state.isSelectMode, isTrue);
      expect(notifier.state.selectedCount, 3);

      notifier.clearSelection();
      expect(notifier.state.isSelectMode, isTrue);
      expect(notifier.state.selectedCount, 0);
    });

    test('exitSelectMode resets mode and clears all selection', () {
      notifier.selectAll(['id-1', 'id-2']);
      notifier.exitSelectMode();
      expect(notifier.state.isSelectMode, isFalse);
      expect(notifier.state.selectedCount, 0);
    });
  });
}
