import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../../../data/repositories/media_repository.dart';
import '../../../domain/models/enums.dart';
import '../../camera/services/evidence_storage_service.dart';
import '../../gallery/media_detail_screen.dart';

class NearbyMediaCard extends ConsumerStatefulWidget {
  final NearbyMediaResult result;
  final VoidCallback? onTap;
  final bool isPicker;
  final bool isEligible;
  final VoidCallback? onSelect;

  const NearbyMediaCard({
    super.key,
    required this.result,
    this.onTap,
    this.isPicker = false,
    this.isEligible = false,
    this.onSelect,
  });

  @override
  ConsumerState<NearbyMediaCard> createState() => _NearbyMediaCardState();
}

class _NearbyMediaCardState extends ConsumerState<NearbyMediaCard> {
  String? _resolvedThumbPath;

  @override
  void initState() {
    super.initState();
    _resolveThumbnail();
  }

  @override
  void didUpdateWidget(covariant NearbyMediaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.item.id != widget.result.item.id ||
        oldWidget.result.item.thumbUri != widget.result.item.thumbUri) {
      _resolveThumbnail();
    }
  }

  Future<void> _resolveThumbnail() async {
    final storage = ref.read(evidenceStorageServiceProvider);
    final targetUri = widget.result.item.thumbUri ?? widget.result.item.uri;
    final abs = await storage.resolveAbsolutePath(targetUri);
    if (mounted) {
      setState(() => _resolvedThumbPath = abs);
    }
  }

  void _navigateToDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaDetailScreen(mediaItem: widget.result.item),
      ),
    );
  }

  void _handleCardTap() {
    if (widget.isPicker) {
      if (widget.isEligible) {
        if (widget.onSelect != null) {
          widget.onSelect!();
        } else if (widget.onTap != null) {
          widget.onTap!();
        }
      } else {
        if (widget.onTap != null) {
          widget.onTap!();
        }
      }
      return;
    }

    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }

    _navigateToDetail();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.result.item;
    final distanceMeters = widget.result.distanceMeters;
    final isVideo = item.type == MediaItemType.video;
    final localTime = DateFormat('yyyy-MM-dd HH:mm').format(item.capturedAt.toLocal());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleCardTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isPicker && widget.isEligible
                  ? AppColors.primary.withAlpha(120)
                  : AppColors.border,
              width: 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Thumbnail Box (tapping opens detail inspection)
              GestureDetector(
                onTap: _navigateToDetail,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                  width: 72,
                  height: 72,
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_resolvedThumbPath != null && File(_resolvedThumbPath!).existsSync())
                        Image.file(
                          File(_resolvedThumbPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => _buildFallback(isVideo),
                        )
                      else
                        _buildFallback(isVideo),

                      if (isVideo)
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(200),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.videocam_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

              const SizedBox(width: 12),

              // 2. Metadata Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Observation Badge & Activity Tag
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: _getObservationColor(item.observationType),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                          child: Text(
                            item.observationType.label.toUpperCase(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        if (item.activityTag != null && item.activityTag!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.activityTag!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 6),

                    // Middle Row: Distance Pill + Accuracy
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.primary.withAlpha(80), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.near_me_rounded,
                                size: 11,
                                color: AppColors.primaryDark,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${distanceMeters.toStringAsFixed(1)}m away',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          localTime,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),

                    // Bottom Row: Optional Note Snippet
                    if (item.note != null && item.note!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.note!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 3. Arrow Indicator or Picker Selection Action
              if (widget.isPicker)
                Padding(
                  padding: const EdgeInsets.only(top: 18, left: 6),
                  child: widget.isEligible
                      ? ElevatedButton.icon(
                          onPressed: () {
                            if (widget.onSelect != null) {
                              widget.onSelect!();
                            } else if (widget.onTap != null) {
                              widget.onTap!();
                            }
                          },
                          icon: const Icon(Icons.check_circle_rounded, size: 14),
                          label: const Text(
                            'Select',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            item.observationType == ObservationType.nonConformity
                                ? 'RESOLVED'
                                : 'INELIGIBLE',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 24, left: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
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
          size: 24,
          color: AppColors.textMuted,
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
}
