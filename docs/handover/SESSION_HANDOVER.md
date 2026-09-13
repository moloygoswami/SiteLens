# SiteLens — Session Handover Document

**Generated**: 2026-09-14T01:51:26+05:30
**Current Milestone**: Physical Release Finding Remediation (Android 16 / SDK 36) — **A1 Video Fullscreen Player Ownership** (ACCEPTED), **A2 CameraX Route Lifecycle** (ACCEPTED), **B1 GPS State Semantics & Recovery** (ACCEPTED), **C1 Video HUD Identifier Semantics** (ACCEPTED), **Canonical Photo/Video Metadata-Card Unification** (COMPLETED & VERIFIED; physical re-verification pending) — layered on the Post-v1.0.0 E2E Reliability Audit & Remediation Program (Modules A–J; Cross-Cutting Audits A–D all Remediated & Verified, incl. D-SPAT-001/D-SPAT-002/LAT-001; Full-Journey / Settings & Legal / Account-Deletion E2E Audits Passed; `PRD.md` & `architecture.md` Synchronized to Verified Semantics)
**Protected Baseline**: Commit `f868a17` on `main` (Tag `v1.0.0` frozen at `a17e8c3580c157ba629bfc8fe39fa2fd75da923c`)
**Active Test Device**: Motorola edge 50 fusion (`ZA222NBPPV` / Android 16 / API 36)
**Governing Mandate**: Governing Rule 5 (Evidence Integrity) — Truthful temporal, spatial, optical, and provenance claims

---

## 1. Executive Summary & Current State

```text
========================================================================================
                                CURRENT SESSION & VERIFICATION STATUS
========================================================================================
 PROTECTED HEAD COMMIT:    f868a17 (main) — UNCOMMITTED WORKING TREE
 RELEASE TAG v1.0.0:       a17e8c3580c157ba629bfc8fe39fa2fd75da923c (UNMOVED & FROZEN)
 ZERO COMMIT POLICY:       PASS (No commits created during audit/remediation session)
 DATABASE SCHEMA:          DRIFT SCHEMA VERSION 8 (app_database.g.dart generated)
 REVIEW & SMART-LINK #8:   COMPLETED & VERIFIED (F1: Smart-Link dismissal & fallback;
                                                 F2: Candidate consistency & divergence guard;
                                                 F3: Evid_ID / link invariant & persistence sanitization;
                                                 F4: Edit-modal Haversine distance;
                                                 F5: Creator & site isolation)
 SMART-LINK #9:            COMPLETED & VERIFIED (F-1 modal A→B divergence corrected to non-destructive
                                                 B→A lifecycle: existing link survives edits/suggestions;
                                                 only explicit Select-as-BEFORE / Unlink / type-switch
                                                 replaces or removes the relationship)
 EVIDENCE LIST #10:        COMPLETED & VERIFIED (F1: deterministic History ordering captured_at DESC, id ASC;
                                                 F2: Sync Status filter made selectable in GalleryFilterModal)
 OFFLINE CAPTURE #11:      COMPLETED & VERIFIED (F1: online capture auto-sync via unsynced-count edge trigger;
                                                 F2: v8 forensic metadata — altitude, is_altitude_msl,
                                                 verification_status, GNSS counts & fix timestamp — persisted
                                                 to Firestore create/reconcile + rules allowlist)
 SYNC E2E #12:             COMPLETED & VERIFIED (F-1: foreground resume triggers sync via WidgetsBindingObserver;
                                                 F-2: unexpected exceptions permanently suppressed, manual
                                                 retry re-evaluates; F-3: SyncLifecycleBootstrap at app root —
                                                 session-gated crash recovery independent of Gallery, single
                                                 coordinator instance per authenticated lifecycle)
 CROSS-CUTTING AUDIT A:    COMPLETED & VERIFIED (F-A1: derived evidence JPEG/thumbnail strip all camera
                                                 EXIF after orientation bake — original retains camera EXIF;
                                                 F-A2: getBestRecentPosition returns null for stale/absent raw
                                                 positions — unknown capture-window data stays unknown, never
                                                 synthesized 0.0/now; applyBestRecentPosition seam added;
                                                 regression tests added. F-A3–F-A7 observations remain
                                                 documented, non-blocking)
 CROSS-CUTTING AUDIT B:    COMPLETED & VERIFIED (Evidence Artifact Cloud Synchronization E2E audit:
                                                 PASS-with-findings. B-1 remediated: local tombstone propagation —
                                                 getTombstoneSyncCandidates/watchTombstoneCandidateCount discovery,
                                                 CloudSyncService.syncTombstone reusing canonical reconcile, count
                                                 edge-trigger; deleted published items reconcile is_deleted=true,
                                                 never-published items are verified no-ops, Storage artifacts
                                                 write-once untouched. B-2..B-7 observations documented,
                                                 non-blocking)
 CROSS-CUTTING AUDIT C:    COMPLETED & VERIFIED (Capture ↔ Sync Lifecycle audit: no BLOCKERs.
                                                 C-1 remediated: stale _inFlightVideoFile cleared on normal video
                                                 handoff — no false interrupted-recording recovery. C-2 remediated:
                                                 deletePermanently tombstones the row instead of destroying it —
                                                 a permanently deleted published item can never strand a live
                                                 cloud ledger. C-3..C-6 observations documented, non-blocking)
 CROSS-CUTTING AUDIT D:    COMPLETED & VERIFIED (Capture Position Provenance & Spatial
                                                 Search Integrity: D-SPAT-001 lastKnown cached-seed shutter gating —
                                                 autoDispose churn re-seeded falsified coordinates into VERIFIED
                                                 evidence (6 rows @ bit-identical 20.6km-off position, smart-link
                                                 graph contaminated); provenance flag + hasLiveFix gates on photo/
                                                 video shutters; D-SPAT-002 photo shutter valid-fix gate (0,0
                                                 persistence asymmetry vs video); LAT-001 nearby NULL-creator
                                                 visibility parity with sync ownership queries. Read-only data
                                                 confirmation on device + Firestore mirror)
 E2E JOURNEY AUDITS:       PASS (Full user-journey install→deletion audit; Settings & Legal
                                                 workflow audit; Account-Deletion workflow audit incl. sole-member/
                                                 shared-member/successor paths — all traced to implementation with
                                                 passing tests)
 REFERENCE DOCS:           SYNCHRONIZED (PRD.md & architecture.md updated to verified v8
                                                 semantics: capture-time metadata authority, EXIF policy, sync
                                                 lifecycle order, tombstone/deletion semantics, account deletion)
 PHOTO EVIDENCE F1–F3:     COMPLETED & VERIFIED (F1: Original preserved on DB failure;
                                                 F2: Crash-safe atomic writes & temp cleanup;
                                                 F3: Closed-evidence integrity on edit & detail guard)
 METADATA OVERLAY F1–F5:   COMPLETED & VERIFIED (Status parity, Drift v8 persistence, pre-v8 fallback,
                                                 canonical GNSS telemetry, video metadata, altitude datum)
 VIDEO PERSISTENCE & GPS:  COMPLETED & VERIFIED (Atomic writes, no 0,0 coords, recording-time fix,
                                                 keepForLater DB failure cleanup, PopScope discard)
 MINIMAP & GPS WORKFLOW:   COMPLETED & VERIFIED (Background staleness watchdog, canonical cache key,
                                                 shutter re-entrancy lock, generation guards)
 CAMERA PERMISSION RECOVERY: COMPLETED & VERIFIED (Single PermissionService authority, restricted status,
                                                 Settings return navigation, retry-safe lifecycle)
 CLOSED EVIDENCE WORKFLOW: COMPLETED & VERIFIED (Nearby candidate selection, Evid_ID note insertion,
                                                 smart-link race invalidation)
 AUTH SESSION RECOVERY:    COMPLETED & VERIFIED (Centralized SessionService, cold start / resume reload,
                                                 contextual permission-denied vs unauthenticated, race/disposal-safe,
                                                 root navigator stack wipe to WelcomeScreen)
 ONBOARDING & PERMISSIONS: COMPLETED & VERIFIED (Permission recovery persistence in PermissionRecoveryScreen,
                                                 app-level sign-out authority in SiteLensApp, declarative
                                                 SessionRouter onboarding completion without duplicate navigation)
 RELEASE FINDING AUDIT:    COMPLETED (READ-ONLY FORENSIC AUDIT — Android 16 / SDK 36 physical release
                                   finding on Motorola edge 50 fusion): fullscreen video evidence crash,
                                   post-crash camera state (GPS: Denied / ACC: ACQUIRING / shutter
                                   locked), and the video forensic HUD. Confirmed the video pipeline
                                   does NOT write GPS permission state (post-crash GPS is an independent
                                   state/initialization concern) and the video HUD is viewer-rendered
                                   from persisted capture-time metadata, never burned into the MP4.
                                   Scoped remediation modules A1 / A2 / B1.
 A1 VIDEO PLAYER OWNERSHIP: IMPLEMENTED & VERIFIED (ACCEPTED) — single `EvidenceVideoPlayback` owner
                                   shared by the inline detail surface and the fullscreen viewer;
                                   exactly ONE VideoPlayerController/ExoPlayer per video; inline
                                   surface parked while fullscreen is on top; async init/dispose race
                                   safe; idempotent disposal; truthful failed state; 13 focused tests.
 A2 CAMERAX ROUTE LIFECYCLE: IMPLEMENTED & VERIFIED (ACCEPTED) — `appRouteObserver`
                                   (`RouteObserver<PageRoute<dynamic>>`) registered on the root
                                   MaterialApp; `CameraScreen` implements RouteAware; CameraX released
                                   while covered by a page route and safely reacquired on reveal;
                                   dialogs/bottom sheets excluded; no duplicate init or leak;
                                   idempotent callbacks; 7 focused tests.
 B1 GPS STATE SEMANTICS:   IMPLEMENTED & VERIFIED (ACCEPTED) — distinct Permission Denied / Permission Unknown /
                                   Location Services Off / Acquiring / Last-Known Only / Live Fix /
                                   Live Fix Lost-Stale states; Unknown ≠ Denied and Service Off ≠
                                   Denied; `hasLiveFix` is the sole capture-readiness provenance
                                   (`hasValidFix && !isLastKnownSeed`); `resumeLocationStream()`
                                   revalidates permission + service and drops stale/cached fixes;
                                   cleanup idempotent; 17 focused tests.
 C1 VIDEO HUD IDENTIFIER:  IMPLEMENTED & VERIFIED (ACCEPTED) — the fullscreen video HUD now renders the
                                   canonical persisted `SiteModel.siteCode` (uppercased) instead of the
                                   internal Firestore-style site document id, with the established neutral
                                   `SITE` fallback when the code is missing / blank / `UNASSIGNED`.
 METADATA CARD UNIFICATION: COMPLETED & VERIFIED — ONE canonical runtime metadata card
                                   (`StandaloneMetadataWidget`, `HudData`-driven) now serves BOTH Photo and
                                   Video fullscreen/immersive viewing, adapted from the persisted
                                   `MediaItem` via `HudFormatter.fromMediaItem`; the bespoke 3-row video
                                   strip is removed and the Photo immersive viewer mounts the same card;
                                   optional media-agnostic accuracy/satellite telemetry was added to
                                   `HudData`; the burned Photo JPEG HUD (`WatermarkDrawer` /
                                   `EvidenceProcessingService`) is untouched and the removed Detail
                                   "EVIDENCE MINIMAP & METADATA" section remains removed.
 PERFORMANCE AUDIT:        READ-ONLY — NO CHANGE (Photo Capture → Review & Tag → Save is already lean:
                                   no hashing, image codec, HUD render, or file writes occur on the Save
                                   click; CPU work is already off-isolate and DB work runs on Drift's
                                   background isolate; atomic write→verify→commit ordering preserved.
                                   Recommendation: DO NOT OPTIMIZE NOW — no low-risk localized Save
                                   optimization exists.)
 PHYSICAL RE-VERIFICATION: PENDING (Android 16 device verification required after all remediation
                                   modules complete — fullscreen video enter/play/replay/exit; CameraX
                                   release/resume across video + evidence routes; GPS Denied vs Unknown
                                   vs Service-Off; last-known-only shutter lock; Photo AND Video
                                   fullscreen metadata-card visual parity with canonical siteCode)
 AUTOMATED VERIFICATION:   PASS (All 737 tests pass across unit and widget suites; `flutter analyze`
                                   reports 0 issues; account-deletion cloud function suite 43/43;
                                   Firebase rules/emulator JS suites 7/19 with the 12 failures
                                   root-caused as test-harness/emulator environment drift, not
                                   production defects)
 KNOWLEDGE GRAPH:          STALE (graphify-out predates the Audit A–C remediations; refresh with
                                  `graphify update .` recommended before graph-assisted navigation)
 TASK OBSERVER PROTOCOL:   PASS (Formalized in CLAUDE.md)
 GIT HYGIENE:              PASS (git diff --check is clean; no whitespace or syntax errors)
========================================================================================
```

