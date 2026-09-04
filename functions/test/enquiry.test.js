const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert');
const {
  escapeHtml,
  validateEnquiryPayload,
  checkPersistentRateLimit,
  sendResendEmail,
  handleUserEnquiry,
  VALID_CATEGORIES,
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

    test('rejects invalid or unknown category', () => {
      assert.throws(
        () =>
          validateEnquiryPayload({
            submissionId: 'test-uuid-1234',
            name: 'John',
            email: 'john@example.com',
            category: 'unauthorized_hack_category',
            message: '1234567890',
          }),
        { code: 'invalid-argument' }
      );
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

    test('rate limits unauthenticated callers by remote IP and ignores spoofed X-Forwarded-For (vuln-0002)', async () => {
      const mockFetch = async () => ({
        ok: true,
        status: 200,
        json: async () => ({ id: 're_123' }),
      });

      const fixedIp = '203.0.113.195';

      // Submit 5 requests from the same real IP, but rotating spoofed X-Forwarded-For header
      for (let i = 1; i <= 5; i++) {
        const req = {
          app: { appId: 'com.sitelens.app' },
          rawRequest: {
            ip: fixedIp,
            headers: { 'x-forwarded-for': `198.51.100.${i}` }, // Spoofed header
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
          ip: fixedIp,
          headers: { 'x-forwarded-for': '198.51.100.99' },
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

      // 10 distinct UIDs from the exact same IP each submit 1 request
      for (let i = 1; i <= 10; i++) {
        const req = {
          app: { appId: 'com.sitelens.app' },
          auth: { uid: `attacker_uid_${i}` },
          rawRequest: { ip: fixedIp },
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
        rawRequest: { ip: fixedIp },
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
          rawRequest: { ip: fixedIp },
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
        rawRequest: { ip: fixedIp },
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
        rawRequest: { ip: fixedIp },
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
            rawRequest: { ip: ip1 },
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
              rawRequest: { ip: ip1 },
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
          rawRequest: { ip: ip2 },
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
  });
});
