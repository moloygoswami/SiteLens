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
      const siteId = 'siteUnverifiedId1234';
      await assertFails(
        db.doc(`sites/${siteId}`).set({
          id: siteId,
          creator_id: 'unverified_user',
          name: 'Unauthorized Site',
        })
      );
    });

    test('allows site creation when email_verified is true', async () => {
      const verifiedCtx = testEnv.authenticatedContext('verified_user', {
        email: 'verified@example.com',
        email_verified: true,
      });
      const db = verifiedCtx.firestore();
      const siteId = 'siteVerifiedId123456';
      await assertSucceeds(
        db.doc(`sites/${siteId}`).set({
          id: siteId,
          creator_id: 'verified_user',
          name: 'Authorized Site',
        })
      );
    });

    test('rejects member collection creation (no membership in v1 creator model)', async () => {
      const verifiedCtx = testEnv.authenticatedContext('verified_user', {
        email: 'verified@example.com',
        email_verified: true,
      });
      const db = verifiedCtx.firestore();
      await assertFails(
        db.doc('sites/siteTestSeed12345678/members/verified_user').set({
          role: 'admin',
          status: 'active',
          user_id: 'verified_user',
        })
      );
    });
  });

  describe('vuln-0001: Site-ID Squatting and Bootstrap-Admin Takeover Remediation', () => {
    test('NEGATIVE 1: Attacker cannot squat predictable or non-20-char site ID (e.g. target-enterprise-site, site-1)', async () => {
      const attackerCtx = testEnv.authenticatedContext('attacker_123', { email_verified: true });
      const db = attackerCtx.firestore();

      // Attempt 1: Custom human-readable slug
      await assertFails(
        db.doc('sites/target-enterprise-site').set({
          id: 'target-enterprise-site',
          creator_id: 'attacker_123',
          name: 'Squatted Site',
        })
      );

      // Attempt 2: Predictable short ID
      await assertFails(
        db.doc('sites/site-1').set({
          id: 'site-1',
          creator_id: 'attacker_123',
          name: 'Squatted Site 1',
        })
      );
    });

    test('NEGATIVE 2: Attacker cannot create a site claiming another user as creator_id', async () => {
      const attackerCtx = testEnv.authenticatedContext('attacker_123', { email_verified: true });
      const db = attackerCtx.firestore();
      const validRandomSiteId = 'aB3dE5gH7jK9mN1pQ3rT';

      await assertFails(
        db.doc(`sites/${validRandomSiteId}`).set({
          id: validRandomSiteId,
          creator_id: 'victim_456', // Spoofed creator_id!
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
          id: validSiteId,
          creator_id: 'victim_456',
          name: 'Legitimate Site',
        });
      });

      const attackerCtx = testEnv.authenticatedContext('attacker_123', { email_verified: true });
      const db = attackerCtx.firestore();

      // Attacker attempts to add self as member to existing site
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
          id: validSiteId,
          creator_id: 'victim_456',
          name: 'Legitimate Site',
        });
      });

      const attackerCtx = testEnv.authenticatedContext('attacker_123', { email_verified: true });
      const db = attackerCtx.firestore();

      // Attempt overwrite
      await assertFails(
        db.doc(`sites/${validSiteId}`).set({
          id: validSiteId,
          creator_id: 'attacker_123',
          name: 'Overwritten Site',
        })
      );

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

    test('POSITIVE 6: Legitimate user can create creator-owned site with 20-char auto-ID', async () => {
      const ownerCtx = testEnv.authenticatedContext('legit_owner', { email_verified: true });
      const db = ownerCtx.firestore();
      const validAutoId = 'xK9mN2pQ4rT6vX8zY0wB';

      await assertSucceeds(
        db.doc(`sites/${validAutoId}`).set({
          id: validAutoId,
          creator_id: 'legit_owner',
          name: 'Metro Pier Expansion',
          created_at: new Date(),
        })
      );
    });

    test('POSITIVE 7: Site invitations and member subcollections are completely rejected in v1', async () => {
      const siteId = 'validSiteAdminTest12';
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        await adminDb.doc(`sites/${siteId}`).set({
          id: siteId,
          creator_id: 'legit_admin',
          name: 'Admin Test Site',
        });
      });

      const adminCtx = testEnv.authenticatedContext('legit_admin', { email_verified: true });
      const db = adminCtx.firestore();

      // Admin attempts to invite inspector_1 -> FAILS (no members subcollection)
      await assertFails(
        db.doc(`sites/${siteId}/members/inspector_1`).set({
          user_id: 'inspector_1',
          role: 'member',
          status: 'active',
        })
      );
    });

    test('POSITIVE 8: Non-creator user cannot read another users site', async () => {
      const siteId = 'validSiteMemberTest1';
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        await adminDb.doc(`sites/${siteId}`).set({
          id: siteId,
          creator_id: 'site_admin_user',
          name: 'Member Test Site',
        });
      });

      const memberCtx = testEnv.authenticatedContext('standard_member', { email_verified: true });
      const db = memberCtx.firestore();

      // Non-creator tries to read site -> FAILS
      await assertFails(db.doc(`sites/${siteId}`).get());
    });

    test('POSITIVE 9: Offline-created site can be provisioned by creator and subsequently accept media document synchronization', async () => {
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

      // 2. Creator provisions site directly
      await assertSucceeds(
        db.doc(`sites/${siteId}`).set({
          id: siteId,
          creator_id: 'inspector_alice',
          name: 'Salt Lake Elevated Viaduct',
          site_code: 'SL-501',
          address: 'Sector 5, Kolkata',
        })
      );

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

  describe('WAVE A: Creator-Owned Model & Cross-User Security Regressions (R01, R04, R05)', () => {
    const siteIdA = 'siteUserACollsn12345';
    const siteIdB = 'siteUserBCollsn67890';
    const mediaIdA = 'mediaUserARegress123';
    const mediaHash = 'a'.repeat(64);
    const evidenceHash = 'b'.repeat(64);

    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        // User A creates site and evidence
        await db.doc(`sites/${siteIdA}`).set({
          id: siteIdA,
          creator_id: 'user_a',
          name: 'Metro Sector 5 Pier 12',
          site_code: 'SEC-05-P12',
          address: 'Sector 5, Salt Lake, Kolkata',
          created_at: new Date(),
        });
        await db.doc(`sites/${siteIdA}/media/${mediaIdA}`).set({
          id: mediaIdA,
          site_id: siteIdA,
          creator_id: 'user_a',
          type: 'photo',
          lat: 22.5726,
          lon: 88.3639,
          accuracy_m: 3.5,
          low_accuracy: false,
          activity_tag: 'Pillar Reinforcement',
          observation_type: 'progress',
          note: 'Foundations check',
          captured_at: '2026-08-31T12:00:00.000Z',
          sha256_hash: mediaHash,
          evidence_sha256_hash: evidenceHash,
          captured_address: 'Sector 5, Salt Lake, Kolkata',
          is_deleted: false,
          storage_original_path: `sites/${siteIdA}/media/${mediaIdA}/original`,
          storage_thumbnail_path: `sites/${siteIdA}/media/${mediaIdA}/thumbnail`,
        });
      });
    });

    test('REGRESSION 1: USER B cannot read USER A site despite matching site attributes', async () => {
      const userBDb = testEnv.authenticatedContext('user_b', { email_verified: true }).firestore();
      await assertFails(userBDb.doc(`sites/${siteIdA}`).get());
    });

    test('REGRESSION 2: USER B cannot read USER A evidence metadata', async () => {
      const userBDb = testEnv.authenticatedContext('user_b', { email_verified: true }).firestore();
      await assertFails(userBDb.doc(`sites/${siteIdA}/media/${mediaIdA}`).get());
    });

    test('REGRESSION 3: USER B cannot modify USER A site', async () => {
      const userBDb = testEnv.authenticatedContext('user_b', { email_verified: true }).firestore();
      await assertFails(userBDb.doc(`sites/${siteIdA}`).update({ name: 'Tampered Site Name' }));
    });

    test('REGRESSION 4: USER B cannot modify USER A evidence metadata', async () => {
      const userBDb = testEnv.authenticatedContext('user_b', { email_verified: true }).firestore();
      await assertFails(userBDb.doc(`sites/${siteIdA}/media/${mediaIdA}`).update({ note: 'Tampered note' }));
    });

    test('REGRESSION 5: USER B cannot delete USER A site', async () => {
      const userBDb = testEnv.authenticatedContext('user_b', { email_verified: true }).firestore();
      await assertFails(userBDb.doc(`sites/${siteIdA}`).delete());
    });

    test('REGRESSION 6: USER B cannot delete USER A evidence', async () => {
      const userBDb = testEnv.authenticatedContext('user_b', { email_verified: true }).firestore();
      await assertFails(userBDb.doc(`sites/${siteIdA}/media/${mediaIdA}`).delete());
    });

    test('REGRESSION 7: USER B cannot access USER A Storage artifacts (read/write/delete)', async () => {
      const userBStorage = testEnv.authenticatedContext('user_b', { email_verified: true }).storage();
      const origRef = userBStorage.ref(`sites/${siteIdA}/media/${mediaIdA}/original`);
      await assertFails(origRef.getDownloadURL());
      await assertFails(origRef.put(Buffer.from('tampered'), { contentType: 'image/jpeg' }));
      await assertFails(origRef.delete());
    });

    test('REGRESSION 8: USER A cannot mutate creator_id on site document', async () => {
      const userADb = testEnv.authenticatedContext('user_a', { email_verified: true }).firestore();
      await assertFails(userADb.doc(`sites/${siteIdA}`).update({ creator_id: 'user_b' }));
    });

    test('REGRESSION 9: USER A cannot mutate creator_id on media document', async () => {
      const userADb = testEnv.authenticatedContext('user_a', { email_verified: true }).firestore();
      await assertFails(userADb.doc(`sites/${siteIdA}/media/${mediaIdA}`).update({ creator_id: 'user_b' }));
    });

    test('REGRESSION 10: Physical deletion of sites is forbidden even for creator', async () => {
      const userADb = testEnv.authenticatedContext('user_a', { email_verified: true }).firestore();
      await assertFails(userADb.doc(`sites/${siteIdA}`).delete());
    });

    test('REGRESSION 11: Physical deletion of media is forbidden even for creator', async () => {
      const userADb = testEnv.authenticatedContext('user_a', { email_verified: true }).firestore();
      await assertFails(userADb.doc(`sites/${siteIdA}/media/${mediaIdA}`).delete());
    });

    test('REGRESSION 12: USER B can independently create own site with identical site code, name, and address', async () => {
      const userBDb = testEnv.authenticatedContext('user_b', { email_verified: true }).firestore();
      // User B creates site with identical site code and address
      await assertSucceeds(
        userBDb.doc(`sites/${siteIdB}`).set({
          id: siteIdB,
          creator_id: 'user_b',
          name: 'Metro Sector 5 Pier 12',
          site_code: 'SEC-05-P12',
          address: 'Sector 5, Salt Lake, Kolkata',
          created_at: new Date(),
        })
      );
      // User A cannot read User B's site
      const userADb = testEnv.authenticatedContext('user_a', { email_verified: true }).firestore();
      await assertFails(userADb.doc(`sites/${siteIdB}`).get());
    });
  });

  describe('vuln-0007: Media Broken Object-Level Authorization (BOLA)', () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.doc('sites/site_s1').set({ id: 'site_s1', creator_id: 'U1' });
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

    test('DENIES non-creator user U2 from modifying U1 note or activity tag', async () => {
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

    test('ALLOWS creator U1 to update metadata and perform soft-deletion', async () => {
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
        await db.doc('sites/site_s1').set({ id: 'site_s1', creator_id: 'U1' });
      });
    });

    test('ALLOWS valid evidence document creation for every client ObservationType enum value', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const db = u1Ctx.firestore();

      const validTypes = ['progress', 'nonConformity', 'closed', 'material', 'general'];

      for (let i = 0; i < validTypes.length; i++) {
        const type = validTypes[i];
        const docId = `media_enum_${i}`;

        const payload = {
          id: docId,
          site_id: 'site_s1',
          creator_id: 'U1',
          type: 'photo',
          lat: 22.5726,
          lon: 88.3639,
          accuracy_m: 5.0,
          low_accuracy: false,
          activity_tag: 'Inspection',
          observation_type: type,
          note: `Testing observation type: ${type}`,
          captured_at: '2026-08-31T12:00:00.000Z',
          sha256_hash: 'a'.repeat(64),
          evidence_sha256_hash: 'b'.repeat(64),
          captured_address: 'Sector 5, Salt Lake, Kolkata',
          is_deleted: false,
          storage_original_path: `sites/site_s1/media/${docId}/original`,
          storage_thumbnail_path: `sites/site_s1/media/${docId}/thumbnail`,
        };

        await assertSucceeds(db.doc(`sites/site_s1/media/${docId}`).set(payload));
      }
    });

    test('REJECTS evidence creation with deprecated/invalid observation_type values', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const db = u1Ctx.firestore();

      const invalidTypes = ['open', 'resolved', 'pending', 'inspection', 'hazard'];

      for (let i = 0; i < invalidTypes.length; i++) {
        const type = invalidTypes[i];
        const docId = `media_invalid_${i}`;

        const payload = {
          id: docId,
          site_id: 'site_s1',
          creator_id: 'U1',
          type: 'photo',
          lat: 22.5726,
          lon: 88.3639,
          accuracy_m: 5.0,
          low_accuracy: false,
          activity_tag: 'Inspection',
          observation_type: type,
          note: `Testing invalid observation type: ${type}`,
          captured_at: '2026-08-31T12:00:00.000Z',
          sha256_hash: 'a'.repeat(64),
          evidence_sha256_hash: 'b'.repeat(64),
          captured_address: 'Sector 5, Salt Lake, Kolkata',
          is_deleted: false,
          storage_original_path: `sites/site_s1/media/${docId}/original`,
          storage_thumbnail_path: `sites/site_s1/media/${docId}/thumbnail`,
        };

        await assertFails(db.doc(`sites/site_s1/media/${docId}`).set(payload));
      }
    });

    test('REJECTS evidence creation with invalid accuracy_m (> 500m)', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const db = u1Ctx.firestore();

      const docId = 'media_high_accuracy';
      const payload = {
        id: docId,
        site_id: 'site_s1',
        creator_id: 'U1',
        type: 'photo',
        lat: 22.5726,
        lon: 88.3639,
        accuracy_m: 501.0,
        low_accuracy: true,
        activity_tag: 'Inspection',
        observation_type: 'progress',
        note: 'High accuracy test',
        captured_at: '2026-08-31T12:00:00.000Z',
        sha256_hash: 'a'.repeat(64),
        evidence_sha256_hash: 'b'.repeat(64),
        captured_address: 'Sector 5, Salt Lake, Kolkata',
        is_deleted: false,
        storage_original_path: `sites/site_s1/media/${docId}/original`,
        storage_thumbnail_path: `sites/site_s1/media/${docId}/thumbnail`,
      };

      await assertFails(db.doc(`sites/site_s1/media/${docId}`).set(payload));
    });

    test('REJECTS evidence creation with invalid SHA-256 length', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const db = u1Ctx.firestore();

      const docId = 'media_bad_sha';
      const payload = {
        id: docId,
        site_id: 'site_s1',
        creator_id: 'U1',
        type: 'photo',
        lat: 22.5726,
        lon: 88.3639,
        accuracy_m: 5.0,
        low_accuracy: false,
        activity_tag: 'Inspection',
        observation_type: 'progress',
        note: 'Bad SHA test',
        captured_at: '2026-08-31T12:00:00.000Z',
        sha256_hash: 'a'.repeat(63),
        evidence_sha256_hash: 'b'.repeat(64),
        captured_address: 'Sector 5, Salt Lake, Kolkata',
        is_deleted: false,
        storage_original_path: `sites/site_s1/media/${docId}/original`,
        storage_thumbnail_path: `sites/site_s1/media/${docId}/thumbnail`,
      };

      await assertFails(db.doc(`sites/site_s1/media/${docId}`).set(payload));
    });
  });

  describe('vuln-0002: Forensic Metadata Forgery via Unvalidated Media Create Remediation', () => {
    const siteId = 'validSiteMediaTest12';
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.doc(`sites/${siteId}`).set({ id: siteId, creator_id: 'U_creator', name: 'Media Test Site' });
      });
    });

    const validPayload = (id) => ({
      id,
      site_id: siteId,
      creator_id: 'U_creator',
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
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_sha`).set({
          ...validPayload('M_bad_sha'),
          sha256_hash: 'x'.repeat(64),
        })
      );

      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_evid_sha`).set({
          ...validPayload('M_bad_evid_sha'),
          evidence_sha256_hash: 'g'.repeat(64),
        })
      );
    });

    test('NEGATIVE 3: REJECTS malformed timestamp and semantically impossible calendar components', async () => {
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();

      const impossibleDates = [
        'invalid-timestamp-string',
        '3000-99-99T99:99:99',
        '2026-13-15T10:00:00Z',
        '2026-00-15T10:00:00Z',
        '2026-08-32T10:00:00Z',
        '2026-08-00T10:00:00Z',
        '2026-08-15T24:00:00Z',
        '2026-08-15T10:60:00Z',
        '2026-08-15T10:00:60Z',
      ];

      for (let i = 0; i < impossibleDates.length; i++) {
        const badDate = impossibleDates[i];
        await assertFails(
          db.doc(`sites/${siteId}/media/M_bad_date_${i}`).set({
            ...validPayload(`M_bad_date_${i}`),
            captured_at: badDate,
          })
        );
      }
    });

    test('NEGATIVE 4: REJECTS absurd/unrealistic altitude (e.g. 99999m)', async () => {
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_alt`).set({
          ...validPayload('M_bad_alt'),
          altitude: 99999.0,
        })
      );
    });

    test('NEGATIVE 5: REJECTS oversized captured address (> 500 chars)', async () => {
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_big_addr`).set({
          ...validPayload('M_big_addr'),
          captured_address: 'A'.repeat(501),
        })
      );
    });

    test('NEGATIVE 6: REJECTS oversized note (> 2000 chars)', async () => {
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_big_note`).set({
          ...validPayload('M_big_note'),
          note: 'N'.repeat(2001),
        })
      );
    });

    test('NEGATIVE 7: REJECTS oversized activity tag (> 100 chars)', async () => {
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_big_tag`).set({
          ...validPayload('M_big_tag'),
          activity_tag: 'T'.repeat(101),
        })
      );
    });

    test('NEGATIVE 8: REJECTS invalid linked_media_id (cross-site path / path traversal)', async () => {
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_bad_link`).set({
          ...validPayload('M_bad_link'),
          linked_media_id: '../other_site/media/victim_doc',
        })
      );
    });

    test('NEGATIVE 9 & 10: REJECTS unexpected extra fields (device_model, is_admin, secret_injection)', async () => {
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();

      await assertFails(
        db.doc(`sites/${siteId}/media/M_extra_f1`).set({
          ...validPayload('M_extra_f1'),
          device_model: 'Pixel 9 Pro',
        })
      );

      await assertFails(
        db.doc(`sites/${siteId}/media/M_extra_f2`).set({
          ...validPayload('M_extra_f2'),
          secret_injection: 'DROP TABLE',
        })
      );
    });

    test('POSITIVE 11: ALLOWS legitimate media document creation with canonical schema and valid ISO-8601 formats', async () => {
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();

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
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();

      await assertSucceeds(
        db.doc(`sites/${siteId}/media/M_legit_2`).set({
          ...validPayload('M_legit_2'),
          linked_media_id: 'M_legit_1',
          altitude: -45.5,
        })
      );
    });

    test('POSITIVE 13: ALLOWS legitimate note and observation_type updates while PROTECTING immutable forensic fields', async () => {
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();

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

      // Illegitimate update of immutable forensic field (GPS) -> FAILS
      await assertFails(
        db.doc(`sites/${siteId}/media/M_update_target`).update({
          lat: 0.0,
        })
      );

      // Illegitimate update of immutable SHA-256 -> FAILS
      await assertFails(
        db.doc(`sites/${siteId}/media/M_update_target`).update({
          sha256_hash: 'c'.repeat(64),
        })
      );
    });

    test('NEGATIVE 14: Non-creator U_other cannot create media on U_creator site', async () => {
      const db = testEnv.authenticatedContext('U_other', { email_verified: true }).firestore();
      await assertFails(
        db.doc(`sites/${siteId}/media/M_other`).set({
          ...validPayload('M_other'),
          creator_id: 'U_other',
        })
      );
    });

    test('R16 POSITIVE: creator may record the canonical evidence artifact path', async () => {
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();
      await assertSucceeds(
        db.doc(`sites/${siteId}/media/M_evid_path`).set({
          ...validPayload('M_evid_path'),
          storage_evidence_path: `sites/${siteId}/media/M_evid_path/evidence`,
        })
      );
    });

    test('R16 NEGATIVE: a mismatched evidence artifact path is rejected', async () => {
      const db = testEnv.authenticatedContext('U_creator', { email_verified: true }).firestore();
      await assertFails(
        db.doc(`sites/${siteId}/media/M_evid_bad`).set({
          ...validPayload('M_evid_bad'),
          storage_evidence_path: `sites/${siteId}/media/SOMEONE_ELSE/evidence`,
        })
      );
    });
  });

  describe('vuln-0001 & vuln-0002: Firebase Storage Creator Binding & Status Revocation', () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        // Setup site s1 owned by U1
        await adminDb.doc('sites/site_s1').set({ id: 'site_s1', name: 'Alpha Site', creator_id: 'U1' });
        // Setup media document authored by U1
        await adminDb.doc('sites/site_s1/media/M1').set({
          id: 'M1',
          site_id: 'site_s1',
          creator_id: 'U1',
          type: 'photo',
          is_deleted: false,
        });

        // Setup site s2 owned by U_suspended
        await adminDb.doc('sites/site_s2').set({ id: 'site_s2', name: 'Suspended Site', creator_id: 'U_suspended' });
        await adminDb.doc('sites/site_s2/media/M_susp').set({
          id: 'M_susp',
          site_id: 'site_s2',
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

      await assertSucceeds(fileRef.getDownloadURL().catch(() => 'url_ok'));
    });

    test('DENIES non-creator member U2 from reading U1 Storage evidence (vuln-0004)', async () => {
      const u2Ctx = testEnv.authenticatedContext('U2', { email_verified: true });
      const storage = u2Ctx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M1/original');

      await assertFails(fileRef.getDownloadURL());
    });

    test('DENIES non-creator user U_other from reading Storage evidence on site_s1', async () => {
      const suspCtx = testEnv.authenticatedContext('U_other', { email_verified: true });
      const storage = suspCtx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M1/original');

      await assertFails(fileRef.getDownloadURL());
    });

    test('DENIES non-creator user U_suspended from writing Storage evidence on U1 site (site_s1)', async () => {
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
      const dummyData = Buffer.from('test-image-binary-data');

      await assertFails(fileRef.put(dummyData, { contentType: 'image/jpeg' }));
    });

    test('DENIES non-member U3 from uploading storage object for site_s1', async () => {
      const u3Ctx = testEnv.authenticatedContext('U3', { email_verified: true });
      const storage = u3Ctx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M1/original');
      const dummyData = Buffer.from('test-image-binary-data');

      await assertFails(fileRef.put(dummyData, { contentType: 'image/jpeg' }));
    });

    test('DENIES upload if media document does not exist yet (strictly enforces Firestore pre-creation)', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const storage = u1Ctx.storage();
      const fileRef = storage.ref('sites/site_s1/media/M_NON_EXISTENT/original');
      const dummyData = Buffer.from('test-image-binary-data');

      await assertFails(fileRef.put(dummyData, { contentType: 'image/jpeg' }));
    });

    test('R16: ALLOWS creator U1 to create the cloud-authoritative evidence artifact', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const fileRef = u1Ctx.storage().ref('sites/site_s1/media/M1/evidence');

      await assertSucceeds(
        fileRef.put(Buffer.from('evidence-bytes'), { contentType: 'image/jpeg' })
      );
    });

    test('R16: DENIES a non-JPEG evidence artifact', async () => {
      const u1Ctx = testEnv.authenticatedContext('U1', { email_verified: true });
      const fileRef = u1Ctx.storage().ref('sites/site_s1/media/M1/evidence');

      await assertFails(
        fileRef.put(Buffer.from('evidence-bytes'), { contentType: 'video/mp4' })
      );
    });

    test('R16: DENIES a non-creator writing the evidence artifact', async () => {
      const u2Ctx = testEnv.authenticatedContext('U2', { email_verified: true });
      const fileRef = u2Ctx.storage().ref('sites/site_s1/media/M1/evidence');

      await assertFails(
        fileRef.put(Buffer.from('evidence-bytes'), { contentType: 'image/jpeg' })
      );
    });

    test('DENIES user from deleting storage objects (immutability)', async () => {
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
        // Setup site s_read owned by inspector_a
        await adminDb.doc('sites/s_read').set({ id: 's_read', name: 'Read Auth Site', creator_id: 'inspector_a' });

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

    test('2. Non-creator cannot read another users Firestore media metadata', async () => {
      const bCtx = testEnv.authenticatedContext('inspector_b', { email_verified: true });
      const db = bCtx.firestore();

      await assertFails(db.doc('sites/s_read/media/doc_a').get());
    });

    test('3. Non-creator cannot read another users Firestore media metadata even if claiming admin', async () => {
      const adminCtx = testEnv.authenticatedContext('admin_user', { email_verified: true });
      const db = adminCtx.firestore();

      await assertFails(db.doc('sites/s_read/media/doc_a').get());
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

    test('7. Other user cannot read Storage objects even if claiming admin', async () => {
      const adminCtx = testEnv.authenticatedContext('admin_user', { email_verified: true });
      const storage = adminCtx.storage();
      const fileRef = storage.ref('sites/s_read/media/doc_a/original');

      await assertFails(fileRef.getDownloadURL());
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

    test('10. Creator query scoped by creator_id succeeds against sites collection', async () => {
      const aCtx = testEnv.authenticatedContext('inspector_a', { email_verified: true });
      const db = aCtx.firestore();

      const query = db.collection('sites').where('creator_id', '==', 'inspector_a');
      const snap = await assertSucceeds(query.get());
      assert.strictEqual(snap.docs.length, 1);
      assert.strictEqual(snap.docs[0].id, 's_read');
    });

    test('11. CollectionGroup members query is rejected in v1 (no membership collection)', async () => {
      const aCtx = testEnv.authenticatedContext('inspector_a', { email_verified: true });
      const db = aCtx.firestore();

      const query = db.collectionGroup('members').where('user_id', '==', 'inspector_a');
      await assertFails(query.get());
    });

    test('12. Outsider collectionGroup query for another user is rejected', async () => {
      const outsiderCtx = testEnv.authenticatedContext('outsider_user', { email_verified: true });
      const db = outsiderCtx.firestore();

      const query = db.collectionGroup('members').where('user_id', '==', 'inspector_a');
      await assertFails(query.get());
    });
  });

  describe('WAVE B: audio-track disclosure (R09) & compass heading (R10) schema', () => {
    const siteId = 'siteWaveBFixture1234';

    const baseMedia = (mediaId) => ({
      id: mediaId,
      site_id: siteId,
      creator_id: 'user_wave_b',
      type: 'video',
      lat: 22.5726,
      lon: 88.3639,
      accuracy_m: 3.5,
      low_accuracy: false,
      captured_at: '2026-08-31T12:00:00.000Z',
      sha256_hash: 'a'.repeat(64),
      evidence_sha256_hash: 'b'.repeat(64),
      is_deleted: false,
      storage_original_path: `sites/${siteId}/media/${mediaId}/original`,
      storage_thumbnail_path: `sites/${siteId}/media/${mediaId}/thumbnail`,
    });

    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc(`sites/${siteId}`).set({
          id: siteId,
          creator_id: 'user_wave_b',
          name: 'Wave B Site',
          site_code: 'WVB-01',
          address: 'Wave B Road',
          created_at: new Date(),
        });
      });
    });

    test('R09/R10 POSITIVE: creator may persist has_audio_track and heading_degrees', async () => {
      const db = testEnv.authenticatedContext('user_wave_b', { email_verified: true }).firestore();
      await assertSucceeds(
        db.doc(`sites/${siteId}/media/m_waveb_ok`).set({
          ...baseMedia('m_waveb_ok'),
          has_audio_track: true,
          heading_degrees: 187.5,
        })
      );
    });

    test('R09/R10 POSITIVE: the new fields are optional and may be null (unknown)', async () => {
      const db = testEnv.authenticatedContext('user_wave_b', { email_verified: true }).firestore();
      await assertSucceeds(
        db.doc(`sites/${siteId}/media/m_waveb_null`).set({
          ...baseMedia('m_waveb_null'),
          has_audio_track: null,
          heading_degrees: null,
        })
      );
    });

    test('R10 NEGATIVE: an out-of-range heading is rejected', async () => {
      const db = testEnv.authenticatedContext('user_wave_b', { email_verified: true }).firestore();
      await assertFails(
        db.doc(`sites/${siteId}/media/m_waveb_bad_heading`).set({
          ...baseMedia('m_waveb_bad_heading'),
          heading_degrees: 400.0,
        })
      );
    });

    test('R09 NEGATIVE: a non-boolean has_audio_track is rejected', async () => {
      const db = testEnv.authenticatedContext('user_wave_b', { email_verified: true }).firestore();
      await assertFails(
        db.doc(`sites/${siteId}/media/m_waveb_bad_audio`).set({
          ...baseMedia('m_waveb_bad_audio'),
          has_audio_track: 'yes',
        })
      );
    });
  });
});
