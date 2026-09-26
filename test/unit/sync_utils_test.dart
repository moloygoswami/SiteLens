import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitelens/features/sync/services/cloud_sync_service.dart';

void main() {
  group('calculateBackoffDelay', () {
    test('attempt 0 returns base delay (no jitter)', () {
      final delay = calculateBackoffDelay(attempt: 0, withJitter: false);
      expect(delay, equals(const Duration(seconds: 2)));
    });

    test('attempt 1 doubles base delay', () {
      final delay = calculateBackoffDelay(attempt: 1, withJitter: false);
      expect(delay, equals(const Duration(seconds: 4)));
    });

    test('delay is capped at maxDelay', () {
      final delay = calculateBackoffDelay(attempt: 100, withJitter: false);
      expect(delay, equals(const Duration(minutes: 5)));
    });

    test('negative attempt treated as 0', () {
      final delay = calculateBackoffDelay(attempt: -5, withJitter: false);
      expect(delay, equals(const Duration(seconds: 2)));
    });

    test('with jitter returns at least 1 second', () {
      for (int i = 0; i < 50; i++) {
        final delay = calculateBackoffDelay(
          attempt: 0,
          random: Random(i),
          withJitter: true,
        );
        expect(delay.inMilliseconds, greaterThanOrEqualTo(1000));
      }
    });

    test('custom baseDelay and maxDelay are respected', () {
      final delay = calculateBackoffDelay(
        attempt: 2,
        baseDelay: const Duration(seconds: 1),
        maxDelay: const Duration(seconds: 10),
        withJitter: false,
      );
      // 1s * 2^2 = 4s
      expect(delay, equals(const Duration(seconds: 4)));
    });
  });

  group('classifySyncFailure', () {
    test('PermanentSyncException -> permanent', () {
      expect(
        classifySyncFailure(PermanentSyncException('bad')),
        SyncFailureCategory.permanent,
      );
    });

    test('IntegrityConflictException -> permanent', () {
      expect(
        classifySyncFailure(IntegrityConflictException('hash mismatch')),
        SyncFailureCategory.permanent,
      );
    });

    test('SocketException -> retryable', () {
      expect(
        classifySyncFailure(const SocketException('no route to host')),
        SyncFailureCategory.retryable,
      );
    });

    test('TimeoutException -> retryable', () {
      expect(
        classifySyncFailure(TimeoutException('timed out')),
        SyncFailureCategory.retryable,
      );
    });

    test('RetryableSyncException -> retryable', () {
      expect(
        classifySyncFailure(RetryableSyncException('transient')),
        SyncFailureCategory.retryable,
      );
    });

    test('FirebaseException permission-denied -> permanent', () {
      expect(
        classifySyncFailure(FirebaseException(plugin: 'firestore', code: 'permission-denied')),
        SyncFailureCategory.permanent,
      );
    });

    test('FirebaseException unauthenticated -> permanent', () {
      expect(
        classifySyncFailure(FirebaseException(plugin: 'firestore', code: 'unauthenticated')),
        SyncFailureCategory.permanent,
      );
    });

    test('FirebaseException quota-exceeded -> permanent', () {
      expect(
        classifySyncFailure(FirebaseException(plugin: 'firestore', code: 'quota-exceeded')),
        SyncFailureCategory.permanent,
      );
    });

    test('FirebaseException invalid-argument -> permanent', () {
      expect(
        classifySyncFailure(FirebaseException(plugin: 'firestore', code: 'invalid-argument')),
        SyncFailureCategory.permanent,
      );
    });

    test('FirebaseException unavailable -> retryable', () {
      expect(
        classifySyncFailure(FirebaseException(plugin: 'firestore', code: 'unavailable')),
        SyncFailureCategory.retryable,
      );
    });

    test('FirebaseException deadline-exceeded -> retryable', () {
      expect(
        classifySyncFailure(FirebaseException(plugin: 'firestore', code: 'deadline-exceeded')),
        SyncFailureCategory.retryable,
      );
    });

    test('FirebaseException resource-exhausted -> retryable', () {
      expect(
        classifySyncFailure(FirebaseException(plugin: 'firestore', code: 'resource-exhausted')),
        SyncFailureCategory.retryable,
      );
    });

    test('unknown error type -> retryable (fail-safe)', () {
      expect(
        classifySyncFailure(Exception('unknown')),
        SyncFailureCategory.retryable,
      );
    });
  });

  group('validateMutableFieldUpdate', () {
    test('passes for all allowed fields', () {
      final updates = {
        'note': 'updated',
        'is_deleted': false,
        'activity_tag': 'civil',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };
      expect(() => validateMutableFieldUpdate(updates), returnsNormally);
    });

    test('throws PermanentSyncException for immutable field sha256_original', () {
      expect(
        () => validateMutableFieldUpdate({'sha256_original': 'tampered'}),
        throwsA(isA<PermanentSyncException>()),
      );
    });

    test('throws for creator_id', () {
      expect(
        () => validateMutableFieldUpdate({'creator_id': 'attacker'}),
        throwsA(isA<PermanentSyncException>()),
      );
    });

    test('empty updates passes without throwing', () {
      expect(() => validateMutableFieldUpdate({}), returnsNormally);
    });

    test('returns the same map on success', () {
      final updates = {'note': 'ok'};
      final result = validateMutableFieldUpdate(updates);
      expect(result, same(updates));
    });
  });
}
