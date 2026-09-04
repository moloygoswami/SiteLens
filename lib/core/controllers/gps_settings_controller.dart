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
      if (savedVal != null && savedVal > 0) {
        state = GpsSettings(lowAccuracyThresholdMeters: savedVal);
      }
    } catch (e) {
      debugPrint('[GpsSettingsNotifier] Error loading GPS settings: $e');
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
