import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/core/controllers/map_type_settings_controller.dart';
import 'package:sitelens/domain/models/enums.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapTypeSettingsNotifier Unit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('AppMapType.fromString handles null and invalid values safely', () {
      expect(AppMapType.fromString(null), equals(AppMapType.satellite));
      expect(AppMapType.fromString(''), equals(AppMapType.satellite));
      expect(AppMapType.fromString('invalid'), equals(AppMapType.satellite));
      expect(AppMapType.fromString('SATELLITE'), equals(AppMapType.satellite));
      expect(AppMapType.fromString('satellite'), equals(AppMapType.satellite));
      expect(AppMapType.fromString('normal'), equals(AppMapType.normal));
      expect(AppMapType.fromString('roadmap'), equals(AppMapType.normal));
    });

    test('default map type is AppMapType.satellite when no preference saved', () {
      final notifier = MapTypeSettingsNotifier();
      expect(notifier.state, equals(AppMapType.satellite));
    });

    test('explicit saved normal preference is preserved on load', () async {
      SharedPreferences.setMockInitialValues({
        'setting_map_type': 'normal',
      });
      final notifier = MapTypeSettingsNotifier();
      // Allow async load to complete
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(notifier.state, equals(AppMapType.normal));
    });

    test('explicit saved satellite preference is preserved on load', () async {
      SharedPreferences.setMockInitialValues({
        'setting_map_type': 'satellite',
      });
      final notifier = MapTypeSettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(notifier.state, equals(AppMapType.satellite));
    });

    test('setMapType updates state and persists preference', () async {
      final notifier = MapTypeSettingsNotifier();
      await notifier.setMapType(AppMapType.normal);
      expect(notifier.state, equals(AppMapType.normal));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('setting_map_type'), equals('normal'));
    });

    test('toggleMapType switches between satellite and normal', () async {
      final notifier = MapTypeSettingsNotifier();
      expect(notifier.state, equals(AppMapType.satellite));

      await notifier.toggleMapType();
      expect(notifier.state, equals(AppMapType.normal));

      await notifier.toggleMapType();
      expect(notifier.state, equals(AppMapType.satellite));
    });
  });
}
