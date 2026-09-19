import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import 'router.dart';
import '../core/services/session_service.dart';
import '../features/auth/session_router.dart';
import '../features/sync/services/sync_coordinator.dart';
import '../features/sync/models/sync_state.dart';
import '../features/sites/site_controller.dart';

class SiteLensApp extends ConsumerWidget {
  const SiteLensApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<UserSessionState>(sessionServiceProvider, (previous, next) {
      if (next.status == SessionStatus.unauthenticated &&
          previous != null &&
          previous.status != SessionStatus.unauthenticated) {
        rootNavigatorKey.currentState?.pushNamedAndRemoveUntil(
          AppRoutes.root,
          (route) => false,
        );
      }
    });

    return SyncLifecycleBootstrap(
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        navigatorObservers: [appRouteObserver],
        title: 'SiteLens',
        debugShowCheckedModeBanner: false,
        theme: SiteLensTheme.lightTheme,
        home: const SessionRouter(),
        onGenerateRoute: AppRoutes.onGenerateRoute,
      ),
    );
  }
}

/// Initializes the synchronization lifecycle (crash recovery, connectivity
/// subscription, resume-driven sync) exactly once per authenticated application
/// session, independently of Gallery. Unauthenticated startup never creates the
/// sync coordinator; sign-out leaves any existing instance dormant (its auth
/// guards prevent further synchronization).
class SyncLifecycleBootstrap extends ConsumerWidget {
  const SyncLifecycleBootstrap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionServiceProvider.select((s) => s.user));
    if (user != null) {
      ref.watch(syncCoordinatorProvider);
      ref.listen<SyncState>(syncCoordinatorProvider, (previous, next) {
        if ((previous == null || !previous.isOnline) && next.isOnline) {
          // Network restored: trigger remote site hydration in background.
          // Active site continuity invariant: hydration preserves current active site.
          ref.read(siteControllerProvider.notifier).hydrateSites();
        }
      });
    }
    return child;
  }
}
