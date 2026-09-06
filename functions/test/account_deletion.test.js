const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert');
const { handleDeleteUserAccount } = require('../index.js');

/**
 * In-memory Mock Firestore with subcollections and collectionGroup support for deletion tests.
 */
class MockDeletionFirestore {
  constructor() {
    this.sites = new Map(); // siteId -> { data: {}, members: Map(userId -> data), media: Map(mediaId -> data) }
    this.users = new Map(); // userId -> data
    this.enquiries = new Map(); // enqId -> data
    this.rateLimits = new Map(); // rlId -> data
  }

  collection(name) {
    if (name === 'sites') {
      return {
        where: (field, op, val) => ({
          get: async () => {
            const docs = [];
            for (const [id, site] of this.sites.entries()) {
              if (op === '==' && site.data[field] === val) {
                docs.push({
                  id,
                  data: () => ({ ...site.data }),
                });
              }
            }
            return { docs, forEach: (fn) => docs.forEach(fn) };
          },
        }),
        doc: (siteId) => ({
          get: async () => {
            const exists = this.sites.has(siteId);
            return {
              exists,
              data: () => (exists ? { ...this.sites.get(siteId).data } : null),
            };
          },
          delete: async () => {
            this.sites.delete(siteId);
          },
          collection: (subName) => {
            const site = this.sites.get(siteId);
            const subMap = site ? site[subName] : null;

            return {
              get: async () => {
                const docs = [];
                if (subMap) {
                  for (const [id, data] of subMap.entries()) {
                    docs.push({
                      id,
                      data: () => ({ ...data }),
                      ref: {
                        delete: async () => {
                          subMap.delete(id);
                        },
                        update: async (patch) => {
                          const existing = subMap.get(id) || {};
                          subMap.set(id, { ...existing, ...patch });
                        },
                      },
                    });
                  }
                }
                return { docs, forEach: (fn) => docs.forEach(fn) };
              },
              doc: (docId) => ({
                get: async () => {
                  const exists = subMap && subMap.has(docId);
                  return {
                    exists,
                    data: () => (exists ? { ...subMap.get(docId) } : null),
                  };
                },
                delete: async () => {
                  if (subMap) subMap.delete(docId);
                },
                update: async (patch) => {
                  if (subMap && subMap.has(docId)) {
                    const existing = subMap.get(docId);
                    subMap.set(docId, { ...existing, ...patch });
                  }
                },
              }),
            };
          },
        }),
      };
    }

    if (name === 'users') {
      return {
        doc: (userId) => ({
          get: async () => {
            const exists = this.users.has(userId);
            return {
              exists,
              data: () => (exists ? { ...this.users.get(userId) } : null),
            };
          },
          delete: async () => {
            this.users.delete(userId);
          },
        }),
      };
    }

    if (name === 'enquiries') {
      return {
        where: (field, op, val) => ({
          get: async () => {
            const docs = [];
            for (const [id, enq] of this.enquiries.entries()) {
              if (op === '==' && enq[field] === val) {
                docs.push({
                  id,
                  data: () => ({ ...enq }),
                  ref: {
                    update: async (patch) => {
                      const cur = this.enquiries.get(id);
                      this.enquiries.set(id, { ...cur, ...patch });
                    },
                  },
                });
              }
            }
            return { docs, forEach: (fn) => docs.forEach(fn) };
          },
        }),
      };
    }

    if (name === '_system_rate_limits') {
      return {
        get: async () => {
          const docs = [];
          for (const [id, data] of this.rateLimits.entries()) {
            docs.push({
              id,
              data: () => ({ ...data }),
              ref: {
                delete: async () => {
                  this.rateLimits.delete(id);
                },
              },
            });
          }
          return { docs, forEach: (fn) => docs.forEach(fn) };
        },
      };
    }

    throw new Error(`Unexpected collection: ${name}`);
  }