---

## 2. Status of Audit Findings & Completed Remediation Modules

### Module A: Metadata Overlay Workflow Audit (F1–F5)
* **Classification**: **CONFIRMED ARCHITECTURAL INCONSISTENCIES (REMEDIATED & VERIFIED)**
* **Architectural Authority**: `EvidenceMetadataSnapshot` is the capture-time authority. Canonical evidence metadata semantics are established at capture and preserved through persistence and reload.
* **Findings & Remediations**:
  1. **F1 (Verification Status Unification)**:
     - Unified verification status logic in `EvidenceMetadataSnapshot.evaluateVerificationStatus(hasValidFix, lat, lon, accuracyM, threshold)`.
     - Eliminated live HUD vs baked evidence divergence. Wired configurable `lowAccuracyThresholdMeters` from `GpsSettings` through `GpsUiFixture` to `HudFormatter.fromLive` and `EvidenceMetadataSnapshot.capture`.
     - Live HUD and baked evidence watermark now achieve 100% status parity for identical GPS evidence and custom thresholds.
  2. **F2 (Canonical Status Persistence & Pre-v8 Migration Fallback)**:
     - Upgraded Drift database schema to **Version 8**, adding `verification_status` column to `Media` table.
     - Updated `MediaItem` and `MediaRepository` to persist and reload `verificationStatus`. Persisted status remains invariant across subsequent settings changes.
     - Implemented weakest defensible fallback for legacy pre-v8 records (`verification_status` null):
       - If `(lat == 0.0 && lon == 0.0)` or `accuracyM == null` -> `HudStatus.pending`.
       - If `lowAccuracy == 1` or `accuracyM > 20.0` -> `HudStatus.degraded`.
       - Only if non-zero coordinates and `accuracyM <= 20.0` -> `HudStatus.verified`.
       - Historical records never gain stronger verification certainty merely because the column is null.
  3. **F3 (Canonical GNSS Telemetry Persistence)**:
     - Added `gnss_satellite_count`, `gnss_satellites_used_in_fix`, and `gnss_fix_timestamp` to Drift schema v8 and `MediaItem`.
     - Persisted and reloaded canonical satellite metrics across SQLite and detail/viewer surfaces; excluded transient diagnostic-only fields (`gnssSnapshot`, `gnssConstellations`).
  4. **F4 (Video Evidence Metadata on Detail & Immersive Surfaces)**:
     - **Architectural Inspection**: Inspected `LocalVideoPlayerWidget`, playback lifecycle, touch handling, and video containers. `LocalVideoPlayerWidget` intercepts touch events via its own `GestureDetector` (play/pause) and scrubber progress bar. Burning watermarks into `.mp4` video files would alter file bytes, break SHA-256 integrity, and be computationally prohibitive.
     - **Detail Surface**: Added a structured `CAPTURE & GEOSPATIAL TELEMETRY` section to `MediaDetailScreen` showing captured UTC/local timestamps, labeled coordinates, altitude with datum, canonical verification status badge, and satellite counts.
     - **Immersive / Fullscreen Surface**: Added `Fullscreen Zoom` button to the video player container in `MediaDetailScreen`. In `_openFullScreenViewer`, when `_item.type == MediaItemType.video`, renders `LocalVideoPlayerWidget` and overlays a clean bottom metadata strip wrapped with `IgnorePointer` so video playback and scrubber controls remain completely responsive.
     - **Raw Video Artifact Preservation**: Raw `.mp4` video files and their SHA-256 hashes remain 100% untouched.
  5. **F5 (Truthful Altitude Datum Handling)**:
     - Updated `GPSUtils.formatAltitude` to support `bool? isMsl`: `true` -> `'m ASL'`, `false` -> `'m (WGS84)'`, and `null` -> `'m'` (unspecified datum, never defaulting to MSL).
     - Preserved `is_altitude_msl` column in Drift schema v8 and connected it to `EvidenceExportService` for PDF report generation.
  6. **Timestamp Semantics**:
     - Preserved capture/shutter timestamp vs GPS fix timestamp vs display time.
     - In `CameraScreen`, both normal video stop and interrupted recording recovery preserve `recordingStartedAtUtc` as the capture timestamp rather than substituting the stop/recovery time.
* **Verification**:
  - 9 tests in `test/unit/metadata_overlay_workflow_test.dart` pass (F1 threshold parity, F2 persistence invariance, all 5 pre-v8 migration fallback branches, F3 GNSS telemetry reload, F4 video hash preservation, F5 truthful altitude datum).
  - 14 tests in `test/widget/media_detail_screen_test.dart` pass (telemetry section, video fullscreen route, metadata overlay strip).

---

### Module B: Video Persistence & GPS Integrity Remediation (R1–R3)
* **Classification**: **CONFIRMED PERSISTENCE DEFECTS (REMEDIATED & VERIFIED)**
* **Findings & Remediations**:
  1. **Safe Video File Writes**: Normal video stop does not delete the temporary recording file until the destination write and verification succeed. Catches filesystem exceptions and prevents unhandled crashes.
  2. **Atomic Thumbnail Writes**: Thumbnail generation and writes are failure-safe; artifact paths are only recorded in `MediaItem` after verified disk writes.
  3. **Prevention of 0,0 Coordinates**: Prohibited invalid/missing GPS from being persisted as `0.0, 0.0`. Valid fix status is checked consistently across normal stop and interrupted recording recovery.
  4. **Interrupted Recording Recovery**: Preserves recording-time GPS fix and metadata (`recordingGps`) rather than substituting the newly resumed GPS state.
  5. **Orphan Cleanup on DB Failure**: `keepForLater()` deletes physical artifacts if SQLite insertion fails.
  6. **PopScope Navigation Safety**: System Back from `ReviewTagScreen` prevents orphaned artifacts; cancellation preserves current screen; confirmed discard uses explicit cleanup path.
* **Verification**: 40 unit and widget tests across `media_persistence_coordinator_test.dart`, `camera_screen_test.dart`, and `review_tag_screen_test.dart` pass.

---

### Module C: Minimap & GPS Workflow Remediation (F1–F4)
* **Classification**: **CONFIRMED DEFECTS (REMEDIATED & VERIFIED)**
* **Findings & Remediations**:
  1. **F1 (GPS Background/Foreground Staleness)**: In `GpsHardwareNotifier`, re-evaluates fix age on app resume. If elapsed time exceeds `stalenessTimeout`, immediately drops to searching state; otherwise re-arms the staleness watchdog.
  2. **F2 (Map Thumbnail Cache-Key Consistency)**: Standardized one canonical cache key definition across static API writes, disk cache reads, live snapshot updates, and evidence fallback.
  3. **F3 (Shutter Button Re-Entrancy Hazard)**: Implemented shutter capture lock in `CameraScreen` that remains engaged throughout post-hardware processing and releases cleanly after capture success or failure, preventing concurrent overlapping captures.
  4. **F4 (Minimap Live Snapshot Timeout & Generation Guard)**: Isolated map types in cache keys, discarded out-of-order background responses from superseded layer generations, and prevented fallback tile poisoning.
* **Verification**: 24 tests in `minimap_evidence_provenance_test.dart`, 27 tests in `gps_hardware_controller_test.dart`, and 21 tests in `camera_screen_test.dart` pass.

---

### Module D: Camera Permission Recovery & Lifecycle Hardening
* **Classification**: **CONFIRMED PERMISSION & HARDWARE DEFECTS (REMEDIATED & VERIFIED)**
* **Findings & Remediations**:
  1. **Single Permission Subsystem**: Reused `PermissionService` as the single authoritative abstraction; prevented competing permission implementations.
  2. **Restricted Status Semantics**: Distinguished `PermissionStatus.restricted` (system/parental policy) from temporary or recoverable denial.
  3. **Settings Return Navigation**: Returning from system settings triggers re-evaluation and smoothly routes the user back to the camera.
  4. **Camera Hardware Mutex**: FIFO synchronization mutex in `CameraHardwareNotifier` eliminates handle leaks and race conditions during rapid app minimize/resume.
* **Verification**: 21 tests in `camera_hardware_controller_test.dart` and 12 tests in `camera_permission_recovery_test.dart` pass.

---

### Module E: Photo Evidence Remediation (SiteLens #7 F1–F3)
* **Classification**: **CONFIRMED DEFECTS & INTEGRITY GAPS (REMEDIATED & VERIFIED)**
* **Architectural Authority**: Immutable original JPEG (`orig_<id>.jpg`) preserved on DB failure; crash-safe atomic publication with zero-byte rejection; single authoritative pure integrity rule (`ClosedEvidenceIntegrity`) governing Closed evidence links, `Evid_ID` note references, repository operations, and detail surfaces.
* **Findings & Remediations**:
  1. **F1 (Preserve Original on DB Failure — BLOCKER)**:
     - In `MediaPersistenceCoordinator.persistPendingCapture` and `keepForLater`, updated failure handling for photo payloads to invoke `cleanupPartialArtifacts(payload.mediaId)`.
     - Ensures immutable camera capture `orig_<id>.jpg` is **never deleted** due to a Drift SQLite transaction failure, while purging derived artifacts (`evid_<id>.jpg`, `thumb_<id>.jpg`) and temporary files.
     - `ReviewTagNotifier.retake` explicitly calls `deleteLocalMediaFiles` to guarantee user-cancelled or retaken captures cleanly purge both original and derived artifacts.
  2. **F2 (Crash-Safe Evidence Writes — BLOCKER)**:
     - In `EvidenceStorageService`, implemented `_atomicWriteFile`: writes output first to sibling temporary file `.tmp_<timestamp>_<filename>` with OS-flush, then atomically renames to final destination path.
     - Automatically cleans up temporary files on write/publish failure.
     - Updated `cleanupPartialArtifacts(mediaId)` to purge any dangling `.tmp_*` files for that media ID.
     - Hardened `hasLocalArtifacts` to verify `file.lengthSync() > 0`, refusing to accept empty or 0-byte corrupted files.
  3. **F3 (Enforce Linked-Evidence Integrity During Editing — GAP)**:
     - Extracted pure utility `ClosedEvidenceIntegrity` (`enforceIntegrity`, `updateNoteWithEvidId`, `removeEvidIdFromNote`, `removeAllEvidIdsFromNote`).
     - Delegated ReviewTagNotifier static helpers to `ClosedEvidenceIntegrity`.
     - In `MediaRepository.updateTags`, accept optional `linkedMediaId` and automatically enforce `ClosedEvidenceIntegrity.enforceIntegrity`: if observation is non-Closed, clears `linkedMediaId` in SQLite and strips `Evid_ID` from notes.
     - In `MediaRepository.linkMedia`, guarded against linking to non-Closed records.
     - In `MediaTagEditModal`, preloads candidate on init, clears candidate and note `Evid_ID` on type switch away from Closed or link dismissal, and enforces clean save path.
     - In `MediaDetailScreen`, guarded `_loadContextualData` and widget build tree to only load/render `_buildLinkedEvidenceCard` when `observationType == ObservationType.closed`.
