import 'dart:io';
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../gallery/controllers/evidence_video_playback.dart';
import '../../gallery/widgets/local_video_player_widget.dart';
import '../models/pending_capture_payload.dart';

class ReviewMediaPreview extends StatelessWidget {
  final PendingCapturePayload payload;
  final String? absoluteEvidencePath;

  /// The single-owner playback for a just-captured video, borrowed for the
  /// duration of Review & Tag. Review renders the SAME owner the gallery later
  /// uses, so there is never a second decoder for one recording (R13).
  final EvidenceVideoPlayback? videoPlayback;

  const ReviewMediaPreview({
    super.key,
    required this.payload,
    this.absoluteEvidencePath,
    this.videoPlayback,
  });

  Widget _buildFallback() {
    return Container(
      color: AppColors.surfaceContainerHigh,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              payload.isVideo ? Icons.videocam_rounded : Icons.photo_rounded,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 8),
            Text(
              payload.isVideo ? 'VIDEO EVIDENCE' : 'PHOTO EVIDENCE',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaContent() {
    if (!payload.isVideo) {
      if (absoluteEvidencePath != null) {
        final file = File(absoluteEvidencePath!);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _buildFallback(),
          );
        }
      }
      // previewBytes fallback only where required (e.g., isolated widget tests)
      if (payload.previewBytes != null) {
        return Image.memory(
          payload.previewBytes!,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildFallback(),
        );
      }
      if (absoluteEvidencePath != null) {
        return Image.file(
          File(absoluteEvidencePath!),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildFallback(),
        );
      }
      return _buildFallback();
    }

    // Video evidence — play the shared owner once it is ready; otherwise show
    // the captured first-frame thumbnail (never a fabricated frame).
    final playback = videoPlayback;
    if (playback != null) {
      return ListenableBuilder(
        listenable: playback,
        builder: (context, _) {
          if (playback.isReady) {
            return LocalVideoPlayerWidget(playback: playback);
          }
          return _buildVideoThumbnail();
        },
      );
    }
    return _buildVideoThumbnail();
  }

  Widget _buildVideoThumbnail() {
    if (payload.previewBytes != null) {
      return Image.memory(
        payload.previewBytes!,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    } else if (absoluteEvidencePath != null) {
      return Image.file(
        File(absoluteEvidencePath!),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    }
    return _buildFallback();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: 420,
          maxWidth: double.infinity,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.loose,
            alignment: Alignment.center,
            children: [
              // 1. Media Image / Frame with errorBuilder safeguard
              _buildMediaContent(),

              // 2. Gradient Overlay for readability (Only on video/fallback to avoid obscuring photo watermark)
              if (payload.isVideo)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withAlpha(80),
                          Colors.transparent,
                          Colors.black.withAlpha(120),
                        ],
                      ),
                    ),
                  ),
                ),

              // 3. Top Badges (Media Type & Video Duration)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(180),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(color: AppColors.border, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        payload.isVideo
                            ? Icons.videocam_rounded
                            : Icons.photo_camera_rounded,
                        color: payload.isVideo
                            ? AppColors.statusRed
                            : AppColors.primaryLight,
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        payload.isVideo ? 'VIDEO EVIDENCE' : 'PHOTO EVIDENCE',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (payload.isVideo && payload.videoDuration != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.statusRed.withAlpha(200),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      '${(payload.videoDuration!.inSeconds ~/ 60).toString().padLeft(2, '0')}:${(payload.videoDuration!.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

              // 4. Center Play Indicator for Video (only while the shared
              // playback owner is not yet rendering the real surface)
              if (payload.isVideo && !(videoPlayback?.isReady ?? false))
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(150),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withAlpha(180), width: 1.5),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),

              // 5. Bottom Metadata Overlay (Only for video where watermark is not burned into frames)
              if (payload.isVideo)
                Positioned(
                  bottom: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${payload.metadataSnapshot.siteCode} • ${payload.metadataSnapshot.canonicalTimestampUtc}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        payload.formattedFileSize,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: AppColors.textSecondary,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
