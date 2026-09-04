import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/timestamp_settings.dart';

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

final timestampSettingsProvider =
    StateNotifierProvider<TimestampSettingsNotifier, TimestampDisplaySettings>((ref) {
  return TimestampSettingsNotifier();
});

class TimestampSettingsNotifier extends StateNotifier<TimestampDisplaySettings> {
  static const String _keyTzMode = 'setting_timestamp_tz_mode';
  static const String _keyFormatStyle = 'setting_timestamp_format_style';

  TimestampSettingsNotifier() : super(const TimestampDisplaySettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tzIndex = prefs.getInt(_keyTzMode);
      final formatIndex = prefs.getInt(_keyFormatStyle);

      state = TimestampDisplaySettings(
        timezoneMode: tzIndex != null && tzIndex < TimezoneMode.values.length
            ? TimezoneMode.values[tzIndex]
            : TimezoneMode.utc,
        formatStyle: formatIndex != null && formatIndex < TimeFormatStyle.values.length
            ? TimeFormatStyle.values[formatIndex]
            : TimeFormatStyle.twentyFourHour,
      );
    } catch (_) {
      // Default to UTC 24-hour on error
    }
  }

  Future<void> setTimezoneMode(TimezoneMode mode) async {
    state = state.copyWith(timezoneMode: mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyTzMode, mode.index);
    } catch (_) {}
  }

  Future<void> setFormatStyle(TimeFormatStyle style) async {
    state = state.copyWith(formatStyle: style);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyFormatStyle, style.index);
    } catch (_) {}
  }
}
