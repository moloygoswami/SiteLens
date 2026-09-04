import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/enums.dart';

/// Persistent controller for shared application map type (Normal vs Satellite).
final mapTypeSettingsProvider =
    StateNotifierProvider<MapTypeSettingsNotifier, AppMapType>((ref) {
  return MapTypeSettingsNotifier();
});

class MapTypeSettingsNotifier extends StateNotifier<AppMapType> {
  static const String _keyMapType = 'setting_map_type';

  MapTypeSettingsNotifier() : super(AppMapType.satellite) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStr = prefs.getString(_keyMapType);
      if (savedStr != null) {
        state = AppMapType.fromString(savedStr);
      }
    } catch (e) {
      debugPrint('[MapTypeSettingsNotifier] Error loading map type setting: $e');
    }
  }

  Future<void> setMapType(AppMapType type) async {
    if (state == type) return;
    state = type;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMapType, type.name);
    } catch (e) {
      debugPrint('[MapTypeSettingsNotifier] Error persisting map type setting: $e');
    }
  }

  Future<void> toggleMapType() async {
    final nextType = state == AppMapType.normal ? AppMapType.satellite : AppMapType.normal;
    await setMapType(nextType);
  }
}
