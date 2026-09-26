import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../models/gps_settings.dart';

final gpsSettingsProvider =
    StateNotifierProvider<GpsSettingsNotifier, GpsSettings>((ref) {
  return GpsSettingsNotifier();
});

class GpsSettingsNotifier extends StateNotifier<GpsSettings> {
  static const String keyLowAccuracyThreshold = 'setting_gps_low_accuracy_threshold';
  static const String keyHighAccuracyMode = 'setting_gps_high_accuracy_mode';
  static const double defaultThreshold = AppConstants.gpsDefaultLowAccuracyThresholdMeters;

  // Standard preset thresholds for user convenience
  static const List<double> presetThresholds = [5.0, 10.0, 15.0, 20.0, 30.0, 50.0];

  GpsSettingsNotifier() : super(const GpsSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVal = prefs.getDouble(keyLowAccuracyThreshold);
      final savedHighAcc = prefs.getBool(keyHighAccuracyMode);
      state = GpsSettings(
        lowAccuracyThresholdMeters: (savedVal != null && savedVal > 0) ? savedVal : defaultThreshold,
        highAccuracyMode: savedHighAcc ?? true,
      );
    } catch (e) {
      debugPrint('[GpsSettingsNotifier] Error loading GPS settings: $e');
    }
  }

  Future<void> setHighAccuracyMode(bool enabled) async {
    if (state.highAccuracyMode == enabled) return;
    state = state.copyWith(highAccuracyMode: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyHighAccuracyMode, enabled);
    } catch (e) {
      debugPrint('[GpsSettingsNotifier] Error persisting high accuracy mode: $e');
    }
  }

  Future<void> setLowAccuracyThreshold(double thresholdMeters) async {
    // Strictly reject invalid, zero, or negative values
    if (thresholdMeters <= 0 || thresholdMeters.isNaN || thresholdMeters.isInfinite) {
      return;
    }
    state = state.copyWith(lowAccuracyThresholdMeters: thresholdMeters);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(keyLowAccuracyThreshold, thresholdMeters);
    } catch (e) {
      debugPrint('[GpsSettingsNotifier] Error persisting GPS settings: $e');
    }
  }

  Future<void> resetToDefault() async {
    await setLowAccuracyThreshold(defaultThreshold);
  }
}
