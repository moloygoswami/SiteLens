import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/core/controllers/nearby_settings_controller.dart';
import 'package:sitelens/data/repositories/media_repository.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/features/nearby/controllers/nearby_search_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NearbySettingsController Unit Tests', () {
    test('1. Default radius is 10.0 meters', () {
      SharedPreferences.setMockInitialValues({});
      final notifier = NearbySettingsNotifier();
      expect(notifier.state, equals(10.0));
    });

    test('2. setDefaultRadius updates state and persists preference', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = NearbySettingsNotifier();

      await notifier.setDefaultRadius(25.0);
      expect(notifier.state, equals(25.0));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(NearbySettingsNotifier.keyDefaultRadius), equals(25.0));
    });

    test('3. Invalid or negative radius values are ignored', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = NearbySettingsNotifier();

      await notifier.setDefaultRadius(-5.0);
      expect(notifier.state, equals(10.0));

      await notifier.setDefaultRadius(0.0);
      expect(notifier.state, equals(10.0));
    });

    test('4. Persisted radius restores on notifier initialization', () async {
      SharedPreferences.setMockInitialValues({
        NearbySettingsNotifier.keyDefaultRadius: 50.0,
      });

      final notifier = NearbySettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state, equals(50.0));
    });

    test('Test A — Default: New NearbySearchNotifier uses authoritative default (10.0m)', () {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        ],
      );
      final sub = container.listen(nearbySearchControllerProvider(null), (_, __) {});
      addTearDown(sub.close);
      addTearDown(container.dispose);

      final state = container.read(nearbySearchControllerProvider(null));
      expect(state.radiusMeters, equals(10.0));
    });

    test('Test B — Persisted value: 50.0m in preferences initializes NearbySearch with 50.0m', () async {
      SharedPreferences.setMockInitialValues({
        NearbySettingsNotifier.keyDefaultRadius: 50.0,
      });

      final container = ProviderContainer(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        ],
      );
      final sub = container.listen(nearbySearchControllerProvider(null), (_, __) {});
      addTearDown(sub.close);
      addTearDown(container.dispose);

      // Wait for async init of settings
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(nearbySearchControllerProvider(null));
      expect(state.radiusMeters, equals(50.0));
    });

    test('Test C — Settings change: Updating nearbySettingsProvider affects subsequent NearbySearch', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        ],
      );
      final sub = container.listen(nearbySearchControllerProvider(null), (_, __) {});
      addTearDown(sub.close);
      addTearDown(container.dispose);

      await container.read(nearbySettingsProvider.notifier).setDefaultRadius(5.0);

      final state = container.read(nearbySearchControllerProvider(null));
      expect(state.radiusMeters, equals(5.0));
    });

    test('Test D — No hardcoded runtime override: controller does not revert to 25.0m', () {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        ],
      );
      final sub = container.listen(nearbySearchControllerProvider(null), (_, __) {});
      addTearDown(sub.close);
      addTearDown(container.dispose);

      final state = container.read(nearbySearchControllerProvider(null));
      expect(state.radiusMeters, isNot(equals(25.0)));
      expect(state.radiusMeters, equals(10.0));
    });
  });
}

class FakeMediaRepository implements MediaRepository {
  @override
  Future<List<NearbyMediaResult>> findNearbyMedia({
    required double centerLat,
    required double centerLon,
    required double radiusMeters,
    String? siteId,
    String? activity,
    ObservationType? observationType,
    String? excludeMediaId,
    String? creatorId,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
