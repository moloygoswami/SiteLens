import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/core/controllers/timestamp_settings_controller.dart';
import 'package:sitelens/core/models/timestamp_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimestampDisplaySettings Unit Tests', () {
    final sampleUtc = DateTime.utc(2026, 8, 15, 14, 30, 45);

    test('Formats UTC in 24-hour style by default', () {
      const settings = TimestampDisplaySettings(
        timezoneMode: TimezoneMode.utc,
        formatStyle: TimeFormatStyle.twentyFourHour,
      );
      expect(settings.format(sampleUtc), '2026-08-15 14:30:45 UTC');
    });

    test('Formats UTC in 12-hour style', () {
      const settings = TimestampDisplaySettings(
        timezoneMode: TimezoneMode.utc,
        formatStyle: TimeFormatStyle.twelveHour,
      );
      expect(settings.format(sampleUtc), '2026-08-15 02:30:45 PM UTC');
    });

    test('Formats UTC in ISO-8601 style', () {
      const settings = TimestampDisplaySettings(
        timezoneMode: TimezoneMode.utc,
        formatStyle: TimeFormatStyle.iso8601,
      );
      expect(settings.format(sampleUtc), '2026-08-15T14:30:45.000Z');
    });

    test('Formats Local timezone with system timezone name', () {
      const settings = TimestampDisplaySettings(
        timezoneMode: TimezoneMode.local,
        formatStyle: TimeFormatStyle.twentyFourHour,
      );
      final localFormatted = settings.format(sampleUtc);
      expect(localFormatted, contains(sampleUtc.toLocal().timeZoneName));
    });

    test('Handles null timestamp gracefully', () {
      const settings = TimestampDisplaySettings();
      expect(settings.format(null), '—');
    });

    test('TimestampSettingsNotifier persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = TimestampSettingsNotifier();

      await notifier.setTimezoneMode(TimezoneMode.local);
      expect(notifier.state.timezoneMode, TimezoneMode.local);

      await notifier.setFormatStyle(TimeFormatStyle.twelveHour);
      expect(notifier.state.formatStyle, TimeFormatStyle.twelveHour);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('setting_timestamp_tz_mode'), TimezoneMode.local.index);
      expect(prefs.getInt('setting_timestamp_format_style'), TimeFormatStyle.twelveHour.index);
    });
  });
}
