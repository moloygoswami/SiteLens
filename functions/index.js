const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK if not already initialized
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const resendApiKeySecret = defineSecret('RESEND_API_KEY');

const VALID_CATEGORIES = Object.freeze({
  general: 'General Enquiry',
  bug_report: 'Bug Report',
  feature_request: 'Feature Request',
  enterprise_sales: 'Enterprise / Site Deployment',
  compliance_enquiry: 'Compliance & Audit',
});

const EMAIL_REGEX =
  /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/;

/**
 * Escapes user-controlled text for safe insertion into HTML.
 * @param {string} unsafe
 * @returns {string}
 */
function escapeHtml(unsafe) {
  if (typeof unsafe !== 'string') return '';
  return unsafe
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

const SUBMISSION_ID_REGEX = /^[A-Za-z0-9_-]{8,128}$/;
const CRLF_OR_CONTROL_REGEX = /[\r\n\x00-\x1F\x7F]/;

/**
 * Validates submission payload.
 * @param {object} data
 */
function validateEnquiryPayload(data) {
  if (!data || typeof data !== 'object') {
    throw new HttpsError('invalid-argument', 'Request payload must be a JSON object.');
  }

  const { name, email, category, message, submissionId } = data;

  if (typeof submissionId !== 'string' || !SUBMISSION_ID_REGEX.test(submissionId.trim())) {
    throw new HttpsError('invalid-argument', 'A valid client submissionId (8-128 alphanumeric characters, dashes, or underscores) is required.');
  }

  if (typeof name !== 'string' || name.trim().length < 1 || name.trim().length > 100 || CRLF_OR_CONTROL_REGEX.test(name)) {
    throw new HttpsError('invalid-argument', 'Name must be between 1 and 100 characters and cannot contain newline or control characters.');
  }

  if (typeof email !== 'string' || !EMAIL_REGEX.test(email.trim()) || email.trim().length > 254 || CRLF_OR_CONTROL_REGEX.test(email)) {
    throw new HttpsError('invalid-argument', 'A valid email address is required.');
  }

  if (typeof category !== 'string' || !VALID_CATEGORIES[category]) {
    throw new HttpsError(
      'invalid-argument',
      `Category must be one of: ${Object.keys(VALID_CATEGORIES).join(', ')}.`
    );
  }

  if (typeof message !== 'string' || message.trim().length < 10 || message.trim().length > 5000) {
    throw new HttpsError('invalid-argument', 'Message must be between 10 and 5000 characters.');
  }

  return {
    submissionId: submissionId.trim(),
    name: name.trim(),
    email: email.trim().toLowerCase(),
    category: category.trim(),
    categoryLabel: VALID_CATEGORIES[category.trim()],
    message: message.trim(),
  };
}

/**
 * Checks and increments persistent rate limit in Firestore.
 * Window: 10 minutes (default). Limit: 5 submissions per identifier (default).
 * @param {admin.firestore.Firestore} db
 * @param {string} identifier
 * @param {number} [maxAttempts=5]
 * @param {number} [windowMs=600000]
 */
async function checkPersistentRateLimit(db, identifier, maxAttempts = 5, windowMs = 10 * 60 * 1000) {
  const now = Date.now();
  const rateLimitRef = db.collection('_system_rate_limits').doc(`enquiry_${identifier}`);

  await db.runTransaction(async (transaction) => {
    const doc = await transaction.get(rateLimitRef);
    let timestamps = [];

    if (doc.exists) {
      const data = doc.data();
      if (Array.isArray(data.timestamps)) {
        // Retain timestamps within the current sliding window
        timestamps = data.timestamps.filter((t) => typeof t === 'number' && now - t < windowMs);
      }
    }

    if (timestamps.length >= maxAttempts) {
      const oldest = timestamps[0];
      const waitSeconds = Math.ceil((oldest + windowMs - now) / 1000);
      throw new HttpsError(
        'resource-exhausted',
        `Rate limit exceeded. Please wait ${waitSeconds > 0 ? waitSeconds : 60} seconds before submitting another enquiry.`
      );
    }

    timestamps.push(now);
    transaction.set(rateLimitRef, {
      identifier,
      timestamps,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

/**
 * Sends email via Resend REST API using native fetch.
 * @param {object} params
 * @param {string} resendApiKey
 * @param {function} [customFetch]
 */
async function sendResendEmail({ submissionId, name, email, categoryLabel, message }, resendApiKey, customFetch = fetch) {
  if (!resendApiKey) {
    throw new HttpsError('internal', 'Email service configuration is unavailable.');
  }

  const fromEmail = process.env.RESEND_FROM_EMAIL || 'SiteLens Support <onboarding@resend.dev>';
  const toEmail = process.env.SUPPORT_EMAIL_RECIPIENT || 'moloygoswami@outlook.com';

  const escapedName = escapeHtml(name);
  const escapedEmail = escapeHtml(email);
  const escapedCategory = escapeHtml(categoryLabel);
  const escapedMessage = escapeHtml(message).replace(/\n/g, '<br/>');

  const textBody = [
    `SiteLens User Enquiry`,
    `----------------------------------------`,
    `Category: ${categoryLabel}`,
    `From: ${name} (${email})`,
    `Submission ID: ${submissionId}`,
    `Date: ${new Date().toISOString()}`,
    `----------------------------------------`,
    ``,
    message,
    ``,
    `----------------------------------------`,
    `Reply directly to this email to respond to ${name}.`,
  ].join('\n');

  const htmlBody = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0d110f; color: #f8fafc; padding: 24px; }
    .container { max-width: 600px; margin: 0 auto; background: #1a221e; border: 1px solid #2d3b34; border-radius: 12px; padding: 24px; box-shadow: 0 4px 12px rgba(0,0,0,0.5); }
    .header { border-bottom: 1px solid #2d3b34; padding-bottom: 16px; margin-bottom: 20px; }
    .title { color: #f97316; font-size: 20px; font-weight: 700; margin: 0 0 6px 0; }
    .meta { font-size: 13px; color: #94a3b8; line-height: 1.6; }
    .badge { display: inline-block; background: #2d3b34; color: #38bdf8; padding: 4px 8px; border-radius: 4px; font-weight: 600; font-size: 12px; }
    .content-box { background: #0d110f; border: 1px solid #2d3b34; border-radius: 8px; padding: 16px; margin: 20px 0; font-size: 14px; line-height: 1.6; color: #e2e8f0; }
    .footer { font-size: 12px; color: #64748b; border-top: 1px solid #2d3b34; padding-top: 16px; margin-top: 24px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="title">SiteLens User Enquiry</div>
      <div class="meta">
        <strong>Category:</strong> <span class="badge">${escapedCategory}</span><br/>
        <strong>From:</strong> ${escapedName} (&lt;a href="mailto:${escapedEmail}" style="color:#38bdf8;"&gt;${escapedEmail}&lt;/a&gt;)<br/>
        <strong>Submission ID:</strong> <code>${escapeHtml(submissionId)}</code>
      </div>
    </div>
    <div class="content-box">
      ${escapedMessage}
    </div>
    <div class="footer">
      This enquiry was submitted securely from the SiteLens mobile app. Reply directly to this email to respond to the user.
    </div>
  </div>
</body>
</html>
`.trim();

    const sanitizedHeaderName = name.replace(/[\r\n\x00-\x1F\x7F]/g, ' ').trim();
    const sanitizedHeaderCategory = categoryLabel.replace(/[\r\n\x00-\x1F\x7F]/g, ' ').trim();

  let response;
  try {
    response = await customFetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
        'Idempotency-Key': submissionId,
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [toEmail],
        reply_to: email,
        subject: `[SiteLens Enquiry] [${sanitizedHeaderCategory}] from ${sanitizedHeaderName}`,
        text: textBody,
        html: htmlBody,
      }),
    });
  } catch (netErr) {
    console.error('[submitUserEnquiry] Network error calling Resend API:', netErr);
    throw new HttpsError('unavailable', 'Network error connecting to email provider. Please try again.');
  }

  if (!response.ok) {
    const errorText = await response.text().catch(() => '');
    console.error(`[submitUserEnquiry] Resend API error (${response.status}):`, errorText);

    if (response.status === 429) {
      throw new HttpsError('resource-exhausted', 'Email service rate limit reached. Please retry shortly.');
    }
    if (response.status >= 400 && response.status < 500) {
      throw new HttpsError('invalid-argument', 'Unable to process enquiry. Please check your submission details.');
    }
    throw new HttpsError('internal', 'Failed to dispatch email. Our support team has been notified.');
  }

  const result = await response.json().catch(() => ({}));
  return result;
}

/**
 * Defensive caller IP extraction for Cloud Functions 2nd-gen runtime.
 * Under Cloud Functions 2nd-gen (Cloud Run / GFE), Express has `trust proxy` enabled,
 * which causes `req.ip` to evaluate to the LEFTMOST (attacker-controlled) entry of X-Forwarded-For.
 * Google Front End appends the real client IP as the RIGHTMOST entry of X-Forwarded-For.
 * This function extracts the trusted rightmost entry, normalizes IPv4-mapped IPv6 addresses,
 * and falls back to socket.remoteAddress.
 *
 * @param {object} request
 * @returns {string}
 */
function extractClientIp(request) {
  let callerIp = 'anonymous';
  let rawForwardedFor;
  if (request.rawRequest && request.rawRequest.headers) {
    rawForwardedFor =
      request.rawRequest.headers['x-forwarded-for'] ||
      request.rawRequest.headers['X-Forwarded-For'];
  }
  if (Array.isArray(rawForwardedFor)) {
    rawForwardedFor = rawForwardedFor.join(',');
  }
  if (typeof rawForwardedFor === 'string' && rawForwardedFor.trim().length > 0) {
    const entries = rawForwardedFor
      .split(',')
      .map((e) => e.trim())
      .filter((e) => e.length > 0);
    if (entries.length > 0) {
      callerIp = entries[entries.length - 1];
    }
  } else if (
    request.rawRequest &&
    ((request.rawRequest.socket && request.rawRequest.socket.remoteAddress) ||
     (request.rawRequest.connection && request.rawRequest.connection.remoteAddress))
  ) {
    callerIp =
      (request.rawRequest.socket && request.rawRequest.socket.remoteAddress) ||
      (request.rawRequest.connection && request.rawRequest.connection.remoteAddress);
  }

  if (callerIp.startsWith('::ffff:')) {
    callerIp = callerIp.slice(7);
  }

  return callerIp;
}

/**
 * Core handler logic for submitUserEnquiry (exported for unit testing).
 */
async function handleUserEnquiry(request, options = {}) {
  const db = options.db || admin.firestore();
  const resendApiKey = options.resendApiKey || (process.env.RESEND_API_KEY || (resendApiKeySecret.value ? resendApiKeySecret.value() : null));
  const customFetch = options.fetch || fetch;

  // 1. Enforce App Check if configured and not bypassed in test mode
  if (options.enforceAppCheck !== false) {
    if (!request.app) {
      throw new HttpsError(
        'unauthenticated',
        'App Check verification failed. Unverified app requests are blocked.'
      );
    }
  }

  // 2. Validate and sanitize input
  const validated = validateEnquiryPayload(request.data);

  // 3. Persistent Rate Limiting (vuln-0002/vuln-0001 remediation; hardened against X-Forwarded-For spoofing)
  const callerUid = request.auth ? request.auth.uid : null;

  // Caller IP MUST NOT come from req.ip: on GCF 2nd-gen the functions-framework
  // runtime enables Express `trust proxy`, so `req.ip` resolves to the LEFTMOST
  // (attacker-controlled) X-Forwarded-For entry. The trusted Google Front End
  // appends the real client IP as the RIGHTMOST entry, so derive the IP from the
  // rightmost entry and fall back to the socket remote address.
  const callerIp = extractClientIp(request);
  const ipKey = callerIp.replace(/[^a-zA-Z0-9]/g, '_') || 'anonymous';

  // Step 3a: Enforce Aggregate Per-IP Limit for ALL requests (prevents multi-account farming)
  // Baseline: 10 attempts per 10-minute sliding window across all accounts from the same IP
  await checkPersistentRateLimit(db, `ip_aggregate_${ipKey}`, 10, 10 * 60 * 1000);

  // Step 3a-2: Global non-IP aggregate cap (defense-in-depth). Even if the caller
  // IP cannot be pinned down reliably, total submission volume stays bounded.
  await checkPersistentRateLimit(db, 'global_total', 100, 10 * 60 * 1000);

  // Step 3b: Enforce granular limit (5 attempts / 10 minutes)
  // - For authenticated callers: scoped to UID + IP (uid_${callerUid}_ip_${ipKey})
  // - For unauthenticated callers: scoped to unauth IP (ip_unauth_${ipKey})
  if (callerUid) {
    await checkPersistentRateLimit(db, `uid_${callerUid}_ip_${ipKey}`, 5, 10 * 60 * 1000);
  } else {
    await checkPersistentRateLimit(db, `ip_unauth_${ipKey}`, 5, 10 * 60 * 1000);
  }

  // 4. Idempotency Check in Firestore
  const enquiryRef = db.collection('enquiries').doc(validated.submissionId);
  const existingDoc = await enquiryRef.get();

  if (existingDoc.exists) {
    const existingData = existingDoc.data();
    if (existingData && existingData.status === 'sent') {
      return {
        success: true,
        submissionId: validated.submissionId,
        message: 'Enquiry previously received and confirmed.',
        idempotencyDuplicate: true,
      };
    }
  }

  // 5. Send email via Resend
  const resendResult = await sendResendEmail(validated, resendApiKey, customFetch);

  // 6. Record completed enquiry in Firestore
  await enquiryRef.set({
    submissionId: validated.submissionId,
    name: validated.name,
    email: validated.email,
    category: validated.category,
    categoryLabel: validated.categoryLabel,
    messageLength: validated.message.length,
    status: 'sent',
    resendId: resendResult.id || null,
    userId: callerUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    submissionId: validated.submissionId,
    message: 'Your enquiry has been successfully received by SiteLens support.',
    idempotencyDuplicate: false,
  };
}

/**
 * 2nd-Gen Firebase Callable Cloud Function: submitUserEnquiry
 */
exports.submitUserEnquiry = onCall(
  {
    enforceAppCheck: true,
    consumeAppCheckToken: true,
    secrets: [resendApiKeySecret],
    region: 'us-central1',
    cors: false,
  },
  async (request) => {
    return handleUserEnquiry(request);
  }
);

// Export internals for testability
exports.escapeHtml = escapeHtml;
exports.validateEnquiryPayload = validateEnquiryPayload;
exports.checkPersistentRateLimit = checkPersistentRateLimit;
exports.sendResendEmail = sendResendEmail;
exports.handleUserEnquiry = handleUserEnquiry;
exports.VALID_CATEGORIES = VALID_CATEGORIES;
exports.extractClientIp = extractClientIp;
