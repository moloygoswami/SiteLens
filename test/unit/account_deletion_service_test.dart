import 'dart:ffi';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sitelens/core/services/auth_service.dart';
import 'package:sitelens/data/local/database/app_database.dart';

void main() {
  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  group('Account Deletion Models & Parser Tests', () {
    test('1. SuccessorSiteRequirement deserializes correctly from backend map', () {
      final map = {
        'siteId': 'site_shared_001',
        'siteName': 'Metro Rail Bridge Project',
        'eligibleMembers': [
          {
            'userId': 'user_eng_42',
            'role': 'member',
            'status': 'active',
          },
          {
            'userId': 'user_inspector_99',
            'role': 'viewer',
            'status': 'active',
          },
        ],
      };

      final requirement = SuccessorSiteRequirement.fromMap(map);

      expect(requirement.siteId, equals('site_shared_001'));
      expect(requirement.siteName, equals('Metro Rail Bridge Project'));
      expect(requirement.eligibleMembers.length, equals(2));
      expect(requirement.eligibleMembers[0].userId, equals('user_eng_42'));
      expect(requirement.eligibleMembers[0].role, equals('member'));
      expect(requirement.eligibleMembers[0].status, equals('active'));
      expect(requirement.eligibleMembers[1].userId, equals('user_inspector_99'));
    });

    test('2. SuccessorSiteRequirement handles empty or missing members gracefully', () {
      final map = {
        'siteId': 'site_isolated',
        'siteName': 'Isolated Project',
      };

      final requirement = SuccessorSiteRequirement.fromMap(map);

      expect(requirement.siteId, equals('site_isolated'));
      expect(requirement.siteName, equals('Isolated Project'));
      expect(requirement.eligibleMembers, isEmpty);
    });

    test('3. EligibleMember defaults gracefully when fields are null or omitted', () {
      final member = EligibleMember.fromMap({});

      expect(member.userId, equals(''));
      expect(member.role, equals('member'));
      expect(member.status, equals('active'));
    });
  });

  group('Local Sandbox Database Purge (clearAllUserData)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('4. clearAllUserData cleanly purges sites, media, and sync queue tables', () async {
      // 1. Insert test Site
      await db.into(db.sites).insert(
            SitesCompanion.insert(
              id: 'site-to-delete-01',
              siteCode: const drift.Value('SITE-DEL'),
              name: const drift.Value('Temporary Excavation'),
              address: const drift.Value('Site Lane 1'),
              creatorId: const drift.Value('user_deleting'),
            ),
          );

      // 2. Insert test Media
      await db.into(db.media).insert(
            MediaCompanion.insert(
              id: 'media-to-delete-01',
              siteId: const drift.Value('site-to-delete-01'),
              uri: 'file:///data/user/0/com.sitelens/media/evid_01.jpg',
              lat: 22.57,
              lon: 88.36,
              capturedAt: '2026-09-06T12:00:00Z',
              creatorId: const drift.Value('user_deleting'),
            ),
          );

      // 3. Insert test Google Photos Sync Entry
      await db.into(db.googlePhotosSyncEntries).insert(
            GooglePhotosSyncEntriesCompanion.insert(
              mediaId: 'media-to-delete-01',
              status: const drift.Value('pending'),
            ),
          );

      // Verify entries exist before purge
      expect((await db.select(db.sites).get()).length, equals(1));
      expect((await db.select(db.media).get()).length, equals(1));
      expect((await db.select(db.googlePhotosSyncEntries).get()).length, equals(1));

      // Execute purge
      await db.clearAllUserData();

      // Verify all tables are completely empty
      expect(await db.select(db.sites).get(), isEmpty);
      expect(await db.select(db.media).get(), isEmpty);
      expect(await db.select(db.googlePhotosSyncEntries).get(), isEmpty);
    });
  });
}