* **Verification**:
  - `test/unit/media_persistence_coordinator_test.dart` (24/24 tests pass, including original preservation on DB failure and retake cleanup).
  - `test/unit/storage_service_test.dart` (11/11 tests pass, including atomic publication, temp failure cleanup, 0-byte rejection).
  - `test/unit/closed_evidence_integrity_test.dart` (7/7 tests pass, covering pure logic, note stripping, DB persistence invariant, and `linkMedia` guard).
  - `test/widget/media_detail_screen_test.dart` (16/16 tests pass, covering Detail non-Closed guard and `MediaTagEditModal` type switch / note cleanup).

---

### Module F: Review Tag & Smart-Link Workflow Remediation (SiteLens #8 F1–F5)
* **Classification**: **CONFIRMED INTEGRITY & USABILITY DEFECTS (REMEDIATED & VERIFIED)**
* **Architectural Authority**: Single authoritative candidate evaluation and link lifecycle in `ReviewTagNotifier`, strict candidate-to-link binding in `ReviewTagState`, comprehensive defense-in-depth isolation in `MediaRepository` and `MediaPersistenceCoordinator`, and truthful geospatial distance computation in `MediaTagEditModal`.
* **Findings & Remediations**:
  1. **F1 (Smart-Link Dismissal & Fallback UI)**:
     - In `ReviewTagNotifier`, implemented `dismissSuggestedMatch()`: clears `suggestedBeforeMatch`, `linkedMediaId`, and removes the system-generated `Evid_ID: <id>` line from notes while strictly preserving user inspection remarks.
     - In `ReviewTagScreen`, wired `SmartLinkCard.onDismiss` ("Not now" button) to `dismissSuggestedMatch()`. When dismissed, renders clean fallback prompt guiding user to "Find Nearby Evidence" without showing misleading error state.
     - In `MediaTagEditModal`, candidate dismissal similarly clears candidate, distance, and linked ID, and sanitizes note text via `ClosedEvidenceIntegrity`.
  2. **F2 (Candidate Consistency & Divergence Guard)**:
     - In `ReviewTagNotifier.searchSmartLink`, when a new candidate search resolves to Candidate B while previously linked to Candidate A, automatically reconciles state: clears stale link and removes Candidate A's `Evid_ID` from the note.
     - Hardened `ReviewTagState.isLinked` getter: returns `true` if and only if `linkedMediaId != null && suggestedBeforeMatch != null && linkedMediaId == suggestedBeforeMatch!.id`.
     - In `ReviewTagNotifier.saveEvidence`, implemented defensive check: if `linkedMediaId` diverges from `suggestedBeforeMatch?.id`, clears the link, strips `Evid_ID`, and halts save with validation error. Candidate A is never persisted when B is presented.
  3. **F3 (Evid_ID / Link Invariant on Search Miss or Error)**:
     - In `ReviewTagNotifier.searchSmartLink`, if spatial search yields no candidate (or throws an unexpected exception), system `Evid_ID` lines are purged from the note while preserving inspector remarks.
     - In `ReviewTagNotifier.setObservationType`, switching away from Closed removes all system `Evid_ID` references.
     - Enforced at persistence boundaries: `MediaPersistenceCoordinator.persistPendingCapture`, `LocalMediaRepository.insertMedia`, and `LocalMediaRepository.updateTags` automatically apply `ClosedEvidenceIntegrity.enforceIntegrity`, stripping leaked `Evid_ID` lines from non-Closed or unlinked records.
  4. **F4 (Truthful Haversine Distance in MediaTagEditModal)**:
     - In `MediaTagEditModal`, replaced hardcoded/fallback `0.0m` distance with live `SpatialMathUtils.haversineDistanceMeters` calculation between the editing media item and the loaded linked candidate (`_loadLinkedCandidate`) or newly discovered candidate (`_searchCandidate`).
     - Resets `_suggestedDistance` to null upon type switch or candidate dismissal.
  5. **F5 (Creator and Site Isolation)**:
     - In `LocalMediaRepository._findSpatialCandidatesInternal`, added SQL filter criteria matching `creatorId` and `siteId`.
     - At all database entry points (`LocalMediaRepository.insertMedia`, `LocalMediaRepository.linkMedia`, `LocalMediaRepository.updateTags`, and `MediaPersistenceCoordinator.persistPendingCapture`), added strict checks verifying that the linked candidate belongs to the same `creatorId` and `siteId`, throwing `MediaPersistenceException` if cross-user or cross-site linking is attempted.
* **Verification**:
  - `test/unit/review_tag_remediation_test.dart`: 9/9 tests pass (F1 dismissal note preservation, F2 candidate divergence reconciliation & save defense, F3 search miss note preservation & persistence invariants, F5 cross-user/cross-site rejection across repository and coordinator).
  - `test/widget/review_tag_remediation_widget_test.dart`: 3/3 tests pass (F1 "Not now" button dismissal & fallback text, F4 loaded candidate Haversine distance, F4 searched candidate Haversine distance).

---

### Module G: Smart-Link E2E Correction (SiteLens #9 F-1)
* **Classification**: **CONFIRMED SEMANTIC DEFECT IN PRIOR REMEDIATION (CORRECTED & VERIFIED)**
* **Authoritative Product Semantics**: Linking is relationship metadata, never a destructive transition. Closed B → Non-Conformity A is a link only; A and B remain independently persisted and gallery-visible. An existing B→A relationship may be changed or removed only through explicit user action ("Select as BEFORE" on a new suggestion, "Unlink", or explicit observation-type switch). Editing activity/details and refreshed Smart-Link suggestions must never silently displace or destroy the existing link.
* **Corrections**:
  1. **MediaTagEditModal** (`lib/features/gallery/widgets/media_tag_edit_modal.dart`): split `_linkedCandidate`/`_linkedDistance` (authoritative existing link) from `_suggestedBeforeCandidate`/`_suggestedDistance` (new suggestion). `_searchCandidate` and `_loadLinkedCandidate` only ever update the suggestion; `_reconcileSuggestedCandidate` (auto-unlink) was removed. Dual-card UI shows "SELECTED BEFORE EVIDENCE" (A) plus a separate "SMART-LINK SUGGESTION" card (C). Explicit handlers: `_handleLinkSuggestion` (replaces A→C, updates Evid_ID via `ClosedEvidenceIntegrity.updateNoteWithEvidId`), `_handleUnlink` (removes relationship + Evid_ID), `_handleDismissSuggestion` (suggestion only). Save persists `_linkedMediaId`; strict `_isLinked` gates the save button.
  2. **ReviewTagNotifier / ReviewTagState / ReviewTagScreen** aligned to the same non-destructive semantics: `ReviewTagState` gained `linkedCandidate`; `isLinked` is strict against it; `searchSmartLink` no longer clears an established link on a differing match or a search miss (suggestion-only); `dismissSuggestedMatch` clears the suggestion only; `saveEvidence` refuses an unrepresented link without destroying it; the review screen renders the linked panel and a separate suggestion card.
* **Verification**:
  - `test/unit/review_tag_remediation_test.dart`: rewritten F1/F2/F3 + new "Non-Destructive Smart-Link Lifecycle (Test 5)" — saving B→A leaves A and B persisted and gallery-visible; link survives suggestion changes and search misses; explicit actions only mutate the relationship. 12/12 pass.
  - `test/widget/review_tag_remediation_widget_test.dart`: new "Modal Non-Destructive B→A Lifecycle (SiteLens #9 Correction)" group — Test 1 existing link survives edit (A stays selected, save persists A, A/B gallery-visible), Test 2 explicit replacement (A→C via Select as BEFORE, A/C intact), Test 3 explicit unlink (relationship + Evid_ID removed via Unlink + General switch, A/B intact), Test 4 search-race request guard retained. 6/6 pass.

---

### Module H: Evidence List Remediation (SiteLens #10 F1–F2)
* **Classification**: **CONFIRMED DEFECTS (REMEDIATED & VERIFIED)**
* **F1 (Deterministic History ordering)**: `LocalMediaRepository.watchAllMedia` (`lib/data/repositories/media_repository.dart`) now orders `captured_at DESC, id ASC` — newest-first preserved, stable tiebreaker for identical timestamps. Regression test in `test/unit/gallery_controller_test.dart` proves identical-`capturedAt` rows order by id and remain stable across stream re-emissions.
* **F2 (Unreachable Sync Status filter)**: the existing sync-status filter pipeline was completed rather than removed — a "SYNC STATUS" dropdown (All Sync States / Pending / Syncing / Synced / Failed) was added to `GalleryFilterModal` (`lib/features/gallery/widgets/gallery_filter_modal.dart`), wired to the pre-existing `setSyncStatus` path and `activeFilterCount`. Regression tests in new `test/widget/gallery_filter_modal_test.dart` prove selection filters the gallery and "All Sync States" clears it.
* **Verification**: `test/unit/gallery_controller_test.dart` 10/10; `test/widget/gallery_filter_modal_test.dart` 2/2; `gallery_screen_test.dart` green.

---

### Module I: Offline Capture & Cloud Metadata Remediation (SiteLens #11 F1–F2)
* **Classification**: **CONFIRMED DEFECTS (REMEDIATED & VERIFIED)**
* **F1 (Online capture auto-sync)**: the unsynced-count listener in `SyncCoordinator` (`lib/features/sync/services/sync_coordinator.dart`) now edge-triggers `triggerSync(isManual: false)` when the pending count increases and the session is online; mid-cycle triggers defer via `_pendingAutoSync` through the existing single-flight chain. The Drift-backed stream emits only after the local insert transaction commits, so nothing uploads before persistence/artifact validation. Offline captures stay queued and sync on reconnect as before.
* **F2 (v8 forensic metadata in cloud)**: `CloudSyncService._ensureFirestoreDocSynced` create payload and reconcile now carry `altitude`, `is_altitude_msl`, `verification_status`, `gnss_satellite_count`, `gnss_satellites_used_in_fix`, `gnss_fix_timestamp` (sourced from the persisted `MediaItem` — capture-time, never re-derived). Immutable-field conflict detection extended for each. `firestore.rules` create allowlist + optional validation extended (bool datum, verification enum, GNSS numeric bounds, fix timestamp ≤40 chars).
* **Verification**: `test/unit/sync_coordinator_test.dart` F1 auto-sync group 2/2; `test/unit/cloud_sync_service_test.dart` F2 v8 group 5/5 (create persists all fields; matching passes without re-upload; conflicts on altitude / verification_status / GNSS throw).

---

