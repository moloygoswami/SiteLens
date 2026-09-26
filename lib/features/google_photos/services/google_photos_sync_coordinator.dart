import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/crypto_utils.dart';
import '../../../data/repositories/media_repository.dart';
import '../../camera/services/evidence_storage_service.dart';
import '../controllers/google_photos_settings_controller.dart';
import '../models/google_photos_sync_entry.dart';
import '../models/google_photos_sync_status.dart';
import '../repositories/google_photos_repository.dart';
import 'google_photos_api_service.dart';

final googlePhotosSyncCoordinatorProvider = Provider<GooglePhotosSyncCoordinator>((ref) {
  final apiService = ref.watch(googlePhotosApiServiceProvider);
  final repo = ref.watch(googlePhotosRepositoryProvider);
  final mediaRepo = ref.watch(mediaRepositoryProvider);
  final storageService = ref.watch(evidenceStorageServiceProvider);
  final settingsNotifier = ref.watch(googlePhotosSettingsProvider.notifier);
  final authService = ref.watch(authServiceProvider);

  final coordinator = GooglePhotosSyncCoordinator(
    apiService: apiService,
    repository: repo,
    mediaRepo: mediaRepo,
    storageService: storageService,
    settingsNotifier: settingsNotifier,
    authService: authService,
  );

  ref.onDispose(() => coordinator.dispose());
  return coordinator;
});

class GooglePhotosSyncCoordinator {
  final GooglePhotosApiService _apiService;
  final GooglePhotosRepository _repository;
  final MediaRepository _mediaRepo;
  final EvidenceStorageService _storageService;
  final GooglePhotosSettingsNotifier _settingsNotifier;
  final AuthService _authService;
  final Connectivity _connectivity;

  final Set<String> _inFlightMediaIds = {};
  final Map<String, int> _retryCounts = {};
  final Map<String, DateTime> _nextRetryTimes = {};
  bool _isProcessing = false;
  bool _isOnline = true;
  static const int maxRetryAttempts = 5;

  StreamSubscription? _connectivitySub;
  StreamSubscription<AuthUser?>? _authSub;
  RemoveListener? _settingsSub;
  bool _prevConnected = false;
  String? _activeUserId;

