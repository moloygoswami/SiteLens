import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../app/theme.dart';
import '../../../core/controllers/map_type_settings_controller.dart';
import '../../../core/services/map_thumbnail_service.dart';
import '../../../domain/models/enums.dart';
import '../controllers/map_thumbnail_controller.dart';

/// Three-Tier Map Thumbnail Renderer for CameraScreen HUD.
///
/// Tier 1 (LIVE): GoogleMap in isolated platform view with distance-throttled updates.
/// Tier 2 (STATIC): Locally cached Google Static Maps image (or background fetch).
/// Tier 3 (OFFLINE): Zero-latency synthetic CustomPainter or Satellite offline indicator.
class GpsMapThumbnail extends ConsumerStatefulWidget {
  final bool isLocked;
  final double latitude;
  final double longitude;
  final double? headingDegrees;

  const GpsMapThumbnail({
    super.key,
    required this.isLocked,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.headingDegrees,
  });

  @override
  ConsumerState<GpsMapThumbnail> createState() => _GpsMapThumbnailState();
}

class _GpsMapThumbnailState extends ConsumerState<GpsMapThumbnail> {
  GoogleMapController? _googleMapController;
  Timer? _initTimeoutTimer;
  double _lastAnimatedLat = 0.0;
  double _lastAnimatedLon = 0.0;
  DateTime? _lastSnapshotTime;
  double _lastSnapshotLat = 0.0;
  double _lastSnapshotLon = 0.0;
  AppMapType? _lastSnapshotMapType;

  @override
  void initState() {
    super.initState();
    _syncGpsState();
  }