  collectionGroup(name) {
    if (name === 'members') {
      return {
        where: (field, op, val) => ({
          get: async () => {
            const docs = [];
            for (const [siteId, site] of this.sites.entries()) {
              for (const [memberId, memberData] of site.members.entries()) {
                if (op === '==' && memberData[field] === val) {
                  docs.push({
                    id: memberId,
                    data: () => ({ ...memberData }),
                    ref: {
                      parent: {
                        parent: {
                          id: siteId,
                        },
                      },
                    },
                  });
                }
              }
            }
            return { docs, forEach: (fn) => docs.forEach(fn) };
          },
        }),
      };
    }
    throw new Error(`Unexpected collectionGroup: ${name}`);
  }
}

/**
 * Mock Auth service.
 */
class MockAuth {
  constructor() {
    this.deletedUsers = [];
    this.failOnUid = null;
    this.simulateUserNotFound = false;
  }

  async deleteUser(uid) {
    if (this.failOnUid === uid) {
      const err = new Error('Auth internal failure');
      err.code = 'auth/internal-error';
      throw err;
    }
    if (this.simulateUserNotFound) {
      const err = new Error('User not found');
      err.code = 'auth/user-not-found';
      throw err;
    }
    this.deletedUsers.push(uid);
  }
}

/**
 * Mock Storage Bucket.
 */
class MockStorageBucket {
  constructor() {
    this.files = new Set();
  }

  async getFiles({ prefix }) {
    const matched = [];
    for (const file of this.files) {
      if (file.startsWith(prefix)) {
        matched.push({ name: file });
      }
    }
    return [matched];
  }

  async deleteFiles({ prefix }) {
    for (const file of Array.from(this.files)) {
      if (file.startsWith(prefix)) {
        this.files.delete(file);
      }
    }
  }
}

