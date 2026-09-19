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

describe('SiteLens Milestone M6-B Firebase Emulator Synchronization E2E Suite', () => {
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

  async function seedSiteAndMembers() {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      // 1. Create site
      await db.doc('sites/site-alpha').set({
        id: 'site-alpha',
        name: 'Metro Line Sector 4',
        site_code: 'SEC-04',
        creator_id: 'engineer-bob',
        created_at: new Date(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // 1. Creator Site Authorization
  // ---------------------------------------------------------------------------
  test('1. Creator authorization: Creator can sync, non-creator is blocked', async () => {
    await seedSiteAndMembers();

    const bobDb = testEnv.authenticatedContext('engineer-bob', { email_verified: true }).firestore();
    const revokedDb = testEnv.authenticatedContext('revoked-alice', { email_verified: true }).firestore();
    const outsiderDb = testEnv.authenticatedContext('outsider-charlie', { email_verified: true }).firestore();

    // Creator can read site
    await assertSucceeds(bobDb.doc('sites/site-alpha').get());

    // Non-creator blocked
    await assertFails(revokedDb.doc('sites/site-alpha').get());
    await assertFails(
      revokedDb.doc('sites/site-alpha/media/m-revoked').set({
        id: 'm-revoked',
        site_id: 'site-alpha',
        creator_id: 'revoked-alice',
        type: 'photo',
        lat: 22.57,
        lon: 88.36,
        captured_at: new Date(),
        sha256_hash: 'a'.repeat(64),
        evidence_sha256_hash: 'b'.repeat(64),
        is_deleted: false,
        synced_at: new Date(),
      })
    );

    // Non-member outsider blocked
    await assertFails(outsiderDb.doc('sites/site-alpha').get());
  });

  // ---------------------------------------------------------------------------
  // 2. Creator Authorization
  // ---------------------------------------------------------------------------
  test('2. Creator authorization: Evidence creator_id must strictly match auth.uid', async () => {
    await seedSiteAndMembers();

    const bobDb = testEnv.authenticatedContext('engineer-bob', { email_verified: true }).firestore();

    // Bob creates evidence claiming he is the creator -> SUCCEEDS
    await assertSucceeds(
      bobDb.doc('sites/site-alpha/media/m-bob-1').set({
        id: 'm-bob-1',
        site_id: 'site-alpha',
        creator_id: 'engineer-bob',
        type: 'photo',
        lat: 22.5726,
        lon: 88.3639,
        accuracy_m: 4.2,
        low_accuracy: false,
        captured_at: new Date().toISOString(),
        sha256_hash: '1'.repeat(64),
        evidence_sha256_hash: '2'.repeat(64),
        is_deleted: false,
        storage_original_path: 'sites/site-alpha/media/m-bob-1/original',
        storage_thumbnail_path: 'sites/site-alpha/media/m-bob-1/thumbnail',
      })
    );

    // Bob tries to create evidence attributing creator_id to admin-user -> FAILS
    await assertFails(
      bobDb.doc('sites/site-alpha/media/m-impersonate').set({
        id: 'm-impersonate',
        site_id: 'site-alpha',
        creator_id: 'admin-user', // Impersonation!
        type: 'photo',
        lat: 22.5726,
        lon: 88.3639,
        low_accuracy: false,
        captured_at: new Date().toISOString(),
        sha256_hash: '1'.repeat(64),
        evidence_sha256_hash: '2'.repeat(64),
        is_deleted: false,
        storage_original_path: 'sites/site-alpha/media/m-impersonate/original',
        storage_thumbnail_path: 'sites/site-alpha/media/m-impersonate/thumbnail',
      })
    );
  });

  // ---------------------------------------------------------------------------
  // 3. Full 3-Tier Synchronization (Storage Original + Storage Thumbnail + Firestore Doc)
  // ---------------------------------------------------------------------------
  test('3. Full 3-tier sync pipeline: Uploads original, thumbnail, and creates Firestore document', async () => {
    await seedSiteAndMembers();

    const bobStorage = testEnv.authenticatedContext('engineer-bob', { email_verified: true }).storage();
    const bobDb = testEnv.authenticatedContext('engineer-bob', { email_verified: true }).firestore();

    const origHash = 'a1b2c3d4e5f6'.padEnd(64, '0');
    const thumbHash = 'f6e5d4c3b2a1'.padEnd(64, '0');

    // Step A: Firestore ledger document first — Storage rules require the
    // media document to exist with a matching creator_id before artifacts
    // may be written (ledger document is published before artifact uploads).
    const mediaDocRef = bobDb.doc('sites/site-alpha/media/m-full-1');
    await assertSucceeds(
      mediaDocRef.set({
        id: 'm-full-1',
        site_id: 'site-alpha',
        creator_id: 'engineer-bob',
        type: 'photo',
        lat: 22.5726,
        lon: 88.3639,
        accuracy_m: 3.5,
        low_accuracy: false,
        captured_at: new Date().toISOString(),
        sha256_hash: origHash,
        evidence_sha256_hash: 'e'.repeat(64),
        activity_tag: 'Reinforcement Inspection',
        observation_type: 'general',
        note: 'Pillar 4B initial alignment',
        is_deleted: false,
        storage_original_path: 'sites/site-alpha/media/m-full-1/original',
        storage_thumbnail_path: 'sites/site-alpha/media/m-full-1/thumbnail',
      })
    );

    // Step B: Storage Original Upload
    const origRef = bobStorage.ref('sites/site-alpha/media/m-full-1/original');
    const dummyImageBytes = Buffer.from('fake-jpeg-raw-bytes');
    await assertSucceeds(
      origRef.put(dummyImageBytes, {
        contentType: 'image/jpeg',
        customMetadata: {
          'x-sitelens-original-sha256': origHash,
        },
      })
    );

    // Step C: Storage Thumbnail Upload
    const thumbRef = bobStorage.ref('sites/site-alpha/media/m-full-1/thumbnail');
    const dummyThumbBytes = Buffer.from('fake-jpeg-thumb-bytes');
    await assertSucceeds(
      thumbRef.put(dummyThumbBytes, {
        contentType: 'image/jpeg',
        customMetadata: {
          'x-sitelens-thumbnail-sha256': thumbHash,
        },
      })
    );

    const docSnapshot = await mediaDocRef.get();
    expect(docSnapshot.exists).toBe(true);
    expect(docSnapshot.data().activity_tag).toBe('Reinforcement Inspection');
  });

  // ---------------------------------------------------------------------------
  // 4. Storage Hash Verification & Idempotency
  // ---------------------------------------------------------------------------
  test('4. Storage hash idempotency: Existing artifacts can be inspected for hash matching', async () => {
    await seedSiteAndMembers();

    const origHash = 'hash-match-123'.padEnd(64, '0');
    const thumbHash = 'thumb-match-456'.padEnd(64, '0');

    // Ledger document must exist before artifacts may be written.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('sites/site-alpha/media/m-idempotent').set({
        id: 'm-idempotent',
        site_id: 'site-alpha',
        creator_id: 'engineer-bob',
        type: 'photo',
        lat: 22.57,
        lon: 88.36,
        low_accuracy: false,
        captured_at: new Date().toISOString(),
        sha256_hash: origHash,
        evidence_sha256_hash: 'b'.repeat(64),
        is_deleted: false,
        storage_original_path: 'sites/site-alpha/media/m-idempotent/original',
        storage_thumbnail_path: 'sites/site-alpha/media/m-idempotent/thumbnail',
      });
    });

    const bobStorage = testEnv.authenticatedContext('engineer-bob', { email_verified: true }).storage();

    // 1. Initial upload creates the storage object
    await assertSucceeds(
      bobStorage.ref('sites/site-alpha/media/m-idempotent/original').put(
        Buffer.from('existing-orig-bytes'),
        {
          contentType: 'image/jpeg',
          customMetadata: { 'x-sitelens-original-sha256': origHash },
        }
      )
    );
    await assertSucceeds(
      bobStorage.ref('sites/site-alpha/media/m-idempotent/thumbnail').put(
        Buffer.from('existing-thumb-bytes'),
        {
          contentType: 'image/jpeg',
          customMetadata: { 'x-sitelens-thumbnail-sha256': thumbHash },
        }
      )
    );

    // 2. Active member can fetch metadata to verify SHA-256 hashes
    const origMeta = await assertSucceeds(
      bobStorage.ref('sites/site-alpha/media/m-idempotent/original').getMetadata()
    );
    expect(origMeta.customMetadata['x-sitelens-original-sha256']).toBe(origHash);

    const thumbMeta = await assertSucceeds(
      bobStorage.ref('sites/site-alpha/media/m-idempotent/thumbnail').getMetadata()
    );
    expect(thumbMeta.customMetadata['x-sitelens-thumbnail-sha256']).toBe(thumbHash);

    // 3. Modifying existing storage artifact metadata is strictly blocked (Immutability: allow update: if false)
    await assertFails(
      bobStorage.ref('sites/site-alpha/media/m-idempotent/original').updateMetadata({
        customMetadata: { 'x-sitelens-original-sha256': 'tampered-hash' },
      })
    );

    // 4. Physical deletion of storage artifact is strictly blocked (allow delete: if false)
    await assertFails(
      bobStorage.ref('sites/site-alpha/media/m-idempotent/original').delete()
    );
  });

  // ---------------------------------------------------------------------------
  // 5. Partial-Upload Recovery Matrix
  // ---------------------------------------------------------------------------
  test('5. Partial-upload recovery: Recovers cleanly from original-only or original+thumb states', async () => {
    await seedSiteAndMembers();

    const origHash = 'orig-partial-hash'.padEnd(64, '0');
    const thumbHash = 'thumb-partial-hash'.padEnd(64, '0');

    // Seed the ledger document + original only (simulating a crash before the
    // thumbnail upload). Storage rules require the media document to exist
    // with a matching creator_id before artifacts may be written.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('sites/site-alpha/media/m-partial-1').set({
        id: 'm-partial-1',
        site_id: 'site-alpha',
        creator_id: 'engineer-bob',
        type: 'photo',
        lat: 22.57,
        lon: 88.36,
        low_accuracy: false,
        captured_at: new Date().toISOString(),
        sha256_hash: origHash,
        evidence_sha256_hash: 'b'.repeat(64),
        is_deleted: false,
        storage_original_path: 'sites/site-alpha/media/m-partial-1/original',
        storage_thumbnail_path: 'sites/site-alpha/media/m-partial-1/thumbnail',
      });
      const storage = context.storage();
      await storage.ref('sites/site-alpha/media/m-partial-1/original').put(
        Buffer.from('raw-orig-bytes'),
        {
          contentType: 'image/jpeg',
          customMetadata: { 'x-sitelens-original-sha256': origHash },
        }
      );
    });

    const bobStorage = testEnv.authenticatedContext('engineer-bob', { email_verified: true }).storage();
    const bobDb = testEnv.authenticatedContext('engineer-bob', { email_verified: true }).firestore();

    // Step 1: Recovery inspects original metadata -> matches -> skips original upload
    const origMeta = await assertSucceeds(
      bobStorage.ref('sites/site-alpha/media/m-partial-1/original').getMetadata()
    );
    expect(origMeta.customMetadata['x-sitelens-original-sha256']).toBe(origHash);

    // Step 2: Uploads missing thumbnail
    await assertSucceeds(
      bobStorage.ref('sites/site-alpha/media/m-partial-1/thumbnail').put(
        Buffer.from('thumb-bytes'),
        {
          contentType: 'image/jpeg',
          customMetadata: { 'x-sitelens-thumbnail-sha256': thumbHash },
        }
      )
    );

    // Step 3: Ledger document remains present after recovery
    const recovered = await assertSucceeds(
      bobDb.doc('sites/site-alpha/media/m-partial-1').get()
    );
    expect(recovered.exists).toBe(true);
  });

  // ---------------------------------------------------------------------------
  // 6. Firestore Document Create / Update / Conflict Semantics
  // ---------------------------------------------------------------------------
  test('6. Firestore metadata update vs forensic immutability conflict', async () => {
    await seedSiteAndMembers();

    const origHash = 'orig-doc-hash'.padEnd(64, '0');
    const evidHash = 'evid-doc-hash'.padEnd(64, '0');

    // Seed existing synced evidence document
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc('sites/site-alpha/media/m-existing').set({
        id: 'm-existing',
        site_id: 'site-alpha',
        creator_id: 'engineer-bob',
        type: 'photo',
        lat: 22.5726,
        lon: 88.3639,
        accuracy_m: 4.0,
        low_accuracy: false,
        captured_at: new Date('2026-08-15T10:00:00Z'),
        sha256_hash: origHash,
        evidence_sha256_hash: evidHash,
        activity_tag: 'Excavation',
        observation_type: 'general',
        note: 'Original note',
        is_deleted: false,
        synced_at: new Date(),
      });
    });

    const bobDb = testEnv.authenticatedContext('engineer-bob', { email_verified: true }).firestore();

    // A. Updating mutable fields (note, tag, observation_type) -> SUCCEEDS
    await assertSucceeds(
      bobDb.doc('sites/site-alpha/media/m-existing').update({
        note: 'Updated note after structural review',
        activity_tag: 'Foundation Inspection',
        observation_type: 'nonConformity',
      })
    );

    // B. Attempting to modify immutable forensic fields (sha256_hash, gps, creator_id, captured_at) -> FAILS
    await assertFails(
      bobDb.doc('sites/site-alpha/media/m-existing').update({
        sha256_hash: 'tampered-hash'.padEnd(64, '0'),
      })
    );
    await assertFails(
      bobDb.doc('sites/site-alpha/media/m-existing').update({
        lat: 10.0000,
        lon: 20.0000,
      })
    );
    await assertFails(
      bobDb.doc('sites/site-alpha/media/m-existing').update({
        creator_id: 'outsider-hacker',
      })
    );
  });

  // ---------------------------------------------------------------------------
  // 7. Soft-Delete Synchronization
  // ---------------------------------------------------------------------------
  test('7. Soft-delete synchronization: is_deleted can be set to true, physical delete is forbidden', async () => {
    await seedSiteAndMembers();

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc('sites/site-alpha/media/m-to-delete').set({
        id: 'm-to-delete',
        site_id: 'site-alpha',
        creator_id: 'engineer-bob',
        type: 'photo',
        lat: 22.57,
        lon: 88.36,
        captured_at: new Date(),
        sha256_hash: '1'.repeat(64),
        evidence_sha256_hash: '2'.repeat(64),
        is_deleted: false,
        synced_at: new Date(),
      });
    });

    const bobDb = testEnv.authenticatedContext('engineer-bob', { email_verified: true }).firestore();

    // Soft-delete: update is_deleted: true -> SUCCEEDS
    await assertSucceeds(
      bobDb.doc('sites/site-alpha/media/m-to-delete').update({
        is_deleted: true,
      })
    );

    // Hard physical deletion -> STRICTLY FAILS
    await assertFails(
      bobDb.doc('sites/site-alpha/media/m-to-delete').delete()
    );
  });
});
