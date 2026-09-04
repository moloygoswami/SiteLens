import 'dart:ffi';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sitelens/data/local/database/app_database.dart';
import 'package:sitelens/data/repositories/site_repository.dart';
import 'package:sitelens/features/sites/site_controller.dart';
import 'package:sitelens/domain/models/site_model.dart';

void main() {
  late AppDatabase db;
  late SiteRepository siteRepo;
  late SiteController siteController;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    siteRepo = LocalSiteRepository(db);
    // Explicit test fixture insertion
    await siteRepo.saveSite(const SiteModel(
      id: 'site-4092',
      siteCode: '4092',
      name: 'Metro Line 3 Pier 42 Construction',
      address: 'Park Street Crossway, Sector 5, Kolkata',
    ));
    await siteRepo.saveSite(const SiteModel(
      id: 'site-1088',
      siteCode: '1088',
      name: 'Flyover Viaduct Segment B',
      address: 'EM Bypass Junction, Kolkata',
    ));
    await siteRepo.saveSite(const SiteModel(
      id: 'site-7721',
      siteCode: '7721',
      name: 'High-Rise Tower Block A Foundation',
      address: 'Rajarhat Main Blvd, New Town',
    ));
    siteController = SiteController(siteRepo);
  });

  tearDown(() async {
    await db.close();
  });

  group('SiteController & SiteRepository Tests', () {
    test('Loads available test sites successfully', () async {
      await siteController.loadSitesAndActiveContext();

      expect(siteController.state.availableSites.length, equals(3));
      expect(siteController.state.activeSite, isNotNull);
      expect(siteController.state.activeSite?.siteCode, equals('4092'));
    });

    test('Can switch active site and persist', () async {
      await siteController.loadSitesAndActiveContext();

      const newSite = SiteModel(
        id: 'site-1088',
        siteCode: '1088',
        name: 'Flyover Viaduct Segment B',
        address: 'EM Bypass Junction, Kolkata',
      );

      await siteController.setActiveSite(newSite);
      expect(siteController.state.activeSite?.id, equals('site-1088'));

      // Verify persistence in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sitelens_active_site_id'), equals('site-1088'));
    });

    test('Can add and select custom offline site with 20-character Firestore-compatible auto-ID', () async {
      await siteController.addCustomOfflineSite(
        siteCode: '9901',
        name: 'Underground Tunnel Segment C',
        address: 'Howrah Station Approach, Kolkata',
      );

      final active = siteController.state.activeSite;
      expect(active?.siteCode, equals('9901'));
      expect(active?.id.length, equals(20));
      expect(RegExp(r'^[a-zA-Z0-9]{20}$').hasMatch(active!.id), isTrue);
      expect(siteController.state.availableSites.length, equals(4));
    });

    test('Can delete cached site', () async {
      await siteController.loadSitesAndActiveContext();
      expect(siteController.state.availableSites.length, equals(3));

      await siteController.deleteSite('site-4092');
      expect(siteController.state.availableSites.length, equals(2));
      expect(siteController.state.availableSites.any((s) => s.id == 'site-4092'), isFalse);
    });
  });
}
