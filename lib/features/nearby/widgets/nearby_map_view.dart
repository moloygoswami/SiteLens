import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../../../core/controllers/map_type_settings_controller.dart';
import '../../../data/repositories/media_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../../camera/services/evidence_storage_service.dart';
import '../../gallery/media_detail_screen.dart';


class NearbyMapView extends ConsumerStatefulWidget {
  final double centerLat;
  final double centerLon;
  final double radiusMeters;
  final MediaItem? sourceMedia;
  final List<NearbyMediaResult> results;
  final ValueChanged<MediaItem>? onMediaSelected;

  const NearbyMapView({
    super.key,
    required this.centerLat,
    required this.centerLon,
    required this.radiusMeters,
    this.sourceMedia,
    required this.results,
    this.onMediaSelected,
  });

  @override
  ConsumerState<NearbyMapView> createState() => _NearbyMapViewState();
}

class _NearbyMapViewState extends ConsumerState<NearbyMapView> {
  GoogleMapController? _mapController;
  NearbyMediaResult? _selectedResult;
  String? _selectedThumbPath;

  @override
  void didUpdateWidget(covariant NearbyMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.centerLat != widget.centerLat ||
        oldWidget.centerLon != widget.centerLon ||
        oldWidget.radiusMeters != widget.radiusMeters) {
      _recenterMap();
    }
  }

  double _calculateZoom(double radius) {
    if (radius <= 5.0) return 21.0;
    if (radius <= 10.0) return 20.0;
    if (radius <= 25.0) return 19.0;
    if (radius <= 50.0) return 18.0;
    if (radius <= 100.0) return 17.0;
    return 16.0;
  }

  void _recenterMap() {
    if (_mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(widget.centerLat, widget.centerLon),
          zoom: _calculateZoom(widget.radiusMeters),
        ),
      ),
    );
  }

  Future<void> _selectResult(NearbyMediaResult result) async {
    setState(() {
      _selectedResult = result;
      _selectedThumbPath = null;
    });

    final storage = ref.read(evidenceStorageServiceProvider);
    final targetUri = result.item.thumbUri ?? result.item.uri;
    final abs = await storage.resolveAbsolutePath(targetUri);
    if (mounted && _selectedResult?.item.id == result.item.id) {
      setState(() {
        _selectedThumbPath = abs;
      });
    }
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // 1. Source Anchor Pin
    markers.add(
      Marker(
        markerId: const MarkerId('source_anchor_marker'),
        position: LatLng(widget.centerLat, widget.centerLon),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: 'SOURCE ANCHOR',
          snippet: 'Lat: ${widget.centerLat.toStringAsFixed(5)}, Lon: ${widget.centerLon.toStringAsFixed(5)}',
        ),
        zIndexInt: 10,
      ),
    );

    // 2. Candidate Media Pins
    for (final res in widget.results) {
      final item = res.item;
      final hue = _getMarkerHue(item.observationType);

      markers.add(
        Marker(
          markerId: MarkerId('candidate_${item.id}'),
          position: LatLng(item.lat, item.lon),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: '${item.activityTag ?? item.observationType.label} • ${res.distanceMeters.toStringAsFixed(1)}m',
            snippet: DateFormat('yyyy-MM-dd HH:mm').format(item.capturedAt.toLocal()),
          ),
          onTap: () => _selectResult(res),
          zIndexInt: 5,
        ),
      );
    }

    return markers;
  }

  Set<Circle> _buildCircles() {
    return {
      Circle(
        circleId: const CircleId('spatial_search_radius'),
        center: LatLng(widget.centerLat, widget.centerLon),
        radius: widget.radiusMeters,
        fillColor: AppColors.primary.withAlpha(35),
        strokeColor: AppColors.primary,
        strokeWidth: 2,
      ),
    };
  }

  double _getMarkerHue(ObservationType type) {
    switch (type) {
      case ObservationType.nonConformity:
        return BitmapDescriptor.hueRed;
      case ObservationType.closed:
        return BitmapDescriptor.hueGreen;
      case ObservationType.progress:
        return BitmapDescriptor.hueOrange;
      case ObservationType.material:
        return BitmapDescriptor.hueCyan;
      case ObservationType.general:
        return BitmapDescriptor.hueViolet;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Graceful fallback for test environments or desktop rendering
    if (kIsWeb || (!kIsWeb && !Platform.isAndroid && !Platform.isIOS)) {
      return _buildMapPlaceholder();
    }

    final zoom = _calculateZoom(widget.radiusMeters);
    final markers = _buildMarkers();
    final circles = _buildCircles();
    final appMapType = ref.watch(mapTypeSettingsProvider);
    final targetGoogleMapType = appMapType == AppMapType.satellite
        ? MapType.satellite
        : MapType.normal;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // 1. Google Maps View
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(widget.centerLat, widget.centerLon),
                zoom: zoom,
              ),
              mapType: targetGoogleMapType,
              markers: markers,
              circles: circles,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              onMapCreated: (ctrl) {
                _mapController = ctrl;
              },
              onTap: (_) {
                if (_selectedResult != null) {
                  setState(() => _selectedResult = null);
                }
              },
            ),

            // 2. Map Overlay Badges & Legend
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Radius Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceTranslucentDark,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.radar_rounded, color: AppColors.primary, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.radiusMeters.toStringAsFixed(0)}m Radius (${widget.results.length} pins)',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action Buttons: Layer Toggle & Recenter (Expanded >=48x48dp Touch Targets)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: FloatingActionButton.small(
                            heroTag: 'nearby_map_layer_toggle_btn',
                            tooltip: 'Toggle satellite imagery map layer',
                            backgroundColor: AppColors.surface,
                            foregroundColor: appMapType == AppMapType.satellite
                                ? AppColors.primary
                                : Colors.white70,
                            elevation: 2,
                            onPressed: () {
                              ref.read(mapTypeSettingsProvider.notifier).toggleMapType();
                            },
                            child: Icon(
                              appMapType == AppMapType.satellite
                                  ? Icons.satellite_alt_rounded
                                  : Icons.layers_rounded,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: FloatingActionButton.small(
                            heroTag: 'recenter_map_btn',
                            tooltip: 'Recenter map on evidence coordinates',
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.primary,
                            elevation: 2,
                            onPressed: _recenterMap,
                            child: const Icon(Icons.my_location_rounded, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),


            // 3. Selected Marker Floating Preview Card
            if (_selectedResult != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildFloatingMediaCard(_selectedResult!),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFloatingMediaCard(NearbyMediaResult result) {
    final item = result.item;
    final isVideo = item.type == MediaItemType.video;
    final formattedTime = DateFormat('yyyy-MM-dd HH:mm').format(item.capturedAt.toLocal());

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 56,
                height: 56,
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_selectedThumbPath != null && File(_selectedThumbPath!).existsSync())
                      Image.file(
                        File(_selectedThumbPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => _buildFallback(isVideo),
                      )
                    else
                      _buildFallback(isVideo),

                    if (isVideo)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(200),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Icon(Icons.videocam_rounded, size: 10, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        item.observationType.label.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '• ${result.distanceMeters.toStringAsFixed(1)}m away',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.activityTag ?? 'General Inspection',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    formattedTime,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            // Action / Dismiss buttons
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _selectedResult = null),
                ),
                const SizedBox(height: 6),
                ElevatedButton(
                  onPressed: () {
                    if (widget.onMediaSelected != null) {
                      widget.onMediaSelected!(item);
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MediaDetailScreen(mediaItem: item),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
                  ),
                  child: const Text('View', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallback(bool isVideo) {
    return Container(
      color: AppColors.surfaceContainerHigh,
      child: Center(
        child: Icon(
          isVideo ? Icons.videocam_rounded : Icons.photo_rounded,
          size: 20,
          color: AppColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildMapPlaceholder() {
    return Container(
      color: AppColors.surfaceContainer,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_rounded, size: 48, color: AppColors.primary),
            const SizedBox(height: 12),
            const Text(
              'Spatial Map Mode Active',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Origin: ${widget.centerLat.toStringAsFixed(5)}, ${widget.centerLon.toStringAsFixed(5)} • Radius: ${widget.radiusMeters.toStringAsFixed(0)}m',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.results.length} nearby candidate pin(s) plotted.',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
