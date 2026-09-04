import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/auth_service.dart';
import '../models/google_photos_settings.dart';
import '../models/google_photos_sync_status.dart';
import '../repositories/google_photos_repository.dart';
import '../services/google_photos_auth_service.dart';

final googlePhotosSettingsProvider =
    StateNotifierProvider<GooglePhotosSettingsNotifier, GooglePhotosSettings>((ref) {
  final authService = ref.watch(googlePhotosAuthServiceProvider);
  final repo = ref.watch(googlePhotosRepositoryProvider);
  final authUser = ref.watch(authStateProvider).value;

  final notifier = GooglePhotosSettingsNotifier(
    authService: authService,
    repository: repo,
    currentUserId: authUser?.uid,
    isEmailVerified: authUser?.isEmailVerified ?? false,
  );

  ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (prev, next) {
    final nextUser = next.value;
    notifier.switchUser(
      nextUser?.uid,
      isEmailVerified: nextUser?.isEmailVerified ?? false,
    );
  });

  return notifier;
});

class GooglePhotosSettingsNotifier extends StateNotifier<GooglePhotosSettings> {
  final GooglePhotosAuthService _authService;
  final GooglePhotosRepository _repository;
  String? _currentUserId;
  bool _isEmailVerified;

  static const String keyAutoUpload = 'setting_google_photos_auto_upload';
  static const String keyConnected = 'setting_google_photos_connected';
  static const String keyEmail = 'setting_google_photos_email';
  static const String keyOwnerUid = 'setting_google_photos_owner_uid';

  StreamSubscription? _authSub;
  StreamSubscription? _repoSub;
  Completer<void> _readyCompleter = Completer<void>();

  GooglePhotosSettingsNotifier({
    required GooglePhotosAuthService authService,
    required GooglePhotosRepository repository,
    String? currentUserId,
    bool isEmailVerified = false,
  })  : _authService = authService,
        _repository = repository,
        _currentUserId = currentUserId,
        _isEmailVerified = isEmailVerified,
        super(const GooglePhotosSettings()) {
    _loadInitialState();
  }

  String _getKey(String base) => _currentUserId != null ? '${base}_$_currentUserId' : base;

  String? get currentUserId => _currentUserId;
  bool get isEmailVerified => _isEmailVerified;

  /// Resolves once initial state (connection status, auto-upload pref) has loaded.
  Future<void> get ready => _readyCompleter.future;

  GooglePhotosSettings get currentSettings => state;

  Future<void> switchUser(String? newUserId, {bool isEmailVerified = false}) async {
    _currentUserId = newUserId;
    _isEmailVerified = isEmailVerified;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
    _readyCompleter = Completer<void>();
    await _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    try {
      // Safe fail-closed: Unauthenticated or unverified sessions cannot have an active Google Photos connection (vuln-0002)
      if (_currentUserId == null || !_isEmailVerified) {
        _authSub?.cancel();
        _repoSub?.cancel();
        if (mounted) {
          state = const GooglePhotosSettings();
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      // Strictly verify stored connection owner matches current Firebase UID without global key fallback
      final storedOwner = prefs.getString(_getKey(keyOwnerUid));
      final isConnected = (storedOwner == _currentUserId) && (prefs.getBool(_getKey(keyConnected)) ?? false);
      final autoUpload = isConnected && (prefs.getBool(_getKey(keyAutoUpload)) ?? false);
      final accountEmail = isConnected ? prefs.getString(_getKey(keyEmail)) : null;

      state = state.copyWith(
        isConnected: isConnected,
        autoUpload: autoUpload,
        accountEmail: accountEmail,
        clearAccountEmail: !isConnected,
        overallStatus: isConnected ? (autoUpload ? GooglePhotosSyncStatus.pending : GooglePhotosSyncStatus.disabled) : GooglePhotosSyncStatus.disabled,
      );

      // Listen to OAuth state changes
      _authSub?.cancel();
      _authSub = _authService.onCurrentUserChanged.listen((account) async {
        if (!mounted) return;
        if (account != null && _currentUserId != null && _isEmailVerified) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_getKey(keyOwnerUid), _currentUserId!);
          await prefs.setBool(_getKey(keyConnected), true);
          await prefs.setString(_getKey(keyEmail), account.email);
          if (!mounted) return;
          state = state.copyWith(
            isConnected: true,
            accountEmail: account.email,
            overallStatus: state.autoUpload ? GooglePhotosSyncStatus.pending : GooglePhotosSyncStatus.disabled,
          );
        } else {
          state = state.copyWith(
            isConnected: false,
            clearAccountEmail: true,
            overallStatus: GooglePhotosSyncStatus.disabled,
          );
        }
      });

      // Listen to repository entry changes
      _repoSub?.cancel();
      _repoSub = _repository.watchAllEntries().listen((entries) {
        if (!mounted) return;
        int pending = 0;
        int uploaded = 0;
        int failed = 0;

        for (final e in entries) {
          if (e.status == GooglePhotosSyncStatus.uploaded) {
            uploaded++;
          } else if (e.status == GooglePhotosSyncStatus.failed) {
            failed++;
          } else if (e.status == GooglePhotosSyncStatus.pending || e.status == GooglePhotosSyncStatus.uploading) {
            pending++;
          }
        }

        state = state.copyWith(
          pendingCount: pending,
          uploadedCount: uploaded,
          failedCount: failed,
        );
      });

      await _refreshCounts();
    } finally {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
    }
  }

