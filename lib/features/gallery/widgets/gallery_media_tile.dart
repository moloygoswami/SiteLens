import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../../camera/services/evidence_storage_service.dart';

class GalleryMediaTile extends ConsumerStatefulWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelectMode;
  final bool isSelected;

  const GalleryMediaTile({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.isSelectMode = false,
    this.isSelected = false,
  });

  @override
  ConsumerState<GalleryMediaTile> createState() => _GalleryMediaTileState();
}

class _GalleryMediaTileState extends ConsumerState<GalleryMediaTile> {
  String? _resolvedPath;

  @override
  void initState() {
    super.initState();
    _resolveThumbnail();
  }

  @override
  void didUpdateWidget(covariant GalleryMediaTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.thumbUri != widget.item.thumbUri ||
        oldWidget.item.uri != widget.item.uri) {
      _resolveThumbnail();
    }
  }

  Future<void> _resolveThumbnail() async {
    final storage = ref.read(evidenceStorageServiceProvider);
    final targetUri = widget.item.thumbUri ?? widget.item.uri;
    final abs = await storage.resolveAbsolutePath(targetUri);
    if (mounted) {
      setState(() => _resolvedPath = abs);
    }
  }

  Widget _buildFallback() {
    return Container(
      color: AppColors.surfaceContainerHigh,
      child: Center(
        child: Icon(
          widget.item.type == MediaItemType.video
              ? Icons.videocam_rounded
              : Icons.photo_rounded,
          size: 32,
          color: AppColors.textMuted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.item.type == MediaItemType.video;
    final isLowGps = widget.item.lowAccuracy ||
        (widget.item.accuracyM != null && widget.item.accuracyM! > 20.0);
    final obsType = widget.item.observationType;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.primary
                  : (isLowGps
                      ? AppColors.statusAmber.withAlpha(150)
                      : AppColors.border),
              width: widget.isSelected ? 2.5 : (isLowGps ? 1.5 : 1),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Thumbnail Image with errorBuilder safeguard
              if (_resolvedPath != null && File(_resolvedPath!).existsSync())
                Image.file(
                  File(_resolvedPath!),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildFallback(),
                )
              else
                _buildFallback(),

              // 3. Selection Scrim Overlay when selected
              if (widget.isSelected)
                Positioned.fill(
                  child: Container(
                    color: AppColors.primary.withAlpha(50),
                  ),
                ),

              // 4. Top Left: Observation Type Chip
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(200),
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _getObservationColor(obsType),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        obsType.label,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 5. Top Right: Selection Checkbox (Select Mode) OR Low GPS Warning Badge
              if (widget.isSelectMode)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? AppColors.primary
                          : Colors.black.withAlpha(180),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isSelected
                            ? AppColors.primary
                            : Colors.white.withAlpha(200),
                        width: 1.5,
                      ),
                    ),
                    child: widget.isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
                )
              else if (isLowGps)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.statusAmber.withAlpha(220),
                      borderRadius: BorderRadius.circular(AppRadii.xs),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      size: 11,
                      color: Colors.black,
                    ),
                  ),
                ),

              // 6. Bottom Left: Video Indicator & Duration
              if (isVideo)
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.statusRed.withAlpha(220),
                      borderRadius: BorderRadius.circular(AppRadii.xs),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_rounded,
                            size: 10, color: Colors.white),
                        SizedBox(width: 3),
                        Text(
                          'VIDEO',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 7. Bottom Right: Sync Status Dot (when not in select mode)
              if (!widget.isSelectMode)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: _buildSyncBadge(widget.item.syncStatus),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getObservationColor(ObservationType type) {
    switch (type) {
      case ObservationType.nonConformity:
        return AppColors.statusRed;
      case ObservationType.closed:
        return AppColors.statusGreen;
      case ObservationType.progress:
        return AppColors.primary;
      case ObservationType.material:
        return const Color(0xFF0288D1);
      case ObservationType.general:
        return AppColors.textSecondary;
    }
  }

  Widget _buildSyncBadge(SyncStatusType status) {
    IconData icon;
    Color color;
    switch (status) {
      case SyncStatusType.synced:
        icon = Icons.cloud_done_rounded;
        color = AppColors.statusGreenLight;
        break;
      case SyncStatusType.syncing:
        icon = Icons.cloud_upload_rounded;
        color = AppColors.primaryLight;
        break;
      case SyncStatusType.failed:
        icon = Icons.cloud_off_rounded;
        color = AppColors.statusRed;
        break;
      case SyncStatusType.pending:
        icon = Icons.cloud_queue_rounded;
        color = AppColors.textMuted;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(160),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 12, color: color),
    );
  }
}
