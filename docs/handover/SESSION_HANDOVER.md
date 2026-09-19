# SiteLens — Session Handover (Fast-Start Operational Context)

**Last updated**: 2026-09-19T16:55:00+05:30 (supersedes 2026-09-19T06:30:00+05:30)
**HEAD**: `f648779` on `main` (with uncommitted Phase 2.3 Wave A + Wave A.1 + Phase 2.4 Wave B + Waves B.1/C/D [R11–R16] + Wave E [R17–R20] + Wave F [R21] remediation)
**Database schema**: Drift **v10**
**Frozen release tag `v1.0.0`**: `a17e8c3580c157ba629bfc8fe39fa2fd75da923c` (UNMOVED)
**Active test device**: Motorola edge 50 fusion `ZA222NBPPV` (Android 16 / API 36)
**Governing mandate**: Rule 5 — Evidence Integrity (truthful temporal, spatial, optical and provenance claims)

> This file is the **fast-start operational context**. Detailed historical and project knowledge lives in
> the documents below — load them only when relevant.

### Documentation Map
- `docs/handover/PRD.md` — canonical product requirements (aligned to approved v1 creator-owned/user-specific product boundary).
- `docs/handover/architecture.md` — architecture specification (aligned to approved v1 non-collaborative / creator-owned model).
- `docs/handover/PROJECT_STATUS.md` — pre-v1.0.0 milestone & toolchain ledger (dated 2026-09-14, HEAD `f868a17`; partially superseded).
- `docs/handover/E2E_RELIABILITY_AUDIT.md` — original read-only E2E reliability audit (F1/F2/F3).
- `docs/handover/REMEDIATION_DESIGN_REVIEW.md` — F1/F2/F3 remediation specification.
- `docs/ALL_TESTS.md` — authoritative test inventory (refresh pending; still states 539).
- `strix-sitelens-instructions.md` — authoritative repository & security instructions (8/8 closed-findings baseline).
- **Detailed Module A–J and Cross-Cutting Audit A–D findings/remediations** — retained in git history
  (`git show f76ef67:docs/handover/SESSION_HANDOVER.md`, 751 lines); this file keeps only their accepted outcomes.

---

## 1. CURRENT STATE

- **Repository**: `main` at `f648779`. Uncommitted controlled remediation for **Phase 2.3 Wave A**, **Wave A.1**
  and **Phase 2.4 Wave B**.
- **Phase 2 Progression**:
  - **Phase 1**: Approved R01–R26 normalized remediation ledger established.
  - **Phase 2.1A**: PRD specification revised and approved for v1 creator-owned, user-specific, location-independent, non-collaborative boundary.
  - **Phase 2.1B**: Architecture specification revised and approved for v1 model.
  - **Phase 2.2**: Concrete remediation implementation plan established for R01–R26 across Waves A–G.
  - **Phase 2.3 Wave A (Security / User Data Domain — R01, R04, R05) COMPLETED**:
    - **R01**: Purged membership/RBAC/sharing/invitation access from the app and security rules. Direct creator-bound hydration only (`creator_id == userId`).
    - **R04**: Enforced strict fail-closed boundary across all local Drift repositories and gallery streams when UID is null/empty. Session teardown decouples active site per user UID (`sitelens_active_site_id_<uid>`) and invalidates cached filters and streams.
    - **R05**: Enforced strict creator binding (`creator_id == request.auth.uid`) across Firestore and Cloud Storage rules, with immutable forensic metadata.
  - **Wave A.1 (follow-up corrections) COMPLETED**:
    - **R01 closure**: removed the remaining active sharing/RBAC paths — the `collectionGroup('members')` discovery, shared-site/sole-member classification and successor-admin logic in the `deleteUserAccount` Cloud Function, plus `successorAdmins` / `SuccessorSiteRequirement` / `EligibleMember` / the "Admin Succession" dialog flow in the client. Corrected the false "shared sites" retention copy.
    - **R04 closure**: `getTombstoneSyncCandidates(null)` was returning **every** user's tombstones — now fail-closed; `watchTombstoneCandidateCount` and `getResolvedMediaIds` scoped and fail-closed; the `SyncCoordinator` count-stream subscription re-bound to the authenticated UID (restoring the F1 new-capture auto-sync trigger).
  - **Phase 2.4 Wave B (GPS / Capture Authority — R02, R03, R06, R07, R08, R09, R10) COMPLETED**:
    - **R02**: Shutter readiness strictly gated on `hasLiveFix` (camera hardware readiness kept distinct from evidence-capture readiness).
    - **R03**: Countdown re-gated on a live fix at every tick; GPS loss aborts the countdown; capture reads the current GPS authority, never a press-time snapshot.
    - **R06**: Position buffer now carries provenance; a cached last-known seed can never enter the live-fix selection path; the single `applyBestRecentPosition` authority replaced three duplicated inline splices.
    - **R07**: Video T₀ is the immutable spatial/telemetry authority — the recording-start GPS snapshot governs persisted coordinates/altitude/GNSS; stop-time fixes never usurp it.
    - **R08**: Lens switching, digital zoom, aspect-ratio and capture-timer controls locked while recording (UI + controller).
    - **R09**: Audio-track disclosure implemented — effective `enableAudio` captured from the initializing preset, frozen at T₀, persisted (`has_audio_track`, Drift v10) and disclosed in Media Detail.
    - **R10**: Unknown telemetry semantics — unestablished altitude stays `null` (no `0.0` substitution), compass heading persisted nullably (`heading_degrees`, Drift v10), HUD no longer zero-fills altitude.
  - **Waves B.1/C/D (R11–R16) — Capture Workflow / Integrity / Replication — COMPLETED**:
    - **R11**: Minimap race guard — monotonic generational tokens prevent stale map tiles burning into evidence on fast shutter; offline fallback is a neutral status, never fabricated map graphics.
    - **R12**: Single-flight capture mutex (`_isCapturing`) wraps the shutter trigger; re-entrant taps during an in-flight video start dispatch exactly one recording.
    - **R13**: Single video playback owner (`EvidenceVideoPlayback`); Review & Tag previews through the shared owner and hands it to the gallery, so there is never a second decoder for one recording. In-flight recording recovery (Keep for Later / Discard) on app restart.
    - **R14**: Review & Tag back/dismiss guarded by `PopScope` — an in-flight save can never be discarded by an accidental back gesture; re-entrance guard prevents stacked discard dialogs.
    - **R15**: Two-tier SHA-256 (`sha256_hash` original, `evidence_sha256_hash` burned evidence); `verifyBytes()` distinguishes stored hash from live-byte verification; published bytes are re-verified against their digest.
    - **R16**: Cloud evidence artifact replication **Option A** — `evid_<id>.jpg` replicated to `users/{uid}/evidence/{siteId}/{mediaId}.jpg` as the cloud-authoritative artifact; path is creator-bound and immutable in rules.
  - **Wave E (R17–R20) — Smart-Link / Spatial / Identity — COMPLETED**:
    - **R17**: Smart-link temporal semantics — a BEFORE Non-Conformity must be captured strictly earlier than the observation; enforced at the repository query, `isEligibleCandidate`, and both persistence boundaries. A missing/unparseable timestamp is not temporal authority.
    - **R18**: Smart-link non-destructive/live-distance — unlinking nulls `linked_media_id` without modifying the candidate record; candidate proximity is dynamic live distance (`null` → "distance unknown", never `0`).
    - **R19**: Nearby-search spatial uncertainty — a candidate's own GNSS accuracy widens the radius bound and synthetic `(0,0)` coordinates are rejected; distance displays disclose the GNSS uncertainty margin (e.g. `X.Xm (±Y.Ym)`) so sub-meter overclaiming is prohibited.
    - **R20**: Canonical site identity — Review & Tag, the Nearby picker, and export metadata resolve the human-facing canonical site code/name via `HudFormatter.resolveSiteIdentifier`; the internal database site id is never rendered as an identifier.
  - **Wave F (R21) — Export Attribution — COMPLETED**:
    - **R21**: Exporter identity is strictly decoupled from the persisted evidence creator. The ZIP `manifest.json` attributes each record to its authentic `creator_id` (top-level `evidence_creator_ids`) and records the exporter separately (`exporter_uid`, `exporter_email`); absent human identity stays `null`, never fabricated (`Field Inspector` removed). The PDF report renders `Evidence Creator (UID)` and `Exported By` as distinct rows (plus `Exported By (UID)` in the forensic chain-of-custody block). A shared `ExportAttribution` value object binds creator = persisted `media.creator_id`, exporter = authenticated session.