describe('Backend: Account Deletion (deleteUserAccount)', () => {
  let mockDb;
  let mockAuth;
  let mockBucket;

  beforeEach(() => {
    mockDb = new MockDeletionFirestore();
    mockAuth = new MockAuth();
    mockBucket = new MockStorageBucket();
  });

  test('1. Rejects request when App Check is missing', async () => {
    const request = {
      app: null,
      auth: { uid: 'user_123' },
    };

    await assert.rejects(
      async () => {
        await handleDeleteUserAccount(request, {
          db: mockDb,
          auth: mockAuth,
          bucket: mockBucket,
          enforceAppCheck: true,
        });
      },
      (err) => {
        assert.strictEqual(err.code, 'unauthenticated');
        assert.match(err.message, /App Check verification failed/);
        return true;
      }
    );
  });

  test('2. Rejects request when user is unauthenticated', async () => {
    const request = {
      app: { appId: 'sitelens' },
      auth: null,
    };

    await assert.rejects(
      async () => {
        await handleDeleteUserAccount(request, {
          db: mockDb,
          auth: mockAuth,
          bucket: mockBucket,
          enforceAppCheck: false,
        });
      },
      (err) => {
        assert.strictEqual(err.code, 'unauthenticated');
        assert.match(err.message, /User must be authenticated/);
        return true;
      }
    );
  });

  test('3. Deletes user with no sites cleanly', async () => {
    const uid = 'user_no_sites';
    mockDb.users.set(uid, { displayName: 'Bob', email: 'bob@example.com' });
    mockDb.enquiries.set('enq_1', { userId: uid, email: 'bob@example.com', name: 'Bob', message: 'Hello' });
    mockDb.rateLimits.set(`uid_${uid}_12345`, { attempts: 1 });

    const request = {
      auth: { uid },
    };

    const result = await handleDeleteUserAccount(request, {
      db: mockDb,
      auth: mockAuth,
      bucket: mockBucket,
      enforceAppCheck: false,
    });

    assert.strictEqual(result.success, true);
    assert.strictEqual(result.deletedSitesCount, 0);
    assert.strictEqual(result.sharedSitesUpdatedCount, 0);
    assert.strictEqual(mockDb.users.has(uid), false);
    assert.deepStrictEqual(mockAuth.deletedUsers, [uid]);

    // Enquiries scrubbing
    const scrubbedEnq = mockDb.enquiries.get('enq_1');
    assert.strictEqual(scrubbedEnq.userId, null);
    assert.strictEqual(scrubbedEnq.email, '[deleted]');
    assert.strictEqual(scrubbedEnq.name, '[deleted]');

    // Rate limit cleanup
    assert.strictEqual(mockDb.rateLimits.has(`uid_${uid}_12345`), false);
  });

  test('4. Sole-member site: cascades deletion to site, members, media, and storage files', async () => {
    const uid = 'sole_admin_1';
    const siteId = 'site_personal';

    // Populate sole-member site
    const members = new Map();
    members.set(uid, { user_id: uid, role: 'admin', status: 'active' });
    const media = new Map();
    media.set('media_1', { photo_hash: 'abc', file_path: `sites/${siteId}/photos/photo1.jpg` });

    mockDb.sites.set(siteId, {
      data: { name: 'Personal Site', creator_id: uid },
      members,
      media,
    });

    mockBucket.files.add(`sites/${siteId}/photos/photo1.jpg`);
    mockBucket.files.add(`sites/${siteId}/thumbnails/thumb1.jpg`);

    const request = {
      auth: { uid },
    };

    const result = await handleDeleteUserAccount(request, {
      db: mockDb,
      auth: mockAuth,
      bucket: mockBucket,
      enforceAppCheck: false,
    });

    assert.strictEqual(result.success, true);
    assert.strictEqual(result.deletedSitesCount, 1);
    assert.strictEqual(result.purgedStorageFilesCount, 2);
    assert.strictEqual(mockDb.sites.has(siteId), false);
    assert.strictEqual(mockBucket.files.size, 0);
    assert.deepStrictEqual(mockAuth.deletedUsers, [uid]);
  });

  test('5. Shared site with multiple admins: caller leaves without requiring successor', async () => {
    const uid = 'admin_leaving';
    const otherAdminUid = 'admin_remaining';
    const siteId = 'shared_site_1';

    const members = new Map();
    members.set(uid, { user_id: uid, role: 'admin', status: 'active' });
    members.set(otherAdminUid, { user_id: otherAdminUid, role: 'admin', status: 'active' });
    const media = new Map();
    media.set('media_shared', { creator_id: uid, photo_hash: '123' });

    mockDb.sites.set(siteId, {
      data: { name: 'Shared Team Site', creator_id: uid },
      members,
      media,
    });

    const request = {
      auth: { uid },
    };

    const result = await handleDeleteUserAccount(request, {
      db: mockDb,
      auth: mockAuth,
      bucket: mockBucket,
      enforceAppCheck: false,
    });

    assert.strictEqual(result.success, true);
    assert.strictEqual(result.deletedSitesCount, 0);
    assert.strictEqual(result.sharedSitesUpdatedCount, 1);
    // Site must remain
    assert.strictEqual(mockDb.sites.has(siteId), true);
    // Caller removed from members
    const updatedMembers = mockDb.sites.get(siteId).members;
    assert.strictEqual(updatedMembers.has(uid), false);
    assert.strictEqual(updatedMembers.has(otherAdminUid), true);
    // Media must remain intact (pseudonymous retention)
    assert.strictEqual(mockDb.sites.get(siteId).media.has('media_shared'), true);
    assert.deepStrictEqual(mockAuth.deletedUsers, [uid]);
  });

  test('6. Sole-admin shared site without designated successor fails with requiresSuccessor', async () => {
    const uid = 'sole_admin_shared';
    const memberUid = 'regular_member_1';
    const siteId = 'company_site';

    const members = new Map();
    members.set(uid, { user_id: uid, role: 'admin', status: 'active' });
    members.set(memberUid, { user_id: memberUid, role: 'member', status: 'active' });

    mockDb.sites.set(siteId, {
      data: { name: 'Company Site', creator_id: uid },
      members,
      media: new Map(),
    });

    const request = {
      auth: { uid },
      data: {}, // no successorAdmins provided
    };

    await assert.rejects(
      async () => {
        await handleDeleteUserAccount(request, {
          db: mockDb,
          auth: mockAuth,
          bucket: mockBucket,
          enforceAppCheck: false,
        });
      },
      (err) => {
        assert.strictEqual(err.code, 'failed-precondition');
        assert.strictEqual(err.details.requiresSuccessor, true);
        assert.strictEqual(err.details.sitesNeedingSuccessor.length, 1);
        assert.strictEqual(err.details.sitesNeedingSuccessor[0].siteId, siteId);
        assert.strictEqual(err.details.sitesNeedingSuccessor[0].eligibleMembers.length, 1);
        assert.strictEqual(err.details.sitesNeedingSuccessor[0].eligibleMembers[0].userId, memberUid);
        return true;
      }
    );

    // Auth user must NOT have been deleted
    assert.strictEqual(mockAuth.deletedUsers.length, 0);
  });

  test('7. Sole-admin shared site with invalid successor (self or not a member) fails safely', async () => {
    const uid = 'sole_admin_shared';
    const memberUid = 'regular_member_1';
    const siteId = 'company_site';

    const members = new Map();
    members.set(uid, { user_id: uid, role: 'admin', status: 'active' });
    members.set(memberUid, { user_id: memberUid, role: 'member', status: 'active' });

    mockDb.sites.set(siteId, {
      data: { name: 'Company Site', creator_id: uid },
      members,
      media: new Map(),
    });

    // Case A: Designating oneself
    await assert.rejects(
      async () => {
        await handleDeleteUserAccount(
          { auth: { uid }, data: { successorAdmins: { [siteId]: uid } } },
          { db: mockDb, auth: mockAuth, bucket: mockBucket, enforceAppCheck: false }
        );
      },
      (err) => err.details && err.details.requiresSuccessor === true
    );

    // Case B: Designating an unknown non-member
    await assert.rejects(
      async () => {
        await handleDeleteUserAccount(
          { auth: { uid }, data: { successorAdmins: { [siteId]: 'random_stranger' } } },
          { db: mockDb, auth: mockAuth, bucket: mockBucket, enforceAppCheck: false }
        );
      },
      (err) => err.details && err.details.requiresSuccessor === true
    );
  });

  test('8. Sole-admin shared site with valid designated successor promotes successor and proceeds', async () => {
    const uid = 'sole_admin_shared';
    const successorUid = 'chosen_successor';
    const siteId = 'company_site';

    const members = new Map();
    members.set(uid, { user_id: uid, role: 'admin', status: 'active' });
    members.set(successorUid, { user_id: successorUid, role: 'member', status: 'active' });

    mockDb.sites.set(siteId, {
      data: { name: 'Company Site', creator_id: uid },
      members,
      media: new Map(),
    });

    const request = {
      auth: { uid },
      data: {
        successorAdmins: {
          [siteId]: successorUid,
        },
      },
    };

    const result = await handleDeleteUserAccount(request, {
      db: mockDb,
      auth: mockAuth,
      bucket: mockBucket,
      enforceAppCheck: false,
    });

    assert.strictEqual(result.success, true);
    assert.strictEqual(result.sharedSitesUpdatedCount, 1);

    const updatedMembers = mockDb.sites.get(siteId).members;
    assert.strictEqual(updatedMembers.has(uid), false);
    assert.strictEqual(updatedMembers.get(successorUid).role, 'admin');
    assert.deepStrictEqual(mockAuth.deletedUsers, [uid]);
  });

  test('9. Idempotency: handles auth/user-not-found without throwing error', async () => {
    const uid = 'already_deleted_in_auth';
    mockAuth.simulateUserNotFound = true;

    const request = {
      auth: { uid },
    };

    const result = await handleDeleteUserAccount(request, {
      db: mockDb,
      auth: mockAuth,
      bucket: mockBucket,
      enforceAppCheck: false,
    });

    assert.strictEqual(result.success, true);
  });
});
