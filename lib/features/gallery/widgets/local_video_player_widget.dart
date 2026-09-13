import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme.dart';
import '../controllers/evidence_video_playback.dart';

/// Renders the video surface for a single shared [EvidenceVideoPlayback].
///
/// This widget does NOT own the player. It never creates and never disposes a
/// [VideoPlayerController]; ownership stays with the [EvidenceVideoPlayback]
/// instance, which is shared by the inline detail surface and the fullscreen
/// surface so exactly one ExoPlayer exists per video.
class LocalVideoPlayerWidget extends StatelessWidget {
  /// The shared playback owner (borrowed for the widget's lifetime).
  final EvidenceVideoPlayback playback;

  /// When false, the platform video surface is not attached (used while the
  /// fullscreen route owns the visible surface). The borrowed controller keeps
  /// its state; only the inline texture is parked.
  final bool isActive;

  const LocalVideoPlayerWidget({
    super.key,
    required this.playback,
    this.isActive = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        if (playback.status == EvidenceVideoStatus.failed) {
          return _buildFallback();
        }

        final VideoPlayerController? controller = playback.controller;
        if (controller == null || !controller.value.isInitialized) {
          return _buildLoading();
        }

        if (!isActive) {
          return Container(color: Colors.black);
        }

        return _buildPlayer(controller);
      },
    );
  }

  Widget _buildPlayer(VideoPlayerController controller) {
    final isPlaying = controller.value.isPlaying;
    final aspectRatio =
        controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9;

    return GestureDetector(
      onTap: () => playback.togglePlayPause(),
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),

            // Play / Pause Overlay Icon when paused
            if (!isPlaying)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(160),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.white.withAlpha(180), width: 1.5),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 36,
                  color: Colors.white,
                ),
              ),

            // Bottom Video Scrubber / Progress Indicator
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: AppColors.primary,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.black54,
                ),
                padding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      color: AppColors.surfaceContainerHigh,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded, size: 48, color: AppColors.textMuted),
            SizedBox(height: 8),
            Text(
              'VIDEO UNAVAILABLE',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
