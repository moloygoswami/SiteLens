import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/geocoding_service.dart';
import '../../../core/utils/gps_utils.dart';
import '../../../core/utils/haversine.dart';
import '../models/gnss_snapshot.dart';
import '../models/gps_hardware_state.dart';
import '../services/location_hardware_service.dart';

final locationHardwareServiceProvider = Provider<LocationHardwareService>((ref) {
  return LocationHardwareService();
});

final gpsHardwareProvider =
    StateNotifierProvider.autoDispose<GpsHardwareNotifier, GpsHardwareState>((ref) {
  final service = ref.watch(locationHardwareServiceProvider);
  final geocodingService = ref.watch(geocodingServiceProvider);
  return GpsHardwareNotifier(service, geocodingService: geocodingService);
});

class GpsHardwareNotifier extends StateNotifier<GpsHardwareState> {
  final LocationHardwareService _service;
  final GeocodingService? _geocodingService;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _stalenessTimer;
  DateTime? _lastEmitTime;
  double? _activeSiteLat;
  double? _activeSiteLon;
  final List<Position> _recentPositions = [];

  /// A fix older than this without a fresh stream emission is treated as
  /// stale and dropped to searching (coordinates cleared). Chosen to sit well
  /// above the 1s stream interval / throttle while staying below a plausible
  /// satellite gap, so a healthy stream never false-positives.
  @visibleForTesting
  static const Duration stalenessTimeout = Duration(seconds: 15);

  /// Maximum retention window for recent position buffer used for best-position selection.
  @visibleForTesting
  static const Duration bufferRetention = Duration(seconds: 10);

  GpsHardwareNotifier(
    this._service, {
    GeocodingService? geocodingService,
  })  : _geocodingService = geocodingService,
        super(const GpsHardwareState()) {
    initialize();
  }

  void setActiveSiteCoordinates(double? lat, double? lon) {
    _activeSiteLat = lat;
    _activeSiteLon = lon;
    if (state.hasValidFix && state.latitude != null && state.longitude != null && lat != null && lon != null) {
      final distance = SpatialMathUtils.haversineDistanceMeters(
        state.latitude!,
        state.longitude!,
        lat,
        lon,
      );
      state = state.copyWith(distanceToSiteMeters: distance);
    } else {
      state = state.copyWith(clearDistanceToSite: true);
    }
  }