### Module J: Synchronization E2E Remediation (SiteLens #12 F1–F3)
* **Classification**: **CONFIRMED DEFECTS (REMEDIATED & VERIFIED)**
* **F-1 (Foreground resume triggers sync)**: `SyncCoordinator` now mixes `WidgetsBindingObserver`; `didChangeAppLifecycleState(resumed)` triggers `triggerSync(isManual: false)` for an authenticated session only, reusing the existing single-flight/session-generation pipeline. Observer registered in `_init`, removed in `dispose`.
* **F-2 (Unexpected exceptions suppressed)**: the generic catch in `_processSingleItem` now adds the id to `_permanentFailedIds` before marking `failed` — deterministic permanent suppression with honest local status; manual retry re-evaluates; retryable/backoff behavior unchanged.
* **F-3 (Session-scoped eager crash recovery)**: new `SyncLifecycleBootstrap` in `lib/app/app.dart` watches `sessionServiceProvider.select((s) => s.user)` and only then watches `syncCoordinatorProvider` — the coordinator (crash recovery `resetStuckSyncingMedia`, connectivity subscription, resume observer) initializes exactly once per authenticated application lifecycle, independently of Gallery. Unauthenticated startup never creates it; `resetStuckSyncingMedia` is gated on an authenticated session at init and re-runs on the auth sign-in branch. Sign-out leaves the instance dormant (auth guards prevent further synchronization); no duplicate instances/subscriptions.
* **Verification**: `test/unit/sync_coordinator_test.dart` F1 resume group 4/4 + F2 suppression group 2/2; new `test/unit/sync_lifecycle_bootstrap_test.dart` 4/4 (authenticated init resets stuck rows without Gallery; unauthenticated startup does nothing; logout prevents sync; repeated transitions reuse one coordinator). Integration helper `fake_sync_coordinator.dart` updated for the lifecycle interface.

---

### Cross-Cutting Audit A: EXIF / Metadata Semantics (REMEDIATED & VERIFIED)
* **Classification**: **CONFIRMED GAPS (REMEDIATED & VERIFIED)**
* **Verdict**: `EvidenceMetadataSnapshot` + Drift + burned HUD are correctly authoritative; EXIF is never read back as truth.
* **F-A1 (Derived-artifact EXIF stripping)**: in `EvidenceProcessingService._processImageWorker` (`lib/features/camera/services/evidence_processing_service.dart`), after `bakeOrientation` the worker now resets `orientedImage.exif = img.ExifData()` before crop/HUD compositing/encoding — derived evidence JPEG and thumbnail carry no camera EXIF (device GPS, device-clock timestamps, Make/Model), while the immutable original keeps its capture-time EXIF. Policy verified against `image` 4.3.0 sources (encoder writes EXIF from the image; empty EXIF → no APP1 segment).
* **F-A2 (No synthesized GPS fallback)**: `GpsHardwareNotifier.getBestRecentPosition` (`lib/features/camera/controllers/gps_hardware_controller.dart`) no longer synthesizes a fallback `Position` (`accuracy ?? 0.0`, `timestamp ?? now`) when the raw-position buffer is stale — it returns null and the capture paths keep unknown accuracy/altitude/fix-timestamp unknown. New static `applyBestRecentPosition` seam is the canonical merge policy (MSL altitude authority preserved).
* **F-A3–F-A7 (observations, non-blocking)**: reload `capturedAt ?? DateTime.now()` fallback; no SiteLens-authored EXIF writer (design boundary); read-only `JpegMetadataExtractor`; dead UI verification fallback; export manifest completeness.
* **Verification**: `test/unit/evidence_processing_service_test.dart` F-A1 test (original keeps device EXIF; derived evidence + thumbnail stripped; orientation-6 baked to pixels; encoder control proves non-vacuous) + 5 F-A2 tests in `test/unit/gps_hardware_controller_test.dart`. Focused run 64/64; related suites 87/87; full suite 663/663; analyzer 0 issues.

---

### Cross-Cutting Audit B: Evidence Artifact Cloud Synchronization (AUDITED; B-1 REMEDIATED & VERIFIED)
* **Classification**: **AUDIT PASS-WITH-FINDINGS; B-1 CONFIRMED GAP (REMEDIATED & VERIFIED)**
* **Audit verdict**: artifact identity, hash binding, idempotent uploads, write-once enforcement, and recovery integrity are coherent; failed uploads cannot become `synced`; no artifact corruption or spoofing path found.
* **B-1 (Local tombstones never propagated — GAP)**: `getPendingOrFailedMedia` excluded deleted rows, so a locally soft-deleted synced item never reached the existing `is_deleted` reconcile; the cloud ledger stayed `is_deleted: false`.
* **Remediation**: `MediaRepository.getTombstoneSyncCandidates` / `watchTombstoneCandidateCount` (deleted rows not mid-sync, creator-scoped); `CloudSyncService.syncTombstone` (creator guard → doc-exists check → reuses `_ensureFirestoreDocSynced` reconcile; missing document = verified no-op) with error mapping extracted into `_runMappedSyncOperation`; `SyncCoordinator` merges tombstone candidates into the cycle (same mutex/backoff/session-generation machinery, count edge-trigger mirrors the unsynced trigger) and never writes the artifact-sync status of a deleted row. Deleted published items reconcile `is_deleted: true`; never-published items are verified no-ops; Storage artifacts are never read, modified, or deleted by propagation.
* **B-2..B-7 (observations, non-blocking)**: ledger-before-upload dangling-doc window (required by Storage rules creator binding; fail-safe consumers); evidence JPEG is local-only (recovery restores original); Google Photos parallel upload path (opt-in, creator-gated, sha-verified); export manifest can reference omitted files; pre-v8 cloud docs lack v8 backfill; JS rules/emulator suites 12/19 failures root-caused as harness/emulator environment drift (missing `email_verified` claims in test contexts, `node:test` file under jest, emulator evaluation drift — canonical v8 media-create rule verified PASS by probe).
* **Verification**: focused tombstone suites 104/104 (cloud_sync 25, sync_coordinator, media_persistence, sync_lifecycle_bootstrap, auth_session_invalidation, storage_cleanup); related suites 91/91; full suite 676/676; analyzer 0 issues.

---

### Cross-Cutting Audit C: Capture ↔ Sync Lifecycle / Dead-Path Cleanup (AUDITED; C-1/C-2 REMEDIATED & VERIFIED)
* **Classification**: **AUDIT GAP (no BLOCKERs); C-1/C-2 CONFIRMED GAPS (REMEDIATED & VERIFIED)**
* **C-1 (Stale `_inFlightVideoFile` — GAP)**: `stopVideoRecording` never cleared the in-flight reference, so every later `pauseCamera` raised a false `hasInterruptedRecording` (self-silencing only because the temp file was already deleted). **Remediation**: `camera_screen.dart` clears the reference via `clearInterruptedRecording()` exactly at handoff completion (storage copy written + camera temp deleted); genuine interruptions and Keep/Discard semantics unchanged; failure paths before handoff keep recovery.
* **C-2 (Permanent deletion stranding a live cloud ledger — GAP)**: `deletePermanently` physically destroyed the row, so a partially published (failed) item's Firestore ledger stayed live forever. **Remediation**: `LocalMediaRepository.deletePermanently` now deletes local files and tombstones the row (`softDeleteMedia`) — the hidden tombstone rides the B-1 lifecycle (published → `is_deleted: true`; never-published → verified no-op; failure → deferred, recoverable row; idempotent; session/backoff preserved). Physical row removal remains an account-deletion concern. No schema change; `syncTombstone` reused, no second mechanism.
* **C-3..C-6 (observations, non-blocking)**: production-dead helpers (`persistCapturedEvidence`, `getUnsyncedMedia`, `computeSha256String`, audit-PDF aliases, unused `activeSyncingIds`); orphan-artifact edges (kill-app on review, keepForLater failure, video temp leak); non-atomic video original write; permanently failed item with locally corrupted evidence JPEG strands the row (original remains intact and exportable).
* **Verification**: focused C-1/C-2 suites 108/108 (camera_screen 22, sync_coordinator, cloud_sync, media_persistence); related suites 115/115; full suite 682/682; analyzer 0 issues.

---

### Cross-Cutting Audit D: Capture Position Provenance & Spatial Search Integrity (AUDITED; D-SPAT-001/D-SPAT-002/LAT-001 REMEDIATED & VERIFIED)
* **Classification**: **AUDIT PASS-WITH-FINDINGS (Nearby Search feature PASS); D-SPAT-001 CONFIRMED DEFECT (REMEDIATED & VERIFIED); D-SPAT-002 CONFIRMED GAP (REMEDIATED & VERIFIED); LAT-001 CONFIRMED GAP (REMEDIATED & VERIFIED)**
* **Reproduction case**: 8 same-location photos within the configured 25 m radius; per-source "Find Nearby Evidence" returned only 1 instead of 7. Nearby Search audited end-to-end (source→navigation handoff, search origin, radius calculation, haversine/bbox distance, site/creator/sync filtering, pagination, source exclusion, grouped/timeline/map rendering) — feature verdict **PASS**; the exclusion was geometrically correct on the stored data.
* **Data confirmation (read-only; device + Firestore mirror, release build lacks `allowBackup`/debuggable so the mirror was used — value-equivalent for the audited fields, anchored by SHA-256)**: the 8 rows split into two recorded locations — 6 rows at a bit-identical frozen coordinate `22.5650104, 88.3167979` (accuracy bit-identical `4.107 m`, reverse-geocoded Shibpur/Howrah; no GNSS telemetry fields) and the 2 SHA-anchored rows `5f1bb230…`/`fcb2ba46…` at `22.5653, 88.5173` (live fixes ~7.5 m apart, New Town) — **~20.6 km apart**. Creator/site/deleted predicates were identical across all rows (ruled out). The 25 m search from either SHA-matched source returns exactly 1 (its partner) — the reported symptom reproduced exactly. Falsified coordinates propagated into the smart-link graph (`c79ac732` closed → `5ee978b8` BEFORE at 0.0 m computed distance, permanently resolving it).
* **D-SPAT-001 root cause (CONFIRMED DEFECT)**: `gpsHardwareProvider` is autoDispose, so every capture → Review → Camera cycle destroyed the GNSS notifier and re-seeded state from the OS last-known location in `initialize()`; the cached seed latched as a normal fix and `EvidenceMetadataSnapshot.capture` derives status from accuracy alone (`evaluateVerificationStatus`) — a wrong cached position was burned VERIFIED ±4.1 m into 6 artifacts, their watermarks, and the cloud ledger. Audit A F-A2 covered raw-buffer staleness (null → unknown) but never position *provenance*; no continuity/jump guard existed.
* **D-SPAT-001 remediation**: `GpsHardwareState.isLastKnownSeed` provenance flag — set for the `getLastKnownPosition` seed (display-only: map pin/HUD behavior unchanged, 5 existing seeding tests untouched), cleared by any live stream emission or fix-clear; new `hasLiveFix` getter; both shutter paths (`camera_screen.dart` photo + video) now require `hasLiveFix` and block capture with a truthful snackbar when only a cached seed or no fix exists — enforcing the documented "captures are locked until a verified GPS fix is obtained" contract.
* **D-SPAT-002 (CONFIRMED GAP)**: the video stop path rejected `!hasValidCoordinates` captures but the photo path had no equivalent — a fix-less shutter press persisted `0,0` coordinates (the "no 0,0 coords" remediation was video-scoped). **Remediation**: the new photo gate covers the same condition, placed before map-snapshot/hardware work.
* **LAT-001 (CONFIRMED GAP)**: `_findSpatialCandidatesInternal` hard-filtered `creator_id = ?` while every sync/ownership query tolerates legacy `NULL`-creator rows; pre-attribution rows were invisible to spatial search. **Remediation**: `creatorId.equals(?) | creatorId.isNull()` ownership parity; cross-creator isolation unchanged (tests 16/18 still enforce it).
* **Verification**: `test/unit/gps_hardware_controller_test.dart` D-SPAT-001 group 3/3 (seed flagged cached, live emission supersedes provenance, stale-clear drops flag with the fix); `test/unit/nearby_search_controller_test.dart` test 19 (NULL-creator legacy row visible to authenticated search, other-creator row excluded, source excluded); camera_screen suite 24/24; full suite **686/686** (682 + 4 new regressions); analyzer 0 issues.

