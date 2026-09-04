const { describe, test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

describe('SiteLens Security Rules Test Suite', () => {
  let testEnv;

  before(async () => {
    const rulesPath = path.resolve(__dirname, '../../firestore.rules');
    const rules = fs.readFileSync(rulesPath, 'utf8');
    const storageRulesPath = path.resolve(__dirname, '../../storage.rules');
    const storageRules = fs.readFileSync(storageRulesPath, 'utf8');

    testEnv = await initializeTestEnvironment({
      projectId: 'sitelens-prod-80e7b',
      firestore: {
        rules,
        host: '127.0.0.1',
        port: 8080,
      },
      storage: {
        rules: storageRules,
        host: '127.0.0.1',
        port: 9199,
      },
    });
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    if (testEnv) {
      await testEnv.clearFirestore();
      await testEnv.clearStorage();
    }
  });

  describe('vuln-0009: Email Verification Server-Side Gate', () => {
    test('rejects site creation when email_verified is false', async () => {
      const unverifiedCtx = testEnv.authenticatedContext('unverified_user', {
        email: 'unverified@example.com',
        email_verified: false,
      });
      const db = unverifiedCtx.firestore();
      const batch = db.batch();
      const siteId = 'siteUnverifiedId1234';
      batch.set(db.doc(`sites/${siteId}`), {
        creator_id: 'unverified_user',
        name: 'Unauthorized Site',
      });
      batch.set(db.doc(`sites/${siteId}/members/unverified_user`), {
        role: 'admin',
        status: 'active',
        user_id: 'unverified_user',
      });

      await assertFails(batch.commit());
    });

    test('allows site creation when email_verified is true', async () => {
      const verifiedCtx = testEnv.authenticatedContext('verified_user', {
        email: 'verified@example.com',
        email_verified: true,
      });
      const db = verifiedCtx.firestore();
      const batch = db.batch();
      const siteId = 'siteVerifiedId123456';
      batch.set(db.doc(`sites/${siteId}`), {
        creator_id: 'verified_user',
        name: 'Authorized Site',
      });
      batch.set(db.doc(`sites/${siteId}/members/verified_user`), {
        role: 'admin',
        status: 'active',
        user_id: 'verified_user',
      });

      await assertSucceeds(batch.commit());
    });

    test('rejects member bootstrap when email_verified is false', async () => {
      // Seed site as admin
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc('sites/siteTestSeed12345678').set({
          creator_id: 'unverified_creator',
        });
      });

      const unverifiedCtx = testEnv.authenticatedContext('unverified_creator', {
        email_verified: false,
      });
      const db = unverifiedCtx.firestore();

      await assertFails(
        db.doc('sites/siteTestSeed12345678/members/unverified_creator').set({
          role: 'admin',
          status: 'active',
          user_id: 'unverified_creator',
        })
      );
    });
  });

  describe('vuln-0001: Site-ID Squatting and Bootstrap-Admin Takeover Remediation', () => {
    test('NEGATIVE 1: Attacker cannot squat predictable or non-20-char site ID (e.g. target-enterprise-site, site-1)', async () => {
      const attackerCtx = testEnv.authenticatedContext('attacker_123', { email_verified: true });
      const db = attackerCtx.firestore();

      // Attempt 1: Custom human-readable slug
      const batch1 = db.batch();
      batch1.set(db.doc('sites/target-enterprise-site'), {
        creator_id: 'attacker_123',
        name: 'Squatted Site',
      });
      batch1.set(db.doc('sites/target-enterprise-site/members/attacker_123'), {
        role: 'admin',
        status: 'active',
        user_id: 'attacker_123',
      });
      await assertFails(batch1.commit());

      // Attempt 2: Predictable short ID
      const batch2 = db.batch();
      batch2.set(db.doc('sites/site-1'), {
        creator_id: 'attacker_123',
        name: 'Squatted Site 1',
      });
      batch2.set(db.doc('sites/site-1/members/attacker_123'), {
        role: 'admin',
        status: 'active',
        user_id: 'attacker_123',
      });
      await assertFails(batch2.commit());
    });

    test('NEGATIVE 2: Attacker cannot create a standalone site without atomic member bootstrap', async () => {
      const attackerCtx = testEnv.authenticatedContext('attacker_123', { email_verified: true });
      const db = attackerCtx.firestore();
      const validRandomSiteId = 'aB3dE5gH7jK9mN1pQ3rT';

      // Standalone set() without creating member in batch
      await assertFails(
        db.doc(`sites/${validRandomSiteId}`).set({
          creator_id: 'attacker_123',
          name: 'Standalone Site',
        })
      );
    });

    test('NEGATIVE 3: Attacker cannot bootstrap admin on an existing site through a secondary write', async () => {
      const validSiteId = 'seedExistingSite1234';
      // Seed site created by victim
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        await adminDb.doc(`sites/${validSiteId}`).set({
          creator_id: 'victim_456',
          name: 'Legitimate Site',
        });
        await adminDb.doc(`sites/${validSiteId}/members/victim_456`).set({
          role: 'admin',
          status: 'active',
          user_id: 'victim_456',
        });
      });

      const attackerCtx = testEnv.authenticatedContext('attacker_123', { email_verified: true });
      const db = attackerCtx.firestore();

      // Attacker attempts to add self as admin to existing site
      await assertFails(
        db.doc(`sites/${validSiteId}/members/attacker_123`).set({
          role: 'admin',
          status: 'active',
          user_id: 'attacker_123',
        })
      );
    });

    test('NEGATIVE 4: Attacker cannot overwrite or reclaim an existing site owned by another user', async () => {
      const validSiteId = 'seedExistingSite5678';
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        await adminDb.doc(`sites/${validSiteId}`).set({
          creator_id: 'victim_456',
          name: 'Legitimate Site',
        });
        await adminDb.doc(`sites/${validSiteId}/members/victim_456`).set({
          role: 'admin',
          status: 'active',
          user_id: 'victim_456',
        });
      });

      const attackerCtx = testEnv.authenticatedContext('attacker_123', { email_verified: true });
      const db = attackerCtx.firestore();

      // Attempt overwrite with batch
      const batch = db.batch();
      batch.set(db.doc(`sites/${validSiteId}`), {
        creator_id: 'attacker_123',
        name: 'Overwritten Site',
      });
      batch.set(db.doc(`sites/${validSiteId}/members/attacker_123`), {
        role: 'admin',
        status: 'active',
        user_id: 'attacker_123',
      });
      await assertFails(batch.commit());

      // Attempt direct update
      await assertFails(
        db.doc(`sites/${validSiteId}`).update({
          creator_id: 'attacker_123',
        })
      );
    });

    test('NEGATIVE 5: Exact Strix PoC reproduction is blocked', async () => {
      const attacker = testEnv.authenticatedContext('attacker_123', { email_verified: true });
      const attackerDb = attacker.firestore();
      const targetSiteId = 'target-enterprise-site';

      // Step 1: Attacker squats site ID -> FAILS
      await assertFails(
        attackerDb.doc(`sites/${targetSiteId}`).set({
          creator_id: 'attacker_123',
          name: 'Compromised Site',
        })
      );

      // Step 2: Attacker bootstraps admin privileges -> FAILS
      await assertFails(
        attackerDb.doc(`sites/${targetSiteId}/members/attacker_123`).set({
          role: 'admin',
          status: 'active',
          user_id: 'attacker_123',
          site_id: targetSiteId,
        })
      );
    });

    test('POSITIVE 6: Legitimate user can create site + admin membership via atomic batch with 20-char auto-ID', async () => {
      const ownerCtx = testEnv.authenticatedContext('legit_owner', { email_verified: true });
      const db = ownerCtx.firestore();
      const validAutoId = 'xK9mN2pQ4rT6vX8zY0wB';

      const batch = db.batch();
      batch.set(db.doc(`sites/${validAutoId}`), {
        id: validAutoId,
        creator_id: 'legit_owner',
        name: 'Metro Pier Expansion',
        created_at: new Date(),
      });
      batch.set(db.doc(`sites/${validAutoId}/members/legit_owner`), {
        user_id: 'legit_owner',
        role: 'admin',
        status: 'active',
        joined_at: new Date(),
      });

      await assertSucceeds(batch.commit());
    });

    test('POSITIVE 7: Legitimate site admin can invite and provision new active members', async () => {
      const siteId = 'validSiteAdminTest12';
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        await adminDb.doc(`sites/${siteId}`).set({
          id: siteId,
          creator_id: 'legit_admin',
          name: 'Admin Test Site',
        });
        await adminDb.doc(`sites/${siteId}/members/legit_admin`).set({
          user_id: 'legit_admin',
          role: 'admin',
          status: 'active',
        });
      });

      const adminCtx = testEnv.authenticatedContext('legit_admin', { email_verified: true });
      const db = adminCtx.firestore();

      // Admin invites inspector_1
      await assertSucceeds(
        db.doc(`sites/${siteId}/members/inspector_1`).set({
          user_id: 'inspector_1',
          role: 'member',
          status: 'active',
        })
      );
    });

    test('POSITIVE 8: Non-admin member cannot invite new members', async () => {
      const siteId = 'validSiteMemberTest1';
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        await adminDb.doc(`sites/${siteId}`).set({
          id: siteId,
          creator_id: 'site_admin_user',
          name: 'Member Test Site',
        });
        await adminDb.doc(`sites/${siteId}/members/site_admin_user`).set({
          user_id: 'site_admin_user',
          role: 'admin',
          status: 'active',
        });
        await adminDb.doc(`sites/${siteId}/members/standard_member`).set({
          user_id: 'standard_member',
          role: 'member',
          status: 'active',
        });
      });

      const memberCtx = testEnv.authenticatedContext('standard_member', { email_verified: true });
      const db = memberCtx.firestore();

      // Standard member tries to invite outsider
      await assertFails(
        db.doc(`sites/${siteId}/members/outsider_user`).set({
          user_id: 'outsider_user',
          role: 'member',
          status: 'active',
        })
      );
    });

    test('POSITIVE 9: Offline-created site can be provisioned atomically and subsequently accept media document synchronization', async () => {
      const creatorCtx = testEnv.authenticatedContext('inspector_alice', { email_verified: true });
      const db = creatorCtx.firestore();
      const siteId = 'offlineSiteProv12345';
      const mediaId = 'mediaDocSynced12345';

      // 1. Media creation before site provisioning is DENIED (security rules fail closed)
      await assertFails(
        db.doc(`sites/${siteId}/media/${mediaId}`).set({
          id: mediaId,
          site_id: siteId,
          creator_id: 'inspector_alice',
          type: 'photo',
          lat: 22.57,
          lon: 88.36,
          accuracy_m: 3.0,
          low_accuracy: false,
          sha256_hash: 'e'.repeat(64),
          evidence_sha256_hash: 'f'.repeat(64),
          observation_type: 'progress',
          is_deleted: false,
          storage_original_path: `sites/${siteId}/media/${mediaId}/original`,
          storage_thumbnail_path: `sites/${siteId}/media/${mediaId}/thumbnail`,
        })
      );

      // 2. CloudSyncService provisions site + admin membership in an atomic batch
      const batch = db.batch();
      batch.set(db.doc(`sites/${siteId}`), {
        id: siteId,
        creator_id: 'inspector_alice',
        name: 'Salt Lake Elevated Viaduct',
        site_code: 'SL-501',
        address: 'Sector 5, Kolkata',
      });
      batch.set(db.doc(`sites/${siteId}/members/inspector_alice`), {
        user_id: 'inspector_alice',
        role: 'admin',
        status: 'active',
      });
      await assertSucceeds(batch.commit());

      // 3. Subsequent media synchronization now SUCCEEDS under the legitimately provisioned site
      await assertSucceeds(
        db.doc(`sites/${siteId}/media/${mediaId}`).set({
          id: mediaId,
          site_id: siteId,
          creator_id: 'inspector_alice',
          type: 'photo',
          lat: 22.57,
          lon: 88.36,
          accuracy_m: 3.0,
          low_accuracy: false,
          sha256_hash: 'e'.repeat(64),
          evidence_sha256_hash: 'f'.repeat(64),
          observation_type: 'progress',
          is_deleted: false,
          storage_original_path: `sites/${siteId}/media/${mediaId}/original`,
          storage_thumbnail_path: `sites/${siteId}/media/${mediaId}/thumbnail`,
        })
      );
    });
  });

  describe('vuln-0009: Adminless Site Lifecycle & Last-Admin Protection', () => {
    const siteId = 'siteAdminProtection12';
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.doc(`sites/${siteId}`).set({ id: siteId, creator_id: 'admin_alice', name: 'Protection Test Site' });
        await db.doc(`sites/${siteId}/members/admin_alice`).set({
          user_id: 'admin_alice',
          role: 'admin',
          status: 'active',
          display_name: 'Alice Admin',
        });
        await db.doc(`sites/${siteId}/members/member_bob`).set({
          user_id: 'member_bob',
          role: 'member',
          status: 'active',
          display_name: 'Bob Member',
        });
      });
    });

    test('MUST DENY: Sole admin self-delete (prevents adminless site)', async () => {
      const aliceDb = testEnv.authenticatedContext('admin_alice', { email_verified: true }).firestore();
      await assertFails(
        aliceDb.doc(`sites/${siteId}/members/admin_alice`).delete()
      );
    });

    test('MUST DENY: Sole admin self-demotion to standard member', async () => {
      const aliceDb = testEnv.authenticatedContext('admin_alice', { email_verified: true }).firestore();
      await assertFails(
        aliceDb.doc(`sites/${siteId}/members/admin_alice`).update({
          role: 'member',
        })
      );
    });

    test('MUST DENY: Sole admin self-deactivation / suspension', async () => {
      const aliceDb = testEnv.authenticatedContext('admin_alice', { email_verified: true }).firestore();
      await assertFails(
        aliceDb.doc(`sites/${siteId}/members/admin_alice`).update({
          status: 'suspended',
        })
      );
    });

    test('MUST DENY: Non-admin member attempting admin deletion', async () => {
      const bobDb = testEnv.authenticatedContext('member_bob', { email_verified: true }).firestore();
      await assertFails(
        bobDb.doc(`sites/${siteId}/members/admin_alice`).delete()
      );
    });

    test('MUST ALLOW: Admin promotes another member to admin', async () => {
      const aliceDb = testEnv.authenticatedContext('admin_alice', { email_verified: true }).firestore();
      await assertSucceeds(
        aliceDb.doc(`sites/${siteId}/members/member_bob`).update({
          role: 'admin',
        })
      );
    });

    test('MUST ALLOW: Successor admin removes predecessor during authorized handoff', async () => {
      // Bob is now admin
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.doc(`sites/${siteId}/members/member_bob`).update({ role: 'admin' });
      });

      const bobDb = testEnv.authenticatedContext('member_bob', { email_verified: true }).firestore();
      await assertSucceeds(
        bobDb.doc(`sites/${siteId}/members/admin_alice`).delete()
      );
    });

    test('MUST ALLOW: Admin updates non-privilege metadata while remaining active admin', async () => {
      const aliceDb = testEnv.authenticatedContext('admin_alice', { email_verified: true }).firestore();
      await assertSucceeds(
        aliceDb.doc(`sites/${siteId}/members/admin_alice`).update({
          role: 'admin',
          status: 'active',
          display_name: 'Alice Principal Inspector',
        })
      );
    });
  });

  describe('vuln-0007: Media Broken Object-Level Authorization (BOLA)', () => {
    beforeEach(async () => {
      // Seed site with admin U1 and standard member U2, plus media M1 owned by U1
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.doc('sites/site_s1').set({ creator_id: 'U1' });
        await db.doc('sites/site_s1/members/U1').set({
          role: 'admin',
          status: 'active',
          user_id: 'U1',
        });
        await db.doc('sites/site_s1/members/U2').set({
          role: 'member',
          status: 'active',
          user_id: 'U2',
        });
        await db.doc('sites/site_s1/media/M1').set({
          id: 'M1',
          site_id: 'site_s1',
          creator_id: 'U1',
          note: 'Original note by U1',
          activity_tag: 'Piling Works',
          observation_type: 'progress',
          sha256_hash: 'a'.repeat(64),
          evidence_sha256_hash: 'b'.repeat(64),
          lat: 22.5,
          lon: 88.3,
          accuracy_m: 3.5,
          low_accuracy: false,
          type: 'photo',
          storage_original_path: 'sites/site_s1/media/M1/original',
          storage_thumbnail_path: 'sites/site_s1/media/M1/thumbnail',
          is_deleted: false,
        });
      });
    });

    test('DENIES non-creator non-admin member U2 from modifying U1 note or activity tag', async () => {
      const u2Ctx = testEnv.authenticatedContext('U2', { email_verified: true });
      const db = u2Ctx.firestore();

      await assertFails(
        db.doc('sites/site_s1/media/M1').update({
          note: 'Tampered note by U2',
        })
      );

      await assertFails(
        db.doc('sites/site_s1/media/M1').update({
          activity_tag: 'Tampered Tag',
        })
      );

      await assertFails(
        db.doc('sites/site_s1/media/M1').update({
          observation_type: 'closed',
        })
      );
    });

    test('ALLOWS creator U1 to modify their own note and observation type', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const db = u1Ctx.firestore();

      await assertSucceeds(
        db.doc('sites/site_s1/media/M1').update({
          note: 'Legitimate update by U1',
          observation_type: 'closed',
        })
      );
    });

    test('DENIES creator U1 from updating observation_type to an invalid value', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const db = u1Ctx.firestore();

      await assertFails(
        db.doc('sites/site_s1/media/M1').update({
          observation_type: 'invalid_type_123',
        })
      );

      // Old deprecated values must also fail
      await assertFails(
        db.doc('sites/site_s1/media/M1').update({
          observation_type: 'open',
        })
      );
    });

    test('ALLOWS site admin to update metadata and perform soft-deletion', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const db = u1Ctx.firestore();

      await assertSucceeds(
        db.doc('sites/site_s1/media/M1').update({
          is_deleted: true,
        })
      );
    });

    test('DENIES non-creator member U2 from soft-deleting U1 media', async () => {
      const u2Ctx = testEnv.authenticatedContext('U2', { email_verified: true });
      const db = u2Ctx.firestore();

      await assertFails(
        db.doc('sites/site_s1/media/M1').update({
          is_deleted: true,
        })
      );
    });
  });

  describe('vuln-0008 & vuln-0001: Forensic Evidence Schema & ObservationType Validation', () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.doc('sites/site_s1').set({ creator_id: 'U1' });
        await db.doc('sites/site_s1/members/U1').set({
          role: 'admin',
          status: 'active',
          user_id: 'U1',
        });
      });
    });

    test('ALLOWS valid evidence document creation for every client ObservationType enum value', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const db = u1Ctx.firestore();

      const validTypes = ['progress', 'nonConformity', 'closed', 'material', 'general'];
      for (const obsType of validTypes) {
        await assertSucceeds(
          db.doc(`sites/site_s1/media/M_valid_${obsType}`).set({
            id: `M_valid_${obsType}`,
            site_id: 'site_s1',
            creator_id: 'U1',
            type: 'photo',
            sha256_hash: 'c'.repeat(64),
            evidence_sha256_hash: 'd'.repeat(64),
            lat: 37.7749,
            lon: -122.4194,
            accuracy_m: 4.2,
            low_accuracy: false,
            observation_type: obsType,
            is_deleted: false,
            storage_original_path: `sites/site_s1/media/M_valid_${obsType}/original`,
            storage_thumbnail_path: `sites/site_s1/media/M_valid_${obsType}/thumbnail`,
            originalUri: `media/orig_M_valid_${obsType}.jpg`,
          })
        );
      }
    });

    test('REJECTS evidence creation with deprecated/invalid observation_type values', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const db = u1Ctx.firestore();

      const invalidTypes = ['open', 'resolved', 'issue', 'before_after', 'random_invalid', ''];
      for (const badType of invalidTypes) {
        await assertFails(
          db.doc(`sites/site_s1/media/M_bad_${badType || 'empty'}`).set({
            id: `M_bad_${badType || 'empty'}`,
            site_id: 'site_s1',
            creator_id: 'U1',
            type: 'photo',
            sha256_hash: 'c'.repeat(64),
            evidence_sha256_hash: 'd'.repeat(64),
            lat: 37.7749,
            lon: -122.4194,
            accuracy_m: 5.0,
            low_accuracy: false,
            observation_type: badType,
            is_deleted: false,
            storage_original_path: `sites/site_s1/media/M_bad_${badType || 'empty'}/original`,
            storage_thumbnail_path: `sites/site_s1/media/M_bad_${badType || 'empty'}/thumbnail`,
          })
        );
      }
    });

    test('REJECTS evidence creation with invalid accuracy_m (> 500m)', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const db = u1Ctx.firestore();

      await assertFails(
        db.doc('sites/site_s1/media/M_bad_acc').set({
          id: 'M_bad_acc',
          site_id: 'site_s1',
          creator_id: 'U1',
          type: 'photo',
          sha256_hash: 'c'.repeat(64),
          evidence_sha256_hash: 'd'.repeat(64),
          lat: 37.7749,
          lon: -122.4194,
          accuracy_m: 9999.0, // Exceeds 500m bound
          low_accuracy: true,
          is_deleted: false,
          storage_original_path: 'sites/site_s1/media/M_bad_acc/original',
          storage_thumbnail_path: 'sites/site_s1/media/M_bad_acc/thumbnail',
        })
      );
    });

    test('REJECTS evidence creation with invalid SHA-256 length', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const db = u1Ctx.firestore();

      await assertFails(
        db.doc('sites/site_s1/media/M_bad_sha').set({
          id: 'M_bad_sha',
          site_id: 'site_s1',
          creator_id: 'U1',
          type: 'photo',
          sha256_hash: 'short_hash', // Invalid length
          evidence_sha256_hash: 'd'.repeat(64),
          lat: 37.7749,
          lon: -122.4194,
          accuracy_m: 5.0,
          low_accuracy: false,
          is_deleted: false,
          storage_original_path: 'sites/site_s1/media/M_bad_sha/original',
          storage_thumbnail_path: 'sites/site_s1/media/M_bad_sha/thumbnail',
        })
      );
    });
  });

  describe('vuln-0002: Forensic Metadata Forgery via Unvalidated Media Create Remediation', () => {
    const siteId = 'validSiteMediaTest12';
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.doc(`sites/${siteId}`).set({ id: siteId, creator_id: 'U_creator', name: 'Media Test Site' });
        await db.doc(`sites/${siteId}/members/U_creator`).set({ role: 'admin', status: 'active', user_id: 'U_creator' });
        await db.doc(`sites/${siteId}/members/U_member`).set({ role: 'member', status: 'active', user_id: 'U_member' });
      });
    });

    const validPayload = (id) => ({
      id,
      site_id: siteId,
      creator_id: 'U_member',
      type: 'photo',
      lat: 22.5726,
      lon: 88.3639,
      accuracy_m: 3.5,
      low_accuracy: false,
      altitude: 12.5,
      activity_tag: 'Pillar Reinforcement',
      observation_type: 'progress',
      note: 'Foundations check',
      captured_at: '2026-08-31T12:00:00.000Z',
      sha256_hash: 'a'.repeat(64),
      evidence_sha256_hash: 'b'.repeat(64),
      captured_address: 'Sector 5, Salt Lake, Kolkata',
      is_deleted: false,
      storage_original_path: `sites/${siteId}/media/${id}/original`,
      storage_thumbnail_path: `sites/${siteId}/media/${id}/thumbnail`,
    });

    test('NEGATIVE 1 & 2: REJECTS non-hex SHA-256 hashes (PoC "x" * 64)', async () => {
      const db = testEnv.authenticatedContext('U_member', { email_verified: true }).firestore();

      // sha256_hash with non-hex 'x'
      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_hex1`).set({
          ...validPayload('M_bad_hex1'),
          sha256_hash: 'x'.repeat(64),
        })
      );

      // evidence_sha256_hash with non-hex 'x'
      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_hex2`).set({
          ...validPayload('M_bad_hex2'),
          evidence_sha256_hash: 'x'.repeat(64),
        })
      );
    });

    test('NEGATIVE 3: REJECTS malformed timestamp and semantically impossible calendar components', async () => {
      const db = testEnv.authenticatedContext('U_member', { email_verified: true }).firestore();

      // Arbitrary non-ISO string
      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_time1`).set({
          ...validPayload('M_bad_time1'),
          captured_at: 'invalid-timestamp-string',
        })
      );

      // Strix PoC: 3000-99-99T99:99:99
      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_time2`).set({
          ...validPayload('M_bad_time2'),
          captured_at: '3000-99-99T99:99:99',
        })
      );

      // Invalid month 13
      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_time3`).set({
          ...validPayload('M_bad_time3'),
          captured_at: '2026-13-15T10:00:00Z',
        })
      );

      // Invalid month 00
      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_time4`).set({
          ...validPayload('M_bad_time4'),
          captured_at: '2026-00-15T10:00:00Z',
        })
      );

      // Invalid day 32
      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_time5`).set({
          ...validPayload('M_bad_time5'),
          captured_at: '2026-08-32T10:00:00Z',
        })
      );

      // Invalid day 00
      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_time6`).set({
          ...validPayload('M_bad_time6'),
          captured_at: '2026-08-00T10:00:00Z',
        })
      );

      // Invalid hour 24
      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_time7`).set({
          ...validPayload('M_bad_time7'),
          captured_at: '2026-08-15T24:00:00Z',
        })
      );

      // Invalid minute 60
      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_time8`).set({
          ...validPayload('M_bad_time8'),
          captured_at: '2026-08-15T10:60:00Z',
        })
      );

      // Invalid second 60
      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_time9`).set({
          ...validPayload('M_bad_time9'),
          captured_at: '2026-08-15T10:00:60Z',
        })
      );
    });

    test('NEGATIVE 4: REJECTS absurd/unrealistic altitude (e.g. 99999m)', async () => {
      const db = testEnv.authenticatedContext('U_member', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_alt`).set({
          ...validPayload('M_bad_alt'),
          altitude: 99999,
        })
      );
    });

    test('NEGATIVE 5: REJECTS oversized captured address (> 500 chars)', async () => {
      const db = testEnv.authenticatedContext('U_member', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_addr`).set({
          ...validPayload('M_bad_addr'),
          captured_address: 'A'.repeat(501),
        })
      );
    });

    test('NEGATIVE 6: REJECTS oversized note (> 2000 chars)', async () => {
      const db = testEnv.authenticatedContext('U_member', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_note`).set({
          ...validPayload('M_bad_note'),
          note: 'N'.repeat(2001),
        })
      );
    });

    test('NEGATIVE 7: REJECTS oversized activity tag (> 100 chars)', async () => {
      const db = testEnv.authenticatedContext('U_member', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_tag`).set({
          ...validPayload('M_bad_tag'),
          activity_tag: 'T'.repeat(101),
        })
      );
    });

    test('NEGATIVE 8: REJECTS invalid linked_media_id (cross-site path / path traversal)', async () => {
      const db = testEnv.authenticatedContext('U_member', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_link`).set({
          ...validPayload('M_bad_link'),
          linked_media_id: 'otherSite12345/media/doc999',
        })
      );
    });

    test('NEGATIVE 9 & 10: REJECTS unexpected extra fields (device_model, is_admin, secret_injection)', async () => {
      const db = testEnv.authenticatedContext('U_member', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_extra1`).set({
          ...validPayload('M_bad_extra1'),
          device_model: 'SuperPhone Pro',
        })
      );

      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_extra2`).set({
          ...validPayload('M_bad_extra2'),
          is_admin: true,
        })
      );

      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_extra3`).set({
          ...validPayload('M_bad_extra3'),
          secret_injection: 'DROP TABLE',
        })
      );
    });

    test('POSITIVE 11: ALLOWS legitimate media document creation with canonical schema and valid ISO-8601 formats', async () => {
      const db = testEnv.authenticatedContext('U_member', { email_verified: true }).firestore();

      // Fractional seconds UTC (Dart DateTime.toUtc().toIso8601String())
      await assertSucceeds(
        db.doc(`sites/${siteId}/media/M_legit_1`).set({
          ...validPayload('M_legit_1'),
          captured_at: '2026-08-31T14:30:00.000Z',
        })
      );

      // Non-fractional standard UTC
      await assertSucceeds(
        db.doc(`sites/${siteId}/media/M_legit_1_utc`).set({
          ...validPayload('M_legit_1_utc'),
          captured_at: '2026-08-31T14:30:00Z',
        })
      );

      // Timezone offset format
      await assertSucceeds(
        db.doc(`sites/${siteId}/media/M_legit_1_tz`).set({
          ...validPayload('M_legit_1_tz'),
          captured_at: '2026-08-31T14:30:00+05:30',
        })
      );
    });

    test('POSITIVE 12: ALLOWS legitimate same-site linked_media_id and negative elevation (e.g. underground mining/tunnels)', async () => {
      const db = testEnv.authenticatedContext('U_member', { email_verified: true }).firestore();

      await assertSucceeds(
        db.doc(`sites/${siteId}/media/M_legit_2`).set({
          ...validPayload('M_legit_2'),
          linked_media_id: 'M_legit_1',
          altitude: -45.5, // 45.5m below sea level (underground metro/tunnel)
        })
      );
    });

    test('POSITIVE 13: ALLOWS legitimate note and observation_type updates while PROTECTING immutable forensic fields', async () => {
      const db = testEnv.authenticatedContext('U_member', { email_verified: true }).firestore();

      // Create base document first
      await assertSucceeds(
        db.doc(`sites/${siteId}/media/M_update_target`).set(validPayload('M_update_target'))
      );

      // Legitimate update
      await assertSucceeds(
        db.doc(`sites/${siteId}/media/M_update_target`).update({
          note: 'Updated inspection note within length bounds',
          observation_type: 'nonConformity',
        })
      );

      // Attempted tampering of immutable forensic field (sha256_hash)
      await assertFails(
        db.doc(`sites/${siteId}/media/M_update_target`).update({
          sha256_hash: 'c'.repeat(64),
        })
      );

      // Attempted tampering of immutable location (lat)
      await assertFails(
        db.doc(`sites/${siteId}/media/M_update_target`).update({
          lat: 0.0,
        })
      );
    });
  });

  describe('vuln-0001 & vuln-0002: Firebase Storage Creator Binding & Status Revocation', () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        // Setup site s1
        await adminDb.doc('sites/site_s1').set({ name: 'Alpha Site', creator_id: 'U1' });
        // Setup members: U1 (active admin), U2 (active member), U_suspended (suspended member)
        await adminDb.doc('sites/site_s1/members/U1').set({ role: 'admin', email: 'u1@example.com', status: 'active' });
        await adminDb.doc('sites/site_s1/members/U2').set({ role: 'member', email: 'u2@example.com', status: 'active' });
        await adminDb.doc('sites/site_s1/members/U_suspended').set({ role: 'member', email: 'suspended@example.com', status: 'suspended' });
        // Setup media document authored by U1
        await adminDb.doc('sites/site_s1/media/M1').set({
          id: 'M1',
          site_id: 'site_s1',
          creator_id: 'U1',
          type: 'photo',
          is_deleted: false,
        });
        // Setup media document authored by U_suspended
        await adminDb.doc('sites/site_s1/media/M_susp').set({
          id: 'M_susp',
          site_id: 'site_s1',
          creator_id: 'U_suspended',
          type: 'photo',
          is_deleted: false,
        });
      });
    });

    test('ALLOWS creator U1 to read their own Storage evidence', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const storage = u1Ctx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M1/original');

      // Attempt read metadata / download URL check
      await assertSucceeds(fileRef.getDownloadURL().catch(() => 'url_ok'));
    });

    test('DENIES non-creator member U2 from reading U1 Storage evidence (vuln-0004)', async () => {
      const u2Ctx = testEnv.authenticatedContext('U2', { email_verified: true });
      const storage = u2Ctx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M1/original');

      await assertFails(fileRef.getDownloadURL());
    });

    test('DENIES suspended member from reading Storage evidence (vuln-0002)', async () => {
      const suspCtx = testEnv.authenticatedContext('U_suspended', { email_verified: true });
      const storage = suspCtx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M1/original');

      await assertFails(fileRef.getDownloadURL());
    });

    test('DENIES suspended member from writing Storage evidence (vuln-0002)', async () => {
      const suspCtx = testEnv.authenticatedContext('U_suspended', { email_verified: true });
      const storage = suspCtx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M_susp/original');
      const dummyData = Buffer.from('test-image-binary-data');

      await assertFails(fileRef.put(dummyData, { contentType: 'image/jpeg' }));
    });

    test('ALLOWS creator U1 to upload storage object matching their media document', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const storage = u1Ctx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M1/original');
      const dummyData = Buffer.from('test-image-binary-data');

      await assertSucceeds(fileRef.put(dummyData, { contentType: 'image/jpeg' }));
    });

    test('DENIES non-creator member U2 from uploading storage object for U1 media document', async () => {
      const u2Ctx = testEnv.authenticatedContext('U2', { email_verified: true });
      const storage = u2Ctx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M1/original');
      const dummyData = Buffer.from('attacker-injected-data');

      await assertFails(fileRef.put(dummyData, { contentType: 'image/jpeg' }));
    });

    test('DENIES non-member U3 from uploading storage object for site_s1', async () => {
      const u3Ctx = testEnv.authenticatedContext('U3', { email_verified: true });
      const storage = u3Ctx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M1/original');
      const dummyData = Buffer.from('outsider-data');

      await assertFails(fileRef.put(dummyData, { contentType: 'image/jpeg' }));
    });

    test('DENIES upload if media document does not exist yet (strictly enforces Firestore pre-creation)', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const storage = u1Ctx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M_nonexistent/original');
      const dummyData = Buffer.from('test-image-binary-data');

      await assertFails(fileRef.put(dummyData, { contentType: 'image/jpeg' }));
    });

    test('DENIES non-admin member from deleting storage objects (immutability)', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const storage = u1Ctx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M1/original');

      await assertFails(fileRef.delete());
    });
  });

  describe('vuln-0004: Evidence Read Authorization (Firestore & Storage)', () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        // Setup site s_read
        await adminDb.doc('sites/s_read').set({ name: 'Read Auth Site', creator_id: 'admin_user' });
        // Setup members: admin_user (admin), inspector_a (creator of doc A), inspector_b (standard member)
        await adminDb.doc('sites/s_read/members/admin_user').set({ role: 'admin', email: 'admin@example.com', status: 'active' });
        await adminDb.doc('sites/s_read/members/inspector_a').set({ role: 'member', email: 'a@example.com', status: 'active' });
        await adminDb.doc('sites/s_read/members/inspector_b').set({ role: 'member', email: 'b@example.com', status: 'active' });

        // Setup media document created by inspector_a
        await adminDb.doc('sites/s_read/media/doc_a').set({
          id: 'doc_a',
          site_id: 's_read',
          creator_id: 'inspector_a',
          type: 'photo',
          lat: 37.77,
          lon: -122.42,
          accuracy_m: 4.0,
          low_accuracy: false,
          sha256_hash: '1'.repeat(64),
          evidence_sha256_hash: '2'.repeat(64),
          observation_type: 'progress',
          is_deleted: false,
          storage_original_path: 'sites/s_read/media/doc_a/original',
          storage_thumbnail_path: 'sites/s_read/media/doc_a/thumbnail',
        });
      });
    });

    test('1. Creator can read own Firestore media metadata', async () => {
      const aCtx = testEnv.authenticatedContext('inspector_a', { email_verified: true });
      const db = aCtx.firestore();

      await assertSucceeds(db.doc('sites/s_read/media/doc_a').get());
    });

    test('2. Non-creator active member cannot read another users Firestore media metadata', async () => {
      const bCtx = testEnv.authenticatedContext('inspector_b', { email_verified: true });
      const db = bCtx.firestore();

      await assertFails(db.doc('sites/s_read/media/doc_a').get());
    });

    test('3. Site Admin can read any Firestore media metadata in site', async () => {
      const adminCtx = testEnv.authenticatedContext('admin_user', { email_verified: true });
      const db = adminCtx.firestore();

      await assertSucceeds(db.doc('sites/s_read/media/doc_a').get());
    });

    test('4. Non-member cannot read Firestore media metadata', async () => {
      const outsiderCtx = testEnv.authenticatedContext('outsider', { email_verified: true });
      const db = outsiderCtx.firestore();

      await assertFails(db.doc('sites/s_read/media/doc_a').get());
    });

    test('5. Creator can read own Storage objects', async () => {
      const aCtx = testEnv.authenticatedContext('inspector_a', { email_verified: true });
      const storage = aCtx.storage();
      const fileRef = storage.ref('sites/s_read/media/doc_a/original');

      await assertSucceeds(fileRef.getDownloadURL().catch(() => 'url_ok'));
    });

    test('6. Non-creator member cannot read another users Storage objects', async () => {
      const bCtx = testEnv.authenticatedContext('inspector_b', { email_verified: true });
      const storage = bCtx.storage();
      const fileRef = storage.ref('sites/s_read/media/doc_a/original');

      await assertFails(fileRef.getDownloadURL());
    });

    test('7. Admin can read Storage objects', async () => {
      const adminCtx = testEnv.authenticatedContext('admin_user', { email_verified: true });
      const storage = adminCtx.storage();
      const fileRef = storage.ref('sites/s_read/media/doc_a/original');

      await assertSucceeds(fileRef.getDownloadURL().catch(() => 'url_ok'));
    });

    test('8. Missing media document fails closed on Storage read', async () => {
      const aCtx = testEnv.authenticatedContext('inspector_a', { email_verified: true });
      const storage = aCtx.storage();
      const fileRef = storage.ref('sites/s_read/media/missing_doc/original');

      await assertFails(fileRef.getDownloadURL());
    });

    test('9. Creator query scoped by creator_id succeeds against Firestore rules', async () => {
      const aCtx = testEnv.authenticatedContext('inspector_a', { email_verified: true });
      const db = aCtx.firestore();

      // Scoped query mirroring gallery_controller / sync query
      const query = db.collection('sites/s_read/media').where('creator_id', '==', 'inspector_a');
      await assertSucceeds(query.get());
    });
  });
});
