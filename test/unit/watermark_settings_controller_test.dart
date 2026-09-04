import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/core/controllers/watermark_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WatermarkSettingsController Unit Tests', () {
    test('1. Default settings have showAddress=true and showMapTile=true', () {
      SharedPreferences.setMockInitialValues({});
      final notifier = WatermarkSettingsNotifier();
      expect(notifier.state.showAddress, isTrue);
      expect(notifier.state.showMapTile, isTrue);
    });

    test('2. setShowAddress updates state and persists preference', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = WatermarkSettingsNotifier();

      await notifier.setShowAddress(false);
      expect(notifier.state.showAddress, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(WatermarkSettingsNotifier.keyShowAddress), isFalse);
    });

    test('3. setShowMapTile updates state and persists preference', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = WatermarkSettingsNotifier();

      await notifier.setShowMapTile(false);
      expect(notifier.state.showMapTile, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(WatermarkSettingsNotifier.keyShowMapTile), isFalse);
    });

    test('4. Persisted values restore on notifier initialization', () async {
      SharedPreferences.setMockInitialValues({
        WatermarkSettingsNotifier.keyShowAddress: false,
        WatermarkSettingsNotifier.keyShowMapTile: false,
      });

      final notifier = WatermarkSettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.showAddress, isFalse);
      expect(notifier.state.showMapTile, isFalse);
    });
  });
}