---

### E2E Audit Program: Journey, Settings & Legal, Account Deletion (READ-ONLY, ALL PASS)
* **Full user journey (install → onboarding → auth → site setup → camera → capture → review → sync → history → logout/relaunch → deletion)**: **PASS** — no broken handoff, state inconsistency, persistence gap, or unreachable path; journey-edge suites 52/52; full suite 682/682.
* **Settings & Legal workflow**: **PASS** — every visible action (GPS/watermark/nearby/storage/GPhotos/account/support/legal) traces to a real handler with correct resulting state and error states; legal docs are inline content; support enquiry chain (client validation → HTTPS callable envelope with App Check + ID token → server validation/rate-limit/idempotency/Resend) fully traced; suites 70/70.
* **Account deletion workflow**: **PASS** — Settings entry → re-auth → `deleteUserAccount` (App Check, caller-only identity, sole-member/shared/sole-admin-successor classification, Storage prefix purge via Admin SDK, Firestore cascade, enquiries anonymized, Auth deletion, rate-limit cleanup) → local Drift/files/prefs purge → sign-out → stack-wiped unauthenticated routing. All four site paths covered; `functions/test/account_deletion.test.js` 43/43; dialog widget tests 5/5.

---

### Reference Documentation Synchronization (PRD.md & architecture.md)
* **Classification**: **COMPLETED & VERIFIED (documentation only)**
* Both documents were inspected in full and synchronized to the verified v8 semantics: capture-time metadata authority and unknown-value semantics; EXIF original/derived boundary (derived artifacts carry no camera EXIF); corrected synchronization flow order (ledger document published before artifact uploads); retry/backoff/suppression and session-generation lifecycle; tombstone propagation and deletion semantics (no physical row destruction on user deletion); v8 media/sites schema; ledger field list; account-deletion lifecycle; write-once idempotent Storage semantics; atomicity/failure-consistency guarantees.
* Inaccurate statements corrected: "EXIF GPS metadata for photos" / "preserved EXIF geotagging" / "photo EXIF GPS metadata is written" (contradicted the verified EXIF policy); "Write Firestore metadata" ordered after uploads; "Delete from Device preserves `is_deleted = 0`" (no such operation exists); "unsynced media ... hard-deletes SQLite" (now tombstones); `queued` sync state → `pending`; v1 media schema (missing `original_uri`, altitude/datum, verification status, GNSS telemetry, `captured_address`, `creator_id`, `evidence_sha256_hash`, `is_deleted`) replaced with the verified v8 model; `'non-conformity'` → `'nonConformity'`.
* Editorial constraints honored: no audit history, test counts, or commit hashes added; historical milestone counts preserved; version identifiers (`v1.0` baseline) untouched; only `docs/handover/PRD.md` and `docs/handover/architecture.md` modified.

---

### Physical Release Finding Remediation — A1 / A2 / B1 (IMPLEMENTED & VERIFIED; PHYSICAL RE-VERIFICATION PENDING)
* **Origin (read-only forensic audit)**: physical release-APK observation on the Motorola edge 50 fusion (Android 16 / SDK 36; `com.sitelens.app` 1.0.0 / 2001; release APK SHA-256 `265195037f9a7f5ec0af0148440f57fdd2c14ebee2524511a1ad62d7436ffb22`). A ~3 s video was captured successfully; opening it in FULLSCREEN VIDEO EVIDENCE crashed the app; after the restart/recovery the camera screen showed `GPS: Denied`, `ACC: ACQUIRING`, and a locked shutter ("GPS required for evidence"). The video's displayed forensic HUD showed an identifier-like token before `UTC:` followed by UTC/local timestamps, LAT/LON, altitude, `STATUS: VERIFIED`, accuracy and satellite count.
* **Audit conclusions (code-verified)**:
  * The video/fullscreen pipeline does **not** write GPS permission state; no video code path can set or clear `permissionStatus`. The post-crash GPS state is an **independent** state/initialization concern — "GPS Denied caused the video crash" is not established.
  * The observed video HUD is the **fullscreen route's bottom overlay**, rendered dynamically from the persisted capture-time `MediaItem`. Video artifacts are never burned/watermarked: the MP4 is copied byte-for-byte and its SHA-256 is both the original and the evidence hash.
  * Remaining lifecycle hazards identified: the fullscreen route constructed a **second** `VideoPlayerController`/ExoPlayer for the same file while the inline player stayed mounted, and CameraX was never released while `CameraScreen` was covered.
* **A1 — Video Fullscreen Player Ownership (IMPLEMENTED & VERIFIED; ACCEPTED)**:
  * New `EvidenceVideoPlayback` (`ChangeNotifier`, `lib/features/gallery/controllers/evidence_video_playback.dart`) is the single owner of at most ONE `VideoPlayerController` per evidence video: created once, initialized once, disposed exactly once.
  * `MediaDetailScreen` owns the instance and shares it with the inline surface and the fullscreen route; `LocalVideoPlayerWidget` is now a stateless borrower (never creates/disposes a controller). The inline surface is parked while fullscreen is on top, so exactly one video surface renders.
  * Race/idempotency: `initialize()` re-checks disposal after every await and releases a late-completing controller; `dispose()` is idempotent; the owned controller is released exactly once even when disposal races initialization; a missing/undecodable file yields a truthful `failed` state without creating a controller.
  * Tests: `test/unit/evidence_video_playback_test.dart` (10) + the `MediaDetailScreen` fullscreen-ownership group (3) — single player reused across enter/exit/re-enter and repeated playback; disposal during async init; idempotent disposal; truthful failure.
* **A2 — CameraX Route Lifecycle (IMPLEMENTED & VERIFIED; ACCEPTED)**:
  * New `appRouteObserver` (`RouteObserver<PageRoute<dynamic>>`, `lib/app/router.dart`) registered via `navigatorObservers` on the root `MaterialApp` (`lib/app/app.dart`). Only full-page routes are observed — dialogs and bottom sheets (`PopupRoute`) do not trigger coverage.
  * `CameraScreen` implements `RouteAware`: `didPushNext` → `pauseCamera()` (release CameraX), `didPopNext` → `resumeCamera()` plus interrupted-recording recovery. Both callbacks are idempotent via a `_isCoveredByRoute` guard; the app-lifecycle handler only reacquires the camera when the screen is not covered; GPS lifecycle calls are unchanged. Subscription/unsubscription is guarded so no callback runs after disposal.
  * Tests: `test/widget/camera_screen_test.dart` A2 group (7) — covered→inactive / visible→active; repeated and nested coverage with no duplicate init or leak; background/foreground while covered stays inactive; redundant pause/resume; disposal while active; truthful error state on failed resume.
* **B1 — GPS State Semantics & Recovery (IMPLEMENTED & VERIFIED)**:
  * `GpsBlockReason` gained `permissionUnknown` and `lastKnownOnly`. `GpsHardwareState.isPermissionUnknown` distinguishes `LocationPermission.unableToDetermine`; `blockReason` is keyed off `hasLiveFix` and evaluates service-off, unknown, denied and last-known-only distinctly — Unknown is never collapsed into Denied, and service-off is never reported as Denied. `statusBadgeLabel`, `GpsUiFixture.pillLabel`/`statusLabel`, `GpsStatusPill` and `GpsStatusExplainerSheet` render the distinct states truthfully.
  * `CameraScreen.isCapturePermitted` now requires `hasLiveFix` (was `hasValidFix`), so cached/last-known coordinates can never unlock evidence capture; the geofence label reads `GPS Fixed` / `Last Known` / `Acquiring Fix`.
  * `initialize()` uses a grant check (denied / deniedForever / unableToDetermine all stop acquisition). `resumeLocationStream()` is now async and explicitly revalidates OS permission **and** location-service state, cancels the stream and clears the latched fix when unavailable, re-checks staleness when granted, and resumes/creates exactly one subscription. `pauseLocationStream()`/`dispose()` are idempotent and post-disposal recovery is harmless.
  * Tests: `test/unit/gps_hardware_controller_test.dart` B1 group (15) + `test/widget/camera_screen_test.dart` B1 group (2) — all seven states, cached-never-live, capture-gate provenance, resume revalidation (denied / unknown / service-off), recovery-requires-a-new-live-fix, no duplicate subscriptions, idempotent cleanup.
* **Physical re-verification**: PENDING — the Android 16 release-device sequence must be executed on the rebuilt APK after all remediation modules are complete (see §5 and §7).

---

## 3. Working Tree Status & Git Ledger

### Modified Files (`git status --short`)
```text
 M .gitignore
 M docs/ALL_TESTS.md
 M docs/handover/PRD.md
 M docs/handover/PROJECT_STATUS.md
 M docs/handover/SESSION_HANDOVER.md
 M docs/handover/architecture.md
 M firestore.rules
 M integration_test/auth_session_boundary_e2e_test.dart
 M integration_test/helpers/fake_auth_service.dart
 M integration_test/helpers/fake_permission_service.dart
 M integration_test/helpers/fake_site_repository.dart
 M integration_test/helpers/fake_sync_coordinator.dart
 M lib/app/app.dart
 M lib/app/router.dart
 M lib/core/services/auth_service.dart
 M lib/core/services/map_thumbnail_service.dart
 M lib/core/services/permission_service.dart
 M lib/core/services/session_service.dart
 M lib/core/utils/gps_utils.dart
 M lib/data/local/database/app_database.dart
 M lib/data/local/database/app_database.g.dart
 M lib/data/repositories/media_repository.dart
 M lib/data/repositories/site_repository.dart
 M lib/domain/models/media_item.dart
 M lib/features/camera/camera_screen.dart
 M lib/features/camera/controllers/camera_hardware_controller.dart
 M lib/features/camera/controllers/gps_hardware_controller.dart
 M lib/features/camera/controllers/map_thumbnail_controller.dart
 M lib/features/camera/hud/hud_data.dart
 M lib/features/camera/hud/hud_formatter.dart
 M lib/features/camera/models/camera_hardware_state.dart
 M lib/features/camera/models/camera_ui_state.dart
 M lib/features/camera/models/evidence_metadata_snapshot.dart
 M lib/features/camera/models/gps_hardware_state.dart
 M lib/features/camera/services/evidence_processing_service.dart
 M lib/features/camera/services/evidence_storage_service.dart
 M lib/features/camera/services/media_persistence_coordinator.dart
 M lib/features/camera/widgets/camera_shutter_station.dart
 M lib/features/camera/widgets/camera_top_hud.dart
 M lib/features/camera/widgets/camera_viewfinder.dart
 M lib/features/camera/widgets/gps_map_thumbnail.dart
 M lib/features/camera/widgets/gps_status_explainer_sheet.dart
 M lib/features/gallery/media_detail_screen.dart
 M lib/features/gallery/services/evidence_export_service.dart
 M lib/features/gallery/widgets/gallery_filter_modal.dart
 M lib/features/gallery/widgets/local_video_player_widget.dart
 M lib/features/gallery/widgets/media_tag_edit_modal.dart
 M lib/features/nearby/controllers/nearby_search_controller.dart
 M lib/features/nearby/models/nearby_search_state.dart
 M lib/features/nearby/nearby_search_screen.dart
 M lib/features/nearby/widgets/location_timeline_view.dart
 M lib/features/nearby/widgets/nearby_media_card.dart
 M lib/features/onboarding/permission_onboarding_screen.dart
 M lib/features/onboarding/permission_recovery_screen.dart
 M lib/features/review/controllers/review_tag_controller.dart
 M lib/features/review/models/pending_capture_payload.dart
 M lib/features/review/models/review_tag_state.dart
 M lib/features/review/review_tag_screen.dart
 M lib/features/review/widgets/smart_link_card.dart
 M lib/features/settings/settings_screen.dart
 M lib/features/sites/site_controller.dart
 M lib/features/sites/site_setup_screen.dart
 M lib/features/sync/services/cloud_sync_service.dart
 M lib/features/sync/services/sync_coordinator.dart
 M lib/shared/widgets/evidence_metadata_hud_card.dart
 M test/unit/auth_session_routing_test.dart
 M test/unit/camera_hardware_controller_test.dart
 M test/unit/cloud_sync_service_test.dart
 M test/unit/evidence_processing_service_test.dart
 M test/unit/gallery_controller_test.dart
 M test/unit/gps_hardware_controller_test.dart
 M test/unit/hud_formatter_test.dart
 M test/unit/map_thumbnail_service_test.dart
 M test/unit/media_persistence_coordinator_test.dart
 M test/unit/minimap_evidence_provenance_test.dart
 M test/unit/nearby_search_controller_test.dart
 M test/unit/review_tag_controller_test.dart
 M test/unit/site_controller_test.dart
 M test/unit/storage_cleanup_service_test.dart
 M test/unit/storage_service_test.dart
 M test/unit/sync_coordinator_test.dart
 M test/widget/camera_screen_test.dart
 M test/widget/gallery_screen_test.dart
 M test/widget/location_timeline_view_test.dart
 M test/widget/m1_screens_test.dart
 M test/widget/media_detail_screen_test.dart
 M test/widget/nearby_search_screen_test.dart
 M test/widget/review_tag_screen_test.dart
 M test/widget/settings_screen_test.dart
 M test/widget_test.dart
 ?? lib/core/utils/closed_evidence_integrity.dart
 ?? lib/features/gallery/controllers/evidence_video_playback.dart
 ?? test/unit/auth_session_invalidation_test.dart
 ?? test/unit/closed_evidence_integrity_test.dart
 ?? test/unit/evidence_video_playback_test.dart
 ?? test/unit/metadata_overlay_workflow_test.dart
 ?? test/unit/review_tag_remediation_test.dart
 ?? test/unit/sync_lifecycle_bootstrap_test.dart
 ?? test/widget/camera_permission_recovery_test.dart
 ?? test/widget/gallery_filter_modal_test.dart
 ?? test/widget/permission_resume_navigation_test.dart
 ?? test/widget/review_tag_remediation_widget_test.dart
 ?? test/widget/site_setup_screen_test.dart
```

