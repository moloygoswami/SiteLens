import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sitelens/features/sync/models/sync_state.dart';
import 'package:sitelens/features/sync/services/sync_coordinator.dart';

class FakeSyncCoordinator extends StateNotifier<SyncState>
    implements SyncCoordinator {
  FakeSyncCoordinator()
      : super(const SyncState(
          isOnline: true,
          pendingCount: 0,
          failedCount: 0,
          isSyncing: false,
        ));

  @override
  Future<void> triggerSync({bool isManual = false}) async {}
}
