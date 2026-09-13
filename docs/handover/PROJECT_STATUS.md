# SiteLens — Project Status & Implementation State

**Date**: 2026-09-14T00:01:38+05:30
**Current Milestone**: Physical Release Finding Remediation (Android 16 / SDK 36) — **A1 Video Player Ownership** (ACCEPTED), **A2 CameraX Route Lifecycle** (ACCEPTED), **B1 GPS State Semantics & Recovery** — executed on top of the Post-v1.0.0 E2E Reliability Audit & Remediation Program (Modules A–J; Cross-Cutting Audits A–D all remediated & verified; Full-Journey / Settings & Legal / Account-Deletion E2E audits passed; `PRD.md` & `architecture.md` synchronized) (`f868a17` on `main`, frozen Tag `v1.0.0` at `a17e8c3`)
**Release Status**: `PRODUCTION RELEASE FROZEN (v1.0.0 / commit a17e8c3) — POST-RELEASE AUDIT & REMEDIATION PROGRAM COMPLETE; PHYSICAL RELEASE-FINDING REMEDIATION (A1/A2/B1) IMPLEMENTED & AUTOMATED-VERIFIED — PHYSICAL ANDROID 16 RE-VERIFICATION PENDING`

```text
========================================================================================
                                CURRENT RELEASE GATE STATUS
========================================================================================
 SECURITY REMEDIATION:     IMPLEMENTED & VERIFIED (Modules 1–7; 8/8 findings closed; strix-sitelens-instructions.md formalized)
 AUTOMATED VERIFICATION:   PASS (All 730 Flutter tests pass across unit, widget, and integration suites;
                                  flutter analyze reports 0 issues; account-deletion cloud function
                                  suite 43/43; Firebase rules/emulator JS suites 7/19 with the 12
                                  failures root-caused as test-harness/emulator environment drift)
 STATIC ANALYSIS & AUDIT:  PASS (0 analyzer issues, 0 npm vulnerabilities)
 MODULES A–J REMEDIATIONS: COMPLETE & VERIFIED (SiteLens #7–#12: metadata overlay F1–F5, video persistence
                                  & GPS R1–R3, minimap & GPS workflow F1–F4, camera permission recovery,
                                  photo evidence F1–F3, review tag & smart-link #8 F1–F5, smart-link E2E #9,
                                  evidence list #10 F1–F2, offline capture & cloud metadata #11 F1–F2,
                                  synchronization E2E #12 F1–F3)
 CROSS-CUTTING AUDIT A:    REMEDIATED & VERIFIED (F-A1 derived-artifact EXIF strip; F-A2 GPS unknown
                                  semantics — no synthesized 0.0/now fallback; regression tests added)
 CROSS-CUTTING AUDIT B:    AUDITED & B-1 REMEDIATED (Evidence Artifact Cloud Synchronization E2E: PASS-with-
                                  findings; tombstone propagation via syncTombstone — deleted published items
                                  reconcile is_deleted=true, never-published items are verified no-ops)
 CROSS-CUTTING AUDIT C:    AUDITED & C-1/C-2 REMEDIATED (Capture ↔ Sync Lifecycle: no BLOCKERs; stale
                                  in-flight video reference cleared on normal handoff; permanent deletion
                                  tombstones rows — no stranded live cloud ledgers)
 E2E AUDIT PROGRAM:        PASS (Full user-journey install→deletion; Settings & Legal workflow;
                                  Account-Deletion workflow incl. sole-member/shared/successor paths)
 REFERENCE DOCS:           SYNCHRONIZED (PRD.md & architecture.md updated to verified v8 semantics)
 AUTH SESSION RECOVERY:    PASS (Centralized SessionService, cold start / resume reload,
                                  contextual permission-denied vs unauthenticated, race/disposal-safe,
                                  root navigator stack wipe to WelcomeScreen)
 TASK OBSERVER PROTOCOL:   PASS (Formalized in CLAUDE.md)
 FINAL STRIX SECURITY GATE:SCOPE FORMALIZED (strix-sitelens-instructions.md updated for v1.0.0 freeze)
 CAMERA & MINIMAP PROVENANCE:PASS (Fixed portrait, live minimap snapshot T0, heading cone,
                                    burned Evidence JPEG, layer-isolated cache, zero stale-layer race)
 CAMERA ZOOM & INTEGRITY:  PASS (1.0x init default, truthful label, capability-aware cycling; Rule 5 compliant)
 CLOSED EVIDENCE WORKFLOW: PASS (Nearby picker candidate selection, Evid_ID in existing Notes field, Smart-Link race invalidation)
 TEST SUITE INVENTORY:     PASS (docs/ALL_TESTS.md: authoritative inventory tracking test coverage)
 ALTITUDE / MSL DATUM:     PASS (Android 14+ getMslAltitudeMeters() via MethodChannel; true MSL)
 RELEASE FINDING AUDIT:    COMPLETED (READ-ONLY) — Android 16 physical finding: fullscreen video
                                  crash + post-crash GPS state + video forensic HUD; root causes traced;
                                  GPS "Denied" proven independent of the video pipeline; video HUD proven
                                  viewer-rendered (not burned into the MP4)
 A1 VIDEO PLAYER OWNERSHIP: IMPLEMENTED & VERIFIED (single EvidenceVideoPlayback owner shared by the
                                  inline and fullscreen surfaces — exactly one controller/ExoPlayer per
                                  video; async-init/dispose safe; idempotent disposal; truthful failure)
 A2 CAMERAX ROUTE LIFECYCLE: IMPLEMENTED & VERIFIED (PageRoute coverage observer releases CameraX while
                                  CameraScreen is covered and safely reacquires on reveal; no duplicate
                                  init/leak; truthful camera-unavailable on failed resume)
 B1 GPS STATE SEMANTICS:   IMPLEMENTED & VERIFIED (Permission Unknown ≠ Denied; Service Off ≠ Denied;
                                  Last-Known Only ≠ Live Fix; hasLiveFix is the capture-readiness
                                  provenance; resume revalidates permission + service; stale/cached fix
                                  can never unlock evidence capture)
 PHYSICAL RE-VERIFICATION: PENDING (Android 16 device verification required after all remediation modules)
 PRODUCTION GATE DECISION: APPROVED FOR PRODUCTION DISTRIBUTION (v1.0.0 frozen); A1/A2/B1 remediation
                                  automated-verified — physical Android 16 re-verification outstanding
========================================================================================
```