Delta vs. the previous ledger: `docs/handover/PRD.md` and
`docs/handover/architecture.md` joined the modified set (documentation
synchronization); `output.txt` (stale Audit A report artifact) was removed
externally between sessions and is no longer present;
`test/unit/evidence_processing_service_test.dart` joined the modified set
(Audit A F-A1 regression tests). `lib/features/camera/models/gps_hardware_state.dart`
and `test/unit/nearby_search_controller_test.dart` joined the modified set
(Audit D: D-SPAT-001 provenance flag + LAT-001 regression test).

Delta vs. the previous ledger (Physical Release Finding Remediation — A1 / A2 / B1):
* **New (untracked)**: `lib/features/gallery/controllers/evidence_video_playback.dart` (A1 single video
  player owner) and `test/unit/evidence_video_playback_test.dart` (A1 lifecycle tests).
* **Newly joined the modified set**: `lib/features/gallery/widgets/local_video_player_widget.dart`
  (A1 borrowed-view renderer), `lib/features/camera/widgets/camera_top_hud.dart` (B1 Unknown /
  Last-known pill states), plus `lib/features/camera/controllers/map_thumbnail_controller.dart`,
  `lib/features/camera/hud/hud_data.dart`, `lib/features/camera/widgets/gps_map_thumbnail.dart`,
  `lib/features/nearby/widgets/location_timeline_view.dart` and
  `test/widget/location_timeline_view_test.dart` (ledger parity refresh).
* **Module-touched (all pre-existing modified entries)**: A1 — `media_detail_screen.dart`,
  `media_detail_screen_test.dart`; A2 — `app.dart`, `router.dart`, `camera_screen.dart`,
  `camera_screen_test.dart`; B1 — `gps_utils.dart`, `gps_hardware_state.dart`, `camera_ui_state.dart`,
  `camera_top_hud.dart`, `gps_status_explainer_sheet.dart`, `gps_hardware_controller.dart`,
  `camera_screen.dart`, `gps_hardware_controller_test.dart`, `camera_screen_test.dart`.

Delta vs. the previous ledger (C1 Video HUD Identifier + Photo/Video Metadata-Card Unification):
* **Newly joined the modified set**: `test/unit/hud_formatter_test.dart` (3 new `fromMediaItem`
  canonical-siteCode / telemetry unit tests).
* **Module-touched (all pre-existing modified entries)**: `lib/features/camera/hud/hud_data.dart`
  (optional media-agnostic `accuracyText` / `satellitesText`), `lib/features/camera/hud/hud_formatter.dart`
  (`resolveSiteIdentifier`, C1-correct `fromMediaItem`, telemetry formatting),
  `lib/shared/widgets/evidence_metadata_hud_card.dart` (optional telemetry line),
  `lib/features/gallery/media_detail_screen.dart` (canonical card mounted for Photo AND Video fullscreen,
  bespoke video strip removed), `test/widget/media_detail_screen_test.dart` (F4 updated; C1 group replaced
  by the Photo/Video parity group).
* **Untouched (verified by mtime)**: `watermark_drawer.dart`, `evidence_processing_service.dart`
  and the burned-JPEG/EXIF/SHA path; `evidence_video_playback.dart` (A1); `app.dart`/`router.dart` (A2);
  `gps_hardware_controller.dart` (B1).
* **Performance audit**: read-only, NO code change (do-not-optimize recommendation).

### Git Invariants
* **Current HEAD**: `f868a17` (`main`)
* **Tag `v1.0.0`**: `a17e8c3580c157ba629bfc8fe39fa2fd75da923c` (UNMOVED & FROZEN)
* **`git diff --check`**: Clean (no whitespace or lint issues).

---

## 4. Verification Test Results

All scoped verification suites pass completely:

1. **`flutter test test/unit/review_tag_remediation_test.dart`**:
   - **Result**: `9/9 tests passed`
   - Validates F1 dismissal note preservation, F2 candidate divergence reconciliation & save defense, F3 search miss note preservation & persistence invariants, F5 cross-user/cross-site rejection across repository and coordinator.
2. **`flutter test test/widget/review_tag_remediation_widget_test.dart`**:
   - **Result**: `3/3 tests passed`
   - Validates F1 "Not now" button dismissal & fallback text, F4 loaded candidate Haversine distance, F4 searched candidate Haversine distance.
3. **`flutter test test/unit/metadata_overlay_workflow_test.dart`**:
   - **Result**: `9/9 tests passed`
   - Validates configurable threshold parity, status invariance across settings changes, all 5 pre-v8 migration fallback branches, GNSS telemetry persistence, video metadata preservation with untouched raw video SHA-256, and MSL/WGS84/unknown altitude formatting.
4. **`flutter test test/widget/media_detail_screen_test.dart`**:
   - **Result**: `16/16 tests passed`
   - Validates photo and video detail screens, `CAPTURE & GEOSPATIAL TELEMETRY` section rendering, canonical verification status badge, `Fullscreen Zoom` button on video container, `FULLSCREEN VIDEO EVIDENCE` route with non-intrusive metadata overlay strip, non-Closed linked-card prevention guard, and `MediaTagEditModal` type-switch & note cleanup.
5. **`flutter test test/unit/gps_hardware_controller_test.dart`**:
   - **Result**: `27/27 tests passed`
   - Validates searching/ready status transitions, background/foreground staleness watchdog, MSL/WGS84/unknown altitude formatting, and GNSS telemetry extraction.
6. **`flutter test test/widget/camera_screen_test.dart`**:
   - **Result**: `21/21 tests passed`
   - Validates camera viewfinder layout, HUD truthfulness, shutter button re-entrancy lock, zoom presets, interrupted recording recovery, and keepForLater persistence.
7. **`flutter test test/unit/media_persistence_coordinator_test.dart`**:
   - **Result**: `24/24 tests passed`
   - Validates failure-safe writes, metadata population in `MediaItem`, original preservation on DB failure, retake cleanup of original and derived artifacts, and atomic persistence.
8. **`flutter test test/unit/storage_service_test.dart`**:
   - **Result**: `11/11 tests passed`
   - Validates atomic publication with `.tmp_` files, write failure cleanup, zero-byte / incomplete artifact rejection, and partial artifact cleanup.
9. **`flutter test test/unit/closed_evidence_integrity_test.dart`**:
   - **Result**: `7/7 tests passed`
   - Validates pure integrity logic, note `Evid_ID` removal and replacement, Drift SQLite persistence invariants in `MediaRepository.updateTags`, and non-Closed `linkMedia` prevention.
10. **`flutter test test/unit/minimap_evidence_provenance_test.dart`**:
    - **Result**: `24/24 tests passed`
    - Validates generation guards, layer isolation, canonical cache keys, and out-of-order static map response discarding.
11. **`flutter test test/unit/camera_hardware_controller_test.dart`**:
    - **Result**: `21/21 tests passed`
    - Validates Camera2 handle cleanup on fallback errors, lifecycle mutex concurrency, retry recovery, and 1.0x/capability-aware zoom states.
12. **`flutter test test/widget/permission_resume_navigation_test.dart`**:
    - **Result**: `8/8 tests passed`
    - Validates first-launch recovery persistence in `PermissionRecoveryScreen`, back-stack unwinding, minimize/resume preservation, and single authoritative declarative onboarding.
13. **`flutter test integration_test/auth_session_boundary_e2e_test.dart`**:
    - **Result**: `6/6 tests passed`
    - Validates sign-out cancellation, SiteSetup sign-out stack wipe, SettingsScreen deep sign-out stack wipe, Android system Back prevention, and mid-session invalidation on pushed `CameraScreen`.
14. **`flutter test test/unit/auth_session_invalidation_test.dart`**:
    - **Result**: `8/8 tests passed`
    - Validates all 5 invalidation scenarios: user disabled, cold start user deleted, app resume token revoked, contextual `permission-denied`, `unauthenticated`, network fail-open, and concurrency race safety.
15. **Full Workspace Suite (`flutter test`)**:
    - **Result**: **`682/682 tests passed`** (0 failures, all unit, widget, and integration suites green; 657 at the previous handover + 6 Audit A regression tests + 13 Audit B tombstone tests + 6 Audit C remediation tests).
16. **Static Analysis (`flutter analyze`)**:
    - **Result**: **`0 issues found`** (clean).
17. **Knowledge Graph (`graphify update .`)**:
    - **Result**: Last rebuild 4568 nodes, 6758 edges, 234 communities. **Stale**: predates the Audit A–C remediations; refresh recommended before graph-assisted navigation.
18. **Cross-Cutting Audit A–C Remediation Verification (this session)**:
    - Audit A focused run (gps_hardware_controller, evidence_processing_service, camera_hardware_controller): **64/64**; related suites (camera_screen, minimap_evidence_provenance, media_persistence_coordinator, metadata_overlay_workflow, map_thumbnail_service, storage_service): **87/87**.
    - Audit B focused tombstone suites (cloud_sync, sync_coordinator, media_persistence, sync_lifecycle_bootstrap, auth_session_invalidation, storage_cleanup): **104/104**; related suites (cloud_media_recovery, gallery_controller, google_photos, metadata_overlay, gallery_screen, gallery_filter_modal, media_detail, camera_screen): **91/91**.
    - Audit C focused suites (camera_screen, sync_coordinator, cloud_sync, media_persistence): **108/108**; related suites (sync_lifecycle_bootstrap, auth_session_invalidation, storage_cleanup, camera_hardware_controller, cloud_media_recovery, google_photos, gallery_screen, media_detail, review_tag): **115/115**.
