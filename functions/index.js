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

// Global rate limiting thresholds (AC-SECF-03 / 04_SECURITY.MD §10 / Finding 6)
const GLOBAL_RATE_LIMIT_CAP = 200;
const GLOBAL_RATE_LIMIT_ALERT = 160;

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

  if (
    typeof category !== 'string' ||
    !Object.prototype.hasOwnProperty.call(VALID_CATEGORIES, category)
  ) {
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
 * @param {number|null} [alertThreshold=null]
 */
async function checkPersistentRateLimit(db, identifier, maxAttempts = 5, windowMs = 10 * 60 * 1000, alertThreshold = null) {
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

    if (typeof alertThreshold === 'number' && timestamps.length >= alertThreshold) {
      console.warn(
        `[RateLimitAlert] High-water mark reached for '${identifier}': ${timestamps.length}/${maxAttempts} submissions in sliding window.`
      );
    }

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

  // Step 3b: Enforce granular limit (5 attempts / 10 minutes)
  // - For authenticated callers: scoped to UID across all IPs (uid_${safeUid}) as well as
  //   UID + IP (uid_${safeUid}_ip_${ipKey}). This strictly prevents an authenticated user
  //   from bypassing limits by rotating IP addresses.
  // - For unauthenticated callers: scoped to unauth IP (ip_unauth_${ipKey})
  const safeUid = callerUid ? callerUid.replace(/[^a-zA-Z0-9_-]/g, '_') : null;
  if (safeUid) {
    await checkPersistentRateLimit(db, `uid_${safeUid}`, 5, 10 * 60 * 1000);
    await checkPersistentRateLimit(db, `uid_${safeUid}_ip_${ipKey}`, 5, 10 * 60 * 1000);
  } else {
    await checkPersistentRateLimit(db, `ip_unauth_${ipKey}`, 5, 10 * 60 * 1000);
  }

  // Step 3c: Enforce Global Non-IP Aggregate Cap (AC-SECF-03 / 04_SECURITY.MD §10)
  // G = 200 submissions / 10-minute sliding window; high-water alert at 160 (80%).
  // Crucial (vuln-0018 remediation): Steps 3a and 3b execute BEFORE this global tier.
  // Because any individual UID is capped at 5 and any single IP is capped at 10,
  // a single abusive actor cannot consume the global quota of 200 and starve others.
  await checkPersistentRateLimit(db, 'global_total', GLOBAL_RATE_LIMIT_CAP, 10 * 60 * 1000, GLOBAL_RATE_LIMIT_ALERT);

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

/**
 * Core handler logic for deleteUserAccount (exported for unit testing).
 * Follows the finalized SiteLens Account Deletion Architecture.
 *
 * @param {object} request - Firebase Callable request
 * @param {object} [options] - Injected dependencies (db, auth, storage, enforceAppCheck)
 */
async function handleDeleteUserAccount(request, options = {}) {
  // 1. Enforce App Check if configured and not explicitly bypassed in test mode
  if (options.enforceAppCheck !== false) {
    if (!request.app) {
      throw new HttpsError(
        'unauthenticated',
        'App Check verification failed. Unverified app requests are blocked.'
      );
    }
  }

  // 2. Strict Authentication Check (Derived exclusively from request.auth.uid)
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError(
      'unauthenticated',
      'User must be authenticated to delete their account.'
    );
  }

  const callerUid = request.auth.uid;
  const db = options.db || admin.firestore();
  const auth = options.auth || admin.auth();
  const storage = options.storage || admin.storage();
  const bucket = options.bucket || (typeof storage.bucket === 'function'
    ? storage.bucket(process.env.STORAGE_BUCKET || 'sitelens-prod-80e7b.firebasestorage.app')
    : null);

  // R23 (Deletion Safety): every required destructive remote cleanup failure is
  // tracked. The function must never report a successful account deletion while
  // any required cleanup remains unresolved, otherwise the client would purge
  // its local evidence (the last surviving copy) after a falsely successful
  // remote deletion.
  const cleanupFailures = [];
  const recordFailure = (operation, err) => {
    const reason = err && err.message ? err.message : String(err);
    cleanupFailures.push({ operation, reason });
    console.warn(`[deleteUserAccount] ${operation} failed:`, reason);
  };

  // 3. Authoritative Firestore Discovery of all creator-owned sites.
  // SiteLens v1 is single-tenant creator-owned: the caller is the only identity
  // processed, and every site they can reach is one where creator_id == callerUid.
  // Membership, shared-site, and successor-administrator concepts do not exist
  // in v1, so no collectionGroup/member discovery is performed.
  const siteIds = new Set();

  try {
    const createdSitesSnap = await db.collection('sites').where('creator_id', '==', callerUid).get();
    createdSitesSnap.forEach((doc) => siteIds.add(doc.id));
  } catch (err) {
    recordFailure('discover creator-owned sites', err);
  }

  // 4. Execute Destructive Cleanup Idempotently (creator-owned sites only).
  // A site document is removed only once every required cleanup for that site
  // succeeded, so a partial failure stays discoverable for a safe, idempotent
  // retry instead of stranding unreclaimed Storage artifacts behind a deleted
  // site document.
  let purgedStorageFilesCount = 0;

  for (const siteId of siteIds) {
    const siteRef = db.collection('sites').doc(siteId);
    let siteCleanupSucceeded = true;

    // Delete Cloud Storage files
    if (bucket && typeof bucket.deleteFiles === 'function') {
      try {
        const [files] = await bucket.getFiles({ prefix: `sites/${siteId}/` });
        if (files && files.length > 0) {
          await bucket.deleteFiles({ prefix: `sites/${siteId}/` });
          purgedStorageFilesCount += files.length;
        }
      } catch (storageErr) {
        siteCleanupSucceeded = false;
        recordFailure(`purge Storage for site ${siteId}`, storageErr);
      }
    } else {
      siteCleanupSucceeded = false;
      recordFailure(`purge Storage for site ${siteId}`, new Error('Storage bucket unavailable'));
    }

    // Delete Firestore /media subcollection documents
    try {
      const mediaSnap = await siteRef.collection('media').get();
      for (const mDoc of mediaSnap.docs) {
        try {
          await mDoc.ref.delete();
        } catch (mediaErr) {
          siteCleanupSucceeded = false;
          recordFailure(`delete media ${mDoc.id} for site ${siteId}`, mediaErr);
        }
      }
    } catch (mediaQueryErr) {
      siteCleanupSucceeded = false;
      recordFailure(`enumerate media for site ${siteId}`, mediaQueryErr);
    }

    // Delete the site document only if its own cleanup fully succeeded.
    if (siteCleanupSucceeded) {
      try {
        await siteRef.delete();
      } catch (siteErr) {
        recordFailure(`delete site ${siteId}`, siteErr);
      }
    }
  }

  // 5a. User Profile Document: Delete /users/{uid} if present
  try {
    await db.collection('users').doc(callerUid).delete();
  } catch (userErr) {
    recordFailure(`delete user profile ${callerUid}`, userErr);
  }

  // 5b. Support / Enquiries Scrubbing: Anonymize personal identifiers
  try {
    const enquiriesSnap = await db.collection('enquiries').where('userId', '==', callerUid).get();
    for (const enqDoc of enquiriesSnap.docs) {
      try {
        await enqDoc.ref.update({
          userId: null,
          email: '[deleted]',
          name: '[deleted]',
        });
      } catch (enqErr) {
        recordFailure(`anonymize enquiry ${enqDoc.id}`, enqErr);
      }
    }
  } catch (enqQueryErr) {
    recordFailure('enumerate enquiries', enqQueryErr);
  }

  // 5c. Ephemeral Rate-Limit Records: Clean up user-specific entries
  try {
    const rateLimitsSnap = await db.collection('_system_rate_limits').get();
    for (const rlDoc of rateLimitsSnap.docs) {
      if (rlDoc.id.includes(`_${callerUid}_`) || rlDoc.id.startsWith(`uid_${callerUid}_`)) {
        try {
          await rlDoc.ref.delete();
        } catch (rlErr) {
          recordFailure(`delete rate-limit record ${rlDoc.id}`, rlErr);
        }
      }
    }
  } catch (rlQueryErr) {
    recordFailure('enumerate rate-limit records', rlQueryErr);
  }

  // 6. R23: Fail closed before deleting the Auth identity. Reporting failure
  // (instead of success) is what stops the client from purging its local
  // evidence. The Auth identity is left intact so the caller can safely retry:
  // every completed step above is idempotent.
  if (cleanupFailures.length > 0) {
    const operations = cleanupFailures.map((f) => f.operation).join('; ');
    throw new HttpsError(
      'internal',
      `Account deletion incomplete: ${cleanupFailures.length} required remote cleanup operation(s) failed (${operations}). Nothing was reported deleted; please retry.`
    );
  }

  // 7. Delete Firebase Authentication Identity
  try {
    await auth.deleteUser(callerUid);
  } catch (authErr) {
    // If the user was already deleted in Auth (idempotent retry), continue cleanly
    if (authErr.code !== 'auth/user-not-found') {
      console.error('[deleteUserAccount] Error deleting Firebase Auth user:', authErr);
      throw new HttpsError('internal', 'Failed to delete authentication credentials. Please retry.');
    }
  }

  return {
    success: true,
    deletedSitesCount: siteIds.size,
    purgedStorageFilesCount,
    message: 'Account and associated personal data successfully deleted.',
  };
}

/**
 * 2nd-Gen Firebase Callable Cloud Function: deleteUserAccount
 */
exports.deleteUserAccount = onCall(
  {
    enforceAppCheck: true,
    region: 'us-central1',
    cors: false,
  },
  async (request) => {
    return handleDeleteUserAccount(request);
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
exports.handleDeleteUserAccount = handleDeleteUserAccount;
exports.GLOBAL_RATE_LIMIT_CAP = GLOBAL_RATE_LIMIT_CAP;
exports.GLOBAL_RATE_LIMIT_ALERT = GLOBAL_RATE_LIMIT_ALERT;

