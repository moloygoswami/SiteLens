import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watermark_settings.dart';

final watermarkSettingsProvider =
    StateNotifierProvider<WatermarkSettingsNotifier, WatermarkSettings>((ref) {
  return WatermarkSettingsNotifier();
});

class WatermarkSettingsNotifier extends StateNotifier<WatermarkSettings> {
  static const String keyShowAddress = 'setting_watermark_show_address';
  static const String keyShowMapTile = 'setting_watermark_show_map_tile';

  WatermarkSettingsNotifier() : super(const WatermarkSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final showAddress = prefs.getBool(keyShowAddress) ?? true;
      final showMapTile = prefs.getBool(keyShowMapTile) ?? true;
      state = WatermarkSettings(
        showAddress: showAddress,
        showMapTile: showMapTile,
      );
    } catch (e) {
      debugPrint('[WatermarkSettingsNotifier] Error loading settings: $e');
    }
  }

  Future<void> setShowAddress(bool value) async {
    if (state.showAddress == value) return;
    state = state.copyWith(showAddress: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyShowAddress, value);
    } catch (e) {
      debugPrint('[WatermarkSettingsNotifier] Error persisting showAddress: $e');
    }
  }

  Future<void> setShowMapTile(bool value) async {
    if (state.showMapTile == value) return;
    state = state.copyWith(showMapTile: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyShowMapTile, value);
    } catch (e) {
      debugPrint('[WatermarkSettingsNotifier] Error persisting showMapTile: $e');
    }
  }
}
