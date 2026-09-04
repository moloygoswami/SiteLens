import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final nearbySettingsProvider =
    StateNotifierProvider<NearbySettingsNotifier, double>((ref) {
  return NearbySettingsNotifier();
});

class NearbySettingsNotifier extends StateNotifier<double> {
  static const String keyDefaultRadius = 'setting_nearby_default_radius';
  static const double defaultRadius = 10.0;

  NearbySettingsNotifier() : super(defaultRadius) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRadius = prefs.getDouble(keyDefaultRadius);
      if (savedRadius != null && savedRadius > 0) {
        state = savedRadius;
      }
    } catch (e) {
      debugPrint('[NearbySettingsNotifier] Error loading settings: $e');
    }
  }

  Future<void> setDefaultRadius(double radius) async {
    if (radius <= 0 || state == radius) return;
    state = radius;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(keyDefaultRadius, radius);
    } catch (e) {
      debugPrint('[NearbySettingsNotifier] Error persisting defaultRadius: $e');
    }
  }
}
