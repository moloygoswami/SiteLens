# SiteLens — Project Status & Implementation State

**Date**: 2026-09-06T02:51:00+05:30
**Current Milestone**: Post-v1.0.0 Reliability Audit & Hardware Verification — Baseline (`6a02f91` on `main`, frozen Tag `v1.0.0` at `a17e8c3`), 507/507 Tests Passing, Physical Hardware Verification Passed (10/10 Matrix + Zoom), Complete Test Inventory Formalized (`docs/ALL_TESTS.md`)
**Release Status**: `PRODUCTION RELEASE FROZEN (v1.0.0 / commit a17e8c3) — POST-RELEASE AUDIT & VERIFICATION ACTIVE`

```text
========================================================================================
                                CURRENT RELEASE GATE STATUS
========================================================================================
 SECURITY REMEDIATION:     IMPLEMENTED & VERIFIED (Modules 1–7; 8/8 findings closed; strix-sitelens-instructions.md formalized)
 AUTOMATED VERIFICATION:   PASS (507/507 Flutter: 407 unit tests + 100 widget tests across 60 files; 57/57 Security Rules, 22/22 Cloud Functions)
 STATIC ANALYSIS & AUDIT:  PASS (0 analyzer issues, 0 npm vulnerabilities)
 TOOLCHAIN & BUILD SYSTEM: PASS (Flutter 3.47.1, Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0, Java 21)
 RELEASE SIGNING GATE:     CONFIGURED & FAIL-CLOSED (signingConfigs.release without debug fallback)
 GOOGLE AUTHENTICATION:    PASS (Release SHA-1/SHA-256 registered, google-services.json updated)
 PHYSICAL DEVICE DEPLOY:   PASS (Verified on Motorola edge 50 fusion ZA222NBPPV / Android 16)
 FINAL STRIX SECURITY GATE:SCOPE FORMALIZED (strix-sitelens-instructions.md updated for v1.0.0 freeze)
 CAMERA & MINIMAP PROVENANCE:PASS (Fixed portrait, live minimap snapshot T0, heading cone,
                                   burned Evidence JPEG, layer-isolated cache, zero stale-layer race)
 CAMERA ZOOM & INTEGRITY:  PASS (1.0x init default, truthful label, capability-aware cycling; Rule 5 compliant)
 TEST SUITE INVENTORY:     PASS (docs/ALL_TESTS.md: 507/507 tests exhaustively cataloged with instructions)
 ALTITUDE / MSL DATUM:     PASS (Android 14+ getMslAltitudeMeters() via MethodChannel; true MSL)
 PRODUCTION GATE DECISION: APPROVED FOR PRODUCTION DISTRIBUTION (v1.0.0 frozen)
========================================================================================
```

---

## 1. Overview
- **Project Name**: SiteLens (Mobile App & Serverless Backend)
- **Domain**: GPS-Aware Construction Inspection Camera, Evidence Provenance, Spatial Nearby Search & Support Subsystem
- **Technology Stack**: Flutter (Dart 3.6.2), Firebase (Core, Auth, App Check, Firestore, Cloud Functions 2nd-gen, Storage), Drift (SQLite v7), Riverpod, Resend REST API, Share Plus, PDF, Printing, Archive, Google Maps Flutter, Google Sign-In & Photos API
- **Current Milestone Accomplishments**:
  - All security findings (Modules 1 through 7 + Module 4 Local Isolation follow-up) remediated and verified.
  - 57/57 Firestore/Storage security rules tests passing in emulator.
  - 507/507 Flutter unit, widget, and integration tests passing across 60 files (407 unit tests, 100 widget tests).
  - 22/22 Cloud Functions backend tests passing.
  - Clean static analysis (`flutter analyze` 0 issues).
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
| **Complete Test Inventory (`docs/ALL_TESTS.md`)** | `docs/ALL_TESTS.md` | **COMPLETED & VERIFIED** | 507/507 automated tests across 60 files (407 unit tests + 100 widget tests) sequentially numbered (#1–#507) with exact names & instructions. |
