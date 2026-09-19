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

/// A buffered position together with its capture provenance and the altitude
/// the device actually established for it.
///
/// Provenance exists so a cached last-known seed can never be selected as a
/// live fix (R06). The resolved altitude/datum exists so an altitude the
/// device never established is never substituted by the raw, non-nullable
/// `Position.altitude` (which reads 0.0 when unavailable) — R10.
@immutable
class BufferedGpsPosition {
  final Position position;
  final bool isLive;
  final double? resolvedAltitudeMeters;
  final bool resolvedIsMsl;

  const BufferedGpsPosition({
    required this.position,
    required this.isLive,
    required this.resolvedAltitudeMeters,
    required this.resolvedIsMsl,
  });

  double get latitude => position.latitude;
  double get longitude => position.longitude;
  double get accuracy => position.accuracy;
  DateTime get timestamp => position.timestamp;
}

class GpsHardwareNotifier extends StateNotifier<GpsHardwareState> {
  final LocationHardwareService _service;
  final GeocodingService? _geocodingService;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _stalenessTimer;
  DateTime? _lastEmitTime;
  double? _activeSiteLat;
  double? _activeSiteLon;
  final List<BufferedGpsPosition> _recentPositions = [];

  /// True while the position subscription is paused because the app left the
  /// foreground. A subscription paused for lifecycle reasons must not be relied
  /// on for recovery: on Android the native stream behind it can stay silent
  /// indefinitely after backgrounding, so lifecycle resume rebuilds the native
  /// stream instead of resuming this subscription.
  bool _isStreamPausedByLifecycle = false;

  /// Bumped by every pause/resume request so an in-flight
  /// [resumeLocationStream] abandons its work when a newer lifecycle transition
  /// supersedes it (e.g. the app is backgrounded again mid-revalidation).
  int _lifecycleGeneration = 0;

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

      final bool granted = permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;