- **Verification Baseline**:
  - Flutter test suite: **805/805 passed** (0 failed). `flutter analyze`: **0 issues**.
  - Security gate (`test/security`): **89/89** (node:test 75/75 + Jest 19/19, 0 failed suites, 0 skipped).
   - Backend (`functions/`): **39/39**.
- **Wave G in-progress totals (R22 + R23)**: Flutter **809/809** · `flutter analyze` **0 issues** · backend **43/43**
  (39 baseline + 4 R23 cases). Security gate unchanged — node:test **75/75** · Jest **19/19**
  (Firestore/Storage rules untouched by R22/R23).
- **Last installed build**: Phase 1 release APK `sha256 1656855954d780a21c3353fb8f5aa1a2a2dafac78bf9e2af1229df98dc1f5d0a`
  (75,545,189 bytes, ABIs arm64-v8a/armeabi-v7a/x86_64) — physically exercised on device.
- **Device data**: app data was cleared and re-authenticated (Google) during the Phase 1 onboarding
  verification; the device currently holds **0 sites / 0 media**.
- **Knowledge graph**: `graphify-out/` **refreshed** via `graphify update .` (4849 nodes, 7215 edges, 256 communities).
  Community labels are hub-renamed from the previous graph; run `graphify label` to re-label with an LLM if needed.

## 2. ACTIVE TASK

- **Waves A (R01, R04, R05), A.1, B (R02, R03, R06–R10), B.1/C/D (R11–R16), E (R17–R20) and F (R21) Execution Complete and Verified.**
- **Wave G — Rule-by-rule remediation in progress (R23 only, per latest scope):**
  - **R22 — Tombstone Remote Propagation: COMPLETED & VERIFIED.** Defect D1: never-published tombstones probed the cloud before any state check, hitting Firestore permission-denied on non-existent docs → spurious "Permission denied", `tombstone_reconciled` stuck at 0, perpetual retry. Fix: `SyncStatusType.pending` early return before the cloud read; published-tombstone permission-denied preserved as a real failure. Focus: `cloud_sync_service_test` + `sync_coordinator_test` = 74/74; 4 R22 cases confirmed executing.
  - **R23 — Deletion Safety: COMPLETED & VERIFIED.** Defect D2: `handleDeleteUserAccount` swallowed every required destructive cleanup failure and returned `{success:true}`, letting the client purge local evidence after a false remote success. Fix: all required cleanups (site discovery, Storage, media, site doc, user profile, enquiries anonymization, rate-limits) tracked; throws `HttpsError('internal')` before `auth.deleteUser`; Auth identity left intact for safe idempotent retry; a site doc is retained while any of its own cleanup is unresolved. Focus: backend 43/43; new client widget test.
  - **R24–R26 — NOT STARTED.** Awaiting scope authorization.
- **DO NOT implement R24–R26 without explicit user authorization.**
- **Post-Remediation Audits**:
  - **M1 (GPS & Capture Readiness)**: **PASS** (F7 defensive hardening, F5 countdown test gap noted).
  - **M2 (Camera & Capture Workflow)**: **FAIL** — Independent verification confirmed reachable defects NF-M2-01 (site-less / wrong-site video recovery) and NF-M2-03 (Android Back dismisses recovery dialog leaving orphaned media). NF-M2-02 is defensive hardening; NF-M2-04 is benign dead code / semantic inconsistency. Minimum remediation set identified.
  - **Local Jev Integration**: Operational and verified via `~/.local/bin/typesafe-jev` (model `jev-1.13.0`).
- **This change**: M2 post-remediation independent verification + handover documentation.

## 3. REPOSITORY STATE

- **HEAD**: `f648779` (`main`). **Tag `v1.0.0`** `a17e8c3…` frozen.
- **Schema**: Drift **v10**. Version history: v2 `original_uri`; v3 `evidence_sha256_hash`; v4 `captured_address`;
  v5 `creator_id`; v6 Google Photos sync table + index; v7 `altitude_m` + `sites.creator_id`; v8
  `verification_status`, `is_altitude_msl`, `gnss_satellite_count`, `gnss_satellites_used_in_fix`,
  `gnss_fix_timestamp`; v9 `tombstone_reconciled` (`0=pending, 1=reconciled`); **v10 `has_audio_track` (R09) and
  `heading_degrees` (R10)** — both **nullable with NO default**, so historical rows stay explicitly unknown.
  New columns must follow the `AppDatabase.onUpgrade` pattern, bump `schemaVersion`, and regenerate
  `app_database.g.dart` via `dart run build_runner build --delete-conflicting-outputs`.
- **FK enforcement**: the app never sets `PRAGMA foreign_keys = ON`, so SQLite FK enforcement is OFF on device;
  application queries and the atomic `deleteSite` cleanup are authoritative. Unit tests enable FK enforcement.

### Commit Ledger (chronological)
| Commit | Subject |
| :--- | :--- |
| `f648779` | test(security): harden Firebase rules test harness |
| `0680664` | Remove unused media permissions (Phase 1) |
| `edb6d82` | Fix safe deletion of sites with media tombstones (v9) |
| `cc16ff0` | Fix GPS stream recovery after lifecycle resume |
| `d02ae8e` | Remove redundant photo fullscreen metadata |
| `f76ef67` | Stabilize SiteLens evidence workflow |
| `f868a17` | fix(android): remove unnecessary battery optimization permission |
| `68a6263` | feat(account): implement secure account deletion |
| `596e936` | fix(camera): F1 capture timestamp authority, F2 minimap stale-result protection, F3 shutter re-entrancy guard |
| `6a02f91` | security: remediate enquiry rate limiting and qs vulnerabilities |
| `a17e8c3` | release: freeze SiteLens v1.0.0 verified baseline (tag `v1.0.0`) |

> No new commits exist for Waves A / A.1 / B — all three waves are **uncommitted working-tree changes**.

### Release Artifacts & Signing
- **Current (Phase 1)** APK `sha256 1656855954d780a21c3353fb8f5aa1a2a2dafac78bf9e2af1229df98dc1f5d0a`
  (75,545,189 bytes; full fat APK with all three ABIs — larger than the earlier arm64-engine artifacts).
  **This artifact predates Waves A/A.1/B and does not contain them.**
