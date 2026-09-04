import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../app/theme.dart';

class LocalVideoPlayerWidget extends StatefulWidget {
  final File videoFile;

  const LocalVideoPlayerWidget({
    super.key,
    required this.videoFile,
  });

  @override
  State<LocalVideoPlayerWidget> createState() => _LocalVideoPlayerWidgetState();
}

class _LocalVideoPlayerWidgetState extends State<LocalVideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (!widget.videoFile.existsSync()) {
      setState(() => _hasError = true);
      return;
    }

    try {
      _controller = VideoPlayerController.file(widget.videoFile);
      await _controller!.initialize();
      _controller!.setLooping(true);
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
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

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildFallback();
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
        ),
      );
    }

    final isPlaying = _controller!.value.isPlaying;

    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio > 0
                    ? _controller!.value.aspectRatio
                    : 16 / 9,
                child: VideoPlayer(_controller!),
              ),
            ),

            // Play / Pause Overlay Icon when paused
            if (!isPlaying)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(160),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withAlpha(180), width: 1.5),
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
                _controller!,
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
}
