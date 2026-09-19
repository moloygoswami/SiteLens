const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert');
const { handleDeleteUserAccount } = require('../index.js');

/**
 * In-memory Mock Firestore with subcollections for creator-owned deletion tests.
 */
class MockDeletionFirestore {
  constructor() {
    this.sites = new Map(); // siteId -> { data: {}, media: Map(mediaId -> data) }
    this.users = new Map(); // userId -> data
    this.enquiries = new Map(); // enqId -> data
    this.rateLimits = new Map(); // rlId -> data

    // R23 failure injection (all default off)
    this.failSiteQuery = false;
    this.failSiteDocDelete = new Set();
    this.failMediaDocDelete = new Set();
    this.failUserDelete = false;
    this.failEnquiryUpdate = new Set();
    this.failRateLimitDelete = new Set();
  }

  collection(name) {
    if (name === 'sites') {
      return {
        where: (field, op, val) => ({
          get: async () => {
            if (this.failSiteQuery) {
              throw new Error('site discovery failed');
            }
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
            if (this.failSiteDocDelete.has(siteId)) {
              throw new Error(`site doc delete failed: ${siteId}`);
            }
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
                          if (this.failMediaDocDelete.has(id)) {
                            throw new Error(`media doc delete failed: ${id}`);
                          }
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
            if (this.failUserDelete) {
              throw new Error(`user delete failed: ${userId}`);
            }
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
                      if (this.failEnquiryUpdate.has(id)) {
                        throw new Error(`enquiry update failed: ${id}`);
                      }
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
                  if (this.failRateLimitDelete.has(id)) {
                    throw new Error(`rate-limit delete failed: ${id}`);
                  }
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
    this.failDeletePrefixes = new Set();
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
    if (this.failDeletePrefixes.has(prefix)) {
      throw new Error(`storage purge failed: ${prefix}`);
    }
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

  test('4. Creator-owned site: cascades deletion to site, media, and storage files', async () => {
    const uid = 'creator_1';
    const siteId = 'site_personal';

    const media = new Map();
    media.set('media_1', { photo_hash: 'abc', file_path: `sites/${siteId}/photos/photo1.jpg` });

    mockDb.sites.set(siteId, {
      data: { name: 'Personal Site', creator_id: uid },
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

  test('5. Idempotency: handles auth/user-not-found without throwing error', async () => {
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

  test('6. R23: reports success only when every required cleanup succeeds', async () => {
    const uid = 'creator_ok';
    const siteId = 'site_ok';
    const media = new Map();
    media.set('media_ok_1', { file_path: `sites/${siteId}/photos/p1.jpg` });

    mockDb.sites.set(siteId, { data: { name: 'Ok Site', creator_id: uid }, media });
    mockBucket.files.add(`sites/${siteId}/photos/p1.jpg`);
    mockDb.users.set(uid, { email: 'ok@example.com' });
    mockDb.enquiries.set('enq_ok', { userId: uid, email: 'ok@example.com', name: 'Ok' });
    mockDb.rateLimits.set(`uid_${uid}_999`, { attempts: 1 });

    const result = await handleDeleteUserAccount({ auth: { uid } }, {
      db: mockDb,
      auth: mockAuth,
      bucket: mockBucket,
      enforceAppCheck: false,
    });

    assert.strictEqual(result.success, true);
    assert.strictEqual(result.deletedSitesCount, 1);
    assert.strictEqual(result.purgedStorageFilesCount, 1);
    assert.strictEqual(mockDb.sites.has(siteId), false);
    assert.strictEqual(mockDb.users.has(uid), false);
    assert.strictEqual(mockDb.enquiries.get('enq_ok').userId, null);
    assert.strictEqual(mockDb.rateLimits.has(`uid_${uid}_999`), false);
    assert.deepStrictEqual(mockAuth.deletedUsers, [uid]);
  });

  test('7. R23: a single required cleanup failure reports failure and never deletes the Auth identity', async () => {
    const uid = 'creator_fail_one';
    const siteId = 'site_fail_one';
    const media = new Map();
    media.set('media_f1', { file_path: `sites/${siteId}/photos/p1.jpg` });

    mockDb.sites.set(siteId, { data: { name: 'Fail Site', creator_id: uid }, media });
    mockBucket.files.add(`sites/${siteId}/photos/p1.jpg`);
    mockBucket.failDeletePrefixes.add(`sites/${siteId}/`);

    await assert.rejects(
      async () => {
        await handleDeleteUserAccount({ auth: { uid } }, {
          db: mockDb,
          auth: mockAuth,
          bucket: mockBucket,
          enforceAppCheck: false,
        });
      },
      (err) => {
        assert.strictEqual(err.code, 'internal');
        assert.match(err.message, /Account deletion incomplete/);
        assert.match(err.message, /1 required remote cleanup operation\(s\) failed/);
        return true;
      }
    );

    // Failure is reported (no falsely successful response) and the Auth
    // identity is intact so the caller can safely retry.
    assert.deepStrictEqual(mockAuth.deletedUsers, []);
    // The site document is retained so the retry can re-discover and reclaim it.
    assert.strictEqual(mockDb.sites.has(siteId), true);
  });

  test('8. R23: multiple required cleanup failures are all tracked and reported as failure', async () => {
    const uid = 'creator_fail_many';
    const siteId = 'site_fail_many';
    const media = new Map();
    media.set('media_m1', { file_path: `sites/${siteId}/photos/p1.jpg` });

    mockDb.sites.set(siteId, { data: { name: 'Many Fail Site', creator_id: uid }, media });
    mockBucket.files.add(`sites/${siteId}/photos/p1.jpg`);
    mockDb.users.set(uid, { email: 'many@example.com' });
    mockBucket.failDeletePrefixes.add(`sites/${siteId}/`);
    mockDb.failMediaDocDelete.add('media_m1');
    mockDb.failUserDelete = true;

    await assert.rejects(
      async () => {
        await handleDeleteUserAccount({ auth: { uid } }, {
          db: mockDb,
          auth: mockAuth,
          bucket: mockBucket,
          enforceAppCheck: false,
        });
      },
      (err) => {
        assert.strictEqual(err.code, 'internal');
        assert.match(err.message, /3 required remote cleanup operation\(s\) failed/);
        return true;
      }
    );

    assert.deepStrictEqual(mockAuth.deletedUsers, []);
    assert.strictEqual(mockDb.sites.has(siteId), true);
    assert.strictEqual(mockDb.users.has(uid), true);
  });

  test('9. R23: retry after a partial failure is safe and idempotent', async () => {
    const uid = 'creator_retry';
    const siteId = 'site_retry';
    const media = new Map();
    media.set('media_r1', { file_path: `sites/${siteId}/photos/p1.jpg` });

    mockDb.sites.set(siteId, { data: { name: 'Retry Site', creator_id: uid }, media });
    mockBucket.files.add(`sites/${siteId}/photos/p1.jpg`);

    // 1st attempt: Storage purge fails -> failure, Auth intact, site retained.
    mockBucket.failDeletePrefixes.add(`sites/${siteId}/`);
    await assert.rejects(
      async () => {
        await handleDeleteUserAccount({ auth: { uid } }, {
          db: mockDb,
          auth: mockAuth,
          bucket: mockBucket,
          enforceAppCheck: false,
        });
      }
    );
    assert.deepStrictEqual(mockAuth.deletedUsers, []);
    assert.strictEqual(mockDb.sites.has(siteId), true);

    // 2nd attempt: the transient failure is resolved -> idempotent success.
    mockBucket.failDeletePrefixes.delete(`sites/${siteId}/`);
    const result = await handleDeleteUserAccount({ auth: { uid } }, {
      db: mockDb,
      auth: mockAuth,
      bucket: mockBucket,
      enforceAppCheck: false,
    });

    assert.strictEqual(result.success, true);
    assert.strictEqual(result.deletedSitesCount, 1);
    assert.strictEqual(result.purgedStorageFilesCount, 1);
    assert.strictEqual(mockDb.sites.has(siteId), false);
    assert.strictEqual(mockBucket.files.size, 0);
    assert.deepStrictEqual(mockAuth.deletedUsers, [uid]);
  });
});