  GooglePhotosSyncCoordinator({
    required GooglePhotosApiService apiService,
    required GooglePhotosRepository repository,
    required MediaRepository mediaRepo,
    required EvidenceStorageService storageService,
    required GooglePhotosSettingsNotifier settingsNotifier,
    required AuthService authService,
    Connectivity? connectivity,
  })  : _apiService = apiService,
        _repository = repository,
        _mediaRepo = mediaRepo,
        _storageService = storageService,
        _settingsNotifier = settingsNotifier,
        _authService = authService,
        _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  void _init() {
    try {
      _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        _isOnline = online;
        if (online) {
          triggerSync();
        }
      });
    } catch (_) {
      _isOnline = true;
    }

    _authSub = _authService.authStateChanges.listen((user) {
      if (user == null || user.uid != _activeUserId) {
        resetSessionState();
        _activeUserId = user?.uid;
      }
    });

    // When the account becomes connected, run a catch-up pass so any photos
    // captured before the connection was established still get uploaded.
    _prevConnected = _settingsNotifier.currentSettings.isConnected;
    _settingsSub = _settingsNotifier.addListener((settings) {
      if (!_settingsNotifier.mounted) return;
      if (settings.isConnected != _prevConnected && settings.isConnected) {
        triggerSync();
      }
      _prevConnected = settings.isConnected;
    }, fireImmediately: false);
  }

  /// Resets in-memory coordinator queue and retry state on sign-out / account switch.
  void resetSessionState() {
    _inFlightMediaIds.clear();
    _retryCounts.clear();
    _nextRetryTimes.clear();
    _isProcessing = false;
  }

  /// Queues captured media for Google Photos auto-upload if feature is enabled.
  Future<void> onMediaCaptured(String mediaId) async {
    // Wait for persisted settings to load so a freshly connected account is
    // not mistaken for a disconnected one (stale default is isConnected=false).
    await _settingsNotifier.ready;

    // 1. Enforce active, verified Firebase session matching settings controller (vuln-0002)
    final authUser = _authService.currentUser;
    if (authUser == null || !authUser.isEmailVerified) return;
    if (_settingsNotifier.currentUserId != authUser.uid || !_settingsNotifier.isEmailVerified) return;

    final settings = _settingsNotifier.currentSettings;
    if (!settings.isConnected || !settings.autoUpload) return;

    final media = await _mediaRepo.getMediaById(mediaId, creatorId: authUser.uid);
    if (media == null) return;

    // 2. Enforce media was created by the active user
    if (media.creatorId != authUser.uid) return;

    await _repository.queueMedia(mediaId, creatorId: authUser.uid);
    await triggerSync();
  }

  /// Triggers a background sync pass for all queued Google Photos items.
  Future<void> triggerSync() async {
    // 1. Enforce active, email-verified Firebase session (vuln-0002)
    final authUser = _authService.currentUser;
    if (authUser == null || !authUser.isEmailVerified) return;

    final currentUid = authUser.uid;
    if (_settingsNotifier.currentUserId != currentUid || !_settingsNotifier.isEmailVerified) return;

    final settings = _settingsNotifier.currentSettings;
    if (!settings.isConnected || !settings.autoUpload || settings.accountEmail == null || settings.accountEmail!.isEmpty) return;

    if (!_isOnline) return;

    if (_isProcessing) return;
    _isProcessing = true;
    _activeUserId = currentUid;

    try {
      // 2. Enqueue only local media created by current authenticated user
      final allMedia = await _mediaRepo.getAllMediaEntriesIncludingDeleted(creatorId: currentUid);
      for (final m in allMedia) {
        if (m.isDeleted) continue;
        if (m.creatorId != currentUid) continue; // STRICT CREATOR FILTER

        final existing = await _repository.getEntryForMedia(m.id, creatorId: currentUid);
        if (existing == null) {
          await _repository.queueMedia(m.id, creatorId: currentUid);
        }
      }

      final entries = await _repository.getPendingOrFailedEntries(creatorId: currentUid);
      if (entries.isEmpty) return;

      for (final entry in entries) {
        // Double-check session before processing each item
        final activeNow = _authService.currentUser;
        if (activeNow == null || activeNow.uid != currentUid || !activeNow.isEmailVerified) {
          break; // Session terminated or switched mid-flight -> abort immediately
        }

        if (_inFlightMediaIds.contains(entry.mediaId)) continue;

        // Exponential backoff check
        if (_nextRetryTimes.containsKey(entry.mediaId)) {
          if (DateTime.now().isBefore(_nextRetryTimes[entry.mediaId]!)) {
            continue;
          }
        }

        await _processSingleEntry(entry, currentUid);
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processSingleEntry(GooglePhotosSyncEntry entry, String expectedUserId) async {
    _inFlightMediaIds.add(entry.mediaId);

    try {
      // Defense-in-depth: Re-verify session, controller UID, and connection validity
      final activeUser = _authService.currentUser;
      if (activeUser == null || activeUser.uid != expectedUserId || !activeUser.isEmailVerified) {
        return;
      }
      if (_settingsNotifier.currentUserId != expectedUserId || !_settingsNotifier.isEmailVerified) {
        return;
      }

      final currentSettings = _settingsNotifier.currentSettings;
      if (!currentSettings.isConnected || !currentSettings.autoUpload || currentSettings.accountEmail == null) {
        // Safe fail-closed boundary: Account is disconnected or altered during queue execution
        return;
      }

      final mediaItem = await _mediaRepo.getMediaById(entry.mediaId, creatorId: expectedUserId);
      if (mediaItem == null) {
        // Media item was deleted locally or does not belong to user
        await _repository.deleteEntry(entry.mediaId, creatorId: expectedUserId);
        return;
      }

      // Assert media item was created by the active authenticated user
      if (mediaItem.creatorId != expectedUserId) {
        // Do not upload foreign user's media under this connection
        return;
      }

      await _repository.updateStatus(
        mediaId: entry.mediaId,
        creatorId: expectedUserId,
        status: GooglePhotosSyncStatus.uploading,
      );

      final mediaDir = await _storageService.getMediaDirectory();
      final rootPath = mediaDir.parent.path;
      final absEvidencePath = '$rootPath/${mediaItem.uri}';

      final evidFile = File(absEvidencePath);
      if (!await evidFile.exists()) {
        await _repository.updateStatus(
          mediaId: entry.mediaId,
          creatorId: expectedUserId,
          status: GooglePhotosSyncStatus.failed,
          errorMessage: 'Evidence file not found on disk.',
        );
        return;
      }

      final bytes = await evidFile.readAsBytes();
      final computedSha = CryptoUtils.computeSha256(bytes);
      if (mediaItem.evidenceSha256Hash != null && computedSha != mediaItem.evidenceSha256Hash) {
        await _repository.updateStatus(
          mediaId: entry.mediaId,
          creatorId: expectedUserId,
          status: GooglePhotosSyncStatus.failed,
          errorMessage: 'Evidence SHA-256 hash mismatch.',
        );
        return;
      }

      // Step 1: Upload Raw Bytes -> uploadToken
      final uploadToken = await _apiService.uploadBytes(
        bytes: bytes,
        mimeType: mediaItem.type.name == 'video' ? 'video/mp4' : 'image/jpeg',
      );

      // Step 2: Get or create album (scoped to the expected user so the cache
      // does not leak across account boundaries)
      final settings = _settingsNotifier.currentSettings;
      final albumId = await _apiService.getOrCreateAlbum(
        settings.albumName,
        ownerUid: expectedUserId,
      );

      // Step 3: Create Media Item in Album (using only user-authored note if provided)
      final fileName = mediaItem.uri.split('/').last;
      final description = (mediaItem.note != null && mediaItem.note!.trim().isNotEmpty)
          ? mediaItem.note!.trim()
          : '';

      String googlePhotosId;
      try {
        googlePhotosId = await _apiService.createMediaItem(
          uploadToken: uploadToken,
          fileName: fileName,
          description: description,
          albumId: albumId,
        );
      } catch (e) {
        if (albumId != null && e.toString().toLowerCase().contains('album')) {
          // Invalid/deleted cached album ID:
          // 1. Invalidate cached album ID for this user
          await _apiService.invalidateAlbumId(ownerUid: expectedUserId);
          // 2. Create a new "SiteLens Evidence" album (persisted automatically)
          final newAlbumId = await _apiService.getOrCreateAlbum(
            settings.albumName,
            ownerUid: expectedUserId,
          );
          // 3. Retry the SAME pending media item using the new album ID (never outside the album)
          googlePhotosId = await _apiService.createMediaItem(
            uploadToken: uploadToken,
            fileName: fileName,
            description: description,
            albumId: newAlbumId,
          );
        } else {
          rethrow;
        }
      }

      // Success
      await _repository.updateStatus(
        mediaId: entry.mediaId,
        creatorId: expectedUserId,
        status: GooglePhotosSyncStatus.uploaded,
        googlePhotosMediaId: googlePhotosId,
        uploadedAt: DateTime.now(),
      );

      _retryCounts.remove(entry.mediaId);
      _nextRetryTimes.remove(entry.mediaId);
      _settingsNotifier.updateOverallStatus(GooglePhotosSyncStatus.uploaded);
    } on GooglePhotosAuthException catch (e) {
      await _repository.updateStatus(
        mediaId: entry.mediaId,
        creatorId: expectedUserId,
        status: GooglePhotosSyncStatus.authRequired,
        errorMessage: e.message,
      );
      _settingsNotifier.updateOverallStatus(GooglePhotosSyncStatus.authRequired, error: e.message);
    } on GooglePhotosApiException catch (e) {
      if (e.isRetryable) {
        final currentRetries = (_retryCounts[entry.mediaId] ?? 0) + 1;
        _retryCounts[entry.mediaId] = currentRetries;

        if (currentRetries >= maxRetryAttempts) {
          await _repository.updateStatus(
            mediaId: entry.mediaId,
            creatorId: expectedUserId,
            status: GooglePhotosSyncStatus.failed,
            errorMessage: 'Max retry attempts ($maxRetryAttempts) exceeded: ${e.message}',
            incrementRetry: true,
          );
          _settingsNotifier.updateOverallStatus(GooglePhotosSyncStatus.failed, error: e.message);
        } else {
          final delaySeconds = (pow(2, currentRetries) as int) + Random().nextInt(2);
          _nextRetryTimes[entry.mediaId] = DateTime.now().add(Duration(seconds: delaySeconds));
          await _repository.updateStatus(
            mediaId: entry.mediaId,
            creatorId: expectedUserId,
            status: GooglePhotosSyncStatus.pending,
            errorMessage: e.message,
            incrementRetry: true,
          );
        }
      } else {
        await _repository.updateStatus(
          mediaId: entry.mediaId,
          creatorId: expectedUserId,
          status: GooglePhotosSyncStatus.failed,
          errorMessage: e.message,
        );
        _settingsNotifier.updateOverallStatus(GooglePhotosSyncStatus.failed, error: e.message);
      }
    } catch (e) {
      await _repository.updateStatus(
        mediaId: entry.mediaId,
        creatorId: expectedUserId,
        status: GooglePhotosSyncStatus.failed,
        errorMessage: e.toString(),
      );
      _settingsNotifier.updateOverallStatus(GooglePhotosSyncStatus.failed, error: e.toString());
    } finally {
      _inFlightMediaIds.remove(entry.mediaId);
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    _settingsSub?.call();
    _authSub?.cancel();
    resetSessionState();
  }
}
