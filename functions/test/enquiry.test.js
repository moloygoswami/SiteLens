const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert');
const {
  escapeHtml,
  validateEnquiryPayload,
  checkPersistentRateLimit,
  sendResendEmail,
  handleUserEnquiry,
  VALID_CATEGORIES,
  extractClientIp,
  GLOBAL_RATE_LIMIT_CAP,
  GLOBAL_RATE_LIMIT_ALERT,
} = require('../index.js');

/**
 * Mock in-memory Firestore implementation for unit testing.
 */
class MockFirestore {
  constructor() {
    this.collections = new Map();
  }

  collection(name) {
    if (!this.collections.has(name)) {
      this.collections.set(name, new Map());
    }
    const map = this.collections.get(name);
    return {
      doc: (id) => ({
        get: async () => ({
          exists: map.has(id),
          data: () => map.get(id),
        }),
        set: async (data) => {
          map.set(id, { ...data });
        },
      }),
    };
  }

  async runTransaction(updateFunction) {
    const transaction = {
      get: async (ref) => ref.get(),
      set: (ref, data) => ref.set(data),
    };
    return await updateFunction(transaction);
  }
}

describe('Backend: User Enquiry System', () => {
  let mockDb;

  beforeEach(() => {
    mockDb = new MockFirestore();
  });

  describe('1. HTML Escaping & Sanitization', () => {
    test('escapes HTML tags and script injections', () => {
      const input = '<script>alert("XSS & breach")</script>\'test\'';
      const output = escapeHtml(input);
      assert.strictEqual(
        output,
        '&lt;script&gt;alert(&quot;XSS &amp; breach&quot;)&lt;/script&gt;&#039;test&#039;'
      );
    });

    test('handles non-string values gracefully', () => {
      assert.strictEqual(escapeHtml(null), '');
      assert.strictEqual(escapeHtml(undefined), '');
    });
  });

  describe('2. Payload Validation', () => {
    test('validates correct enquiry payload', () => {
      const payload = {
        name: 'Sarah Connor',
        email: 'sarah.connor@cyberdyne.com',
        category: 'bug_report',
        message: 'The GPS overlay did not fix altitude after satellite drop.',
        submissionId: 'test-uuid-1234-5678-abcdef',
      };

      const result = validateEnquiryPayload(payload);
      assert.strictEqual(result.name, 'Sarah Connor');
      assert.strictEqual(result.email, 'sarah.connor@cyberdyne.com');
      assert.strictEqual(result.category, 'bug_report');
      assert.strictEqual(result.categoryLabel, 'Bug Report');
      assert.strictEqual(result.submissionId, 'test-uuid-1234-5678-abcdef');
    });

    test('rejects missing or empty submissionId', () => {
      assert.throws(
        () => validateEnquiryPayload({ name: 'A', email: 'a@b.com', category: 'general', message: '1234567890' }),
        { code: 'invalid-argument' }
      );
    });

    test('rejects submissionId containing path traversal, control chars, or invalid symbols (vuln-0003)', () => {
      const maliciousIds = [
        '../path/traversal',
        'sub/slash/injection',
        'sub\\backslash\\injection',
        'sub id with spaces',
        'sub\r\ninjection',
        'sub\x00nullbyte',
        'sub@#$*!?',
        'short', // < 8 chars
        'a'.repeat(129), // > 128 chars
      ];

      for (const badId of maliciousIds) {
        assert.throws(
          () =>
            validateEnquiryPayload({
              submissionId: badId,
              name: 'John',
              email: 'john@example.com',
              category: 'general',
              message: '1234567890',
            }),
          { code: 'invalid-argument' },
          `Expected submissionId '${badId}' to be rejected`
        );
      }
    });

    test('rejects name containing CRLF or control characters (vuln-0004)', () => {
      const maliciousNames = [
        'John\r\nBcc: evil@attacker.com',
        'Jane\nSubject: Injected Subject',
        'Alice\rCarrier Return',
        'Bob\x00NullByte',
        'Attacker\x1bEscapeCode',
      ];

      for (const badName of maliciousNames) {
        assert.throws(
          () =>
            validateEnquiryPayload({
              submissionId: 'test-uuid-1234',
              name: badName,
              email: 'john@example.com',
              category: 'general',
              message: '1234567890',
            }),
          { code: 'invalid-argument' },
          `Expected name with CRLF/control char to be rejected: ${JSON.stringify(badName)}`
        );
      }
    });

    test('rejects invalid email formats', () => {
      const invalidEmails = ['invalid-email', 'foo@', '@bar.com', 'foo@bar'];
      for (const badEmail of invalidEmails) {
        assert.throws(
          () =>
            validateEnquiryPayload({
              submissionId: 'test-uuid-1234',
              name: 'John',
              email: badEmail,
              category: 'general',
              message: '1234567890',
            }),
          { code: 'invalid-argument' }
        );
      }
    });

    test('validates and accepts every currently supported category in VALID_CATEGORIES', () => {
      for (const [catKey, expectedLabel] of Object.entries(VALID_CATEGORIES)) {
        const payload = {
          submissionId: 'test-uuid-1234-5678-abcdef',
          name: 'Jane Doe',
          email: 'jane@example.com',
          category: catKey,
          message: 'Valid category enquiry message comfortably over 10 chars.',
        };
        const result = validateEnquiryPayload(payload);
        assert.strictEqual(result.category, catKey);
        assert.strictEqual(result.categoryLabel, expectedLabel);
      }
    });

    test('rejects prototype property constructor cleanly (vuln-0019)', () => {
      assert.throws(
        () =>
          validateEnquiryPayload({
            submissionId: 'test-uuid-1234',
            name: 'John',
            email: 'john@example.com',
            category: 'constructor',
            message: '1234567890',
          }),
        (err) => err.code === 'invalid-argument' && err.message.includes('Category must be one of')
      );
    });

    test('rejects prototype property toString cleanly (vuln-0019)', () => {
      assert.throws(
        () =>
          validateEnquiryPayload({
            submissionId: 'test-uuid-1234',
            name: 'John',
            email: 'john@example.com',
            category: 'toString',
            message: '1234567890',
          }),
        (err) => err.code === 'invalid-argument' && err.message.includes('Category must be one of')
      );
    });

    test('rejects prototype property __proto__ cleanly (vuln-0019)', () => {
      assert.throws(
        () =>
          validateEnquiryPayload({
            submissionId: 'test-uuid-1234',
            name: 'John',
            email: 'john@example.com',
            category: '__proto__',
            message: '1234567890',
          }),
        (err) => err.code === 'invalid-argument' && err.message.includes('Category must be one of')
      );
    });

    test('rejects other prototype properties and unknown categories (vuln-0019)', () => {
      const invalidCategories = [
        'valueOf',
        'hasOwnProperty',
        'isPrototypeOf',
        'propertyIsEnumerable',
        'toLocaleString',
        'unauthorized_hack_category',
        ' GENERAL ',
        '',
      ];
      for (const badCategory of invalidCategories) {
        assert.throws(
          () =>
            validateEnquiryPayload({
              submissionId: 'test-uuid-1234',
              name: 'John',
              email: 'john@example.com',
              category: badCategory,
              message: '1234567890',
            }),
          (err) => err.code === 'invalid-argument' && err.message.includes('Category must be one of'),
          `Expected bad category '${badCategory}' to be rejected`
        );
      }
    });

    test('rejects messages shorter than 10 characters', () => {
      assert.throws(
        () =>
          validateEnquiryPayload({
            submissionId: 'test-uuid-1234',
            name: 'John',
            email: 'john@example.com',
            category: 'general',
            message: 'Too short',
          }),
        { code: 'invalid-argument' }
      );
    });
  });

  describe('3. Persistent Rate Limiting', () => {
    test('allows up to 5 attempts within 10-minute window for a single identifier', async () => {
      const id = 'user_123';
      for (let i = 0; i < 5; i++) {
        await checkPersistentRateLimit(mockDb, id);
      }
    });

    test('throws resource-exhausted on 6th attempt within window for a single identifier', async () => {
      const id = 'user_456';
      for (let i = 0; i < 5; i++) {
        await checkPersistentRateLimit(mockDb, id);
      }

      await assert.rejects(
        async () => {
          await checkPersistentRateLimit(mockDb, id);
        },
        { code: 'resource-exhausted' }
      );
    });

    test('rate limits unauthenticated callers by remote IP and ignores spoofed X-Forwarded-For (vuln-0001 / vuln-0002)', async () => {
      const mockFetch = async () => ({
        ok: true,
        status: 200,
        json: async () => ({ id: 're_123' }),
      });

      const fixedIp = '203.0.113.195';

      // Submit 5 requests from the same real IP, but rotating spoofed X-Forwarded-For header.
      // In production Cloud Functions 2nd-gen with Express trust proxy:
      // Client sends: X-Forwarded-For: 198.51.100.i
      // Google Front End appends real IP: X-Forwarded-For: 198.51.100.i, 203.0.113.195
      // Express trust-proxy sets rawRequest.ip to the LEFTMOST (spoofed) IP: 198.51.100.i
      // Backend extractClientIp extracts the RIGHTMOST IP: 203.0.113.195
      for (let i = 1; i <= 5; i++) {
        const spoofedIp = `198.51.100.${i}`;
        const req = {
          app: { appId: 'com.sitelens.app' },
          rawRequest: {
            ip: spoofedIp,
            headers: { 'x-forwarded-for': `${spoofedIp}, ${fixedIp}` },
            socket: { remoteAddress: '127.0.0.1' },
          },
          data: {
            submissionId: `sub-rate-test-ip-${i}`,
            name: 'Test Attacker',
            email: 'attacker@example.com',
            category: 'general',
            message: 'Valid message exceeding 10 characters.',
          },
        };

        const res = await handleUserEnquiry(req, {
          db: mockDb,
          resendApiKey: 're_test_key',
          fetch: mockFetch,
          enforceAppCheck: true,
        });
        assert.strictEqual(res.success, true);
      }

      // 6th attempt with a new spoofed header from same real IP MUST fail with resource-exhausted
      const sixthReq = {
        app: { appId: 'com.sitelens.app' },
        rawRequest: {
          ip: '198.51.100.99',
          headers: { 'x-forwarded-for': `198.51.100.99, ${fixedIp}` },
          socket: { remoteAddress: '127.0.0.1' },
        },
        data: {
          submissionId: 'sub-rate-test-ip-6',
          name: 'Test Attacker',
          email: 'attacker@example.com',
          category: 'general',
          message: 'Valid message exceeding 10 characters.',
        },
      };

      await assert.rejects(
        async () => {
          await handleUserEnquiry(sixthReq, {
            db: mockDb,
            resendApiKey: 're_test_key',
            fetch: mockFetch,
            enforceAppCheck: true,
          });
        },
        { code: 'resource-exhausted' }
      );
    });

    test('enforces aggregate per-IP rate limit across multiple distinct Firebase UIDs (vuln-0001)', async () => {
      const mockFetch = async () => ({
        ok: true,
        status: 200,
        json: async () => ({ id: 're_multi_uid' }),
      });

      const fixedIp = '198.51.100.42';

      // 10 distinct UIDs from the exact same real IP each submit 1 request,
      // rotating spoofed X-Forwarded-For to simulate multi-account bypass attempts
      for (let i = 1; i <= 10; i++) {
        const spoofedIp = `203.0.113.${i}`;
        const req = {
          app: { appId: 'com.sitelens.app' },
          auth: { uid: `attacker_uid_${i}` },
          rawRequest: {
            ip: spoofedIp,
            headers: { 'x-forwarded-for': `${spoofedIp}, ${fixedIp}` },
            socket: { remoteAddress: '127.0.0.1' },
          },
          data: {
            submissionId: `sub-multi-uid-${i}`,
            name: `Attacker Account ${i}`,
            email: `attacker${i}@example.com`,
            category: 'general',
            message: `Message from account ${i} with sufficient length.`,
          },
        };

        const res = await handleUserEnquiry(req, {
          db: mockDb,
          resendApiKey: 're_test_key',
          fetch: mockFetch,
          enforceAppCheck: true,
        });
        assert.strictEqual(res.success, true);
      }

      // 11th request from an 11th distinct UID on the same IP must be BLOCKED by aggregate IP limit
      const eleventhReq = {
        app: { appId: 'com.sitelens.app' },
        auth: { uid: 'attacker_uid_11' },
        rawRequest: {
          ip: '203.0.113.99',
          headers: { 'x-forwarded-for': `203.0.113.99, ${fixedIp}` },
          socket: { remoteAddress: '127.0.0.1' },
        },
        data: {
          submissionId: 'sub-multi-uid-11',
          name: 'Attacker Account 11',
          email: 'attacker11@example.com',
          category: 'general',
          message: 'Message from account 11 attempting to bypass limit.',
        },
      };

      await assert.rejects(
        async () => {
          await handleUserEnquiry(eleventhReq, {
            db: mockDb,
            resendApiKey: 're_test_key',
            fetch: mockFetch,
            enforceAppCheck: true,
          });
        },
        { code: 'resource-exhausted' }
      );
    });

    test('enforces per-user limit for a single UID before aggregate limit is reached', async () => {
      const mockFetch = async () => ({
        ok: true,
        status: 200,
        json: async () => ({ id: 're_single_uid' }),
      });

      const fixedIp = '198.51.100.99';

      // Same UID makes 5 requests from this IP
      for (let i = 1; i <= 5; i++) {
        const req = {
          app: { appId: 'com.sitelens.app' },
          auth: { uid: 'heavy_user_1' },
          rawRequest: {
            headers: { 'x-forwarded-for': fixedIp },
            socket: { remoteAddress: fixedIp },
          },
          data: {
            submissionId: `sub-heavy-uid-${i}`,
            name: 'Heavy User',
            email: 'heavy@example.com',
            category: 'general',
            message: 'Valid enquiry message meeting minimum length requirement.',
          },
        };

        const res = await handleUserEnquiry(req, {
          db: mockDb,
          resendApiKey: 're_test_key',
          fetch: mockFetch,
          enforceAppCheck: true,
        });
        assert.strictEqual(res.success, true);
      }

      // 6th request by the SAME UID must fail on the per-user limit
      const sixthReq = {
        app: { appId: 'com.sitelens.app' },
        auth: { uid: 'heavy_user_1' },
        rawRequest: {
          headers: { 'x-forwarded-for': fixedIp },
          socket: { remoteAddress: fixedIp },
        },
        data: {
          submissionId: 'sub-heavy-uid-6',
          name: 'Heavy User',
          email: 'heavy@example.com',
          category: 'general',
          message: 'Valid enquiry message meeting minimum length requirement.',
        },
      };

      await assert.rejects(
        async () => {
          await handleUserEnquiry(sixthReq, {
            db: mockDb,
            resendApiKey: 're_test_key',
            fetch: mockFetch,
            enforceAppCheck: true,
          });
        },
        { code: 'resource-exhausted' }
      );

      // But another distinct UID on that same IP can still submit up to the aggregate remaining limit
      const anotherReq = {
        app: { appId: 'com.sitelens.app' },
        auth: { uid: 'distinct_user_2' },
        rawRequest: {
          headers: { 'x-forwarded-for': fixedIp },
          socket: { remoteAddress: fixedIp },
        },
        data: {
          submissionId: 'sub-distinct-uid-2',
          name: 'Distinct User',
          email: 'distinct@example.com',
          category: 'general',
          message: 'Valid enquiry message from second user on shared IP.',
        },
      };

      const res = await handleUserEnquiry(anotherReq, {
        db: mockDb,
        resendApiKey: 're_test_key',
        fetch: mockFetch,
        enforceAppCheck: true,
      });
      assert.strictEqual(res.success, true);
    });

    test('different IPs have independent aggregate rate limits', async () => {
      const mockFetch = async () => ({
        ok: true,
        status: 200,
        json: async () => ({ id: 're_ip_indep' }),
      });

      const ip1 = '192.0.2.1';
      const ip2 = '192.0.2.2';

      // Exhaust IP 1
      for (let i = 1; i <= 10; i++) {
        await handleUserEnquiry(
          {
            app: { appId: 'com.sitelens.app' },
            auth: { uid: `user_ip1_${i}` },
            rawRequest: {
              headers: { 'x-forwarded-for': ip1 },
              socket: { remoteAddress: ip1 },
            },
            data: {
              submissionId: `sub-ip1-${i}`,
              name: `User ${i}`,
              email: `user${i}@example.com`,
              category: 'general',
              message: 'Valid message meeting length.',
            },
          },
          { db: mockDb, resendApiKey: 're_test_key', fetch: mockFetch, enforceAppCheck: true }
        );
      }

      // IP 1 is exhausted
      await assert.rejects(
        async () => {
          await handleUserEnquiry(
            {
              app: { appId: 'com.sitelens.app' },
              auth: { uid: 'user_ip1_11' },
              rawRequest: {
                headers: { 'x-forwarded-for': ip1 },
                socket: { remoteAddress: ip1 },
              },
              data: {
                submissionId: 'sub-ip1-11',
                name: 'User 11',
                email: 'user11@example.com',
                category: 'general',
                message: 'Valid message meeting length.',
              },
            },
            { db: mockDb, resendApiKey: 're_test_key', fetch: mockFetch, enforceAppCheck: true }
          );
        },
        { code: 'resource-exhausted' }
      );

      // IP 2 is unaffected and succeeds
      const ip2Res = await handleUserEnquiry(
        {
          app: { appId: 'com.sitelens.app' },
          auth: { uid: 'user_ip2_1' },
          rawRequest: {
            headers: { 'x-forwarded-for': ip2 },
            socket: { remoteAddress: ip2 },
          },
          data: {
            submissionId: 'sub-ip2-1',
            name: 'User on IP2',
            email: 'user_ip2@example.com',
            category: 'general',
            message: 'Valid message from IP2.',
          },
        },
        { db: mockDb, resendApiKey: 're_test_key', fetch: mockFetch, enforceAppCheck: true }
      );
      assert.strictEqual(ip2Res.success, true);
    });

    test('one caller or abusive set cannot exhaust capacity for unrelated callers (vuln-0018 remediation)', async () => {
      const mockFetch = async () => ({
        ok: true,
        status: 200,
        json: async () => ({ id: 're_global_no_dos' }),
      });

      // Submit 100 requests across distinct IPs from automated traffic
      for (let i = 1; i <= 100; i++) {
        const ip = `10.0.${Math.floor(i / 250)}.${i % 250}`;
        const req = {
          app: { appId: 'com.sitelens.app' },
          auth: { uid: `bulk_user_${i}` },
          rawRequest: {
            headers: { 'x-forwarded-for': ip },
            socket: { remoteAddress: ip },
          },
          data: {
            submissionId: `sub-bulk-${i}`,
            name: `User ${i}`,
            email: `user${i}@example.com`,
            category: 'general',
            message: 'Testing bulk submissions do not block unrelated callers.',
          },
        };

        const res = await handleUserEnquiry(req, {
          db: mockDb,
          resendApiKey: 're_test_key',
          fetch: mockFetch,
          enforceAppCheck: true,
        });
        assert.strictEqual(res.success, true);
      }

      // 101st request from a fresh IP and fresh UID (unrelated legitimate caller)
      // MUST NOT be blocked by an arbitrary shared global counter!
      const legitimateReq = {
        app: { appId: 'com.sitelens.app' },
        auth: { uid: 'legitimate_fresh_user_101' },
        rawRequest: {
          headers: { 'x-forwarded-for': '198.51.100.200' },
          socket: { remoteAddress: '198.51.100.200' },
        },
        data: {
          submissionId: 'sub-legitimate-101',
          name: 'Legitimate Fresh User',
          email: 'legit@example.com',
          category: 'general',
          message: 'This enquiry must be accepted despite previous bulk traffic.',
        },
      };

      const legitimateRes = await handleUserEnquiry(legitimateReq, {
        db: mockDb,
        resendApiKey: 're_test_key',
        fetch: mockFetch,
        enforceAppCheck: true,
      });
      assert.strictEqual(legitimateRes.success, true);
    });

    test('enforces global non-IP aggregate rate limit (G=200, rejection at 201) and logs high-water alert at 160', async () => {
      assert.strictEqual(GLOBAL_RATE_LIMIT_CAP, 200);
      assert.strictEqual(GLOBAL_RATE_LIMIT_ALERT, 160);

      const mockFetch = async () => ({
        ok: true,
        status: 200,
        json: async () => ({ id: 're_global_200' }),
      });

      const warnLogs = [];
      const originalWarn = console.warn;
      console.warn = (...args) => {
        warnLogs.push(args.join(' '));
        originalWarn(...args);
      };

      try {
        // Submit 200 requests across distinct IPs and distinct UIDs (below 10/IP and 5/UID limits)
        for (let i = 1; i <= 200; i++) {
          const ip = `10.2.${Math.floor(i / 250)}.${i % 250}`;
          const req = {
            app: { appId: 'com.sitelens.app' },
            auth: { uid: `global_cap_user_${i}` },
            rawRequest: {
              headers: { 'x-forwarded-for': ip },
              socket: { remoteAddress: ip },
            },
            data: {
              submissionId: `sub-global-cap-${i}`,
              name: `User ${i}`,
              email: `globaluser${i}@example.com`,
              category: 'general',
              message: 'Testing three-tier global aggregate submission limits.',
            },
          };

          const res = await handleUserEnquiry(req, {
            db: mockDb,
            resendApiKey: 're_test_key',
            fetch: mockFetch,
            enforceAppCheck: true,
          });
          assert.strictEqual(res.success, true);
        }

        // Verify high-water alert was logged starting at submission 160
        const alertLogs = warnLogs.filter((log) =>
          log.includes("[RateLimitAlert] High-water mark reached for 'global_total'")
        );
        assert.strictEqual(alertLogs.length >= 41, true, 'Alert should be emitted from request 160 to 200 (41 times)');
        assert.match(alertLogs[0], /160\/200/);

        // 201st request from a fresh IP and fresh UID must be rejected by global_total
        const overLimitReq = {
          app: { appId: 'com.sitelens.app' },
          auth: { uid: 'over_limit_user_201' },
          rawRequest: {
            headers: { 'x-forwarded-for': '198.51.100.201' },
            socket: { remoteAddress: '198.51.100.201' },
          },
          data: {
            submissionId: 'sub-global-cap-201',
            name: 'Over Limit User',
            email: 'overlimit@example.com',
            category: 'general',
            message: 'Should be rejected at the 201st global submission threshold.',
          },
        };

        await assert.rejects(
          async () => {
            await handleUserEnquiry(overLimitReq, {
              db: mockDb,
              resendApiKey: 're_test_key',
              fetch: mockFetch,
              enforceAppCheck: true,
            });
          },
          (err) => {
            assert.strictEqual(err.code, 'resource-exhausted');
            assert.match(err.message, /Rate limit exceeded/);
            return true;
          }
        );
      } finally {
        console.warn = originalWarn;
      }
    });

    test('single abusive caller is throttled by granular tiers and cannot starve independent callers through global tier', async () => {
      const mockFetch = async () => ({
        ok: true,
        status: 200,
        json: async () => ({ id: 're_abusive_isolation' }),
      });

      const abusiveIp = '203.0.113.88';
      const abusiveUid = 'abusive_flooder_uid';

      // Abusive caller makes 15 attempts
      // Attempts 1-5 succeed
      for (let i = 1; i <= 5; i++) {
        const req = {
          app: { appId: 'com.sitelens.app' },
          auth: { uid: abusiveUid },
          rawRequest: {
            headers: { 'x-forwarded-for': abusiveIp },
            socket: { remoteAddress: abusiveIp },
          },
          data: {
            submissionId: `sub-abusive-${i}`,
            name: 'Abusive Flooder',
            email: 'abuser@example.com',
            category: 'general',
            message: 'Flooding request attempt from single abuser.',
          },
        };
        const res = await handleUserEnquiry(req, {
          db: mockDb,
          resendApiKey: 're_test_key',
          fetch: mockFetch,
          enforceAppCheck: true,
        });
        assert.strictEqual(res.success, true);
      }

      // Attempts 6 through 15 are blocked at the granular UID tier
      for (let i = 6; i <= 15; i++) {
        const req = {
          app: { appId: 'com.sitelens.app' },
          auth: { uid: abusiveUid },
          rawRequest: {
            headers: { 'x-forwarded-for': abusiveIp },
            socket: { remoteAddress: abusiveIp },
          },
          data: {
            submissionId: `sub-abusive-${i}`,
            name: 'Abusive Flooder',
            email: 'abuser@example.com',
            category: 'general',
            message: 'Flooding request attempt from single abuser.',
          },
        };
        await assert.rejects(
          async () => {
            await handleUserEnquiry(req, {
              db: mockDb,
              resendApiKey: 're_test_key',
              fetch: mockFetch,
              enforceAppCheck: true,
            });
          },
          { code: 'resource-exhausted' }
        );
      }

      // Check global_total document in Firestore: it only recorded the 5 allowed attempts
      const globalDoc = await mockDb.collection('_system_rate_limits').doc('enquiry_global_total').get();
      assert.strictEqual(globalDoc.exists, true);
      assert.strictEqual(globalDoc.data().timestamps.length, 5);

      // An unrelated innocent caller on a distinct IP can submit with zero starvation
      const innocentReq = {
        app: { appId: 'com.sitelens.app' },
        auth: { uid: 'innocent_bystander' },
        rawRequest: {
          headers: { 'x-forwarded-for': '198.51.100.77' },
          socket: { remoteAddress: '198.51.100.77' },
        },
        data: {
          submissionId: 'sub-innocent-bystander',
          name: 'Innocent Bystander',
          email: 'innocent@example.com',
          category: 'general',
          message: 'Legitimate request completely unblocked by abusive caller.',
        },
      };

      const innocentRes = await handleUserEnquiry(innocentReq, {
        db: mockDb,
        resendApiKey: 're_test_key',
        fetch: mockFetch,
        enforceAppCheck: true,
      });
      assert.strictEqual(innocentRes.success, true);

      // Global count is now 6
      const globalDocAfter = await mockDb.collection('_system_rate_limits').doc('enquiry_global_total').get();
      assert.strictEqual(globalDocAfter.data().timestamps.length, 6);
    });

    test('enforces per-caller rate limit across rotated IPs for authenticated user', async () => {
      const mockFetch = async () => ({
        ok: true,
        status: 200,
        json: async () => ({ id: 're_ip_rotation' }),
      });

      const singleUid = 'attacker_rotating_ips';

      // Attacker uses 5 distinct IPs, each with 1 submission
      for (let i = 1; i <= 5; i++) {
        const rotatingIp = `192.0.2.${i}`;
        const req = {
          app: { appId: 'com.sitelens.app' },
          auth: { uid: singleUid },
          rawRequest: {
            headers: { 'x-forwarded-for': rotatingIp },
            socket: { remoteAddress: rotatingIp },
          },
          data: {
            submissionId: `sub-rotated-${i}`,
            name: 'Rotating Attacker',
            email: 'attacker@example.com',
            category: 'general',
            message: 'Attempting to bypass rate limiting by rotating source IPs.',
          },
        };

        const res = await handleUserEnquiry(req, {
          db: mockDb,
          resendApiKey: 're_test_key',
          fetch: mockFetch,
          enforceAppCheck: true,
        });
        assert.strictEqual(res.success, true);
      }

      // 6th attempt from a 6th distinct IP must still be BLOCKED by per-UID limit
      const sixthReq = {
        app: { appId: 'com.sitelens.app' },
        auth: { uid: singleUid },
        rawRequest: {
          headers: { 'x-forwarded-for': '192.0.2.6' },
          socket: { remoteAddress: '192.0.2.6' },
        },
        data: {
          submissionId: 'sub-rotated-6',
          name: 'Rotating Attacker',
          email: 'attacker@example.com',
          category: 'general',
          message: '6th attempt from 6th IP should be rejected by uid limit.',
        },
      };

      await assert.rejects(
        async () => {
          await handleUserEnquiry(sixthReq, {
            db: mockDb,
            resendApiKey: 're_test_key',
            fetch: mockFetch,
            enforceAppCheck: true,
          });
        },
        (err) => {
          assert.strictEqual(err.code, 'resource-exhausted');
          assert.match(err.message, /Rate limit exceeded\. Please wait/);
          return true;
        }
      );

      // Meanwhile, an unrelated legitimate caller on that 6th IP still succeeds
      const unrelatedReq = {
        app: { appId: 'com.sitelens.app' },
        auth: { uid: 'innocent_user_on_ip_6' },
        rawRequest: {
          headers: { 'x-forwarded-for': '192.0.2.6' },
          socket: { remoteAddress: '192.0.2.6' },
        },
        data: {
          submissionId: 'sub-innocent-ip-6',
          name: 'Innocent User',
          email: 'innocent@example.com',
          category: 'general',
          message: 'Legitimate message from distinct user on 6th IP.',
        },
      };

      const unrelatedRes = await handleUserEnquiry(unrelatedReq, {
        db: mockDb,
        resendApiKey: 're_test_key',
        fetch: mockFetch,
        enforceAppCheck: true,
      });
      assert.strictEqual(unrelatedRes.success, true);
    });

    test('unauthenticated callers are rate-limited per-IP while unrelated IPs remain serviceable', async () => {
      const mockFetch = async () => ({
        ok: true,
        status: 200,
        json: async () => ({ id: 're_unauth_limits' }),
      });

      const ipA = '198.51.100.11';
      const ipB = '198.51.100.22';

      // 5 unauthenticated requests from ipA
      for (let i = 1; i <= 5; i++) {
        const req = {
          app: { appId: 'com.sitelens.app' },
          rawRequest: {
            headers: { 'x-forwarded-for': ipA },
            socket: { remoteAddress: ipA },
          },
          data: {
            submissionId: `sub-unauth-a-${i}`,
            name: 'Unauth User A',
            email: 'unauth_a@example.com',
            category: 'general',
            message: 'Unauthenticated valid submission meeting length requirements.',
          },
        };
        const res = await handleUserEnquiry(req, {
          db: mockDb,
          resendApiKey: 're_test_key',
          fetch: mockFetch,
          enforceAppCheck: true,
        });
        assert.strictEqual(res.success, true);
      }

      // 6th unauthenticated request from ipA must be rejected
      const sixthReqA = {
        app: { appId: 'com.sitelens.app' },
        rawRequest: {
          headers: { 'x-forwarded-for': ipA },
          socket: { remoteAddress: ipA },
        },
        data: {
          submissionId: 'sub-unauth-a-6',
          name: 'Unauth User A',
          email: 'unauth_a@example.com',
          category: 'general',
          message: 'Exceeding unauthenticated rate limit on IP A.',
        },
      };

      await assert.rejects(
        async () => {
          await handleUserEnquiry(sixthReqA, {
            db: mockDb,
            resendApiKey: 're_test_key',
            fetch: mockFetch,
            enforceAppCheck: true,
          });
        },
        (err) => {
          assert.strictEqual(err.code, 'resource-exhausted');
          assert.match(err.message, /Rate limit exceeded\. Please wait/);
          return true;
        }
      );

      // Unauthenticated caller from ipB is completely unaffected and succeeds
      const reqB = {
        app: { appId: 'com.sitelens.app' },
        rawRequest: {
          headers: { 'x-forwarded-for': ipB },
          socket: { remoteAddress: ipB },
        },
        data: {
          submissionId: 'sub-unauth-b-1',
          name: 'Unauth User B',
          email: 'unauth_b@example.com',
          category: 'general',
          message: 'Valid unauthenticated enquiry from unaffected IP B.',
        },
      };

      const resB = await handleUserEnquiry(reqB, {
        db: mockDb,
        resendApiKey: 're_test_key',
        fetch: mockFetch,
        enforceAppCheck: true,
      });
      assert.strictEqual(resB.success, true);
    });

    test('rate-limit failure remains fail-closed when database transaction throws', async () => {
      let emailSent = false;
      const mockFetch = async () => {
        emailSent = true;
        return { ok: true, status: 200, json: async () => ({ id: 're_fail' }) };
      };

      const brokenDb = {
        collection: () => ({
          doc: () => ({ get: async () => ({ exists: false }) }),
        }),
        runTransaction: async () => {
          throw new Error('Firestore connection unavailable');
        },
      };

      const req = {
        app: { appId: 'com.sitelens.app' },
        rawRequest: {
          headers: { 'x-forwarded-for': '203.0.113.1' },
          socket: { remoteAddress: '203.0.113.1' },
        },
        data: {
          submissionId: 'sub-fail-closed-1',
          name: 'Fail Closed Tester',
          email: 'test@example.com',
          category: 'general',
          message: 'Ensuring fail-closed rate limit guarantees.',
        },
      };

      await assert.rejects(
        async () => {
          await handleUserEnquiry(req, {
            db: brokenDb,
            resendApiKey: 're_test_key',
            fetch: mockFetch,
            enforceAppCheck: true,
          });
        },
        /Firestore connection unavailable/
      );

      // Verify email was NOT sent
      assert.strictEqual(emailSent, false);
    });
  });

  describe('Defensive IP Extraction (extractClientIp)', () => {
    test('extracts rightmost IP from multiple comma-separated X-Forwarded-For entries', () => {
      const req = {
        rawRequest: {
          headers: { 'x-forwarded-for': '198.51.100.1, 10.0.0.1, 203.0.113.195' },
          socket: { remoteAddress: '127.0.0.1' },
          ip: '198.51.100.1',
        },
      };
      assert.strictEqual(extractClientIp(req), '203.0.113.195');
    });

    test('trims whitespace around entries in X-Forwarded-For', () => {
      const req = {
        rawRequest: {
          headers: { 'x-forwarded-for': '  198.51.100.1 ,   203.0.113.195   ' },
        },
      };
      assert.strictEqual(extractClientIp(req), '203.0.113.195');
    });

    test('handles array-valued X-Forwarded-For header', () => {
      const req = {
        rawRequest: {
          headers: { 'x-forwarded-for': ['198.51.100.1', '203.0.113.195'] },
        },
      };
      assert.strictEqual(extractClientIp(req), '203.0.113.195');
    });

    test('case-insensitively checks X-Forwarded-For header', () => {
      const req = {
        rawRequest: {
          headers: { 'X-Forwarded-For': '203.0.113.55' },
        },
      };
      assert.strictEqual(extractClientIp(req), '203.0.113.55');
    });

    test('normalizes IPv4-mapped IPv6 address (strips ::ffff:)', () => {
      const req = {
        rawRequest: {
          headers: { 'x-forwarded-for': '::ffff:203.0.113.195' },
        },
      };
      assert.strictEqual(extractClientIp(req), '203.0.113.195');
    });

    test('normalizes IPv4-mapped IPv6 address from socket.remoteAddress', () => {
      const req = {
        rawRequest: {
          headers: {},
          socket: { remoteAddress: '::ffff:192.0.2.5' },
        },
      };
      assert.strictEqual(extractClientIp(req), '192.0.2.5');
    });

    test('falls back to socket.remoteAddress when X-Forwarded-For is absent', () => {
      const req = {
        rawRequest: {
          headers: {},
          socket: { remoteAddress: '198.51.100.88' },
        },
      };
      assert.strictEqual(extractClientIp(req), '198.51.100.88');
    });

    test('falls back to connection.remoteAddress when socket is absent', () => {
      const req = {
        rawRequest: {
          headers: {},
          connection: { remoteAddress: '198.51.100.77' },
        },
      };
      assert.strictEqual(extractClientIp(req), '198.51.100.77');
    });

    test('returns anonymous when neither header nor socket exists', () => {
      const req = {
        rawRequest: {
          headers: {},
        },
      };
      assert.strictEqual(extractClientIp(req), 'anonymous');
    });

    test('never uses rawRequest.ip when header or socket is available', () => {
      const req = {
        rawRequest: {
          ip: 'attacker.controlled.ip',
          headers: { 'x-forwarded-for': 'spoofed.ip, 203.0.113.195' },
          socket: { remoteAddress: '127.0.0.1' },
        },
      };
      // Must not be attacker.controlled.ip or spoofed.ip
      assert.strictEqual(extractClientIp(req), '203.0.113.195');
    });
  });

  describe('4. Resend Email Dispatching & Error Handling', () => {
    test('dispatches email with Idempotency-Key and reply-to set to user email', async () => {
      let capturedUrl = '';
      let capturedOptions = null;

      const mockFetch = async (url, options) => {
        capturedUrl = url;
        capturedOptions = options;
        return {
          ok: true,
          status: 200,
          json: async () => ({ id: 'resend_email_id_999' }),
        };
      };

      const result = await sendResendEmail(
        {
          submissionId: 'sub-12345',
          name: 'Jane Doe',
          email: 'jane@sitelens.test',
          categoryLabel: 'Feature Request',
          message: 'Please add LIDAR sensor telemetry integration to the HUD.',
        },
        're_test_secret_key_123',
        mockFetch
      );

      assert.strictEqual(capturedUrl, 'https://api.resend.com/emails');
      assert.strictEqual(capturedOptions.headers['Authorization'], 'Bearer re_test_secret_key_123');
      assert.strictEqual(capturedOptions.headers['Idempotency-Key'], 'sub-12345');

      const parsedBody = JSON.parse(capturedOptions.body);
      assert.strictEqual(parsedBody.reply_to, 'jane@sitelens.test');
      assert.strictEqual(parsedBody.subject, '[SiteLens Enquiry] [Feature Request] from Jane Doe');
      assert.strictEqual(result.id, 'resend_email_id_999');
    });

    test('sanitizes subject and header fields against CRLF injection in sendResendEmail (vuln-0004)', async () => {
      let capturedOptions = null;
      const mockFetch = async (url, options) => {
        capturedOptions = options;
        return {
          ok: true,
          status: 200,
          json: async () => ({ id: 'resend_123' }),
        };
      };

      await sendResendEmail(
        {
          submissionId: 'sub-header-test-123',
          name: 'Jane\r\nBcc: evil@attacker.com\x00',
          email: 'jane@sitelens.test',
          categoryLabel: 'General\r\nEnquiry',
          message: 'Testing header sanitization defenses.',
        },
        're_test_secret_key_123',
        mockFetch
      );

      const parsedBody = JSON.parse(capturedOptions.body);
      assert.strictEqual(!parsedBody.subject.includes('\r'), true);
      assert.strictEqual(!parsedBody.subject.includes('\n'), true);
      assert.strictEqual(!parsedBody.subject.includes('\x00'), true);
      assert.strictEqual(parsedBody.subject, '[SiteLens Enquiry] [General  Enquiry] from Jane  Bcc: evil@attacker.com');
    });

    test('handles Resend 429 rate-limit response gracefully', async () => {
      const mockFetch = async () => ({
        ok: false,
        status: 429,
        text: async () => 'Rate limit exceeded on Resend API',
      });

      await assert.rejects(
        async () => {
          await sendResendEmail(
            {
              submissionId: 'sub-12345',
              name: 'Jane Doe',
              email: 'jane@sitelens.test',
              categoryLabel: 'General',
              message: 'Test message over 10 chars.',
            },
            're_key',
            mockFetch
          );
        },
        { code: 'resource-exhausted' }
      );
    });

    test('handles network failure gracefully', async () => {
      const mockFetch = async () => {
        throw new Error('Connection reset by peer');
      };

      await assert.rejects(
        async () => {
          await sendResendEmail(
            {
              submissionId: 'sub-12345',
              name: 'Jane Doe',
              email: 'jane@sitelens.test',
              categoryLabel: 'General',
              message: 'Test message over 10 chars.',
            },
            're_key',
            mockFetch
          );
        },
        { code: 'unavailable' }
      );
    });
  });

  describe('5. End-to-End Handler (App Check, Idempotency & Persistence)', () => {
    test('blocks request when App Check verification fails', async () => {
      const request = {
        app: null, // missing App Check token
        data: {
          submissionId: 'sub-appcheck-1',
          name: 'Hacker',
          email: 'hacker@bot.net',
          category: 'general',
          message: 'Automated spam message exceeding ten chars.',
        },
      };

      await assert.rejects(
        async () => {
          await handleUserEnquiry(request, { db: mockDb, enforceAppCheck: true });
        },
        { code: 'unauthenticated' }
      );
    });

    test('successfully processes valid enquiry and records persistence in Firestore', async () => {
      const mockFetch = async () => ({
        ok: true,
        status: 200,
        json: async () => ({ id: 're_123' }),
      });

      const request = {
        app: { appId: 'com.sitelens.app' },
        auth: { uid: 'user_engineering_lead' },
        data: {
          submissionId: 'sub-unique-001',
          name: 'Moloy Goswami',
          email: 'moloy@sitelens.app',
          category: 'enterprise_sales',
          message: 'Inquiring about deploying SiteLens to 50 active highway construction sites.',
        },
      };

      const response = await handleUserEnquiry(request, {
        db: mockDb,
        resendApiKey: 're_test_key',
        fetch: mockFetch,
        enforceAppCheck: true,
      });

      assert.strictEqual(response.success, true);
      assert.strictEqual(response.idempotencyDuplicate, false);

      // Verify record exists in Firestore
      const savedDoc = await mockDb.collection('enquiries').doc('sub-unique-001').get();
      assert.strictEqual(savedDoc.exists, true);
      assert.strictEqual(savedDoc.data().name, 'Moloy Goswami');
      assert.strictEqual(savedDoc.data().userId, 'user_engineering_lead');
      assert.strictEqual(savedDoc.data().status, 'sent');
    });

    test('returns idempotent cached success when submissionId was already processed', async () => {
      let emailSendCount = 0;
      const mockFetch = async () => {
        emailSendCount++;
        return {
          ok: true,
          status: 200,
          json: async () => ({ id: 're_123' }),
        };
      };

      const request = {
        app: { appId: 'com.sitelens.app' },
        auth: { uid: 'user_1' },
        data: {
          submissionId: 'sub-idempotent-retry',
          name: 'Inspector Dave',
          email: 'dave@inspector.com',
          category: 'compliance_enquiry',
          message: 'Verifying SHA-256 compliance audit log export standards.',
        },
      };

      // First submission
      const firstResponse = await handleUserEnquiry(request, {
        db: mockDb,
        resendApiKey: 're_test_key',
        fetch: mockFetch,
        enforceAppCheck: true,
      });
      assert.strictEqual(firstResponse.success, true);
      assert.strictEqual(firstResponse.idempotencyDuplicate, false);
      assert.strictEqual(emailSendCount, 1);

      // Second submission with identical submissionId (e.g. user retried on flaky network)
      const secondResponse = await handleUserEnquiry(request, {
        db: mockDb,
        resendApiKey: 're_test_key',
        fetch: mockFetch,
        enforceAppCheck: true,
      });
      assert.strictEqual(secondResponse.success, true);
      assert.strictEqual(secondResponse.idempotencyDuplicate, true);
      assert.strictEqual(emailSendCount, 1); // Email was NOT sent a second time!
    });

    test('rejects prototype-chain categories without unhandled TypeError or persistence (vuln-0019)', async () => {
      let emailCallCount = 0;
      const mockFetch = async () => {
        emailCallCount++;
        return { ok: true, status: 200, json: async () => ({ id: 're_123' }) };
      };

      const prototypeCategories = ['constructor', 'toString', '__proto__'];
      for (const protoCat of prototypeCategories) {
        const request = {
          app: { appId: 'com.sitelens.app' },
          auth: { uid: 'user_attacker' },
          data: {
            submissionId: `sub-proto-${protoCat}`,
            name: 'Attacker',
            email: 'attacker@example.com',
            category: protoCat,
            message: 'Testing prototype-chain injection resistance.',
          },
        };

        await assert.rejects(
          async () => {
            await handleUserEnquiry(request, {
              db: mockDb,
              resendApiKey: 're_test_key',
              fetch: mockFetch,
              enforceAppCheck: true,
            });
          },
          (err) => {
            // Must be an HttpsError with code 'invalid-argument', NOT a TypeError or generic internal error
            return err.code === 'invalid-argument' && err.message.includes('Category must be one of');
          },
          `Expected prototype category '${protoCat}' to throw invalid-argument HttpsError`
        );

        // Verify no enquiry was persisted
        const savedDoc = await mockDb.collection('enquiries').doc(`sub-proto-${protoCat}`).get();
        assert.strictEqual(savedDoc.exists, false, `Enquiry for ${protoCat} must not be saved to Firestore`);
      }

      // Verify no emails were dispatched
      assert.strictEqual(emailCallCount, 0, 'No emails should be dispatched for prototype categories');
    });

    test('processes all valid categories end-to-end with persistence and email dispatch', async () => {
      const dispatchedEmails = [];
      const mockFetch = async (url, options) => {
        const body = JSON.parse(options.body);
        dispatchedEmails.push(body);
        return {
          ok: true,
          status: 200,
          json: async () => ({ id: `re_${dispatchedEmails.length}` }),
        };
      };

      for (const [catKey, expectedLabel] of Object.entries(VALID_CATEGORIES)) {
        const subId = `sub-valid-${catKey}`;
        const request = {
          app: { appId: 'com.sitelens.app' },
          auth: { uid: `user_${catKey}` },
          data: {
            submissionId: subId,
            name: `User for ${catKey}`,
            email: `${catKey}@example.com`,
            category: catKey,
            message: `Detailed enquiry message for category ${catKey} exceeding ten chars.`,
          },
        };

        const response = await handleUserEnquiry(request, {
          db: mockDb,
          resendApiKey: 're_test_key',
          fetch: mockFetch,
          enforceAppCheck: true,
        });

        assert.strictEqual(response.success, true);
        assert.strictEqual(response.submissionId, subId);

        // Verify Firestore persistence
        const doc = await mockDb.collection('enquiries').doc(subId).get();
        assert.strictEqual(doc.exists, true);
        assert.strictEqual(doc.data().category, catKey);
        assert.strictEqual(doc.data().categoryLabel, expectedLabel);
      }

      // All categories were dispatched
      assert.strictEqual(dispatchedEmails.length, Object.keys(VALID_CATEGORIES).length);
      for (let i = 0; i < dispatchedEmails.length; i++) {
        const expectedLabel = Object.values(VALID_CATEGORIES)[i];
        assert.strictEqual(dispatchedEmails[i].subject.includes(`[${expectedLabel}]`), true);
      }
    });
  });
});