      if (!serviceEnabled || !granted) {
        // Cannot acquire: denied, denied-forever, or an indeterminate
        // permission. Drop any latched fix; blockReason distinguishes the
        // specific cause for the UI (denied / unknown / service off) and never
        // collapses unknown or service-off into denied.
        state = state.copyWith(
          fixStatus: GPSFixStatus.searching,
          hasValidFix: false,
          isLastKnownSeed: false,
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
    _isStreamPausedByLifecycle = false;
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

  /// Cancels the current subscription and drops the reference, so the next
  /// [_startStream] is served by a brand-new native stream.
  ///
  /// The subscription is cancelled rather than resumed: a subscription paused
  /// for lifecycle reasons is not a reliable recovery path, and cancelling is
  /// what makes `geolocator_android` discard its cached position stream.
  ///
  /// The returned future is deliberately not awaited — Dart does not complete
  /// the cancellation of a *paused* subscription promptly, while the cached
  /// stream is invalidated synchronously inside the cancel, so the stream
  /// requested immediately afterwards is already a fresh native subscription.
  void _releaseStream() {
    final existing = _positionSubscription;
    _positionSubscription = null;
    _isStreamPausedByLifecycle = false;
    if (existing != null) {
      unawaited(existing.cancel());
    }
  }

  Future<void> _processPosition(Position position, {bool isInitial = false}) async {
    if (!mounted) return;

    final now = clock.now();

    // Resolve the truthful altitude/datum BEFORE buffering, so every buffered
    // entry carries the altitude the device actually established. An altitude
    // the device did not establish stays null — the raw, non-nullable
    // `Position.altitude` (0.0 when unavailable) is never substituted (R10).
    double? altitudeMeters;
    bool isAltitudeMsl;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      altitudeMeters = position.altitude;
      isAltitudeMsl = true;
    } else {
      final telemetry = await _service.getAltitudeTelemetry();
      if (telemetry.hasMslAltitude && telemetry.mslAltitudeMeters != null) {
        altitudeMeters = telemetry.mslAltitudeMeters;
        isAltitudeMsl = true;
      } else if (telemetry.wgs84AltitudeMeters != null) {
        altitudeMeters = telemetry.wgs84AltitudeMeters;
        isAltitudeMsl = false;
      } else {
        altitudeMeters = null;
        isAltitudeMsl = false;
      }
    }

    if (!mounted) return;

    _recentPositions.add(BufferedGpsPosition(
      position: position,
      isLive: !isInitial,
      resolvedAltitudeMeters: altitudeMeters,
      resolvedIsMsl: isAltitudeMsl,
    ));
    if (!isInitial) {
      // A genuine stream emission supersedes any cached seed: once live
      // provenance exists a seed must never remain selectable (R06).
      _recentPositions.removeWhere((entry) => !entry.isLive);
    }
    final cutoff = now.subtract(bufferRetention);
    _recentPositions.removeWhere((entry) => entry.position.timestamp.isBefore(cutoff));

    // 1-second throttle before Riverpod state updates
    if (!isInitial && _lastEmitTime != null) {
      final elapsedMs = now.difference(_lastEmitTime!).inMilliseconds;
      if (elapsedMs < 1000) {
        return;
      }
    }
    _lastEmitTime = now;

    final fixStatus = GPSUtils.evaluateAccuracy(position.accuracy, hasFix: true);

    // Bearing 0.0 is the plugin's "unavailable" sentinel, not an established
    // north: geolocator_android's LocationMapper only puts `heading` into the
    // result when `Location.hasBearing()` is true, and Position.fromMap maps
    // the absent key to 0.0. A stationary device (no course over ground) is
    // therefore indistinguishable at this layer from a genuine due-north
    // course, so 0.0 stays unknown rather than being disclosed as 0° (R10).
    final double? headingDegrees =
        (position.heading > 0.0 && position.heading <= 360.0)
            ? position.heading
            : null;

    double? distance;
    if (_activeSiteLat != null && _activeSiteLon != null) {
      distance = SpatialMathUtils.haversineDistanceMeters(
        position.latitude,
        position.longitude,
        _activeSiteLat!,
        _activeSiteLon!,
      );
    }

    state = state.copyWith(
      fixStatus: fixStatus,
      hasValidFix: true,
      latitude: position.latitude,
      longitude: position.longitude,
      altitudeMeters: altitudeMeters,
      clearAltitude: altitudeMeters == null,
      isAltitudeMsl: isAltitudeMsl,
      accuracyMeters: position.accuracy,
      headingDegrees: headingDegrees,
      clearHeading: headingDegrees == null,
      timestampUtc: position.timestamp.toUtc(),
      distanceToSiteMeters: distance,
      clearError: true,
      isLastKnownSeed: isInitial,
    );

    _restartStalenessWatchdog();
    _resolveLocationName(position.latitude, position.longitude);
    refreshGnssStatus();
  }

  /// Returns the buffered position with the best (lowest) reported horizontal
  /// accuracy among recent LIVE positions within [window] (default: 5 seconds).
  /// If multiple positions share the best accuracy, the newest is preferred.
  ///
  /// Only genuinely live positions are eligible: a cached last-known seed is
  /// display-only and must never enter the live-fix selection path (R06).
  ///
  /// Returns null when no live position is available in the window — even if a
  /// valid fix is still latched. Callers must then keep the current GPS state
  /// as-is so unknown accuracy/altitude/fix-timestamp remain unknown
  /// (Cross-Cutting Audit A, F-A2: never synthesize concrete values).
  BufferedGpsPosition? getBestRecentPosition({Duration window = const Duration(seconds: 5)}) {
    final now = clock.now();
    final cutoff = now.subtract(window);
    final candidates = _recentPositions
        .where((entry) => entry.isLive && !entry.position.timestamp.isBefore(cutoff))
        .toList();

    if (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        final accComp = a.position.accuracy.compareTo(b.position.accuracy);
        if (accComp != 0) return accComp;
        return b.position.timestamp.compareTo(a.position.timestamp);
      });
      return candidates.first;
    }

