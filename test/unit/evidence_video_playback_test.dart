import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/features/gallery/controllers/evidence_video_playback.dart';
import 'package:video_player/video_player.dart';

/// Controllable fake platform-backed controller.
///
/// Never touches the native video platform; [initialize] can be gated so tests
/// can dispose the owner while initialization is still in flight.
class _FakeVideoPlayerController extends VideoPlayerController {
  _FakeVideoPlayerController({
    this.failInitialize = false,
    Completer<void>? initializeGate,
  })  : _initializeGate = initializeGate,
        super.file(File('/fake/evidence.mp4'));

  final bool failInitialize;
  final Completer<void>? _initializeGate;

  int initializeCalls = 0;
  int disposeCalls = 0;
  bool loopRequested = false;
  Duration? lastSeekTo;
  bool _disposed = false;

  bool get wasDisposed => _disposed;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (_initializeGate != null) {
      await _initializeGate.future;
    }
    if (_disposed) return;
    if (failInitialize) {
      throw PlatformException(
        code: 'VideoError',
        message: 'decoder unavailable',
      );
    }
    value = VideoPlayerValue(
      duration: const Duration(seconds: 3),
      size: const Size(1080, 1920),
      isInitialized: true,
    );
  }

  @override
  Future<void> setLooping(bool looping) async {
    loopRequested = looping;
    if (_disposed) return;
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> seekTo(Duration position) async {
    lastSeekTo = position;
    if (_disposed) return;
    value = value.copyWith(position: position, isCompleted: false);
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sitelens_video_unit_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  File realVideoFile() {
    final file = File('${tempDir.path}/orig_v1.mp4');
    file.writeAsBytesSync(const [0, 1, 2, 3, 4]);
    return file;
  }

  group('EvidenceVideoPlayback single-owner lifecycle', () {
    test('creates and initializes exactly one controller and reports ready',
        () async {
      final created = <_FakeVideoPlayerController>[];
      final playback = EvidenceVideoPlayback(
        videoFile: realVideoFile(),
        createController: (_) {
          final controller = _FakeVideoPlayerController();
          created.add(controller);
          return controller;
        },
      );

      await playback.initialize();

      expect(created, hasLength(1));
      expect(playback.status, EvidenceVideoStatus.ready);
      expect(playback.controller, same(created.single));
      expect(playback.isReady, isTrue);
      expect(created.single.loopRequested, isFalse);

      playback.dispose();
    });

    test('initialize is idempotent and never creates a second controller',
        () async {
      final created = <_FakeVideoPlayerController>[];
      final playback = EvidenceVideoPlayback(
        videoFile: realVideoFile(),
        createController: (_) {
          final controller = _FakeVideoPlayerController();
          created.add(controller);
          return controller;
        },
      );

      await playback.initialize();
      await playback.initialize();
      await playback.initialize();

      expect(created, hasLength(1));
      playback.dispose();
    });

    test('missing file yields truthful failed state without a controller',
        () async {
      var createdCount = 0;
      final playback = EvidenceVideoPlayback(
        videoFile: File('${tempDir.path}/does_not_exist.mp4'),
        createController: (_) {
          createdCount++;
          return _FakeVideoPlayerController();
        },
      );

      await playback.initialize();

      expect(playback.status, EvidenceVideoStatus.failed);
      expect(playback.controller, isNull);
      expect(playback.isReady, isFalse);
      expect(createdCount, 0);

      playback.dispose();
    });

    test('initialization failure yields failed state and releases once',
        () async {
      final fake = _FakeVideoPlayerController(failInitialize: true);
      final playback = EvidenceVideoPlayback(
        videoFile: realVideoFile(),
        createController: (_) => fake,
      );

      await playback.initialize();

      expect(playback.status, EvidenceVideoStatus.failed);
      expect(playback.controller, isNull);
      expect(fake.disposeCalls, 1);

      playback.dispose();
      expect(fake.disposeCalls, 1);
    });

    test('dispose is idempotent and releases the controller exactly once',
        () async {
      final fake = _FakeVideoPlayerController();
      final playback = EvidenceVideoPlayback(
        videoFile: realVideoFile(),
        createController: (_) => fake,
      );

      await playback.initialize();

      playback.dispose();
      playback.dispose();
      playback.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(fake.disposeCalls, 1);
      expect(playback.controller, isNull);
      expect(playback.isDisposed, isTrue);
    });

    test(
        'dispose during async initialization never accesses state afterwards '
        'and releases exactly once', () async {
      final gate = Completer<void>();
      final fake = _FakeVideoPlayerController(initializeGate: gate);
      final playback = EvidenceVideoPlayback(
        videoFile: realVideoFile(),
        createController: (_) => fake,
      );

      var notifications = 0;
      playback.addListener(() => notifications++);

      final initFuture = playback.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(playback.status, EvidenceVideoStatus.initializing);
      expect(fake.initializeCalls, 1);

      playback.dispose();
      expect(notifications, 0);

      // Initialization completes only after disposal.
      gate.complete();
      await initFuture;
      await Future<void>.delayed(Duration.zero);

      expect(fake.disposeCalls, 1);
      expect(fake.wasDisposed, isTrue);
      expect(playback.controller, isNull);
      expect(notifications, 0);
      expect(playback.isDisposed, isTrue);
    });

    test('initialize after dispose is a no-op', () async {
      var createdCount = 0;
      final playback = EvidenceVideoPlayback(
        videoFile: realVideoFile(),
        createController: (_) {
          createdCount++;
          return _FakeVideoPlayerController();
        },
      );

      playback.dispose();
      await playback.initialize();

      expect(createdCount, 0);
      expect(playback.controller, isNull);
      expect(playback.isDisposed, isTrue);
    });

    test('togglePlayPause after dispose is a safe no-op', () async {
      final fake = _FakeVideoPlayerController();
      final playback = EvidenceVideoPlayback(
        videoFile: realVideoFile(),
        createController: (_) => fake,
      );

      await playback.initialize();
      playback.dispose();

      await playback.togglePlayPause();
      await playback.togglePlayPause();

      expect(fake.disposeCalls, 1);
    });

    test('togglePlayPause flips play state while ready and notifies',
        () async {
      final fake = _FakeVideoPlayerController();
      final playback = EvidenceVideoPlayback(
        videoFile: realVideoFile(),
        createController: (_) => fake,
      );

      await playback.initialize();

      var notifications = 0;
      playback.addListener(() => notifications++);

      await playback.togglePlayPause();
      expect(playback.controller!.value.isPlaying, isTrue);

      await playback.togglePlayPause();
      expect(playback.controller!.value.isPlaying, isFalse);

      expect(notifications, greaterThanOrEqualTo(2));

      playback.dispose();
    });

    test('R13: a completed video replays only on an explicit toggle (no loop)',
        () async {
      final fake = _FakeVideoPlayerController();
      final playback = EvidenceVideoPlayback(
        videoFile: realVideoFile(),
        createController: (_) => fake,
      );

      await playback.initialize();

      // Parked on the final frame: playback completed, not looping.
      fake.value = fake.value.copyWith(
        isPlaying: false,
        isCompleted: true,
        position: const Duration(seconds: 3),
        isLooping: false,
      );

      await playback.togglePlayPause();

      // The explicit replay seeks to the start and plays.
      expect(fake.lastSeekTo, Duration.zero);
      expect(playback.controller!.value.isPlaying, isTrue);
      expect(playback.controller!.value.isCompleted, isFalse);
      expect(fake.loopRequested, isFalse);

      playback.dispose();
    });

    test('repeated initialize/toggle cycles keep exactly one controller',
        () async {
      final created = <_FakeVideoPlayerController>[];
      final playback = EvidenceVideoPlayback(
        videoFile: realVideoFile(),
        createController: (_) {
          final controller = _FakeVideoPlayerController();
          created.add(controller);
          return controller;
        },
      );

      await playback.initialize();
      for (var i = 0; i < 5; i++) {
        await playback.togglePlayPause();
      }

      expect(created, hasLength(1));
      expect(playback.status, EvidenceVideoStatus.ready);

      playback.dispose();
      expect(created.single.disposeCalls, 1);
    });
  });
}