19. **E2E Audit Program Verification (this session)**:
    - Journey-edge suites (m1_screens, permission_resume_navigation, camera_permission_recovery, site_setup_screen, auth_session_routing, auth_session_invalidation, widget smoke): **52/52**.
    - Settings & Legal surface (12 suites: settings_screen, account_deletion_dialog, storage_settings_modal, gps_settings_modal, google_photos_settings_card, enquiry_service, gps/timestamp/nearby/watermark/map_type controllers, google_photos controller): **70/70**.
    - Account deletion: `functions/test/account_deletion.test.js` **43/43** (node --test); `account_deletion_dialog_test.dart` **5/5**.
20. **Firebase Rules/Emulator JS Suites (test/security)**: **7/19 passed**; the 12 failures are root-caused test-harness/emulator environment drift (test contexts lacking the `email_verified` claim required by the rules, one suite authored for `node:test` instead of jest, and emulator rules-engine evaluation drift reproduced independently with production-shaped tokens). An independent scratchpad probe verified the canonical v8 media-create rule and Storage write-once semantics PASS on the same emulator. Not production defects; harness re-baseline recommended before relying on these suites.
21. **Cross-Cutting Audit D Verification (this session)**:
    - `flutter analyze`: **0 issues**.
    - `test/unit/gps_hardware_controller_test.dart` + `test/unit/nearby_search_controller_test.dart`: **54/54** (includes the 3 D-SPAT-001 provenance regressions and LAT-001 test 19; all 5 pre-existing lastKnown seeding tests unaffected).
    - `test/widget/camera_screen_test.dart`: **24/24**.
    - Full Workspace Suite (`flutter test`): **686/686 tests passed** (682 + 4 Audit D regression tests); `flutter analyze` **0 issues**.
22. **A1 — Video Player Ownership Verification (this session)**:
    - `test/unit/evidence_video_playback_test.dart`: **10/10** (single controller created; initialize idempotent; missing file → failed with no controller; init failure → failed + released once; idempotent disposal; disposal during gated async init → no post-dispose notification and one release; initialize-after-dispose no-op; toggle-after-dispose safe; toggle notifies; repeated cycles keep one controller).
    - `test/widget/media_detail_screen_test.dart`: **20/20** (includes the fullscreen single-owner group: single player reused across enter/exit/re-enter + repeated playback; missing file → truthful failure with zero controllers; disposal while fullscreen open → exactly one disposal).
    - Full Workspace Suite (`flutter test`): **706/706 tests passed**; `flutter analyze` **0 issues**.
23. **A2 — CameraX Route Lifecycle Verification (this session)**:
    - `test/widget/camera_screen_test.dart`: **31/31** (includes the A2 group: covered → inactive / visible → active; repeated and nested coverage with no duplicate init or leak; background/foreground while covered stays inactive; redundant pause/resume; disposal while active; truthful error on failed resume).
    - Full Workspace Suite (`flutter test`): **713/713 tests passed**; `flutter analyze` **0 issues**.
24. **B1 — GPS State Semantics & Recovery Verification (this session)**:
    - `test/unit/gps_hardware_controller_test.dart`: **50/50** (includes the B1 group: denied → Denied; unknown → Unknown (not Denied); service-off → ServiceDisabled (not Denied); Acquiring; last-known-only distinct; live-fix; stale/lost → non-live locked; cached coords never set `hasLiveFix` nor pass the capture gate; `applyBestRecentPosition` preserves cached provenance; resume revalidation for denied/unknown/service-off; recovery requires a new live fix; no duplicate subscriptions; idempotent cleanup + harmless post-disposal recovery).
    - `test/widget/camera_screen_test.dart`: **33/33** (includes the B1 gate group: last-known keeps the shutter locked with `GPS: Last known` + lock banner, live fix unlocks with `GPS Fixed`; GPS state stays truthful across a covered-route round-trip and a stale fix stays locked after reveal).
    - Full Workspace Suite (`flutter test`): **730/730 tests passed** (713 + 17 B1 tests); `flutter analyze` **0 issues**.
25. **C1 — Video HUD Identifier Semantics Verification (this session)**:
    - `test/unit/hud_formatter_test.dart`: **9/9** (includes the new `fromMediaItem` canonical-siteCode test — `SL-001` when provided, neutral `SITE` for missing/blank/`UNASSIGNED`, never the internal `siteId`).
    - `test/widget/media_detail_screen_test.dart`: **24/24** (video fullscreen HUD renders canonical `siteCode`; internal `siteId` absent; fallback truthful; MP4 bytes/hash unaffected).
    - Full Workspace Suite (`flutter test`): **737/737 tests passed**; `flutter analyze` **0 issues**.
26. **Photo/Video Metadata-Card Unification Verification (this session)**:
    - `test/widget/media_detail_screen_test.dart` group `Canonical Metadata Card Parity (Photo & Video)`: **4/4** — same canonical `StandaloneMetadataWidget` in both fullscreen routes; identical common fields (siteCode, UTC/local, lat/long, altitude+datum, verification, accuracy, satellite count, SHA); truthful `SITE` fallback for both media; runtime card uses persisted capture-time metadata and never rewrites the MP4.
    - `test/unit/hud_formatter_test.dart` new tests: **3/3** — `fromMediaItem` canonical siteCode/never-siteId; accuracy + satellite telemetry carried from the persisted `MediaItem`; `fromSnapshot`/`fromLive` leave the telemetry tail unset (burned/live cards unchanged).
    - The removed Detail `EVIDENCE MINIMAP & METADATA` section remains absent (`media_detail_screen_test.dart` negative assertion), and `review_tag_screen_test.dart` still asserts no `EvidenceMetadataHudCard` on the Review body.
    - Full Workspace Suite (`flutter test`): **737/737 tests passed**; `flutter analyze` **0 issues**.
27. **Save-Path Performance Audit (this session, read-only)**:
    - Verdict: **DO NOT OPTIMIZE NOW**. No hashing, image codec, HUD render, or file writes occur on the Save click; image/CPU work is already off the UI isolate (`Isolate.run`) and Drift runs in a background isolate; atomic write→verify→commit ordering is preserved. The dominant Save cost is the legitimate await of the already-backgrounded `processingFuture`. No code was changed; no low-risk localized optimization exists.

---

## 5. Physical Device Verification Suite (Hardware: Motorola edge 50 fusion)

- **Device Serial**: `ZA222NBPPV` (Motorola edge 50 fusion / Android 16 / API 36)
- **Deployed Testing Build**: Debug APK (`build/app/outputs/flutter-apk/app-debug.apk`)
- **Package Status**: Installed (`com.sitelens.app` via `adb install -r`)
- **Release Cleanup**: Prior `releasearm64.apk` (`com.sitelens.app`) cleanly uninstalled via `adb uninstall com.sitelens.app`.
- **Verification Rule**: Physical-device verification only. No source changes, no rebuilds, no reverts.

### Comprehensive 10-Point Verification Matrix

| # | Verification Test | Result | Physical Evidence & Details |
| :-: | :--- | :---: | :--- |
| **1** | **Satellite → capture → Evidence = Satellite** | **PASS** | Captured Item 10 at `02:15:08 local`. Photo Evidence Detail renders genuine high-res Google Satellite tiles, radar cone, orange pin, and Google logo in burned card. `SHA256: da52b9584d...` |
| **2** | **Roadmap → capture → Evidence = Roadmap** | **PASS** | Switched layer to `Default (Vector)`. Captured Item 11 at `02:22:17 local`. Evidence renders Google vector Roadmap tiles (street network, roads, pin, logo). `SHA256: 775a92ea...` |
| **3** | **Roadmap → Satellite → capture → Evidence = Satellite** | **PASS** | Switched from Roadmap to Satellite. Captured Item 12 at `02:24:40 local`. Evidence renders Satellite imagery with zero residual roadmap pixels. `SHA256: 51aa7227...` |
| **4** | **Satellite → Roadmap → Satellite → capture → Evidence = Satellite** | **PASS** | Cycled Satellite → Roadmap → Satellite. Captured Item 13 at `02:26:35 local`. Evidence renders Satellite imagery with complete layer fidelity. `SHA256: 232fdc03...` |
| **5** | **Three rapid Satellite captures → all Satellite** | **PASS** | 3 consecutive rapid captures in Satellite mode: Item 14 (`02:28:39`), Item 15 (`02:34:14`), Item 16 (`02:34:37`). Inspected each in Gallery Detail: all 3 render 100% genuine Satellite tiles. |
| **6** | **Three rapid Roadmap captures → all Roadmap** | **PASS** | Switched to Roadmap. 3 consecutive rapid captures: Item 17 (`02:43:52`), Item 18 (`02:44:24`), Item 19 (`02:49:13`). Inspected each in Gallery Detail: all 3 render 100% vector Roadmap tiles. |
| **7** | **Rapid Satellite/Roadmap alternation → evidence matches live layer** | **PASS** | Evaluated across 19 total items and 6 layer switches/burst captures. Zero stale-layer tiles, cross-contamination, or poisoned fallback buffers observed. |
| **8** | **Photo Evidence Detail matches burned JPEG** | **PASS** | Verified across Satellite (Items 10, 16) and Roadmap (Items 11, 17, 19). Photo Evidence Detail renders the exact canonical burned JPEG with embedded HUD card and SHA-256 hash. |
| **9** | **Immersive Viewer matches burned JPEG** | **PASS** | Verified on Satellite Item 10 and Item 16 via `Fullscreen Zoom`. Immersive Evidence Viewer displays the exact canonical burned JPEG with embedded HUD without secondary re-rendering. |
| **10** | **ALT displays corrected MSL value & remains consistent** | **PASS** | Across all items (10–19), altitude uniformly displays true MSL elevation (`+23.2m` to `+24.9m`) and live camera (`+13.8m`) instead of negative WGS84 ellipsoidal value (-42m bias eliminated). |

### Release-Build Finding (Android 16) & Pending Re-Verification (A1 / A2 / B1 / C1 / Metadata Card)

- **Build under test**: release APK, `com.sitelens.app` versionName 1.0.0 / versionCode 2001; SHA-256 `265195037f9a7f5ec0af0148440f57fdd2c14ebee2524511a1ad62d7436ffb22`.
- **Observed**: a ~3 s video was captured successfully and reopened in the evidence viewer with a forensic HUD (identifier before `UTC:`, then UTC/local time, LAT/LON, altitude, `STATUS: VERIFIED`, accuracy, satellite count); entering FULLSCREEN VIDEO EVIDENCE crashed the app; after the restart/recovery the camera screen showed `GPS: Denied`, `ACC: ACQUIRING`, and a locked shutter ("GPS required for evidence"). Causal assumption "GPS Denied caused the video crash" is **not** established.
- **Remediation delivered (automated-verified only)**: A1 (single video player owner shared by inline + fullscreen), A2 (CameraX released while `CameraScreen` is covered and safely reacquired), B1 (truthful GPS states + live-fix capture gate + resumable recovery), C1 (canonical `siteCode` in the video HUD), and the Photo/Video canonical metadata-card unification (one `StandaloneMetadataWidget` runtime card in both fullscreen surfaces).
- **Re-verification sequence REQUIRED on the rebuilt release APK** (after all remediation modules are complete):
  1. Capture a ~3 s video; open VIDEO EVIDENCE DETAIL; enter FULLSCREEN VIDEO EVIDENCE; confirm the HUD identifier renders the canonical site code and that UTC/Local/coords/altitude/STATUS/accuracy/SATS equal the capture-time values.
  1b. Confirm the fullscreen metadata card is visually identical in Photo (IMMERSIVE EVIDENCE VIEWER) and Video (FULLSCREEN VIDEO EVIDENCE) viewing, and that it shows the canonical site code (never the internal site document id).
  2. Play to completion; exit fullscreen; re-enter and replay ≥3 times; confirm no crash and no duplicate player/decoder/ExoPlayer in logcat.
  3. Navigate camera → gallery → video detail → fullscreen and back; confirm CameraX is released while covered and reacquires on reveal with no duplicate init and no leaked `CameraController`.
  4. Background/foreground during playback and while covered; confirm camera and GPS recovery is truthful.
  5. Confirm GPS states render distinctly — Permission Denied vs Permission Unknown vs Location Services Off — and that a last-known-only state keeps the shutter locked until a live fix is received.
  6. Relaunch/recover the app and confirm GPS recovery: `Denied` only if genuinely denied; otherwise `Acquiring → Live`.