  @override
  void didUpdateWidget(covariant GpsMapThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude ||
        oldWidget.isLocked != widget.isLocked) {
      _syncGpsState();
    }
  }

  void _syncGpsState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentMapType = ref.read(mapTypeSettingsProvider);
      ref.read(mapThumbnailControllerProvider.notifier).handleGpsUpdate(
            newLat: widget.latitude,
            newLon: widget.longitude,
            isLocked: widget.isLocked,
            mapType: currentMapType,
          );

      // Throttled camera movement: only animate if spatial delta >= 20 meters
      if (_googleMapController != null &&
          widget.isLocked &&
          (widget.latitude != 0.0 || widget.longitude != 0.0)) {
        final distance = (_lastAnimatedLat == 0.0 && _lastAnimatedLon == 0.0)
            ? 999.0
            : MapThumbnailService.haversineDistanceMeters(
                _lastAnimatedLat,
                _lastAnimatedLon,
                widget.latitude,
                widget.longitude,
              );

        if (distance >= MapThumbnailPolicy.movementThresholdMeters) {
          _lastAnimatedLat = widget.latitude;
          _lastAnimatedLon = widget.longitude;
          _googleMapController?.moveCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(widget.latitude, widget.longitude),
                zoom: 18.0,
              ),
            ),
          );
        }
      }
    });
  }

  void _startInitTimeoutGuard() {
    _initTimeoutTimer?.cancel();
    _initTimeoutTimer = Timer(MapThumbnailPolicy.liveMapInitTimeout, () {
      if (!mounted) return;
      if (_googleMapController == null) {
        ref.read(mapThumbnailControllerProvider.notifier).onLiveMapFailed();
      }
    });
  }

  Future<void> _captureSnapshotIfEligible(double lat, double lon) async {
    if (!mounted || _googleMapController == null || !widget.isLocked) return;
    if (lat == 0.0 && lon == 0.0) return;

    final currentMapType = ref.read(mapTypeSettingsProvider);

    // A Normal ↔ Satellite switch must never be throttled: force a fresh
    // type-matched snapshot so the static/snapshot cache (and the evidence
    // fallback) reflects the newly selected map layer instead of stale imagery.
    final isMapTypeChanged =
        _lastSnapshotMapType != null && _lastSnapshotMapType != currentMapType;

    final now = DateTime.now();
    final distance = (_lastSnapshotLat == 0.0 && _lastSnapshotLon == 0.0)
        ? 999.0
        : MapThumbnailService.haversineDistanceMeters(
            _lastSnapshotLat,
            _lastSnapshotLon,
            lat,
            lon,
          );

    final elapsed = _lastSnapshotTime == null
        ? const Duration(hours: 1)
        : now.difference(_lastSnapshotTime!);

    if (!isMapTypeChanged &&
        distance < MapThumbnailPolicy.movementThresholdMeters &&
        elapsed < MapThumbnailPolicy.minSnapshotInterval) {
      return;
    }

    _lastSnapshotTime = now;
    _lastSnapshotLat = lat;
    _lastSnapshotLon = lon;

    try {
      final snapshot = await _googleMapController?.takeSnapshot();
      if (snapshot != null && snapshot.isNotEmpty && mounted) {
        ref.read(mapThumbnailControllerProvider.notifier).updateLiveSnapshot(
          snapshot,
          lat: lat,
          lon: lon,
          mapType: currentMapType,
        );
        // Record the map type only after the snapshot is successfully accepted,
        // so a failed capture leaves _lastSnapshotMapType unchanged and the next
        // attempt still recognizes the pending Normal ↔ Satellite switch.
        _lastSnapshotMapType = currentMapType;
      }
    } catch (_) {}
  }

  void _showMapTypeSelectorSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E221F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final currentType = ref.watch(mapTypeSettingsProvider);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.layers_rounded, color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Map Type',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: Icon(
                        Icons.map_outlined,
                        color: currentType == AppMapType.normal ? AppColors.primary : Colors.white70,
                      ),
                      title: const Text('Default (Vector)', style: TextStyle(color: Colors.white)),
                      trailing: currentType == AppMapType.normal
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                          : null,
                      onTap: () {
                        ref.read(mapTypeSettingsProvider.notifier).setMapType(AppMapType.normal);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.satellite_alt_rounded,
                        color: currentType == AppMapType.satellite ? AppColors.primary : Colors.white70,
                      ),
                      title: const Text('Satellite (Imagery)', style: TextStyle(color: Colors.white)),
                      trailing: currentType == AppMapType.satellite
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                          : null,
                      onTap: () {
                        ref.read(mapTypeSettingsProvider.notifier).setMapType(AppMapType.satellite);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _initTimeoutTimer?.cancel();
    _googleMapController?.dispose();
    _googleMapController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appMapType = ref.watch(mapTypeSettingsProvider);
    final mapState = ref.watch(mapThumbnailControllerProvider);
    final isSupportedPlatform = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    // Listen for map type changes to keep controller synchronized
    ref.listen<AppMapType>(mapTypeSettingsProvider, (_, nextMapType) {
      if (mounted) {
        ref.read(mapThumbnailControllerProvider.notifier).handleGpsUpdate(
              newLat: widget.latitude,
              newLon: widget.longitude,
              isLocked: widget.isLocked,
              mapType: nextMapType,
            );
        // After an in-place Normal ↔ Satellite change, refresh the static
        // snapshot cache only once the live map has had a chance to apply the
        // new layer. The throttle bypass plus _lastSnapshotMapType guard ensure
        // a stale pre-change frame is never accepted as the new map type.
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            _captureSnapshotIfEligible(widget.latitude, widget.longitude);
          }
        });
      }
    });

    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF131714),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.isLocked
                ? AppColors.primary.withAlpha(180)
                : Colors.white.withAlpha(50),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(120),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 1. Map View & HUD Overlay (Clipped)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6.5),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Tier Resolution & Underlying Map Content with Smooth Cross-Fade
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      switchInCurve: Curves.easeIn,
                      switchOutCurve: Curves.easeOut,
                      child: KeyedSubtree(
                        key: ValueKey('${mapState.tier}_${mapState.cachedImage != null}_${widget.isLocked}'),
                        child: _buildMapContent(mapState, appMapType, isSupportedPlatform),
                      ),
                    ),

                    // Radar Scan Sweep (Active when GPS fix is locked)
                    if (widget.isLocked)
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withAlpha(20),
                          border: Border.all(color: AppColors.primary.withAlpha(90), width: 1.2),
                        ),
                      ),

                    // Camera View / Heading Cone
                    if (widget.isLocked && widget.headingDegrees != null)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _HeadingConePainter(
                            headingDegrees: widget.headingDegrees,
                          ),
                        ),
                      ),

                    // Foreground Dropped Pin HUD Overlay with High-Contrast Shadow
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black87,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 20,
                            color: widget.isLocked ? const Color(0xFFEA4335) : AppColors.statusAmber,
                          ),
                        ),
                        Container(
                          width: 6,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(140),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),

                    // Google Branding Attribution
                    Positioned(
                      bottom: 2,
                      left: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(120),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'Google',
                          style: TextStyle(
                            fontFamily: 'sans-serif',
                            fontSize: 7.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Dedicated Map Layer Control Chip (Top-Right Overlay above Platform View)
            Positioned(
              top: 3,
              right: 3,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _showMapTypeSelectorSheet,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xEE141815),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: appMapType == AppMapType.satellite
                            ? AppColors.primary
                            : Colors.white.withAlpha(220),
                        width: 1.2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(
                      appMapType == AppMapType.satellite
                          ? Icons.satellite_alt_rounded
                          : Icons.layers_rounded,
                      size: 13,
                      color: appMapType == AppMapType.satellite
                          ? AppColors.primary
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapContent(
    MapThumbnailState state,
    AppMapType appMapType,
    bool isSupportedPlatform,
  ) {
    // 1. LIVE Tier (when supported, locked, and live tier is selected)
    if (isSupportedPlatform && state.tier == MapThumbnailTier.live && widget.isLocked) {
      return _buildLiveGoogleMap(state, appMapType);
    }

    // 2. STATIC Tier (cached static map image on disk)
    final cacheFile = state.cachedImage;
    if (cacheFile != null && cacheFile.existsSync()) {
      return _buildCachedStaticMap(cacheFile, appMapType);
    }

    // 3. OFFLINE Fallback
    return _buildSyntheticOfflineMap(appMapType);
  }

  Widget _buildLiveGoogleMap(MapThumbnailState state, AppMapType appMapType) {
    final targetLat = widget.latitude != 0.0 ? widget.latitude : 22.5629;
    final targetLon = widget.longitude != 0.0 ? widget.longitude : 88.3008;

    if (_googleMapController == null && (_initTimeoutTimer == null || !_initTimeoutTimer!.isActive)) {
      _startInitTimeoutGuard();
    }

    final targetGoogleMapType = appMapType == AppMapType.satellite
        ? MapType.satellite
        : MapType.normal;

    return SizedBox.expand(
      child: IgnorePointer(
        child: GoogleMap(
          key: const ValueKey('camera_live_gps_map_thumbnail'),
          initialCameraPosition: CameraPosition(
            target: LatLng(targetLat, targetLon),
            zoom: 18.0,
          ),
          mapType: targetGoogleMapType,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          liteModeEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          rotateGesturesEnabled: false,
          scrollGesturesEnabled: false,
          tiltGesturesEnabled: false,
          zoomGesturesEnabled: false,
          onMapCreated: (controller) {
            _initTimeoutTimer?.cancel();
            _googleMapController = controller;
            ref.read(mapThumbnailControllerProvider.notifier)
              ..registerLiveSnapshotProvider(
                () => controller.takeSnapshot(),
              )
              ..onLiveMapInitialized();
            Future.delayed(const Duration(milliseconds: 1000), () {
              _captureSnapshotIfEligible(widget.latitude, widget.longitude);
            });
          },
          onCameraIdle: () {
            _captureSnapshotIfEligible(widget.latitude, widget.longitude);
          },
        ),
      ),
    );
  }

  Widget _buildCachedStaticMap(File imageFile, AppMapType appMapType) {
    return SizedBox.expand(
      child: Image.file(
        imageFile,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _buildSyntheticOfflineMap(appMapType),
      ),
    );
  }

  Widget _buildSyntheticOfflineMap(AppMapType appMapType) {
    if (appMapType == AppMapType.satellite) {
      return SizedBox.expand(
        child: Container(
          color: const Color(0xFF141715),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: const Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.satellite_alt_rounded, size: 14, color: AppColors.statusAmber),
                  SizedBox(height: 1),
                  Text(
                    'SAT',
                    style: TextStyle(
                      color: AppColors.statusAmber,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    'OFFLINE',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 7,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: CustomPaint(
        painter: _MiniMapGridPainter(),
      ),
    );
  }
}

class _MiniMapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(15)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final roadPaint = Paint()
      ..color = Colors.white.withAlpha(40)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Grid lines
    canvas.drawLine(Offset(size.width * 0.33, 0), Offset(size.width * 0.33, size.height), gridPaint);
    canvas.drawLine(Offset(size.width * 0.66, 0), Offset(size.width * 0.66, size.height), gridPaint);
    canvas.drawLine(Offset(0, size.height * 0.5), Offset(size.width, size.height * 0.5), gridPaint);

    // Diagonal road path
    final roadPath = Path()
      ..moveTo(0, size.height * 0.75)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.6, size.width, size.height * 0.2);
    canvas.drawPath(roadPath, roadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HeadingConePainter extends CustomPainter {
  final double? headingDegrees;
  const _HeadingConePainter({
    this.headingDegrees,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x444285F4)
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;

    canvas.save();
    if (headingDegrees != null) {
      final rad = (headingDegrees! * 3.141592653589793 / 180.0);
      canvas.translate(cx, cy);
      canvas.rotate(rad);
      canvas.translate(-cx, -cy);
    }

    // Facing forward (North / 0 degrees by default)
    final path = Path()
      ..moveTo(cx, cy - 2)
      ..lineTo(cx - size.width * 0.35, cy - size.height * 0.45)
      ..arcToPoint(
        Offset(cx + size.width * 0.35, cy - size.height * 0.45),
        radius: Radius.circular(size.width * 0.5),
      )
      ..close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeadingConePainter oldDelegate) =>
      oldDelegate.headingDegrees != headingDegrees;
}