- `edb6d82` APK `sha256 84ec35f1…5717a8a` (30,980,555 bytes); `cc16ff0` APK `sha256 f7fa8f8d…487df3a`
  (30,980,555 bytes, reproducible byte-identically; preserved on disk incl. `build/gps_audit/installed_base.apk`).
- `v1.0.0` baseline APK `sha256 3a98caec498e93fc32852592bccce7c618d0a3b4673fec3cde27ef063f3ba655`; physical-finding
  APK (1.0.0 / 2001) `sha256 265195037f9a7f5ec0af0148440f57fdd2c14ebee2524511a1ad62d7436ffb22`.
- **Signed, not debug-signed**: `CN=SiteLens Release, OU=Mobile Engineering, O=SiteLens, L=Howrah, ST=West Bengal,
  C=IN`, cert SHA-256 `e6b4adb081090f989a5909c87eb832a132afbc7bc1bdc151fea4e02f8d0bbfee`; keystore outside the repo
  (`~/.android/sitelens/release-keystore.jks`, alias `sitelens-release`, valid 2026-09-01 → 2054-01-17). Production
  signing SHA-1 `D8:22:85:B2:0D:1E:11:F4:D2:6C:F0:2F:D1:F7:DF:61:EB:79:2A:69`. **READY FOR PRODUCTION SIGNING**.
- **Secret hygiene**: `android/key.properties`, `android/local.properties`, `android/app/google-services.json`,
  `firebase.json`, `lib/firebase_options.dart` are untracked + gitignored; no `*.jks`/`*.keystore`/`*.p12`/`*.pem` tracked.
- **Permissions shipped (release APK)**: CAMERA, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, RECORD_AUDIO,
  POST_NOTIFICATIONS, INTERNET, ACCESS_NETWORK_STATE (plus library-injected WAKE_LOCK / C2DM RECEIVE / READ_GSERVICES).

## 4. ACCEPTED MODULES

