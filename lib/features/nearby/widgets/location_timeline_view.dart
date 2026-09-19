import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../../../core/utils/gps_utils.dart';
import '../../../data/repositories/media_repository.dart';
import '../../../domain/models/enums.dart';
import '../../camera/services/evidence_storage_service.dart';
import '../../gallery/media_detail_screen.dart';

class LocationTimelineView extends ConsumerStatefulWidget {
  final List<NearbyMediaResult> items;

  const LocationTimelineView({
    super.key,
    required this.items,
  });

  @override
  ConsumerState<LocationTimelineView> createState() => _LocationTimelineViewState();
}

class _LocationTimelineViewState extends ConsumerState<LocationTimelineView> {
  final Map<String, String> _resolvedThumbnails = {};

  @override
  void initState() {
    super.initState();
    _resolveThumbnails();
  }

  @override
  void didUpdateWidget(covariant LocationTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _resolveThumbnails();
    }
  }

  Future<void> _resolveThumbnails() async {
    final storage = ref.read(evidenceStorageServiceProvider);
    for (final result in widget.items) {
      final targetUri = result.item.thumbUri ?? result.item.uri;
      if (!_resolvedThumbnails.containsKey(result.item.id)) {
        final abs = await storage.resolveAbsolutePath(targetUri);
        if (mounted) {
          setState(() {
            _resolvedThumbnails[result.item.id] = abs;
          });
        }
      }
    }
  }

  String _formatTimeDelta(DateTime previous, DateTime current) {
    final diff = current.difference(previous);
    if (diff.isNegative) return 'earlier';
    if (diff.inDays > 0) {
      final days = diff.inDays;
      final hours = diff.inHours % 24;
      return hours > 0 ? '+$days d ${hours}h later' : '+$days d later';
    } else if (diff.inHours > 0) {
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      return mins > 0 ? '+$hours h ${mins}m later' : '+$hours h later';
    } else if (diff.inMinutes > 0) {
      return '+${diff.inMinutes}m later';
    } else {
      return '+${diff.inSeconds}s later';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timeline_rounded, size: 48, color: AppColors.textMuted),
              SizedBox(height: 12),
              Text(
                'No Timeline Evidence',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Expand search radius to uncover chronological inspection history.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final currentResult = widget.items[index];
        final isFirst = index == 0;
        final isLast = index == widget.items.length - 1;
        final timeDelta = !isFirst
            ? _formatTimeDelta(widget.items[index - 1].item.capturedAt, currentResult.item.capturedAt)
            : 'INITIAL CAPTURE';

        return _buildTimelineRow(
          result: currentResult,
          timeDelta: timeDelta,
          isFirst: isFirst,
          isLast: isLast,
        );
      },
    );
  }

  Widget _buildTimelineRow({
    required NearbyMediaResult result,
    required String timeDelta,
    required bool isFirst,
    required bool isLast,
  }) {
    final item = result.item;
    final thumbPath = _resolvedThumbnails[item.id];
    final isVideo = item.type == MediaItemType.video;
    final formattedTime = DateFormat('yyyy-MM-dd HH:mm').format(item.capturedAt.toLocal());
    final nodeColor = _getObservationColor(item.observationType);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Vertical Connected Timeline Line
          SizedBox(
            width: 16,
            child: Column(
              children: [
                // Top line
                Container(
                  width: 2,
                  height: 12,
                  color: isFirst ? Colors.transparent : AppColors.border,
                ),
                // Bottom connecting line
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : AppColors.border,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // 2. Timeline Step Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MediaDetailScreen(mediaItem: item),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Header: Time Delta
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                timeDelta,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Middle: Thumbnail & Primary Metadata
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Thumbnail
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 64,
                                height: 64,
                                color: Colors.black,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (thumbPath != null && File(thumbPath).existsSync())
                                      Image.file(
                                        File(thumbPath),
                                        fit: BoxFit.cover,
                                        errorBuilder: (ctx, err, stack) => _buildFallback(isVideo),
                                      )
                                    else
                                      _buildFallback(isVideo),

                                    if (isVideo)
                                      Positioned(
                                        bottom: 3,
                                        right: 3,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withAlpha(200),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                          child: const Icon(
                                            Icons.videocam_rounded,
                                            size: 10,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(width: 10),

                            // Tags & Telemetry
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Activity Pill
                                  if (item.activityTag != null && item.activityTag!.isNotEmpty)
                                    Text(
                                      item.activityTag!,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),

                                  const SizedBox(height: 4),

                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: nodeColor.withAlpha(25),
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(color: nodeColor.withAlpha(80), width: 0.8),
                                        ),
                                        child: Text(
                                          item.observationType.label.toUpperCase(),
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: nodeColor,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${GPSUtils.formatDistanceWithUncertainty(result.distanceMeters, accuracyMeters: result.item.accuracyM) ?? 'distance unknown'} away',
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 4),

                                  // Capture Timestamp
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
                          ],
                        ),

                        // Optional Note
                        if (item.note != null && item.note!.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            item.note!.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