  Future<void> initialize() async {
    try {
      final serviceEnabled = await _service.isLocationServiceEnabled();
      final permission = await _service.checkPermission();

      state = state.copyWith(
        isLocationServiceEnabled: serviceEnabled,
        permissionStatus: permission,
      );

      if (!serviceEnabled ||
          (permission == LocationPermission.denied ||
              permission == LocationPermission.deniedForever)) {
        state = state.copyWith(
          fixStatus: GPSFixStatus.searching,
          hasValidFix: false,
          clearFix: true,
        );
        return;
      }

      _service.startGnssUpdates();
      refreshGnssStatus();

      // Check last known position for quick fix (fresh within 60s and <= 30m accuracy)
      final lastKnown = await _service.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        final ageSeconds = DateTime.now().toUtc().difference(lastKnown.timestamp.toUtc()).inSeconds.abs();
        final isFresh = ageSeconds <= 60;
        final isAccurate = lastKnown.accuracy <= 30.0;
        if (isFresh && isAccurate) {
          _processPosition(lastKnown, isInitial: true);
        }
      }

      _startStream();
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          fixStatus: GPSFixStatus.searching,
          hasValidFix: false,
          errorMessage: 'GPS initialization error: $e',
          clearFix: true,
        );
      }
    }
  }

  void _startStream() {
    _positionSubscription?.cancel();
    _positionSubscription = _service.getPositionStream().listen(
      (position) {
        _processPosition(position);
      },
      onError: (error) {
        if (mounted) {
          state = state.copyWith(
            fixStatus: GPSFixStatus.searching,
            hasValidFix: false,
            errorMessage: 'GPS stream error: $error',
            clearFix: true,
          );
        }
      },
    );
  }

  Future<void> _processPosition(Position position, {bool isInitial = false}) async {
    if (!mounted) return;

    final now = clock.now();
    _recentPositions.add(position);
    final cutoff = now.subtract(bufferRetention);
    _recentPositions.removeWhere((p) => p.timestamp.isBefore(cutoff));

    // 1-second throttle before Riverpod state updates
    if (!isInitial && _lastEmitTime != null) {
      final elapsedMs = now.difference(_lastEmitTime!).inMilliseconds;
      if (elapsedMs < 1000) {
        return;
      }
    }
    _lastEmitTime = now;

    final fixStatus = GPSUtils.evaluateAccuracy(position.accuracy, hasFix: true);

    double? distance;
    if (_activeSiteLat != null && _activeSiteLon != null) {
      distance = SpatialMathUtils.haversineDistanceMeters(
        position.latitude,
        position.longitude,
        _activeSiteLat!,
        _activeSiteLon!,
      );
    }

    // Determine truthful altitude and datum
    double altitudeMeters = position.altitude;
    bool isAltitudeMsl = false;

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      isAltitudeMsl = true;
    } else {
      final telemetry = await _service.getAltitudeTelemetry();
      if (telemetry.hasMslAltitude && telemetry.mslAltitudeMeters != null) {
        altitudeMeters = telemetry.mslAltitudeMeters!;
        isAltitudeMsl = true;
      } else {
        altitudeMeters = telemetry.wgs84AltitudeMeters ?? position.altitude;
        isAltitudeMsl = false;
      }
    }

    if (!mounted) return;

    state = state.copyWith(
      fixStatus: fixStatus,
      hasValidFix: true,
      latitude: position.latitude,
      longitude: position.longitude,
      altitudeMeters: altitudeMeters,
      isAltitudeMsl: isAltitudeMsl,
      accuracyMeters: position.accuracy,
      headingDegrees: (position.heading >= 0.0 && position.heading <= 360.0) ? position.heading : null,
      timestampUtc: position.timestamp.toUtc(),
      distanceToSiteMeters: distance,
      clearError: true,
    );

    _restartStalenessWatchdog();
    _resolveLocationName(position.latitude, position.longitude);
    refreshGnssStatus();
  }

  /// Returns the position with the best (lowest) reported horizontal accuracy
  /// among recent valid positions within [window] (default: 5 seconds).
  /// If multiple positions have the same best accuracy, the newest position is preferred.
  /// Falls back to the current valid fix or null if no fix is available.
  Position? getBestRecentPosition({Duration window = const Duration(seconds: 5)}) {
    final now = clock.now();
    final cutoff = now.subtract(window);
    final candidates = _recentPositions
        .where((p) => !p.timestamp.isBefore(cutoff))
        .toList();

    if (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        final accComp = a.accuracy.compareTo(b.accuracy);
        if (accComp != 0) return accComp;
        return b.timestamp.compareTo(a.timestamp);
      });
      return candidates.first;
    }

    if (state.hasValidFix && state.latitude != null && state.longitude != null) {
      return Position(
        latitude: state.latitude!,
        longitude: state.longitude!,
        timestamp: state.timestampUtc ?? now,
        accuracy: state.accuracyMeters ?? 0.0,
        altitude: state.altitudeMeters ?? 0.0,
        altitudeAccuracy: 0.0,
        heading: state.headingDegrees ?? 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
    }
    return null;
  }

  /// Fetches fresh GNSS status and updates state.
  Future<GnssSnapshot> refreshGnssStatus() async {
    try {
      final snapshot = await _service.getGnssStatus();
      if (mounted) {
        state = state.copyWith(gnssSnapshot: snapshot);
      }
      return snapshot;
    } catch (_) {
      return state.gnssSnapshot ?? GnssSnapshot.unavailable;
    }
  }

  /// Restarts the periodic watchdog that drops a fix to searching once no
  /// fresh stream emission has arrived within [stalenessTimeout].
  void _restartStalenessWatchdog() {
    _stalenessTimer?.cancel();
    if (!mounted) return;
    _stalenessTimer = Timer.periodic(stalenessTimeout, (_) {
      if (!mounted) {
        _stalenessTimer?.cancel();
        return;
      }
      final lastEmit = _lastEmitTime;
      if (lastEmit == null) return;
      final elapsed = clock.now().difference(lastEmit);
      if (elapsed >= stalenessTimeout) {
        _stalenessTimer?.cancel();
        setStaleOrSearching();
      }
    });
  }

  Future<void> _resolveLocationName(double lat, double lon) async {
    if (_geocodingService == null) return;
    try {
      final name = await _geocodingService.reverseGeocode(lat, lon);
      if (name != null && mounted) {
        state = state.copyWith(
          resolvedLocationName: name,
          resolvedLocationLat: lat,
          resolvedLocationLon: lon,
        );
      } else if (mounted) {
        debugPrint('[GpsHardwareNotifier] reverseGeocode returned no name for ($lat,$lon)');
      }
    } catch (e) {
      debugPrint('[GpsHardwareNotifier] reverseGeocode failed for ($lat,$lon): $e');
    }
  }

  void setStaleOrSearching() {
    _stalenessTimer?.cancel();
    _stalenessTimer = null;
    _recentPositions.clear();
    state = state.copyWith(
      fixStatus: GPSFixStatus.searching,
      hasValidFix: false,
      clearFix: true,
    );
  }

  void pauseLocationStream() {
    _positionSubscription?.pause();
    _stalenessTimer?.cancel();
    _stalenessTimer = null;
    _service.stopGnssUpdates();
  }

  void resumeLocationStream() {
    _service.startGnssUpdates();
    refreshGnssStatus();
    if (_positionSubscription?.isPaused ?? false) {
      _positionSubscription?.resume();
    } else if (_positionSubscription == null) {
      _startStream();
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _stalenessTimer?.cancel();
    _stalenessTimer = null;
    _recentPositions.clear();
    _service.stopGnssUpdates();
    super.dispose();
  }
}
