// ignore_for_file: subtype_of_sealed_class
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:sitelens/domain/models/enums.dart';
import 'package:sitelens/features/camera/models/evidence_metadata_snapshot.dart';
import 'package:sitelens/features/gallery/controllers/evidence_video_playback.dart';
import 'package:sitelens/features/gallery/widgets/local_video_player_widget.dart';
import 'package:sitelens/features/review/models/pending_capture_payload.dart';
import 'package:sitelens/features/review/widgets/review_media_preview.dart';

/// Fake platform-backed controller: no native calls.
class _FakeVideoController extends VideoPlayerController {
  _FakeVideoController() : super.file(File('/fake/evidence.mp4'));

  bool _disposed = false;

  @override
  Future<void> initialize() async {
    value = VideoPlayerValue(
      duration: const Duration(seconds: 3),
      size: const Size(1080, 1920),
      isInitialized: true,
    );
  }

  @override
  Future<void> setLooping(bool looping) async {
    if (_disposed) return;
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

EvidenceMetadataSnapshot _snapshot() => EvidenceMetadataSnapshot(
      mediaId: 'v1',
      siteId: 'S1',
      siteCode: 'SC',
      siteName: 'Site',
      latitude: 22.5,
      longitude: 88.3,
      lowAccuracy: false,
      capturedAtUtc: DateTime.utc(2026, 9, 18, 10),
      canonicalTimestampUtc: '2026-09-18 10:00:00 UTC',
      resolvedAddress: 'Address',
    );

PendingCapturePayload _videoPayload() => PendingCapturePayload(
      mediaId: 'v1',
      mediaType: MediaItemType.video,
      originalFilePath: 'media/orig_v1.mp4',
      evidenceFilePath: 'media/orig_v1.mp4',
      sha256Hash: 'a' * 64,
      fileSizeBytes: 5,
      videoDuration: const Duration(seconds: 3),
      metadataSnapshot: _snapshot(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'R13: a just-captured video previews through the shared single-owner player',
      (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('sitelens_review_video_');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final videoFile = File('${tempDir.path}/orig_v1.mp4')
      ..writeAsBytesSync(const [0, 1, 2, 3, 4]);

    final playback = EvidenceVideoPlayback(
      videoFile: videoFile,
      createController: (_) => _FakeVideoController(),
    );
    addTearDown(playback.dispose);
    await playback.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewMediaPreview(
            payload: _videoPayload(),
            videoPlayback: playback,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LocalVideoPlayerWidget), findsOneWidget);
    expect(playback.controller, isNotNull);
    expect(playback.controller!.value.isLooping, isFalse);
  });

  testWidgets(
      'R13: without a playback owner the preview stays a captured-thumbnail surface',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewMediaPreview(payload: _videoPayload()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LocalVideoPlayerWidget), findsNothing);
  });
}
