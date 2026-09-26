import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Core seam for deterministic teardown at the end of an application session.
///
/// Implementations are registered in [sessionEndTeardownsProvider] at the
/// composition root. [SessionService] captures the ending user's UID and awaits
/// every registered teardown before the incoming identity can be adopted,
/// ensuring no prior user's auxiliary state survives across account boundaries.
abstract class SessionEndTeardown {
  Future<void> onSessionEnded(String endingUid);
}

/// Registered list of session-end teardowns. Empty by default; the composition
/// root appends feature-specific implementations (e.g. Google Photos) without
/// creating core -> feature dependencies.
final sessionEndTeardownsProvider = Provider<List<SessionEndTeardown>>((ref) => const []);