  Future<void> _refreshCounts() async {
    if (!mounted) return;
    final pending = await _repository.countByStatus(GooglePhotosSyncStatus.pending);
    final uploading = await _repository.countByStatus(GooglePhotosSyncStatus.uploading);
    final uploaded = await _repository.countByStatus(GooglePhotosSyncStatus.uploaded);
    final failed = await _repository.countByStatus(GooglePhotosSyncStatus.failed);

    if (!mounted) return;
    state = state.copyWith(
      pendingCount: pending + uploading,
      uploadedCount: uploaded,
      failedCount: failed,
    );
  }

  Future<void> connect() async {
    if (_currentUserId == null || !_isEmailVerified) {
      if (mounted) {
        state = state.copyWith(
          lastError: 'Authentication and email verification required to connect Google Photos.',
          overallStatus: GooglePhotosSyncStatus.failed,
        );
      }
      return;
    }

    try {
      final account = await _authService.connect();
      if (account != null && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_getKey(keyOwnerUid), _currentUserId!);
        await prefs.setBool(_getKey(keyConnected), true);
        await prefs.setString(_getKey(keyEmail), account.email);

        if (!mounted) return;
        state = state.copyWith(
          isConnected: true,
          accountEmail: account.email,
          overallStatus: state.autoUpload ? GooglePhotosSyncStatus.pending : GooglePhotosSyncStatus.disabled,
          clearLastError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        lastError: 'Google Photos connection failed: $e',
        overallStatus: GooglePhotosSyncStatus.failed,
      );
    }
  }

  Future<void> disconnect() async {
    try {
      await _authService.disconnect();
      if (_currentUserId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_getKey(keyOwnerUid));
        await prefs.setBool(_getKey(keyConnected), false);
        await prefs.remove(_getKey(keyEmail));
      }

      if (!mounted) return;
      state = state.copyWith(
        isConnected: false,
        clearAccountEmail: true,
        overallStatus: GooglePhotosSyncStatus.disabled,
        clearLastError: true,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(lastError: 'Google Photos disconnect failed: $e');
    }
  }

  Future<void> setAutoUpload(bool enabled) async {
    if (_currentUserId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_getKey(keyAutoUpload), enabled);
    }

    if (!mounted) return;
    state = state.copyWith(
      autoUpload: enabled,
      overallStatus: state.isConnected
          ? (enabled ? GooglePhotosSyncStatus.pending : GooglePhotosSyncStatus.disabled)
          : GooglePhotosSyncStatus.disabled,
    );
  }

  void updateOverallStatus(GooglePhotosSyncStatus status, {String? error}) {
    if (!mounted) return;
    state = state.copyWith(
      overallStatus: status,
      lastError: error,
      clearLastError: error == null,
      lastSyncTime: status == GooglePhotosSyncStatus.uploaded ? DateTime.now() : null,
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _repoSub?.cancel();
    super.dispose();
  }
}
