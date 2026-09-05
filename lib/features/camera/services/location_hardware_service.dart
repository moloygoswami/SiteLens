import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../models/gnss_snapshot.dart';

class LocationHardwareService {
  static const MethodChannel _gnssChannel = MethodChannel('com.sitelens.app/gnss');

  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  Future<Position?> getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  LocationSettings _buildHighAccuracySettings({Duration? timeLimit}) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        forceLocationManager: false,
        intervalDuration: const Duration(milliseconds: 500),
        timeLimit: timeLimit,
        useMSLAltitude: true,
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.other,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        timeLimit: timeLimit,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      timeLimit: timeLimit,
    );
  }

  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: _buildHighAccuracySettings(timeLimit: const Duration(seconds: 5)),
      );
    } catch (_) {
      return null;
    }
  }

  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    return Geolocator.getPositionStream(
      locationSettings: locationSettings ?? _buildHighAccuracySettings(),
    );
  }

  /// Fetches native altitude telemetry (MSL availability and values) from Android layer.
  Future<AltitudeTelemetry> getAltitudeTelemetry() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return AltitudeTelemetry.unavailable;
    }
    try {
      final res = await _gnssChannel.invokeMapMethod<dynamic, dynamic>('getAltitudeTelemetry');
      if (res != null) {
        return AltitudeTelemetry.fromMap(res);
      }
      return AltitudeTelemetry.unavailable;
    } catch (_) {
      return AltitudeTelemetry.unavailable;
    }
  }

  /// Fetches the latest GNSS status from the native Android layer.
  Future<GnssSnapshot> getGnssStatus() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return GnssSnapshot.unsupported;
    }
    try {
      final res = await _gnssChannel.invokeMapMethod<dynamic, dynamic>('getGnssStatus');
      return GnssSnapshot.fromMap(res);
    } catch (_) {
      return GnssSnapshot.unavailable;
    }
  }

  /// Starts listening to native GNSS status updates.
  Future<bool> startGnssUpdates() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _gnssChannel.invokeMethod<bool>('startGnssUpdates');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stops listening to native GNSS status updates.
  Future<bool> stopGnssUpdates() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _gnssChannel.invokeMethod<bool>('stopGnssUpdates');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