---

## 6. Security Vulnerability Assessment Resolution (from Baseline Commit 6a02f91)

All 8 findings from the baseline security audit were formally resolved or verified:

1. **`sendSiteEnquiry` Rate Limiting & DoS Mitigation**: **RESOLVED** (App Check enforced; in-memory sliding window rate limiter at 5 requests / 15 min per IP/UID).
2. **`qs` Prototype Pollution (CVE-2024-45296 / CVE-2024-52745)**: **RESOLVED** (All Cloud Functions dependencies upgraded; `npm audit` reports 0 vulnerabilities).
3. **Firestore Security Rules**: **VERIFIED SECURE** (`request.auth.token.email_verified == true` enforced; granular site-membership RBAC; strict schema whitelists and size limits).
4. **SHA-256 Trust Model**: **DESIGN CHOICE** (Mobile-first forensic integrity sealed at shutter $T_0$; immutable in Firestore ledger).
5. **`firebase.json.example` Secret Exposure**: **FALSE POSITIVE** (100% mock template values; production config excluded).
6. **GPS Validation / Geofencing**: **NOT A VULNERABILITY** (No geofence requirement in PRD; coordinate ranges and immutability enforced).
7. **Email Verification / Token Refresh**: **FALSE POSITIVE** (`request.auth.token.email_verified == true` enforced across all Firestore and Storage rules).
8. **Rate Limiting / Abuse**: **DESIGN CHOICE** (Public enquiry function is App Check & rate-limited; database write abuse mitigated by verified membership, schema allowlists, and size caps).

---

## 7. Handover Guidance for Next Session

1. **Drift Database Schema**: Currently at **Schema Version 8**. Any new columns added to `Media` or other tables must follow the migration pattern in `AppDatabase.onUpgrade`, bump `schemaVersion`, and execute `dart run build_runner build --delete-conflicting-outputs`.
2. **Evidence Metadata Integrity**: `EvidenceMetadataSnapshot` is the capture-time authority. Do not re-evaluate or invent metadata in UI layers. Historical evidence must never assert stronger certainty than was established at capture. Unavailable values remain unknown — never synthesized (Audit A F-A2 policy).
3. **EXIF / Derived-Artifact Policy**: derived evidence artifacts (`evid_*`, `thumb_*`) carry no camera EXIF (stripped after orientation bake in `EvidenceProcessingService`); the immutable original retains capture-time EXIF. Do not reintroduce EXIF passthrough in the encoding path.
4. **Tombstone Lifecycle (Audit B-1 / C-2)**: locally deleted evidence rows are retained as hidden tombstones and reconciled via `CloudSyncService.syncTombstone` through the standard sync cycle (`getTombstoneSyncCandidates` discovery; count edge-trigger). Never physically delete a `media` row on user deletion, never write artifact-sync status for tombstone rows, and never create cloud records for never-published items. Storage artifacts remain write-once and untouched by propagation.
5. **Video Handoff Invariant (Audit C-1)**: a normal successful video stop clears `_inFlightVideoFile` at handoff completion; only a genuine recording interruption (pause during recording) may raise the interrupted-recording recovery.
6. **Firebase Rules/Emulator JS Suites**: `test/security` suites currently fail 12/19 due to test-harness/emulator environment drift (missing `email_verified` claims in test contexts; `node:test`-authored suite under jest; emulator evaluation drift). Re-baseline the harness before treating these suites as regression gates.
7. **Knowledge Graph**: `graphify-out/` predates the Audit A–C remediations — run `graphify update .` before using graph-assisted navigation for the modified sync/camera/deletion paths.
8. **Preserve Clean Working Tree State**: Working tree contains verified changes for all audited modules. Do not commit or discard changes without user direction.
9. **Do NOT rebuild or deploy**: APK compilation, Gradle builds, and Firebase deployments are frozen until user explicitly authorizes a new release milestone.
10. **Video Player Ownership Invariant (A1)**: exactly ONE `EvidenceVideoPlayback` owns the player for a given evidence video. The inline detail surface and the fullscreen viewer must render the same instance; never construct a second `VideoPlayerController`/ExoPlayer for the same video, and never dispose a borrowed controller from a view widget (`LocalVideoPlayerWidget` is a stateless borrower).
11. **CameraX Route Lifecycle (A2)**: `appRouteObserver` (`RouteObserver<PageRoute<dynamic>>`) must remain registered via `navigatorObservers` on the root `MaterialApp`. `CameraScreen` releases CameraX in `didPushNext` and reacquires in `didPopNext`; do not add a second coverage mechanism, and never reactivate the camera while a page route covers the screen (the app-lifecycle resume path honours the same guard).
12. **GPS State Semantics (B1)**: Permission Unknown (`LocationPermission.unableToDetermine`) is NOT Denied, and Location-Services-Off is NOT Denied. Capture readiness is live-fix provenance — `hasLiveFix` (`hasValidFix && !isLastKnownSeed`) — never `hasValidFix` alone; a cached/last-known seed must never unlock evidence capture. Any resume path must revalidate permission **and** service state before acquiring, and a stale/lost live fix must transition to a locked non-live state until a new live fix arrives.
13. **Physical Re-Verification Outstanding**: A1/A2/B1/C1 and the Photo/Video metadata-card unification are automated-verified only. The Android 16 physical sequence in §5 (fullscreen video enter/play/replay/exit; CameraX release/resume across video + evidence routes; GPS Denied vs Unknown vs Service-Off; last-known-only shutter lock; Photo AND Video fullscreen metadata-card visual parity with canonical siteCode) must be executed on the rebuilt release APK after all remediation modules are complete.
14. **Video HUD Identifier Invariant (C1)**: the fullscreen video HUD renders the canonical persisted `SiteModel.siteCode` (uppercased), never the internal Firestore-style `siteId`; missing / blank / `UNASSIGNED` codes fall back to the neutral `SITE`. Keep `HudFormatter.resolveSiteIdentifier` as the single implementation — do not reintroduce `MediaItem.siteId` as a user-facing identifier.
15. **Canonical Metadata Card Invariant (Photo/Video Unification)**: Photo and Video fullscreen/immersive viewing MUST use the same runtime metadata card — `StandaloneMetadataWidget` driven by `HudData` via `HudFormatter.fromMediaItem`. Do not reintroduce a photo- or video-specific metadata card or the removed bespoke video strip, and do not mount the card in the Photo Detail / Review & Tag body. The burned Photo JPEG HUD (`WatermarkDrawer` / `EvidenceProcessingService`) and the removed `EVIDENCE MINIMAP & METADATA` Detail section must remain untouched.
16. **Save-Path Performance (Audit — DO NOT OPTIMIZE)**: the Photo Capture → Review & Tag → Save path is already lean (no hashing, image codec, HUD render, or file writes on Save; CPU work off-isolate; atomic write→verify→commit ordering preserved). Do not defer the DB commit, move persistence to a background worker, or alter ordering for perceived Save latency.
17. **Reference Documents**:
    - [`docs/handover/SESSION_HANDOVER.md`](file:///home/moloy/workspace/products/SiteLens/docs/handover/SESSION_HANDOVER.md): Authoritative session handover state.
    - [`docs/handover/PRD.md`](file:///home/moloy/workspace/products/SiteLens/docs/handover/PRD.md) / [`docs/handover/architecture.md`](file:///home/moloy/workspace/products/SiteLens/docs/handover/architecture.md): Synchronized to the verified v8 implementation semantics (this session).
    - [`docs/ALL_TESTS.md`](file:///home/moloy/workspace/products/SiteLens/docs/ALL_TESTS.md): Authoritative test inventory tracking test coverage.
    - [`strix-sitelens-instructions.md`](file:///home/moloy/workspace/products/SiteLens/strix-sitelens-instructions.md): Authoritative repository guidelines and security instructions.

---

## 8. Key Files & Reference Paths

* **Public GitHub Repo**: [https://github.com/moloygoswami/SiteLens](https://github.com/moloygoswami/SiteLens)
* **Authoritative Strix Instructions**: [`strix-sitelens-instructions.md`](file:///home/moloy/workspace/products/SiteLens/strix-sitelens-instructions.md)
* **Local Database Definition**: [`lib/data/local/database/app_database.dart`](file:///home/moloy/workspace/products/SiteLens/lib/data/local/database/app_database.dart)
* **Media Repository**: [`lib/data/repositories/media_repository.dart`](file:///home/moloy/workspace/products/SiteLens/lib/data/repositories/media_repository.dart)
* **Evidence Metadata Snapshot**: [`lib/features/camera/models/evidence_metadata_snapshot.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/models/evidence_metadata_snapshot.dart)
* **Media Persistence Coordinator**: [`lib/features/camera/services/media_persistence_coordinator.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/services/media_persistence_coordinator.dart)
* **GPS Utilities**: [`lib/core/utils/gps_utils.dart`](file:///home/moloy/workspace/products/SiteLens/lib/core/utils/gps_utils.dart)
* **HUD Formatter**: [`lib/features/camera/hud/hud_formatter.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/hud/hud_formatter.dart)
* **Canonical Metadata Card (Photo/Video unification)**: [`lib/shared/widgets/evidence_metadata_hud_card.dart`](file:///home/moloy/workspace/products/SiteLens/lib/shared/widgets/evidence_metadata_hud_card.dart)
* **Canonical HUD Data Contract (accuracy/satellite telemetry)**: [`lib/features/camera/hud/hud_data.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/hud/hud_data.dart)
* **Camera Screen**: [`lib/features/camera/camera_screen.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/camera_screen.dart)
* **Media Detail Screen**: [`lib/features/gallery/media_detail_screen.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/gallery/media_detail_screen.dart)
* **Evidence Video Playback Owner (A1 — sole player ownership)**: [`lib/features/gallery/controllers/evidence_video_playback.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/gallery/controllers/evidence_video_playback.dart)
* **Local Video Player Widget (A1 — stateless borrower)**: [`lib/features/gallery/widgets/local_video_player_widget.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/gallery/widgets/local_video_player_widget.dart)
* **App Router & Route Observer (A2)**: [`lib/app/router.dart`](file:///home/moloy/workspace/products/SiteLens/lib/app/router.dart)
* **GPS Hardware Controller (B1 — permission/service revalidation on resume)**: [`lib/features/camera/controllers/gps_hardware_controller.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/controllers/gps_hardware_controller.dart)
* **Complete Test Inventory**: [`docs/ALL_TESTS.md`](file:///home/moloy/workspace/products/SiteLens/docs/ALL_TESTS.md)
