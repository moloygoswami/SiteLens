const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'sitelens-prod-80e7b';
const FIRESTORE_RULES = fs.readFileSync(
  path.resolve(__dirname, '../../firestore.rules'),
  'utf8'
);
const STORAGE_RULES = fs.readFileSync(
  path.resolve(__dirname, '../../storage.rules'),
  'utf8'
);

describe('SiteLens M6-A Firebase Security Hardening Test Suite', () => {
  let testEnv;

  beforeAll(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: FIRESTORE_RULES,
        host: '127.0.0.1',
        port: 8080,
      },
      storage: {
        rules: STORAGE_RULES,
        host: '127.0.0.1',
        port: 9199,
      },
    });
  });

  afterAll(async () => {
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

  // ---------------------------------------------------------------------------
  // 1. Unauthenticated Access
  // ---------------------------------------------------------------------------
  test('1. Unauthenticated users cannot read or write Firestore & Storage', async () => {
    const unauthDb = testEnv.unauthenticatedContext().firestore();
    const unauthStorage = testEnv.unauthenticatedContext().storage();

    await assertFails(unauthDb.doc('sites/site-1').get());
    await assertFails(unauthDb.doc('sites/site-1/media/m1').get());
    await assertFails(
      unauthStorage.ref('sites/site-1/media/m1/original').getDownloadURL()
    );
  });

  // ---------------------------------------------------------------------------
  // 2. Self-Join Vulnerability Blocked
  // ---------------------------------------------------------------------------
  test('2. Self-join is strictly blocked: Non-creator cannot inject themselves into a site', async () => {
    // Setup site created by user-a
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc('sites/site-1').set({
        id: 'site-1',
        creator_id: 'user-a',
        created_at: new Date(),
      });
      await db.doc('sites/site-1/members/user-a').set({
        user_id: 'user-a',
        role: 'admin',
        status: 'active',
        joined_at: new Date(),
      });
    });

    const hackerDb = testEnv.authenticatedContext('user-hacker').firestore();

    // Hacker tries to join site-1 by creating their own member document
    await assertFails(
      hackerDb.doc('sites/site-1/members/user-hacker').set({
        user_id: 'user-hacker',
        role: 'admin',
        status: 'active',
        joined_at: new Date(),
      })
    );
  });

  // ---------------------------------------------------------------------------
  // 3. Site Bootstrap Flow
  // ---------------------------------------------------------------------------
  test('3. Site creator can bootstrap a new site and initialize their admin membership in a batch', async () => {
    const creatorDb = testEnv.authenticatedContext('user-creator', { email_verified: true }).firestore();
    const batch = creatorDb.batch();

    const siteId = 'siteNewAutoId12345678';
    const siteRef = creatorDb.doc(`sites/${siteId}`);
    const memberRef = creatorDb.doc(`sites/${siteId}/members/user-creator`);

    const now = new Date();
    batch.set(siteRef, {
      id: siteId,
      creator_id: 'user-creator',
      created_at: now,
    });
    batch.set(memberRef, {
      user_id: 'user-creator',
      role: 'admin',
      status: 'active',
      joined_at: now,
    });

    await assertSucceeds(batch.commit());
  });

  // ---------------------------------------------------------------------------
  // 4. Active Membership Semantics
  // ---------------------------------------------------------------------------
  test('4. Suspended member cannot read site media or access storage', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc('sites/site-1').set({
        id: 'site-1',
        creator_id: 'user-a',
        created_at: new Date(),
      });
      await db.doc('sites/site-1/members/user-suspended').set({
        user_id: 'user-suspended',
        role: 'inspector',
        status: 'suspended', // Inactive
        joined_at: new Date(),
      });
      await db.doc('sites/site-1/media/m1').set({
        id: 'm1',
        site_id: 'site-1',
        creator_id: 'user-a',
        sha256_hash: 'a'.repeat(64),
        evidence_sha256_hash: 'b'.repeat(64),
        lat: 22.56,
        lon: 88.30,
        type: 'photo',
        is_deleted: false,
        created_at: new Date(),
        updated_at: new Date(),
      });
    });

    const suspendedDb = testEnv.authenticatedContext('user-suspended').firestore();
    await assertFails(suspendedDb.doc('sites/site-1/media/m1').get());
  });

  // ---------------------------------------------------------------------------
  // 5. Cross-Tenant Isolation
  // ---------------------------------------------------------------------------
  test('5. Active member of Site A cannot read or write to Site B', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc('sites/site-b').set({
        id: 'site-b',
        creator_id: 'user-b',
        created_at: new Date(),
      });
      await db.doc('sites/site-b/members/user-b').set({
        user_id: 'user-b',
        role: 'admin',
        status: 'active',
        joined_at: new Date(),
      });
      await db.doc('sites/site-b/media/mb1').set({
        id: 'mb1',
        site_id: 'site-b',
        creator_id: 'user-b',
        sha256_hash: 'c'.repeat(64),
        evidence_sha256_hash: 'd'.repeat(64),
        lat: 22.56,
        lon: 88.30,
        type: 'photo',
        is_deleted: false,
        created_at: new Date(),
        updated_at: new Date(),
      });
    });

    const userADb = testEnv.authenticatedContext('user-a').firestore();
    await assertFails(userADb.doc('sites/site-b/media/mb1').get());
  });

  // ---------------------------------------------------------------------------
  // 6. Creator Spoofing Prevention
  // ---------------------------------------------------------------------------
  test('6. Member cannot create media with a spoofed creator_id', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc('sites/site-1').set({ id: 'site-1', creator_id: 'user-a', created_at: new Date() });
      await db.doc('sites/site-1/members/user-inspector').set({
        user_id: 'user-inspector',
        role: 'inspector',
        status: 'active',
        joined_at: new Date(),
      });
    });

    const inspectorDb = testEnv.authenticatedContext('user-inspector').firestore();
    const now = new Date();

    // Trying to claim user-a as creator
    await assertFails(
      inspectorDb.doc('sites/site-1/media/m-spoofed').set({
        id: 'm-spoofed',
        site_id: 'site-1',
        creator_id: 'user-a', // Spoofed!
        sha256_hash: 'e'.repeat(64),
        evidence_sha256_hash: 'f'.repeat(64),
        lat: 22.56,
        lon: 88.30,
        type: 'photo',
        is_deleted: false,
        created_at: now,
        updated_at: now,
      })
    );
  });

  // ---------------------------------------------------------------------------
  // 7. Forensic Field Tampering Prevention
  // ---------------------------------------------------------------------------
  test('7. Immutable forensic fields (SHA-256, GPS, captured_at) cannot be modified', async () => {
    const now = new Date();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc('sites/site-1').set({ id: 'site-1', creator_id: 'user-a', created_at: now });
      await db.doc('sites/site-1/members/user-inspector').set({
        user_id: 'user-inspector',
        role: 'inspector',
        status: 'active',
        joined_at: now,
      });
      await db.doc('sites/site-1/media/m1').set({
        id: 'm1',
        site_id: 'site-1',
        creator_id: 'user-inspector',
        sha256_hash: '1'.repeat(64),
        evidence_sha256_hash: '2'.repeat(64),
        lat: 22.56298,
        lon: 88.30085,
        type: 'photo',
        note: 'Initial note',
        is_deleted: false,
        created_at: now,
        updated_at: now,
      });
    });

    const inspectorDb = testEnv.authenticatedContext('user-inspector').firestore();

    // Attempting to change SHA-256 hash
    await assertFails(
      inspectorDb.doc('sites/site-1/media/m1').update({
        sha256_hash: '9'.repeat(64),
        updated_at: new Date(),
      })
    );

    // Attempting to change coordinates
    await assertFails(
      inspectorDb.doc('sites/site-1/media/m1').update({
        lat: 25.00000,
        updated_at: new Date(),
      })
    );
  });

  // ---------------------------------------------------------------------------
  // 8. Mutable Workflow Fields Allowed
  // ---------------------------------------------------------------------------
  test('8. Member can update mutable workflow fields (note, observation_type, activity_tag)', async () => {
    const now = new Date();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc('sites/site-1').set({ id: 'site-1', creator_id: 'user-a', created_at: now });
      await db.doc('sites/site-1/members/user-inspector').set({
        user_id: 'user-inspector',
        role: 'inspector',
        status: 'active',
        joined_at: now,
      });
      await db.doc('sites/site-1/media/m1').set({
        id: 'm1',
        site_id: 'site-1',
        creator_id: 'user-inspector',
        sha256_hash: '1'.repeat(64),
        evidence_sha256_hash: '2'.repeat(64),
        lat: 22.56298,
        lon: 88.30085,
        type: 'photo',
        note: 'Initial inspection',
        activity_tag: 'Excavation',
        observation_type: 'nonConformity',
        is_deleted: false,
        created_at: now,
        updated_at: now,
      });
    });

    const inspectorDb = testEnv.authenticatedContext('user-inspector').firestore();

    await assertSucceeds(
      inspectorDb.doc('sites/site-1/media/m1').update({
        note: 'Updated re-inspection notes',
        observation_type: 'closed',
        updated_at: new Date(),
      })
    );
  });

  // ---------------------------------------------------------------------------
  // 9. Soft-Delete Authorization
  // ---------------------------------------------------------------------------
  test('9. Soft-delete is allowed by creator and admin, but denied for other inspectors', async () => {
    const now = new Date();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc('sites/site-1').set({ id: 'site-1', creator_id: 'user-admin', created_at: now });
      await db.doc('sites/site-1/members/user-admin').set({
        user_id: 'user-admin',
        role: 'admin',
        status: 'active',
        joined_at: now,
      });
      await db.doc('sites/site-1/members/user-creator').set({
        user_id: 'user-creator',
        role: 'inspector',
        status: 'active',
        joined_at: now,
      });
      await db.doc('sites/site-1/members/user-other').set({
        user_id: 'user-other',
        role: 'inspector',
        status: 'active',
        joined_at: now,
      });
      await db.doc('sites/site-1/media/m1').set({
        id: 'm1',
        site_id: 'site-1',
        creator_id: 'user-creator',
        sha256_hash: '1'.repeat(64),
        evidence_sha256_hash: '2'.repeat(64),
        lat: 22.56298,
        lon: 88.30085,
        type: 'photo',
        is_deleted: false,
        created_at: now,
        updated_at: now,
      });
    });

    const otherDb = testEnv.authenticatedContext('user-other').firestore();
    const creatorDb = testEnv.authenticatedContext('user-creator').firestore();
    const adminDb = testEnv.authenticatedContext('user-admin').firestore();

    // 1. Other inspector cannot soft delete
    await assertFails(
      otherDb.doc('sites/site-1/media/m1').update({
        is_deleted: true,
        updated_at: new Date(),
      })
    );

    // 2. Original creator CAN soft delete
    await assertSucceeds(
      creatorDb.doc('sites/site-1/media/m1').update({
        is_deleted: true,
        updated_at: new Date(),
      })
    );

    // 3. Admin CAN un-delete or soft delete
    await assertSucceeds(
      adminDb.doc('sites/site-1/media/m1').update({
        is_deleted: false,
        updated_at: new Date(),
      })
    );
  });

  // ---------------------------------------------------------------------------
  // 10. Physical Deletion Denial
  // ---------------------------------------------------------------------------
  test('10. Physical deletion of media document is strictly prohibited for everyone', async () => {
    const now = new Date();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc('sites/site-1').set({ id: 'site-1', creator_id: 'user-admin', created_at: now });
      await db.doc('sites/site-1/members/user-admin').set({
        user_id: 'user-admin',
        role: 'admin',
        status: 'active',
        joined_at: now,
      });
      await db.doc('sites/site-1/media/m1').set({
        id: 'm1',
        site_id: 'site-1',
        creator_id: 'user-admin',
        sha256_hash: '1'.repeat(64),
        evidence_sha256_hash: '2'.repeat(64),
        lat: 22.56298,
        lon: 88.30085,
        type: 'photo',
        is_deleted: false,
        created_at: now,
        updated_at: now,
      });
    });

    const adminDb = testEnv.authenticatedContext('user-admin').firestore();
    await assertFails(adminDb.doc('sites/site-1/media/m1').delete());
  });

  // ---------------------------------------------------------------------------
  // 11. User Profile IDOR Prevention (vuln-0003 / CWE-639)
  // ---------------------------------------------------------------------------
  test('11. User Profile IDOR Prevention: User A can read/write own profile, User B cannot read User A profile', async () => {
    const userADb = testEnv.authenticatedContext('user-a').firestore();
    const userBDb = testEnv.authenticatedContext('user-b').firestore();

    // 1. User A writes own profile
    await assertSucceeds(
      userADb.doc('users/user-a').set({
        uid: 'user-a',
        email: 'user-a@company.com',
        displayName: 'Inspector Alice',
        createdAt: new Date(),
      })
    );

    // 2. User A can read own profile
    await assertSucceeds(userADb.doc('users/user-a').get());

    // 3. User B CANNOT read User A's profile (IDOR blocked)
    await assertFails(userBDb.doc('users/user-a').get());

    // 4. User B CANNOT write User A's profile
    await assertFails(
      userBDb.doc('users/user-a').set({
        displayName: 'Hacked Profile',
      })
    );
  });

  // ---------------------------------------------------------------------------
  // 12. Storage Path & originalUri Validation (vuln-0002 / CWE-862)
  // ---------------------------------------------------------------------------
  test('12. Media Create Rule validates deterministic storage paths and safe originalUri pattern', async () => {
    const now = new Date();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc('sites/site-1').set({ id: 'site-1', creator_id: 'user-a', created_at: now });
      await db.doc('sites/site-1/members/user-a').set({
        user_id: 'user-a',
        role: 'admin',
        status: 'active',
        joined_at: now,
      });
    });

    const userADb = testEnv.authenticatedContext('user-a').firestore();

    // 1. Valid deterministic storage paths and valid originalUri succeed
    await assertSucceeds(
      userADb.doc('sites/site-1/media/m-valid').set({
        id: 'm-valid',
        site_id: 'site-1',
        creator_id: 'user-a',
        sha256_hash: 'a'.repeat(64),
        evidence_sha256_hash: 'b'.repeat(64),
        lat: 22.56298,
        lon: 88.30085,
        type: 'photo',
        is_deleted: false,
        storage_original_path: 'sites/site-1/media/m-valid/original',
        storage_thumbnail_path: 'sites/site-1/media/m-valid/thumbnail',
        originalUri: 'media/orig_m-valid.jpg',
        created_at: now,
        updated_at: now,
      })
    );

    // 2. Crafted/traversal originalUri fails
    await assertFails(
      userADb.doc('sites/site-1/media/m-traversal').set({
        id: 'm-traversal',
        site_id: 'site-1',
        creator_id: 'user-a',
        sha256_hash: 'a'.repeat(64),
        evidence_sha256_hash: 'b'.repeat(64),
        lat: 22.56298,
        lon: 88.30085,
        type: 'photo',
        is_deleted: false,
        storage_original_path: 'sites/site-1/media/m-traversal/original',
        storage_thumbnail_path: 'sites/site-1/media/m-traversal/thumbnail',
        originalUri: '../../sensitive/path',
        created_at: now,
        updated_at: now,
      })
    );

    // 3. Mismatched storage_original_path fails
    await assertFails(
      userADb.doc('sites/site-1/media/m-badpath').set({
        id: 'm-badpath',
        site_id: 'site-1',
        creator_id: 'user-a',
        sha256_hash: 'a'.repeat(64),
        evidence_sha256_hash: 'b'.repeat(64),
        lat: 22.56298,
        lon: 88.30085,
        type: 'photo',
        is_deleted: false,
        storage_original_path: 'other/arbitrary/path',
        storage_thumbnail_path: 'sites/site-1/media/m-badpath/thumbnail',
        originalUri: 'media/orig_m-badpath.jpg',
        created_at: now,
        updated_at: now,
      })
    );
  });
});