    return null;
  }

  /// Applies the best recent live position to a capture GPS state.
  ///
  /// Production seam shared by the shutter paths. When [best] is null — no live
  /// position available in the capture window — the incoming state is returned
  /// unchanged so unknown accuracy/altitude/fix-timestamp stay unknown instead
  /// of being upgraded to 0.0/now (Cross-Cutting Audit A, F-A2).
  ///
  /// Altitude authority: an established MSL altitude on the state always wins;
  /// otherwise the selected position's *resolved* altitude/datum is adopted when
  /// the device established one, and the state's value is kept when it did not.
  /// The raw `Position.altitude` sentinel is never substituted (R10).
  static GpsHardwareState applyBestRecentPosition(
    GpsHardwareState gpsState,
    BufferedGpsPosition? best,
  ) {
    if (best == null || !gpsState.hasValidFix) {
      return gpsState;
    }

    final bool hasEstablishedMsl =
        gpsState.isAltitudeMsl && gpsState.altitudeMeters != null;

    final double? altitudeMeters;
    final bool isAltitudeMsl;
    if (hasEstablishedMsl) {
      altitudeMeters = gpsState.altitudeMeters;
      isAltitudeMsl = true;
    } else if (best.resolvedAltitudeMeters != null) {
      altitudeMeters = best.resolvedAltitudeMeters;
      isAltitudeMsl = best.resolvedIsMsl;
    } else {
      altitudeMeters = gpsState.altitudeMeters;
      isAltitudeMsl = gpsState.isAltitudeMsl;
    }

    return gpsState.copyWith(
      latitude: best.latitude,
      longitude: best.longitude,
      altitudeMeters: altitudeMeters,
      clearAltitude: altitudeMeters == null,
      isAltitudeMsl: isAltitudeMsl,
      accuracyMeters: best.accuracy,
      timestampUtc: best.timestamp.toUtc(),
    );
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
    _stalenessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _stalenessTimer?.cancel();
        _stalenessTimer = null;
        return;
      }
      final lastEmit = _lastEmitTime;
      if (lastEmit == null) {
        _stalenessTimer?.cancel();
        _stalenessTimer = null;
        setStaleOrSearching();
        return;
      }
      final elapsed = clock.now().difference(lastEmit);
      if (elapsed >= stalenessTimeout) {
        _stalenessTimer?.cancel();
        _stalenessTimer = null;
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
    if (!mounted) return;
    _lifecycleGeneration++;
    if (_isStreamPausedByLifecycle) return; // idempotent: never double-pause

    final subscription = _positionSubscription;
    _isStreamPausedByLifecycle = subscription != null;
    subscription?.pause();
    _stalenessTimer?.cancel();
    _stalenessTimer = null;
    _service.stopGnssUpdates();
  }

  /// Resumes the location stream after backgrounding, explicitly revalidating
  /// permission, location-service availability, subscription state, and
  /// live-fix provenance before any acquisition can occur.
  ///
  /// Truthful recovery: permission and service state are re-read from the OS
  /// (both can change while backgrounded). A non-granted, indeterminate, or
  /// service-disabled state cancels the stream and drops any latched fix so no
  /// stale/cached coordinate can be mistaken for a live fix. A previously valid
  /// fix is kept only while still fresh; otherwise it is cleared and the state
  /// transitions back through Acquiring until a new live position arrives.
  ///
  /// The stream itself is rebuilt rather than resumed: a subscription paused by
  /// a lifecycle pause can stay silent indefinitely after resume, so a fresh
  /// native stream is created through [_startStream]. Only a genuine emission
  /// from that stream can restore a live fix.
  Future<void> resumeLocationStream() async {
    if (!mounted) return;

    final int requestGeneration = ++_lifecycleGeneration;

    _service.startGnssUpdates();
    refreshGnssStatus();

    // 1. Revalidate permission + location service from the OS.
    final bool serviceEnabled = await _service.isLocationServiceEnabled();
    final LocationPermission permission = await _service.checkPermission();
    if (!mounted || requestGeneration != _lifecycleGeneration) return;

    state = state.copyWith(
      isLocationServiceEnabled: serviceEnabled,
      permissionStatus: permission,
    );

    final bool granted = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;

    if (!serviceEnabled || !granted) {
      // Cannot acquire: stop the stream and drop any latched fix so no stale or
      // cached coordinate can be promoted to a live fix.
      _releaseStream();
      _stalenessTimer?.cancel();
      _stalenessTimer = null;
      _recentPositions.clear();
      _lastEmitTime = null;
      if (!mounted) return;
      state = state.copyWith(
        fixStatus: GPSFixStatus.searching,
        hasValidFix: false,
        isLastKnownSeed: false,
        clearFix: true,
      );
      return;
    }

    // 2. Revalidate the latched fix: keep it only while still fresh, otherwise
    //    drop to Acquiring. A live fix is never inferred from cached data.
    if (state.hasValidFix) {
      final lastEmit = _lastEmitTime;
      final bool isStale;
      if (lastEmit != null) {
        isStale = clock.now().difference(lastEmit) >= stalenessTimeout;
      } else if (state.timestampUtc != null) {
        isStale = clock.now().toUtc().difference(state.timestampUtc!) >= stalenessTimeout;
      } else {
        isStale = true;
      }

      if (isStale) {
        setStaleOrSearching();
      } else {
        _restartStalenessWatchdog();
      }
    } else {
      state = state.copyWith(
        fixStatus: GPSFixStatus.searching,
        hasValidFix: false,
        isLastKnownSeed: false,
        clearFix: true,
      );
    }

    // 3. Re-establish the stream. A subscription paused by a lifecycle pause is
    //    replaced by a brand-new native stream (resuming it is not a reliable
    //    recovery path); an already-active subscription is left untouched so
    //    repeated resumes never open a duplicate stream.
    if (_isStreamPausedByLifecycle || _positionSubscription == null) {
      _releaseStream();
      _startStream();
    }
  }

  @override
  void dispose() {
    if (!mounted) return; // idempotent cleanup
    final subscription = _positionSubscription;
    _positionSubscription = null;
    subscription?.cancel();
    _stalenessTimer?.cancel();
    _stalenessTimer = null;
    _recentPositions.clear();
    _lastEmitTime = null;
    _service.stopGnssUpdates();
    super.dispose();
  }
}