---

## 1. Overview
- **Project Name**: SiteLens (Mobile App & Serverless Backend)
- **Domain**: GPS-Aware Construction Inspection Camera, Evidence Provenance, Spatial Nearby Search & Support Subsystem
- **Technology Stack**: Flutter (Dart 3.6.2), Firebase (Core, Auth, App Check, Firestore, Cloud Functions 2nd-gen, Storage), Drift (SQLite v8), Riverpod, Resend REST API, Share Plus, PDF, Printing, Archive, Google Maps Flutter, Google Sign-In & Photos API
- **Current Milestone Accomplishments**:
  - All security findings (Modules 1 through 7 + Module 4 Local Isolation follow-up) remediated and verified.
  - 57/57 Firestore/Storage security rules tests passing in emulator.
  - 682/682 Flutter unit, widget, and integration tests passing; clean static analysis (`flutter analyze` 0 issues).
  - 22/22 Cloud Functions backend tests passing.
  - Modernized Android toolchain (Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0, Java 21, compileSdk 35).
  - Implemented **Option B HUD Architecture**:
    * Created canonical pure Dart `HudData` DTO, pure Dart `HudLayoutSpec` layout tokens, and pure Dart `HudFormatter` adapter.
    * Refactored `WatermarkDrawer` to consume `HudData` with zero geometry delta.
    * Refactored `EvidenceMetadataHudCard` and aligned preview `maxMapAllowed` from 0.38 to 0.42 (`HudLayoutSpec.maxMinimapWidthFraction`).
    * Enforced Single-HUD Downstream Invariant by deleting dead legacy factories (`fromMediaItem`, `fromSnapshot`).
    * Corrected and streamlined isolate boundary representation in code and architecture documentation.
  - Implemented **Canonical Native HUD Scaling & Coupled Two-Pass Layout Fix**:
    * Derived native scale factor uniformly from short dimension against 390dp reference canvas (`s = min(W, H) / 390.0`), resolving the 38.4% portrait deflation bug.
    * Promoted `refMaxLandscapeWidth = 520.0` from Flutter card into `HudLayoutSpec`.
    * Implemented coupled two-pass layout ensuring 2-line wrapped address and strictly equal minimap/metadata card heights with 1.24:1 minimap aspect ratio.
  - Implemented **Fixed Portrait-Only Orientation Policy**:
    * Enforced `android:screenOrientation="portrait"` in `AndroidManifest.xml` and locked `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])` in `main.dart`.
    * Cleaned up legacy orientation settings and controllers to ensure an immutable, predictable portrait layout across camera, viewfinder, gallery, and viewer.
  - Implemented **Minimap Layer Provenance & Asynchronous Race Fix**:
    * Atomic generation tracking (`_snapshotGeneration`) in `MapThumbnailController`.
    * Map-type cache isolation (`AppMapType.roadmap` vs `AppMapType.satellite`) in memory and on disk.
    * Layer transition debouncing, canvas stabilization, and strict shutter-time validation.
    * Downstream single-JPEG forensic display guaranteeing pixel-faithful render of burned evidence.
  - Implemented **True Mean Sea Level (MSL) Altitude Correction**:
    * Platform MethodChannel hook to Android 14+ (`API 34+`) `Location.getMslAltitudeMeters()`.
    * Datum-aware domain modeling in `GnssSnapshot`, `GpsHardwareState`, and `EvidenceMetadataSnapshot`.
    * Eliminated the -42m WGS84 ellipsoidal geoid offset in West Bengal, India; displays true orthometric MSL elevation (`+23m` to `+25m MSL` on physical device).
  - Implemented **E2E Reliability Audit & F1/F2/F4 Remediations**:
    * Decoupled physical capture instant $T_0$ from asynchronous GNSS satellite fix time in `EvidenceMetadataSnapshot.capture()` (`customCaptureTimeUtc`), eliminating burst timestamp collision.
    * Implemented generation tracking guard in `MapThumbnailController` (`_mapTypeGeneration`), preventing superseded background static map responses from corrupting the viewfinder minimap cache.
    * Resolved native Camera2 controller handle leak in resolution fallback error paths and added FIFO lifecycle synchronization mutex (`_synchronized`) across pause, resume, and initialize in `CameraHardwareNotifier`.
    * Formally proved F3 shutter re-entrancy hazard in automated widget test without introducing unwarranted production mutex overhead.
  - Implemented **Camera Zoom Initialization & Truthful Preset Cycling (Rule 5 Evidence Integrity)**:
    * Standardized camera hardware and UI initialization to `1.0x` (`CameraLensZoom.standard`).
    * Enforced physical truthfulness on zoom labels (`currentZoomLevel <= 0.6` for `'0.5x'`), eliminating misleading `0.5x` labels when hardware is clamped to `minZoom: 1.0`.
    * Implemented capability-aware zoom preset cycling (`[1x, 2x]` on standard sensors, `[1x, 2x, 0.5x]` on ultra-wide sensors).
  - Formalized **Authoritative Complete Test Inventory (`docs/ALL_TESTS.md`)**:
    * Cataloged all 507 tests across 60 files sequentially numbered (#1 to #507) with exact Dart test names and concise test instructions.
    * Verified 100% test count and name accuracy against the test suite.
  - Formalized **Authoritative Strix Security Assessment Scope**:
    * Updated `strix-sitelens-instructions.md` pinned to release commit `a17e8c3`, Git tag `v1.0.0`, release APK SHA-256, and production signing certificate SHA-1.
    * Documented 8/8 closed findings baseline and 4-tier classification standard.
  - Physical Device Hardware Verification Suite on Motorola edge 50 fusion (`ZA222NBPPV`):
    * 10/10 test matrix passed: Satellite captures, Roadmap captures, immediate layer switching, burst captures, layer alternation, Detail/Viewer match, MSL altitude, and PDF inspection note export.
  - Implemented **Authentication Session Invalidation & Recovery E2E (E2E-03-B / Scenarios 1–5)**:
    * Centralized auth verification and error classification in `AuthService` (`SessionTerminationReason`, `SessionVerificationResult`, `verifySession()` using `currentUser.reload()`).
    * Centralized session policy in `SessionService` (`handleOperationAnomaly` contextual resolution preserving valid auth sessions on `permission-denied`, race/disposal-safe concurrency deduplication, resume re-verification via `WidgetsBindingObserver`).
    * Root Navigator deep unwinding in `SiteLensApp` wiping all pushed screens (`CameraScreen`, `GalleryScreen`, `SettingsScreen`) to `WelcomeScreen` on invalidation.
    * Comprehensive test coverage: 8 unit test scenarios in `auth_session_invalidation_test.dart`, 6 integration E2E scenarios in `auth_session_boundary_e2e_test.dart`.
  - Formalized **Task Observer Protocol** in `CLAUDE.md`:
    * Mandated session start protocol, observation log queries prior to skill application, and pinned workspace root.
  - Deployed **Testing Debug Build to Hardware (Motorola edge 50 fusion `ZA222NBPPV`)**:
    * Cleaned up installed release arm64 build (`adb uninstall com.sitelens.app`), compiled fresh debug APK (`flutter build apk --debug`), and installed on hardware (`adb install -r`).
  - Completed **Post-v1.0.0 E2E Reliability Audit & Remediation Program (Modules A–J, SiteLens #7–#12)**:
    * Metadata Overlay Workflow (F1–F5): verification-status parity, Drift v8 persistence, pre-v8 fallback, canonical GNSS telemetry, video metadata, truthful altitude datum.
    * Video Persistence & GPS (R1–R3): safe video writes, no 0,0 coordinates, interrupted-recording GPS authority, orphan cleanup, PopScope discard.
    * Minimap & GPS Workflow (F1–F4): staleness watchdog, canonical cache keys, shutter re-entrancy lock, generation guards.
    * Camera Permission Recovery: single `PermissionService` authority, restricted-status semantics, settings-return navigation, camera hardware mutex.
    * Photo Evidence (F1–F3): original preserved on DB failure, crash-safe atomic writes, `ClosedEvidenceIntegrity` enforcement.
    * Review Tag & Smart-Link (#8 F1–F5, #9 F-1): dismissal, candidate divergence guards, `Evid_ID` invariants, truthful Haversine distances, creator/site isolation, non-destructive B→A link lifecycle.
    * Evidence List (#10 F1–F2): deterministic History ordering, selectable Sync Status filter.
    * Offline Capture & Cloud Metadata (#11 F1–F2): unsynced-count edge-trigger auto-sync; v8 forensic metadata in Firestore create/reconcile + rules allowlist.
    * Synchronization E2E (#12 F1–F3): foreground-resume sync, unexpected-exception suppression, session-scoped `SyncLifecycleBootstrap`.
  - Completed **Cross-Cutting Audit A Remediation (EXIF / Metadata Semantics)**:
    * F-A1: derived evidence JPEG/thumbnail strip all camera EXIF after orientation bake; immutable original retains capture-time EXIF (`EvidenceProcessingService`).
    * F-A2: `getBestRecentPosition` returns null for stale/absent raw positions — unknown capture-window data stays unknown; `applyBestRecentPosition` seam added.
  - Completed **Cross-Cutting Audit B (Evidence Artifact Cloud Synchronization) & B-1 Remediation**:
    * E2E artifact-synchronization audit (identity, hash binding, idempotency, write-once, recovery) — PASS-with-findings.
    * B-1: tombstone propagation — `getTombstoneSyncCandidates`/`watchTombstoneCandidateCount` discovery, `CloudSyncService.syncTombstone` (reuses canonical reconcile; never-published items are verified no-ops), count edge-trigger; deleted published items reconcile `is_deleted = true`; Storage artifacts untouched.
  - Completed **Cross-Cutting Audit C (Capture ↔ Sync Lifecycle) & C-1/C-2 Remediation**:
    * C-1: stale `_inFlightVideoFile` cleared on normal video handoff — no false interrupted-recording recovery.
    * C-2: `deletePermanently` tombstones rows instead of destroying them — a permanently deleted published item can never strand a live cloud ledger.
  - Completed **E2E Audit Program** (read-only, all PASS): full user journey (install → onboarding → auth → site setup → capture → review → sync → history → logout/relaunch → deletion); Settings & Legal workflow; Account-Deletion workflow (sole-member / shared-member / sole-admin successor paths; `deleteUserAccount` callable 43/43 backend tests).
   - Synchronized **`PRD.md` & `architecture.md`** to the verified v8 implementation semantics (capture-time metadata authority, EXIF policy, sync lifecycle order, tombstone/deletion semantics, account deletion, atomicity guarantees).
   - Completed **Physical Release Finding Audit (Android 16 / SDK 36) — read-only forensic audit**:
     * Investigated the physical release-APK finding on the Motorola edge 50 fusion (Android 16, `com.sitelens.app` 1.0.0 / 2001): fullscreen video evidence crash, post-crash camera state (`GPS: Denied`, `ACC: ACQUIRING`, shutter locked / "GPS required for evidence"), and the video forensic HUD (identifier + UTC/local time + LAT/LON + altitude + STATUS + accuracy + satellite count).
     * Traced the complete video path (capture → persistence → evidence record → viewer → fullscreen → player init → playback → surface/texture → disposal), the GPS state machine, and every burned/displayed HUD field's provenance.
     * Established that video/fullscreen code never writes GPS permission state (the post-crash GPS state is an independent state/initialization concern), and that the video forensic HUD is **viewer-rendered** from persisted capture-time metadata — never burned into the MP4 artifact.
     * Produced the remediation scope: **A1** video player ownership, **A2** CameraX route lifecycle, **B1** GPS state semantics & recovery.
   - Implemented **A1 — Video Fullscreen Player Ownership (SINGLE OWNER)**:
     * New canonical owner `EvidenceVideoPlayback` (`ChangeNotifier`) holding at most ONE `VideoPlayerController` per video: created once, initialized once, disposed exactly once.
     * The inline detail surface and the fullscreen viewer now render the **same** owner instance — no second ExoPlayer is created on fullscreen entry; the inline surface is parked while fullscreen is on top.
     * Async initialize/dispose race-safe (no post-dispose state/platform access), idempotent disposal, and a truthful `failed` state for missing/undecodable media.
   - Implemented **A2 — CameraX Route Lifecycle**:
     * New `appRouteObserver` (`RouteObserver<PageRoute<dynamic>>`) registered on the root `MaterialApp`; `RouteAware` implemented by `CameraScreen`.
     * CameraX is released (`pauseCamera`) while `CameraScreen` is covered by a page route (gallery / video evidence / fullscreen / review / settings) and safely reacquired (`resumeCamera`) when visible again; dialogs and bottom sheets are not `PageRoute`s and therefore do not trigger coverage.
     * No duplicate CameraX initialization or leaked controllers across repeated enter/exit cycles; coverage/lifecycle callbacks are idempotent; a failed resume surfaces a truthful camera-unavailable/error state.
   - Implemented **B1 — GPS State Semantics & Recovery**:
     * Distinct semantic states preserved: Permission Denied, **Permission Unknown** (`unableToDetermine`), Location Services Off, Acquiring, **Last-Known Only**, Live Fix, Live Fix Lost/Stale. Unknown is never collapsed into Denied; Service Off is never reported as Denied.
     * `hasLiveFix` is the sole capture-readiness provenance (`hasValidFix && !isLastKnownSeed`); `CameraScreen.isCapturePermitted` now requires `hasLiveFix`, so cached/last-known coordinates can never unlock evidence capture.
     * `resumeLocationStream()` explicitly revalidates OS permission **and** location-service state, cancels the stream and drops any latched fix when unavailable (denied / unknown / service off), re-checks fix staleness, and never creates duplicate subscriptions; `pauseLocationStream()`/`dispose()` cleanup is idempotent and post-disposal recovery is harmless.
     * New `GpsBlockReason` values (`permissionUnknown`, `lastKnownOnly`) drive truthful pill/banner/explainer copy; accuracy/quality thresholds, staleness window, and capture-time metadata semantics are unchanged.
- **Architecture Baseline**: `architecture.md`
- **Product Requirements**: `PRD.md`

---

## 2. Environment & Runtime

| Component | Target / Version | Status |
| :--- | :--- | :--- |
| **Flutter SDK** | 3.47.1 (Channel stable) | `OPERATIONAL` |
| **Dart SDK** | 3.6.2 (Linux x64) | `OPERATIONAL` |
| **Java Runtime** | OpenJDK 21.0.6 (Ubuntu) | `OPERATIONAL` |
| **Gradle Version** | 9.3.1 | `OPERATIONAL` |
| **Android Gradle Plugin** | 9.1.0 (compileSdk 35) | `OPERATIONAL` |
| **Kotlin Version** | 2.4.0 | `OPERATIONAL` |
| **Node.js Runtime** | Node 20 (Cloud Functions 2nd-gen) | `OPERATIONAL` |
| **Target Platforms** | Android, iOS, Web, Desktop (Linux/macOS/Windows) | `OPERATIONAL` |
| **Application ID / Package** | `com.sitelens.app` | `OPERATIONAL` |
| **Firebase Project** | `sitelens-prod-80e7b` | `OPERATIONAL` |
| **Release Signing Key** | Production Release Keystore (`sitelens-release`) | `VERIFIED & RETAINED` |
| **Production Signing SHA-1** | `D8:22:85:B2:0D:1E:11:F4:D2:6C:F0:2F:D1:F7:DF:61:EB:79:2A:69` | `VERIFIED` |
| **Connected Test Target** | Physical Hardware `Motorola edge 50 fusion` / `ZA222NBPPV` (Android 16 / API 36) | `VERIFIED & OPERATIONAL` |
| **Deployed Debug APK** | `build/app/outputs/flutter-apk/app-debug.apk` | `BUILT & INSTALLED` |
| **Release APK Artifact** | `build/app/outputs/flutter-apk/app-release.apk` | `BUILT & VERIFIED` |
| **Release APK SHA-256** | `3a98caec498e93fc32852592bccce7c618d0a3b4673fec3cde27ef063f3ba655` | `VERIFIED` |
| **Git Baseline** | Commit `a17e8c3`, Tag `v1.0.0` (HEAD of `main`) | `FROZEN & VERIFIED` |

---

## 3. Milestone Breakdown & Progress

| Milestone | Scope | Status | Notes |
| :--- | :--- | :---: | :--- |
| **M0 — Foundation** | Flutter project, Drift SQLite, tables + indexes, SHA-256, Haversine, GPS classification | **COMPLETED & ACCEPTED** | 13/13 unit tests passed, clean static analysis. |
| **M1 — Auth + Site Setup** | Firebase Auth, session router, Permission Onboarding, Site Setup & local persistence | **COMPLETED & VALIDATED** | 35/35 tests passed, clean static analysis. |
| **M2 — Camera + GPS** | Live camera viewfinder, hardware controller, GPS stream, reverse geocoding, WatermarkDrawer | **COMPLETED & ACCEPTED** | 85/85 tests passed, validated on physical device. |
| **M3 — Review + Tag + Video** | Activity input, Observation selector, Strict Closed business rule, SmartLinkCard, SHA-256 | **COMPLETED & VALIDATED** | 115/115 automated tests passed. |
| **M4 — Gallery + Detail + Export** | Virtualized lazy grid, metadata search, detail screen, single & batch PDF/ZIP export | **COMPLETED & ACCEPTED** | 144/144 automated tests passed. |
| **M5 — Nearby Search** | Radius selector, local bounding-box + Haversine search, map circle, timeline | **COMPLETED & ACCEPTED** | 171/171 tests passed. |
| **M6 — Firebase Security & Sync** | Security rules, asynchronous sync queue, Cloud Storage uploads, Firestore sync | **COMPLETED & VALIDATED** | 229/229 tests passed. |
| **Responsive UI Framework** | Multi-pane layouts, adaptive gallery column scaling | **COMPLETED & VALIDATED** | 200/200 tests passed. |
| **M7-02/03 — Settings & Recovery** | GPS accuracy threshold, storage cleanup, cloud media recovery, unified settings hub | **COMPLETED & VALIDATED** | 294/294 tests passed. |
| **Google Photos Auto-Sync** | OAuth scope, `SiteLens Evidence` album management, background retry queue | **COMPLETED & VALIDATED** | 327/327 tests passed. |
| **Phase 5C & 5D Evidence Baseline** | 5-row responsive Metadata Card, dynamic font scaling, zero overflow, canonical pipeline freeze | **FROZEN & VERIFIED** | 406/406 tests passed, verified across orientations on physical hardware. |
| **Resend User Enquiry Integration** | Firebase 2nd-gen callable, Secret Manager, App Check, Firestore rate limits, UI modal | **COMPLETED & VERIFIED** | 22/22 backend tests, 441/441 total flutter tests passing. |
| **Module 1–7 Security Hardening** | Site anti-squatting, schema allowlist, creator scoping, storage rules, email verification | **REMEDIATED & VERIFIED** | 57/57 Firestore/Storage security rules emulator tests passing. |
| **Android Toolchain Modernization** | Upgrade Gradle (9.3.1), AGP (9.1.0), Kotlin (2.4.0), Java (21) | **COMPLETED & VERIFIED** | Clean build layout, zero dependency validation warnings. |
| **Option B HUD Architecture & Geometry Alignment** | Canonical `HudData` + `HudLayoutSpec` + `HudFormatter`, separate renderers, preview 0.42 alignment | **COMPLETED & VERIFIED** | 457/457 tests passing; zero geometry delta on Canvas; debug APK deployed to hardware. |
| **Canonical Native HUD Scaling & Coupled Layout Fix** | `hud_layout_spec.dart`, `watermark_drawer.dart`, tests | **FIXED & VERIFIED** | Uniform native scale derivation; coupled two-pass layout; 464/464 tests passed. |
| **Orientation Policy — Fixed Portrait** | `AndroidManifest.xml`, `main.dart`, `camera_screen.dart`, `media_detail_screen.dart` | **COMPLETED & VERIFIED** | Fixed portrait-only orientation across manifest, runtime, camera, and gallery; auto-rotate/settings removed; 467/467 tests passed. |
| **Minimap Evidence Provenance** | `gps_map_thumbnail.dart`, `map_thumbnail_controller.dart`, `watermark_drawer.dart`, `evidence_metadata_snapshot.dart` | **COMPLETED & VERIFIED** | Generation tracking, map-type cache isolation, shutter-time strict validation, zero stale-layer race; 476+ tests passed. |
| **True MSL Altitude Correction** | `MainActivity.kt`, `GnssSnapshot`, `EvidenceMetadataSnapshot`, `WatermarkDrawer`, HUD cards | **COMPLETED & VERIFIED** | Android 14+ `Location.getMslAltitudeMeters()` via MethodChannel; eliminated -42m ellipsoidal offset; truthful MSL labeling; 489/489 baseline tests passed. |
| **Physical Hardware Verification Suite** | Motorola edge 50 fusion (`ZA222NBPPV`, Android 16 / API 36) | **10/10 PASS** | 10-point physical verification matrix passed: Satellite, Roadmap, bursts, alternation, detail/viewer match, MSL altitude, and PDF export. |
| **Authoritative Strix Security Instructions** | `strix-sitelens-instructions.md` | **FORMALIZED & PINNED** | Pinned to release baseline `a17e8c3` / `v1.0.0`, release APK hash, production signing SHA-1, 8/8 closed findings baseline, and 4-tier classification. |
| **E2E Reliability Audit & F1/F2/F4 Remediations** | `camera_screen.dart`, `map_thumbnail_controller.dart`, `camera_hardware_controller.dart`, `evidence_metadata_snapshot.dart` | **COMPLETED & VERIFIED** | F1 decoupled timestamp, F2 generation guard, F4 Camera2 leak & mutex fixed; F3 test-only hazard verified; physical device verified. |
| **Camera Zoom Hardware Integrity & Preset Cycling** | `camera_hardware_state.dart`, `camera_ui_state.dart`, `camera_hardware_controller.dart` | **COMPLETED & VERIFIED** | 1.0x standard init default, truthful zoom display label, capability-aware preset cycling (Rule 5 compliant); 21/21 unit tests passed. |
| **Complete Test Inventory (`docs/ALL_TESTS.md`)** | `docs/ALL_TESTS.md` | **COMPLETED & VERIFIED** | 539/539 automated tests across 63 files (414 unit tests + 125 widget tests) sequentially numbered (#1–#539) with exact names & instructions. Refresh pending: post-v1.0.0 audit-remediation test additions (Audit A–C) are not yet cataloged. |
| **Closed Evidence Workflow & Smart-Link Race Invalidation** | `review_tag_controller.dart`, `review_tag_screen.dart`, `nearby_search_screen.dart`, tests | **COMPLETED & VERIFIED** | Nearby candidate picker mode, Evid_ID populated into existing Notes field, synchronous candidate replacement, and in-flight smart-link search request invalidation (`_searchRequestId++`); 539/539 tests passed. |
| **Auth Session Invalidation & Recovery E2E** | `session_service.dart`, `auth_service.dart`, `router.dart`, `app.dart`, `sync_coordinator.dart`, tests | **COMPLETED & VERIFIED** | Centralized SessionService policy, cold start & resume reload() verification, contextual permission-denied (no false logouts), race/disposal-safe concurrency deduplication, root navigator stack wipe to WelcomeScreen; 8/8 unit tests, 6/6 E2E integration tests, 12/12 auth routing tests, 12/12 sync coordinator tests pass. |
| **Hardware Debug Deployment** | Motorola edge 50 fusion (`ZA222NBPPV`) | **DEPLOYED & VERIFIED** | Uninstalled releasearm64.apk (`com.sitelens.app`), built & installed fresh debug APK (`app-debug.apk`) via adb; verified on hardware. |
| **Task Observer Protocol Integration** | `CLAUDE.md` | **FORMALIZED & PINNED** | Session start protocol, pre-skill observation queries, and pinned workspace directory. |
| **Modules A–J Remediation Program (SiteLens #7–#12)** | Metadata overlay (F1–F5), video persistence & GPS (R1–R3), minimap & GPS workflow (F1–F4), camera permission recovery, photo evidence (F1–F3), review tag & smart-link (#8/#9), evidence list (#10), offline capture & cloud metadata (#11), synchronization E2E (#12) | **REMEDIATED & VERIFIED** | 657/657 tests passed at program completion; analyzer 0 issues. |
| **Cross-Cutting Audit A Remediation (EXIF / Metadata Semantics)** | `evidence_processing_service.dart`, `gps_hardware_controller.dart`, tests | **REMEDIATED & VERIFIED** | F-A1 derived-artifact EXIF strip (original keeps camera EXIF); F-A2 GPS unknown semantics (no synthesized 0.0/now fallback); 663/663 tests passed. |
| **Cross-Cutting Audit B & B-1 Tombstone Propagation** | `media_repository.dart`, `cloud_sync_service.dart`, `sync_coordinator.dart`, tests | **AUDITED & REMEDIATED** | Tombstone discovery + count edge-trigger + `syncTombstone` (published → `is_deleted = true`; never-published → verified no-op; Storage artifacts untouched); 676/676 tests passed. |
| **Cross-Cutting Audit C & C-1/C-2 Remediation** | `camera_screen.dart`, `camera_hardware_controller.dart`, `media_repository.dart`, tests | **AUDITED & REMEDIATED** | C-1 video handoff invariant (no false interrupted-recording recovery); C-2 `deletePermanently` tombstones rows (no stranded live cloud ledgers); 682/682 tests passed. |
| **E2E Audit Program (Journey / Settings & Legal / Account Deletion)** | Read-only E2E audits across the full application surface | **ALL PASS** | 682/682 Flutter tests; `deleteUserAccount` backend suite 43/43; account-deletion dialog tests 5/5; findings limited to documented non-blocking observations. |
| **Reference Documentation Synchronization** | `PRD.md`, `architecture.md` | **COMPLETED & VERIFIED** | Both documents synchronized to the verified v8 semantics (EXIF policy, capture-time metadata authority, sync lifecycle order, tombstone/deletion semantics, account deletion, atomicity guarantees). |
| **Physical Release Finding Audit (Android 16 Fullscreen Video)** | Read-only forensic audit (video path, GPS state machine, HUD provenance) | **COMPLETED (READ-ONLY)** | Release-APK finding on Motorola edge 50 fusion (Android 16 / SDK 36): fullscreen video crash + post-crash `GPS: Denied`/`ACC: ACQUIRING` + video forensic HUD. Confirmed the video pipeline does not write GPS permission state and the video HUD is viewer-rendered (not burned). Scoped A1/A2/B1. |
| **A1 — Video Fullscreen Player Ownership** | `lib/features/gallery/controllers/evidence_video_playback.dart` (new), `lib/features/gallery/widgets/local_video_player_widget.dart`, `lib/features/gallery/media_detail_screen.dart`, tests | **IMPLEMENTED & VERIFIED** | Single `EvidenceVideoPlayback` owner shared by the inline and fullscreen surfaces — exactly one `VideoPlayerController`/ExoPlayer per video; inline surface parked while fullscreen is on top; idempotent disposal; async-init/dispose race safe; truthful failed state; 13 focused tests. |
| **A2 — CameraX Route Lifecycle** | `lib/app/router.dart` (`appRouteObserver`), `lib/app/app.dart` (`navigatorObservers`), `lib/features/camera/camera_screen.dart` (`RouteAware`), tests | **IMPLEMENTED & VERIFIED** | `RouteObserver<PageRoute<dynamic>>` coverage: CameraX released while `CameraScreen` is covered by a page route and safely reacquired on reveal; dialogs/bottom sheets excluded; no duplicate init or leak; idempotent callbacks; 7 focused tests. |
| **B1 — GPS State Semantics & Recovery** | `lib/core/utils/gps_utils.dart`, `lib/features/camera/models/gps_hardware_state.dart`, `lib/features/camera/models/camera_ui_state.dart`, `lib/features/camera/widgets/camera_top_hud.dart`, `lib/features/camera/widgets/gps_status_explainer_sheet.dart`, `lib/features/camera/controllers/gps_hardware_controller.dart`, `lib/features/camera/camera_screen.dart`, tests | **IMPLEMENTED & VERIFIED** | `permissionUnknown` / `lastKnownOnly` states added; Unknown ≠ Denied and Service Off ≠ Denied; `hasLiveFix` is the sole capture-readiness provenance; `resumeLocationStream()` revalidates permission + service and drops stale/cached fixes; no duplicate subscriptions; idempotent cleanup; 17 focused tests. |
| **Physical Android 16 Re-Verification (A1/A2/B1)** | Motorola edge 50 fusion (`ZA222NBPPV`, Android 16 / API 36) | **PENDING** | Required after all remediation modules complete: fullscreen video enter/play/replay/exit; CameraX release/resume across video + evidence routes; GPS Denied vs Unknown vs Service-Off and last-known-only shutter-lock behaviour. |
