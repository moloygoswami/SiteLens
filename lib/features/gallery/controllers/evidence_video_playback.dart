import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

/// Creates the single platform-backed controller for one evidence video file.
typedef VideoControllerFactory = VideoPlayerController Function(File file);

/// Truthful lifecycle state of a single evidence video playback owner.
enum EvidenceVideoStatus {
  /// The controller is being created / initialized.
  initializing,

  /// The controller is initialized and usable.
  ready,

  /// Initialization failed (missing file / decoder error). Not usable.
  failed,
}

/// Single-owner lifecycle for one evidence video file.
///
/// INVARIANT: one [EvidenceVideoPlayback] instance owns at most ONE
/// [VideoPlayerController] for its [videoFile]. That controller is created at
/// most once, initialized at most once, and disposed exactly once — even when
/// [dispose] races an in-flight [initialize], and even if [dispose] is called
/// more than once.
///
/// This instance is a [ChangeNotifier]. The inline video surface and the
/// fullscreen video surface observe the SAME instance and therefore render the
/// SAME player — never two ExoPlayer instances for one video.
class EvidenceVideoPlayback extends ChangeNotifier {
  EvidenceVideoPlayback({
    required this.videoFile,
    VideoControllerFactory? createController,
  }) : _createController = createController ?? VideoPlayerController.file;

  /// The evidence video file this owner is responsible for.
  final File videoFile;

  final VideoControllerFactory _createController;

  VideoPlayerController? _controller;
  EvidenceVideoStatus _status = EvidenceVideoStatus.initializing;
  bool _disposed = false;
  bool _disposeStarted = false;
  bool _initializeStarted = false;

  /// Current truthful lifecycle state.
  EvidenceVideoStatus get status => _status;

  /// The single owned controller, or null when not (yet) usable.
  VideoPlayerController? get controller => _controller;

  bool get isDisposed => _disposed;

  bool get isReady =>
      !_disposed && _status == EvidenceVideoStatus.ready && _controller != null;

  /// Creates and initializes the single controller exactly once.
  ///
  /// Safe to call after [dispose] (no-op) and safe to race [dispose]: a
  /// controller whose initialization completes after disposal is released
  /// without ever being observed or notified.
  Future<void> initialize() async {
    if (_disposed || _disposeStarted || _initializeStarted) return;
    _initializeStarted = true;
    try {
      if (!videoFile.existsSync()) {
        _setStatus(EvidenceVideoStatus.failed);
        return;
      }

      final VideoPlayerController created = _createController(videoFile);
      _controller = created;

      await created.initialize();
      if (_disposed || _disposeStarted) {
        await _disposeOwnedController();
        return;
      }

      // Saved evidence videos play once and stop on the final frame. Looping is
      // explicitly disabled so a replay can only ever be an explicit user
      // action (R13).
      await created.setLooping(false);
      if (_disposed || _disposeStarted) {
        await _disposeOwnedController();
        return;
      }

      _setStatus(EvidenceVideoStatus.ready);
    } catch (_) {
      // Truthful failure: release the owned controller and report failure.
      // Never touches state once disposed.
      await _disposeOwnedController();
      _setStatus(EvidenceVideoStatus.failed);
    }
  }

  /// Toggles play/pause on the owned controller.
  ///
  /// No-op when not ready or already disposed; never accesses the controller
  /// after disposal.
  Future<void> togglePlayPause() async {
    final VideoPlayerController? current = _controller;
    if (_disposed ||
        _disposeStarted ||
        current == null ||
        _status != EvidenceVideoStatus.ready) {
      return;
    }
    try {
      if (current.value.isPlaying) {
        await current.pause();
      } else {
        // A completed video is parked on its final frame. Replaying is an
        // explicit user action, so an explicit tap restarts it from the start
        // rather than resuming a finished playback (R13).
        if (current.value.isCompleted) {
          await current.seekTo(Duration.zero);
        }
        await current.play();
      }
    } catch (_) {
      // The playback command failed; keep the last truthful state.
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return; // idempotent
    _disposed = true;
    super.dispose();
    unawaited(_disposeOwnedController());
  }

  /// Releases the owned controller exactly once, regardless of how many
  /// callers (dispose, failed initialize, raced dispose) request it.
  Future<void> _disposeOwnedController() async {
    if (_disposeStarted) return;
    _disposeStarted = true;
    final VideoPlayerController? owned = _controller;
    _controller = null;
    if (owned == null) return;
    try {
      await owned.dispose();
    } catch (_) {
      // Teardown must never throw.
    }
  }

  void _setStatus(EvidenceVideoStatus next) {
    if (_disposed) return;
    _status = next;
    notifyListeners();
  }
}

/// Factory seam so tests can inject a fake controller without touching the
/// native video platform.
final evidenceVideoControllerFactoryProvider =
    Provider<VideoControllerFactory>((ref) => VideoPlayerController.file);

final evidenceVideoPlaybackFactoryProvider =
    Provider<EvidenceVideoPlayback Function(File)>((ref) {
  final factory = ref.watch(evidenceVideoControllerFactoryProvider);
  return (file) =>
      EvidenceVideoPlayback(videoFile: file, createController: factory);
});