- **Modules A–J (SiteLens #7–#12)** — metadata overlay F1–F5; video persistence & GPS R1–R3; minimap & GPS F1–F4;
  camera permission recovery; photo evidence F1–F3; review tag & smart-link #8 F1–F5; smart-link E2E #9 F-1
  (non-destructive B→A link lifecycle); evidence list #10 F1–F2; offline capture & cloud metadata #11 F1–F2;
  synchronization E2E #12 F-1–F-3.
  - **Waves B.1/C/D (R11–R16)** — minimap race guard (R11); capture mutex (R12); single video playback owner + interrupted-recording recovery (R13); Review & Tag `PopScope`/discard guard (R14); two-tier SHA-256 + live-byte verification (R15); cloud evidence artifact replication Option A (R16).
  - **Wave E (R17–R20)** — smart-link temporal semantics (R17); non-destructive unlinking + live distance (R18); nearby-search spatial uncertainty disclosure (R19); canonical site identity resolver (R20).
  - **Wave F (R21)** — export attribution: persisted evidence creator and authenticated exporter recorded separately; fabricated `Field Inspector` default removed; `ExportAttribution` value object binds creator ≠ exporter.
- **Cross-Cutting Audit A** — F-A1 derived-artifact EXIF strip (original keeps camera EXIF); F-A2 no synthesized GPS
  fallback. **Audit B** — B-1 tombstone propagation (`syncTombstone`; never-published = verified no-op).
  **Audit C** — C-1 video handoff invariant; C-2 `deletePermanently` tombstones rows. **Audit D** — D-SPAT-001
  cached-seed shutter gating (`hasLiveFix`), D-SPAT-002 photo valid-fix gate, LAT-001 NULL-creator parity.
- **E2E Audit Program** — full user journey, Settings & Legal, Account Deletion: all PASS. Backend `functions/`
  suite **39/39** (the `deleteUserAccount` suite is now 5 tests after Wave A.1 removed the 4 obsolete
  shared-site/successor tests; the previous "43/43" was the whole `functions/` total); dialog tests **4/4** (was 5/5).
- **Security hardening (Modules 1–7 + Module 4 local-isolation follow-up)** — 8/8 findings closed; baseline
  documented in `strix-sitelens-instructions.md`.
- **A1** single `EvidenceVideoPlayback` owner (inline + fullscreen share one controller). **A2** `appRouteObserver`
  releases/reacquires CameraX across page routes. **B1** GPS state semantics (Unknown ≠ Denied, Service-Off ≠ Denied,
  Last-Known ≠ Live Fix). **C1** fullscreen video HUD renders canonical `siteCode` (never internal `siteId`).
- **Photo/Video metadata-card unification** — one canonical runtime card for **Video** only; **Photo fullscreen**
  (`d02ae8e`) shows only the burned evidence JPEG (`showHud && isVideo`).
- **B1 GPS lifecycle recovery (`cc16ff0`)** — lifecycle resume cancels the paused subscription and creates a NEW
  native stream (never `Subscription.resume()`).
- **Onboarding/permissions, auth session recovery, closed-evidence workflow, true MSL altitude, fixed portrait
  orientation, HUD geometry/scaling** — accepted (see `PROJECT_STATUS.md`).
- **Save-path performance audit** — read-only; **DO NOT OPTIMIZE**.
- **v9 safe site deletion (`edb6d82`)** — `hasMediaForSite` blocks active media + published-but-unreconciled
  tombstones; `deleteSite` atomically removes eligible tombstones before deleting the site; `markTombstoneReconciled`
  is applied on tombstone sync success.
- **Phase 1 unused-media-permission removal (`0680664`)** — SiteLens never reads/imports the device media library;
  camera capture, evidence storage, video, export/share and Google Photos all operate on app-private files, so the
  four media/storage permissions and the onboarding "Photos & Storage" prompt were removed.
- **Security test-harness remediation (`f648779`)** — authenticated contexts now carry `email_verified`, media
  fixtures aligned to the canonical rules, and the gate runs node:test + Jest with a zero-test guard.
- **Phase 2.3 Wave A (R01, R04, R05)** — purged membership/sharing/RBAC from app + rules; creator-only Firestore &
  Storage rules (`request.auth.uid == resource.data.creator_id`); strict fail-closed repository queries on
  null/empty creatorId; per-user active-site decoupling; multi-user session isolation (User A sign out → User B
  sign in).
- **Wave A.1 (R01/R04 follow-up)** — removed the residual `collectionGroup('members')`, shared-site and
  successor-admin logic from the `deleteUserAccount` Cloud Function and the account-deletion client path (incl. the
  false "shared sites" retention copy); closed the `getTombstoneSyncCandidates` null leak; scoped
  `watchTombstoneCandidateCount` and `getResolvedMediaIds`; restored the UID-scoped sync count subscription.
- **Phase 2.4 Wave B (R02, R03, R06–R10)** — GPS/capture authority: live-fix provenance is now carried on every
  buffered position (a cached seed can never be baked into evidence); countdown aborts on GPS loss; video T₀ is the
  spatial/telemetry authority; recording locks cover lens/zoom/aspect/timer; audio-track presence is captured,
  frozen at T₀, persisted and disclosed; unestablished altitude/heading stay `null` (no synthetic fabrication).
- **Physical verification** — pre-v1.0.0 10/10 matrix PASS (Satellite/Roadmap captures, burst/alternation, Detail/
  Viewer match, MSL altitude, PDF export). A1/A2/B1/C1/Photo-fullscreen re-verified PASS on `f7fa8f8d`. Phase 1
  verified on `1656855954`: no Photos dialog/tile, camera+location onboarding flow progresses, photo + video
  captured with live GPS, gallery/detail/fullscreen correct, SHA present, PDF export share sheet opens, single PID
  (no crash/ANR). **Waves A/A.1/B are NOT physically verified (see §6).**

## 5. CRITICAL INVARIANTS

1. **Evidence authority**: `EvidenceMetadataSnapshot` is the capture-time authority; UI never re-derives or invents
   metadata. Unavailable values stay unknown — never synthesized.
2. **EXIF policy**: derived evidence (`evid_*`, `thumb_*`) carries no camera EXIF; the immutable original retains it.
3. **Tombstone lifecycle**: never physically destroy a `media` row on user deletion; never write artifact-sync status
   for tombstone rows; never create cloud records for never-published items. Storage artifacts are write-once.
4. **v9 site deletion**: block on active media and on published-but-unreconciled tombstones; remove only eligible
   (never-published or reconciled) tombstones, atomically with the site, inside one transaction.
5. **Video handoff**: a normal successful stop clears `_inFlightVideoFile`; only a genuine interruption raises recovery.
6. **A1**: exactly one `EvidenceVideoPlayback` owns a video's player; views are stateless borrowers.
7. **A2**: `appRouteObserver` stays registered; CameraX is released while `CameraScreen` is covered, reacquired on reveal.
8. **B1 / R06**: `hasLiveFix` (`hasValidFix && !isLastKnownSeed`) is the sole capture-readiness provenance; cached/last-known
   never unlocks capture; resume revalidates permission **and** service state.
9. **C1**: `HudFormatter.resolveSiteIdentifier` is the single site-identifier implementation; never use `MediaItem.siteId`
   as a user-facing identifier.
10. **Metadata card scope**: runtime card is Video-fullscreen only (`showHud && isVideo`); Photo shows the burned JPEG.
11. **GPS stream lifecycle**: never `Subscription.resume()` a lifecycle-paused subscription; cancel and recreate.
12. **Save path**: do not defer the DB commit, move persistence off the critical path, or alter atomic
    write→verify→commit.
13. **Media permissions**: the app must not declare `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`,
    `READ_EXTERNAL_STORAGE` or `WRITE_EXTERNAL_STORAGE` (the latter two only as `tools:node="remove"` merger
    suppressions against camera-plugin injection). Camera + location are the only core capture permissions.
14. **Security gate runners**: `test/security/firestore_rules.test.js` stays on `node:test` and is executed by
    `node-test-gate.mjs`; Jest must keep excluding it via `jest.config.js`. Do not convert it to Jest.
15. **v1 Creator Ownership & Local Isolation (R01, R04, R05)**: SiteLens v1 is creator-owned, user-specific,
    location-independent, and non-collaborative. Same site code, name, address, or GPS never implies cross-user access.
    All repository queries must fail closed (`[]` or `null`) when UID is null or empty. Active site selection is
    strictly keyed by user UID. `creator_id` and all capture-time forensic fields are immutable in cloud rules
    and local databases.
16. **R06 position-buffer provenance**: every buffered position carries `isLive` + its resolved altitude/datum; only
    live entries are selectable by `getBestRecentPosition()`; a live emission purges cached entries. The single
    production selection authority is `GpsHardwareNotifier.applyBestRecentPosition` — never re-inline the splice.
17. **R03 countdown gate**: the self-timer re-gates on `hasLiveFix` every tick and aborts on GPS loss; capture reads
    the **current** GPS authority (never a press-time snapshot).
18. **R07 video T₀ authority**: the recording-start timestamp **and** the recording-start GPS snapshot govern video
    evidence; stop-time GPS must never be persisted as the video's spatial/telemetry authority.
19. **R08 recording lock**: lens switching, digital zoom gestures, aspect-ratio and capture-timer controls are inert
    while `isRecordingVideo` (enforced in the UI and in `setZoomPreset`/`setPinchZoom`).
20. **R09 audio disclosure**: `has_audio_track` records the **effective** `enableAudio` of the preset that actually
    initialized, frozen at T₀. Unknown/not-applicable is `null` — never assumed `true` or `false`.
21. **R10 unknown telemetry**: unestablished altitude/heading/satellite telemetry stays `null`. Never substitute
    `0`, `0.0`, or `DateTime.now()`. Nullable columns carry **no default** (historical rows read as unknown).
22. **R11 minimap race**: shutter-time minimap snapshot is guarded by a monotonic generational token; a mismatched
    token rejects the snapshot (no stale tile burns into evidence).
23. **R12 capture mutex**: a single-flight `_isCapturing` lock wraps the shutter trigger; concurrent/re-entrant taps
    while persistence is in flight are ignored (exactly one record per intentional capture).
24. **R13 video playback ownership**: exactly one `EvidenceVideoPlayback` owns a recording's player across Review & Tag
    and the gallery (A1); an interrupted in-flight recording is recovered on restart (Keep for Later / Discard).
25. **R14 Review & Tag discard guard**: `PopScope` back/dismiss while a save is in flight can never silently discard the
    uncommitted capture; a re-entrance guard prevents stacked discard dialogs.
26. **R15 hash semantics**: two-tier SHA-256 — `sha256_hash` (original) and `evidence_sha256_hash` (burned evidence);
    `verifyBytes()` re-verifies published bytes against their recorded digest (live-byte vs. stored-hash).
27. **R16 cloud evidence replication (Option A)**: `evid_<id>.jpg` is the cloud-authoritative artifact, replicated to
    a creator-bound, path-immutable location in Cloud Storage.
28. **R17 smart-link temporal precedence**: a BEFORE candidate must be captured strictly earlier than the observation
    it precedes; enforced at query, eligibility, and both persistence boundaries.
29. **R18 smart-link non-destructive unlinking**: unlinking restores candidate status without touching the record;
    proximity is dynamic live distance (`null` is "distance unknown", never `0`).
30. **R19 spatial uncertainty**: a candidate's GNSS accuracy widens the nearby radius bound; synthetic `(0,0)` is not a
    valid location; displayed distances carry the uncertainty margin (sub-meter overclaiming prohibited).
31. **R20 canonical site identity**: all UI/export surfaces resolve the human-facing site code/name via
    `HudFormatter.resolveSiteIdentifier`; the internal site id is never rendered as an identifier.
32. **R21 export attribution**: exported artifacts attribute each record to its persisted `creator_id` and record the
    authenticated exporter separately; absent human identity stays unknown (never a fabricated default).

## 6. KNOWN ISSUES / OPEN ITEMS

- **RESOLVED (`f648779`) — `test/security` "7/19"**: was a harness defect, not rule drift. Root causes were
  (a) missing `email_verified` claims in the M6-A/M6-B contexts, (b) `firestore_rules.test.js` being a `node:test`
  suite run under Jest (invisible to it and falsely "failed"), and (c) pre-existing fixture defects the claim
  error had masked. Gate now reports **89/89** (node:test 75 + Jest 19).
- **Residual harness concerns**: `node-test-gate.mjs` uses `passed >= 57` (a floor, not an exact count — current
  node:test count is 75); a stale emulator on port 8080 yields a misleading "port taken" failure (no port pre-check).
- **Pending-tombstone block not reproducible on-device**: a previously-synced tombstone reconciles almost immediately
  even offline — Firestore caches the doc so `syncTombstone`'s `docRef.get()` resolves from cache and the queued
  `update()` succeeds (plain get/set/update, no transaction). The pending state only persists on a genuine sync
  failure (no cached doc / permission-denied / creator mismatch). Deterministic coverage exists in unit tests.
- **Site Setup trash icon is not gated**: the delete `IconButton` is always enabled; impossibility is only revealed
  after opening the dialog and tapping Delete. A read-only audit recommends disabling it when `hasMediaForSite` is
  true (reuse that method; no schema/API change). **Not implemented.**
- **Wave B residual telemetry ambiguities (documented, not fixed)**:
  - `LocalMediaRepository._entryToModel` still substitutes `DateTime.now()` when a stored `captured_at` cannot be
    parsed (corruption-only path; not a sensor value).
  - `GnssSnapshot.fromMap` defaults absent satellite counts to `0` when `isAvailable` is true (over-the-wire ambiguity).
  - Compass heading is accepted for `0.0 ≤ heading ≤ 360.0`, so a device reporting `heading == 0.0` for
    "unavailable" is persisted as `0°` rather than `null` (no reliable availability signal without `headingAccuracy`
    semantics).
  - The live-HUD coordinates retain the established `0.0` "no fix" sentinel (the HUD card rejects a `0.0` pair as a
    fix); only altitude is genuinely nullable in `GpsUiFixture`.
- **`docs/ALL_TESTS.md` refresh pending**: post-v1.0.0 audit-remediation tests are not cataloged (still states 539;
  actual Flutter total is 776). Wave A.1 also removed 4 obsolete successor/shared-site tests still listed there.
- **`PROJECT_STATUS.md` partially superseded**: dated 2026-09-14 (HEAD `f868a17`); counts and the account-deletion
  description (sole-member / shared / successor paths) predate Wave A.1.
- **Documented non-blocking audit observations** (Audit A F-A3–F-A7, Audit B B-2–B-7, Audit C C-3–C-6) remain
  open-by-design and non-blocking; full text retained in git history.
- **Physical re-verification scope**: the Phase 1 build covered the permission/onboarding + capture/evidence/export
  paths only; A1/A2/B1/C1/Photo-fullscreen were last verified on `f7fa8f8d`. **Waves A/A.1/B are unverified on
  hardware** — the installed APK predates them. Google Photos remains unverifiable on-device (not connected), and the
  Detail screen shows only a truncated SHA prefix.
- **Play Store readiness (from the final audit)**: no AAB yet, no hosted privacy-policy URL, Data Safety /
  content rating / app access not supplied, store assets still SVG + one screenshot, and the removed media
  permissions must not be reintroduced.

## 7. TEST / BUILD BASELINE

- **`flutter test`**: **805/805 passed** (0 failed); `flutter analyze`: **0 issues**.
- **Security gate (`test/security`)**: **89/89** — node:test **75/75** (`firestore_rules.test.js`, incl. the Wave A
  User A vs User B collision suite and the Wave B R09/R10 rules schema suite) + Jest **19/19**
  (`security_rules.test.js`, `m6b_sync_emulator.test.js`); 0 failed suites, 0 skipped.
- Backend (`functions/`): **39/39** (8 suites) — includes the creator-owned-only `deleteUserAccount` suite after
  Wave A.1.
- Test-count progression (full Flutter suite incl. the root smoke test): 663 → … → 742 (`cc16ff0`) → 754
  (`edb6d82`) → 758 (`0680664`/`f648779`) → **767** (Wave A) → **765** (Wave A.1: −3 unit + −1 widget obsolete,
  +2 R04 unit) → **776** (Wave B: +11 unit; widget unchanged) → **805** (Waves B.1/C/D [R11–R16] + Wave E [R17–R20] + Wave F [R21], all uncommitted in the working tree).
- **Build**: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`. Current artifact =
  `1656855954…` (75,545,189 bytes, **pre-Waves A/A.1/B**); `edb6d82` = `84ec35f1…5717a8a`; `cc16ff0` = `f7fa8f8d…487df3a`.
  `versionName 1.0.0` / `versionCode 1`.
- **Schema/codegen**: a schema change requires bumping `schemaVersion`, adding an `onUpgrade` branch, and running
  `dart run build_runner build --delete-conflicting-outputs` (v10 added `has_audio_track` + `heading_degrees`).
- **Security gate invocation** (emulator required):
  `firebase emulators:exec --only firestore,storage --project sitelens-prod-80e7b "cd test/security && npm test"`.
  The node:test half alone: `firebase emulators:exec --only firestore,storage "node --test test/security/firestore_rules.test.js"`.

## 8. WORKFLOW RULES

- Do not commit, push, rewrite history, rebuild for release, or deploy Firebase without explicit instruction.
- Gradle/APK builds require explicit authorization; the `cc16ff0` artifact reproduces byte-identically.
- Run the full security gate (both runners) after any rules or harness change; never treat a single-runner result
  as the gate. Kill/avoid stale emulators before running (ports 8080/9199).
- Bump `versionCode` in `pubspec.yaml` for every Play upload after the first; verify a keystore backup exists before
  Play App Signing enrolment (an upload key cannot be regenerated).
- Never print keystore passwords, key material, Firebase keys or tokens; comparisons/indirection only.
- **On-device verification discipline**: release builds emit no Dart GPS instrumentation and the Detail screen shows
  only a truncated SHA prefix — report observed UI + code facts + native logs separately; never infer Dart state from
  logcat silence, and never claim a full-hash verification from a screenshot.
- `graphify update .` after code changes; schema changes follow the `onUpgrade` + `build_runner` pattern.
- **Task Observer Protocol** is formalized in `CLAUDE.md` (mandatory session-start protocol, pre-skill observation
  queries, pinned workspace root).

## 9. DO-NOT-TOUCH / PRESERVE

- **Burned Photo JPEG pipeline** (`WatermarkDrawer` / `EvidenceProcessingService`), EXIF stripping, and SHA-256
  semantics — do not reintroduce EXIF passthrough or mutate artifacts.
- **Photo fullscreen gating** (`showHud && isVideo`) — never mount a runtime card/minimap/overlay over Photo.
- **`EvidenceVideoPlayback` ownership** (A1) and **`appRouteObserver`** registration (A2) — do not add a second
  player or a second coverage mechanism.
- **GPS semantics** (B1/R06) — Unknown/Denied/Service-Off distinctions, `hasLiveFix` capture gate, last-known block,
  and the provenance-carrying position buffer.
- **Capture authority** (R03/R07) — countdown live-fix re-gate; video T₀ timestamp **and** T₀ GPS snapshot authority.
- **Recording lock** (R08) — lens/zoom/aspect/timer inert while recording.
- **Audio disclosure** (R09) — `hasAudioTrack` records the effective controller audio at T₀; unknown is `null`.
- **Unknown telemetry** (R10) — nullable altitude/heading with no migration default; never zero-fill or `now()`-fill.
- **Minimap race** (R11) — generational token must guard the shutter-time snapshot; never burn an unguarded tile.
- **Capture mutex** (R12) — single-flight shutter lock; never allow concurrent/re-entrant captures.
- **Video playback ownership** (R13/A1) — exactly one player per recording across Review & Tag and gallery.
- **Review & Tag discard guard** (R14) — `PopScope`/re-entrance guard must protect in-flight saves from accidental discard.
- **Hash semantics** (R15) — two-tier SHA-256 with live-byte re-verification; never trust a stored digest unchecked.
- **Cloud evidence replication** (R16) — `evid_<id>.jpg` is the cloud-authoritative artifact (Option A).
- **Smart-link temporal precedence** (R17) — BEFORE must be strictly earlier; never relax to ≤.
- **Smart-link non-destructive unlinking** (R18) — unlinking must not mutate the candidate record; `null` distance is "unknown".
- **Spatial uncertainty** (R19) — candidate GNSS accuracy widens the bound; `(0,0)` is invalid; uncertainty must be disclosed.
- **Canonical site identity** (R20) — resolve via `HudFormatter.resolveSiteIdentifier`; never emit the internal site id.
- **Export attribution** (R21) — creator and exporter are distinct; never fabricate a default human identity on export.
- **Tombstone lifecycle** (v9) — no physical row destruction on user deletion; no cloud records for never-published items.
- **Media permissions** (Phase 1) — do not reintroduce the four removed permissions or the onboarding photos prompt;
  keep the `tools:node="remove"` suppressions; keep the security gate on both runners.
- **Active-site/creator scoping** and fail-closed unauthenticated behaviour.
- **Secrets/signing**: keep `key.properties`, `local.properties`, `google-services.json`, `firebase.json`,
  `lib/firebase_options.dart` untracked; never fall back to the debug signing config for release.
- **No membership/sharing/successor-admin paths** (R01/A.1) — do not reintroduce `collectionGroup('members')`,
  member hydration, RBAC, invitations, shared-site classification or successor-admin logic in any layer (app, rules,
  Cloud Functions, tests).
- **Explicitly rejected approaches (do not reintroduce)**: consuming camera EXIF as truth; synthesized GPS fallbacks
  (`accuracy ?? 0.0`, `timestamp ?? now`); `Subscription.resume()` lifecycle recovery; save-path optimization;
  runtime metadata card over Photo; physical row deletion on user deletion; using `MediaItem.siteId` as a user-facing id;
  selecting a cached/last-known seed for capture; stop-time GPS as video spatial authority; zero-filled telemetry.

## 10. NEXT ACTION

1. **AWAIT EXPLICIT USER AUTHORIZATION FOR WAVE G (R24–R26)**:
   - Waves A, A.1, B, B.1/C/D (R11–R16), E (R17–R20) and F (R21) are complete and verified against the
     automated suites (no physical verification). All remain uncommitted in the working tree.
   - Wave G implemented to date per the §34 matrix & per-rule directives: **R22 (Tombstone Remote
     Propagation) and R23 (Deletion Safety) are COMPLETED & VERIFIED.** R24 (tombstone retention/purge),
     R25 (sync backoff/error classification) and R26 (deterministic gallery sort) are NOT STARTED — awaiting scope.
   - DO NOT commit, push, or start Wave G without explicit instructions.
2. **Physical verification of Waves A/A.1/B/B.1–F is outstanding** — build and exercise live-fix gating, countdown abort,
   recording locks, audio disclosure, audio/heading persistence, smart-link behavior and export attribution on the
   device before any release.
3. Decide the Site Setup trash-icon gating (recommended: disable when `hasMediaForSite` is true; reuse the existing
   repository method; update `site_setup_screen_test.dart` which currently drives deletion errors through the dialog).
4. Close the harness residuals: assert an exact node:test count (`tests === passed`), add a stale-emulator/port
   pre-check, and document the combined `npm test` invocation.
5. Optionally refresh `docs/ALL_TESTS.md` (539 → 805) and reconcile `PROJECT_STATUS.md` with Waves A/A.1/B/B.1–F.
6. Before a Play release: build the AAB, re-run the full physical A1/A2/B1/C1/Photo-fullscreen suite on the current
   build, and complete the Play Console items listed in §6.

---

## 11. POST-REMEDIATION AUDITS

### 11.1 R22 — Tombstone Remote Propagation (independent Jev evaluation)

Independent, read-only Jev evaluation of R22 against current HEAD.

- **Overall decision**: PASS. Jev confidence: 0.33 (distributions: PASS 0.55, FAIL 0.02, NOT_VERIFIED 0.43).
- All six R22 requirements are directly supported by implementation evidence in `lib/features/sync/services/cloud_sync_service.dart` (`syncTombstone`) and `lib/features/sync/services/sync_coordinator.dart` (`_processSingleItem`), with focused tests in `test/unit/cloud_sync_service_test.dart` ("B-1 Cloud Tombstone Synchronization Tests").
- Key evidence: `syncTombstone` checks the creator guard first, then returns early when `item.syncStatus == SyncStatusType.pending` (no cloud read, no cloud write); published/non-pending items continue through the canonical Firestore reconcile path via `_ensureFirestoreDocSynced`; permission-denied `FirebaseException` is rethrown verbatim by `_runMappedSyncOperation`; successful reconciliation calls `markTombstoneReconciled` via `SyncCoordinator`; no Firestore or Storage security rules were changed.
- **Known residual (not an R22 violation)**: `SyncStatusType.pending` is overloaded — it can mean both "never-attempted" and "Firestore ledger created but first Attempt Storage write failed." The implementation treats all pending tombstones as never-published no-ops. Jev's 0.15 FAIL probability on the overall and 0.15 NOT_VERIFIED probability on R22.2 reflect this latent lifecycle ambiguity, not a direct violation of the six R22 requirements.

### 11.2 M1 — GPS & Capture Readiness (post-remediation audit)

Read-only audit of the GPS/capture readiness remediation (Waves B + B1/D-SPAT). Overall: PASS.

- **R1**: `hasLiveFix` is the sole capture-readiness authority — `hasValidFix && !isLastKnownSeed` (`gps_hardware_state.dart:61`; `camera_screen.dart:1095–1097`).
- **R2/R06**: cached/last-known GPS is a display-only seed; `hasLiveFix` is false and the shutter stays locked (`gps_hardware_controller.dart:158–169`, `233–242`; `gps_hardware_state.dart:29–35, 61`).
- **R6**: cached GPS never enters live-position selection — `getBestRecentPosition` filters `entry.isLive == true` and purges non-live entries on first live emission (`gps_hardware_controller.dart:242, 312–329`).
- **R3**: countdown re-gates on `hasLiveFix` every tick and aborts on GPS loss; capture reads the current GPS authority, not a press-time snapshot (`camera_screen.dart:718–740`, `805–828`).
- **R7**: video T₀ GPS snapshot is frozen at `startVideoRecording` and used at stop; stop-time GPS cannot usurp T₀ (`camera_hardware_controller.dart:448`; `camera_screen.dart:488–511`).
- **R8/R09/R10**: recording locks, audio disclosure, and unknown-telemetry semantics are enforced.
- **D1–D4**: RESOLVED (purge on first live emission; per-tick/countdown gate; T₀ video authority; shutter refusal on invalid GPS).
- **D6**: NO drift — PRD.md §615–616 and architecture.md §361–370, §393 match implementation.
- **D5**: PARTIALLY VERIFIED — production shutter paths are correct, but there is no automated test for GPS loss during an active countdown (coverage gap, not a behavior defect; see Known Issues entry below).

#### M1 Findings

- **F7 (defensive-hardening gap, not a current Rule 5 defect)** — Severity LOW.
  - `_showInterruptedRecordingRecovery` selects `recordingGps = (recordingGpsState != null && recordingGpsState.hasValidFix) ? recordingGpsState! : gpsHardware` and passes it to `EvidenceMetadataSnapshot.capture` without an explicit `!isLastKnownSeed` guard (`camera_screen.dart:189–195`).
  - Safety is invariant-dependent: the only `startVideoRecording` call site passes `gpsHardware` only when `isCapturePermitted` (i.e. `hasLiveFix`) is true (`camera_screen.dart:638–640`), and `pauseCamera` preserves `recordingGpsState` while recovery is pending (`camera_hardware_controller.dart:518`).
  - Under the current single call site, `recordingGpsState` is non-null and live during recovery; the theoretical state (`recordingGpsState == null && gpsHardware.isLastKnownSeed`) is not reachable. If a future caller invokes `startVideoRecording` without a live-fix `recordingGpsState`, cached coordinates could reach the sealing factory (which does not itself reject last-known provenance). Defensive recommendation: add an explicit `hasLiveFix`/`!isLastKnownSeed` gate in the recovery path to make safety local rather than call-site-dependent. No fix applied — audit only.
  - Rule 5 impact: current behavior is truthful; the gap is latent and invariant-dependent.
  - Regression status: not a regression.
- **F5 (test coverage gap)** — Severity LOW.
  - Requirement R5 is satisfied by implementation (per-tick gate + final capture gate), but no automated test exercises GPS loss during an active countdown.
  - Rule 5 impact: missing regression coverage; does not imply incorrect behavior.
  - Regression status: not a regression; pre-existing coverage gap.

#### Physical-device verification still required (M1)
1. Photo countdown: disable GPS/locate-loss mid-countdown; verify countdown cancels and no evidence is created.
2. Interrupted video: background with GPS transition to last-known, resume; verify recovery uses the frozen T₀ live GPS, not current cached coordinates.
3. Resume without a fresh live fix: verify shutter stays locked (no cached-seed unlock).
4. Permission toggle to Denied during countdown: verify capture aborts.

### 11.3 M2 — Camera & Capture Workflow Post-Remediation Verification

Independent read-only verification of the M2 post-remediation audit against current HEAD (`f648779` + uncommitted Waves A–F + R22/R23).

- **Overall Decision**: **FAIL** (confirmed reachable defects NF-M2-01 and NF-M2-03).

#### Verified Findings

1. **NF-M2-01: Site-less / Wrong-Site Interrupted Video Recovery** — Severity HIGH
   - **Verdict**: **CONFIRMED DEFECT**
   - **Decisive Evidence**:
     - `CameraHardwareNotifier.startVideoRecording()` accepts `GpsHardwareState recordingGpsState`, but does not receive or store site identity (`siteId`, `siteCode`, `siteName`) in `CameraHardwareState`.
     - `CameraScreen._showInterruptedRecordingRecovery()` resolves `activeSite` at recovery time via `ref.read(siteControllerProvider).activeSite`. If no site is active upon recovery, `activeSite` is null, defaulting to `siteId: ''`. If the user switched sites or accounts during interruption/backgrounding, the recording is bound to the wrong site and current authenticated `creatorId`.
     - In `MediaPersistenceCoordinator.keepForLater()`, site validation is conditionally checked only `if (siteId.isNotEmpty)`. Unlike `persistCapturedEvidence()` and `persistPendingCapture()`, it does not reject or throw on `siteId.isEmpty`, persisting a row with `site_id = ''`.
     - Reachable defect: media saved with `siteId: ''` is excluded by `activeSiteMediaStreamProvider` (which filters by `siteId`), becoming permanently orphaned and invisible across all site galleries.

2. **NF-M2-02: `switchCamera()` Lacks Controller-Level Recording Guard** — Severity MEDIUM
   - **Verdict**: **DEFENSIVE HARDENING / PARTIALLY CORRECT**
   - **Decisive Evidence**:
     - `CameraHardwareNotifier.switchCamera()` checks `if (_isSwitching || _isPaused) return;`, omitting `state.isRecordingVideo`. In contrast, `setCaptureMode`, `setZoomPreset`, and `setPinchZoom` strictly enforce `if (state.isRecordingVideo) return;`.
     - However, all existing UI callers (`CameraShutterStation:141` and `CameraScreen._handleFlipCamera:434`) strictly gate camera flipping behind `!isRecordingVideo`.
     - Unreachable from current UI, but represents an architectural inconsistency against R08 defensive controller-level invariant principles.

3. **NF-M2-03: Android Back Can Dismiss Interrupted-Recording Recovery** — Severity MEDIUM
   - **Verdict**: **CONFIRMED DEFECT**
   - **Decisive Evidence**:
     - `CameraScreen._showInterruptedRecordingRecovery()` displays the recovery `AlertDialog` via `showDialog` with `barrierDismissible: false`, but **omits `PopScope`**.
     - On Android devices, system back navigation (hardware back button or predictive back gesture) dismisses the dialog route, returning `null`.
     - Prior to showing the dialog, lines 207–213 have already written the permanent file `media/orig_${snapshot.mediaId}.mp4` to disk and deleted the temporary camera file via `storageService.deleteTempCameraFile()`.
     - Dismissal prevents execution of both `_keepInterruptedRecording` and `_discardInterruptedRecording`.
     - Subsequent recovery retries fail with `FileSystemException` (temp file gone), clearing `_inFlightVideoFile` and leaving `orig_${snapshot.mediaId}.mp4` orphaned on disk without a database row, violating R14 atomic lifecycle mandates.

4. **NF-M2-04: `isCameraFunctional` Semantic Inconsistency / Optical Simulation Dead Code** — Severity LOW
   - **Verdict**: **SEMANTIC INCONSISTENCY / DEAD CODE ONLY (Harmless Residual)**
   - **Decisive Evidence**:
     - `CameraScreen:1094` defines `isCameraFunctional = cameraHardware.isReady || cameraHardware.isUnavailable;`, causing `isCapturePermitted` to be mathematically true when GPS has a live fix even if the camera is unavailable.
     - However, `CameraShutterStation:35` independently locks the shutter button (`cameraStatus == CameraStatus.unavailable`), and `_handleShutterPressed:654` rejects capture with a `'Camera unavailable'` SnackBar.
     - Residual simulation code in `camera_screen.dart:983–995` displays an `'Optical Simulation Capture'` SnackBar, but returns immediately without writing evidence, mutating state, or navigating to review. No false evidence or Rule 5 violation occurs.

#### Confirmation of Historical M2 Resolutions
- **D1 (Cached GPS)**: **CONFIRMED RESOLVED**. `hasLiveFix` strictly enforced; non-live buffer entries purged; live-fix re-gated on countdown tick; video T₀ GPS snapshot governs.
- **D3 (Video Persistence Atomicity)**: **CONFIRMED RESOLVED**. Database transaction failures trigger disk cleanup. The gap where app kill occurs on `ReviewTagScreen` is an uncommitted draft lifecycle boundary, not a database corruption.
- **D6 (Audio Fallback Disclosure)**: **CONFIRMED RESOLVED**. Preset `enableAudio` status captured and frozen at T₀ as `recordingHasAudioTrack`, persisted in Drift v10 `has_audio_track` (nullable with no default), and disclosed in `MediaDetailScreen` (`CAPTURED`, `MUTED`, or `—`).
- **D7 (Unavailable Camera)**: **CONFIRMED PARTIALLY RESOLVED**. Shutter and handler block capture, but semantic definition and dead simulation code remain as harmless technical debt.

#### Minimum Remediation Set (Required for M2 PASS)
1. **NF-M2-01**:
   - Capture and store `siteId`, `siteCode`, and `siteName` in `CameraHardwareState` at $T_0$ (`startVideoRecording`).
   - In `MediaPersistenceCoordinator.keepForLater()`, enforce `if (siteId.isEmpty) throw SiteAssociationException(...)`.
   - In `CameraScreen._showInterruptedRecordingRecovery()`, restore original $T_0$ site and creator identity rather than querying live controllers.
2. **NF-M2-03**:
   - Wrap recovery `AlertDialog` in `PopScope(canPop: false)` or handle `null` route pop by invoking `_discardInterruptedRecording()`.
3. **NF-M2-02 (Defensive)**:
   - Add `if (state.isRecordingVideo) return;` to `CameraHardwareNotifier.switchCamera()`.

#### Physical-Device Verification Required (M2)
1. **Hardware Video Interruption**: Background app or simulate incoming phone call during active video recording; verify CameraX flushes MP4 and recovery prompts with authentic $T_0$ site metadata.
2. **Microphone Permission Denial**: Deny audio permission at Android OS level; record video; verify `MediaDetailScreen` displays `MUTED` and database persists `has_audio_track = 0`.
3. **GNSS Shielding Mid-Countdown**: Initiate capture with 5s countdown under live fix, shield device; verify countdown cancels before shutter fires.

### 11.4 Local Jev Integration Verification

- Verified operational on local environment via `~/.local/bin/typesafe-jev`.
- Model: `jev-1.13.0` (evaluated test state "Antigravity is testing its local Jev integration" with question `working` of type `noul`, returning probability `0.92`).
- Accessible for zero-cost semantic verification, structured extraction, and policy adherence audits.

### Reference Links
* **Public GitHub Repo**: [https://github.com/moloygoswami/SiteLens](https://github.com/moloygoswami/SiteLens)
* **Authoritative Strix Instructions**: [`strix-sitelens-instructions.md`](file:///home/moloy/workspace/products/SiteLens/strix-sitelens-instructions.md)
* **Local Database Definition**: [`lib/data/local/database/app_database.dart`](file:///home/moloy/workspace/products/SiteLens/lib/data/local/database/app_database.dart)
* **Media Repository**: [`lib/data/repositories/media_repository.dart`](file:///home/moloy/workspace/products/SiteLens/lib/data/repositories/media_repository.dart)
* **Site Repository**: [`lib/data/repositories/site_repository.dart`](file:///home/moloy/workspace/products/SiteLens/lib/data/repositories/site_repository.dart)
* **Evidence Metadata Snapshot**: [`lib/features/camera/models/evidence_metadata_snapshot.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/models/evidence_metadata_snapshot.dart)
* **Media Persistence Coordinator**: [`lib/features/camera/services/media_persistence_coordinator.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/services/media_persistence_coordinator.dart)
* **GPS Utilities**: [`lib/core/utils/gps_utils.dart`](file:///home/moloy/workspace/products/SiteLens/lib/core/utils/gps_utils.dart)
* **HUD Formatter**: [`lib/features/camera/hud/hud_formatter.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/hud/hud_formatter.dart)
* **Canonical Metadata Card (Photo/Video unification)**: [`lib/shared/widgets/evidence_metadata_hud_card.dart`](file:///home/moloy/workspace/products/SiteLens/lib/shared/widgets/evidence_metadata_hud_card.dart)
* **Canonical HUD Data Contract (accuracy/satellite telemetry)**: [`lib/features/camera/hud/hud_data.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/hud/hud_data.dart)
* **Camera Screen (capture orchestration, countdown guard, video T₀ handoff)**: [`lib/features/camera/camera_screen.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/camera_screen.dart)
* **Camera Hardware Controller (R07 T₀ snapshot, R08 recording lock, R09 audio)**: [`lib/features/camera/controllers/camera_hardware_controller.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/controllers/camera_hardware_controller.dart)
* **Camera Hardware State (R09 `isAudioEnabled`/`recordingHasAudioTrack`)**: [`lib/features/camera/models/camera_hardware_state.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/models/camera_hardware_state.dart)
* **Camera Viewfinder (R08 locked controls/gestures)**: [`lib/features/camera/widgets/camera_viewfinder.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/widgets/camera_viewfinder.dart)
* **Media Detail Screen (R09 AUDIO / R10 HEADING disclosure)**: [`lib/features/gallery/media_detail_screen.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/gallery/media_detail_screen.dart)
* **Evidence Video Playback Owner (A1 — sole player ownership)**: [`lib/features/gallery/controllers/evidence_video_playback.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/gallery/controllers/evidence_video_playback.dart)
* **Local Video Player Widget (A1 — stateless borrower)**: [`lib/features/gallery/widgets/local_video_player_widget.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/gallery/widgets/local_video_player_widget.dart)
* **App Router & Route Observer (A2)**: [`lib/app/router.dart`](file:///home/moloy/workspace/products/SiteLens/lib/app/router.dart)
* **GPS Hardware Controller (B1/R06 — provenance buffer, live-fix selection authority)**: [`lib/features/camera/controllers/gps_hardware_controller.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/controllers/gps_hardware_controller.dart)
* **Cloud Sync Service (R05/R09/R10 payload + immutability checks)**: [`lib/features/sync/services/cloud_sync_service.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/sync/services/cloud_sync_service.dart)
* **Firestore Security Rules (creator-owned model, R09/R10 field allowlist)**: [`firestore.rules`](file:///home/moloy/workspace/products/SiteLens/firestore.rules)
* **Wave A isolation regression suite**: [`test/unit/wave_a_isolation_regression_test.dart`](file:///home/moloy/workspace/products/SiteLens/test/unit/wave_a_isolation_regression_test.dart)
* **Wave B telemetry persistence suite**: [`test/unit/wave_b_telemetry_persistence_test.dart`](file:///home/workspace/products/SiteLens/test/unit/wave_b_telemetry_persistence_test.dart)
* **Nearby Search Controller (R19 spatial-uncertainty candidate evaluation)**: [`lib/features/nearby/controllers/nearby_search_controller.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/nearby/controllers/nearby_search_controller.dart)
* **Smart-Link Engine + Media Repository (R17 temporal gate, R18 live distance)**: [`lib/data/repositories/media_repository.dart`](file:///home/moloy/workspace/products/SiteLens/lib/data/repositories/media_repository.dart)
* **GPS Utilities — distance + GNSS uncertainty formatting (R19)**: [`lib/core/utils/gps_utils.dart`](file:///home/moloy/workspace/products/SiteLens/lib/core/utils/gps_utils.dart)
* **Evidence Export Service (R21 creator/exporter attribution)**: [`lib/features/gallery/services/evidence_export_service.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/gallery/services/evidence_export_service.dart)
* **R21 export-attribution regression suite**: [`test/unit/r21_export_attribution_test.dart`](file:///home/moloy/workspace/products/SiteLens/test/unit/r21_export_attribution_test.dart)
* **Complete Test Inventory**: [`docs/ALL_TESTS.md`](file:///home/moloy/workspace/products/SiteLens/docs/ALL_TESTS.md)
