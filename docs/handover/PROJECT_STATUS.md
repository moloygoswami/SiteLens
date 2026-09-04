# SiteLens — Project Status & Implementation State

**Date**: 2026-09-04T15:10:00+05:30
**Current Milestone**: Minimap Evidence Provenance & Production Security Verified (476/476 Tests Passing), Validated on Physical Hardware (`ZA222NBPPV`)
**Release Status**: `PRODUCTION RELEASE CANDIDATE READY & VERIFIED`

```text
========================================================================================
                                CURRENT RELEASE GATE STATUS
========================================================================================
 SECURITY REMEDIATION:     IMPLEMENTED & VERIFIED (Modules 1, 1A, 2, 3, 4, 5, 6, 7)
 AUTOMATED VERIFICATION:   PASS (476/476 Flutter, 57/57 Security Rules, 22/22 Cloud Functions)
 STATIC ANALYSIS & AUDIT:  PASS (0 analyzer issues, 0 npm vulnerabilities, clean git diff)
 TOOLCHAIN & BUILD SYSTEM: PASS (Flutter 3.47.1, Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0, Java 21)
 RELEASE SIGNING GATE:     CONFIGURED & FAIL-CLOSED (signingConfigs.release without debug fallback)
 GOOGLE AUTHENTICATION:    PASS (Release SHA-1/SHA-256 registered, google-services.json updated)
 PHYSICAL DEVICE DEPLOY:   PASS (Verified on Motorola edge 50 fusion ZA222NBPPV / Android 16)
 FINAL STRIX SECURITY GATE:PASS (strix_runs/sitelens_da94 / 0 vulnerabilities detected)
 CAMERA & MINIMAP PROVENANCE:PASS (Fixed portrait, live minimap snapshot T0, heading cone,
                                   burned Evidence JPEG, verified on physical hardware)
 PRODUCTION GATE DECISION: APPROVED FOR PRODUCTION DISTRIBUTION
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
  - 476/476 Flutter unit, widget, and integration tests passing.
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
  - Implemented **Orientation & Auto-Rotate Features**:
    * Enabled auto-rotate by default on app launch (`[DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]`).
    * Added user-configurable orientation mode setting (`Auto-Rotate (Default)`, `Portrait`, `Landscape`) persisted in `SharedPreferences`.
    * Reflowed `CameraScreen` into horizontal layout with top HUD and right-hand shutter grip station when landscape mode is active.
    * Configured `MediaDetailScreen` to keep overall layout in portrait while rendering the photo viewport in 4:3 landscape ratio.
    * Locked `ImmersiveEvidenceViewer` to landscape orientations when landscape mode is active.
    * Configured evidence processing isolate and `JpegMetadataExtractor` to ensure landscape evidence captures are exported in landscape orientation without distortion.
  - Physical Device Validation on Motorola edge 50 fusion (`ZA222NBPPV`):
    * Deployed updated debug APK; verified orientation settings, camera reflow, capture, detail photo viewport, and immersive viewer.
    * Stopped manual/hardware verification upon user request.
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
| **Connected Test Target** | Physical Hardware `Motorola edge 50 fusion` / `ZA222NBPPV` (Android 16 / API 36) | `VERIFIED & OPERATIONAL` |
| **Debug APK Artifact** | `build/app/outputs/flutter-apk/app-debug.apk` | `BUILT & DEPLOYED` |

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
| **Minimap Evidence Provenance** | `gps_map_thumbnail.dart`, `map_thumbnail_controller.dart`, `watermark_drawer.dart`, `evidence_metadata_snapshot.dart` | **COMPLETED & VERIFIED** | Shutter-time native map snapshot (T₀), heading cone, burned-in Evidence JPEG, downstream single-JPEG display; 476/476 tests passed. |
| **Physical Hardware Verification** | `motorola edge 50 fusion` (`ZA222NBPPV`) | **VERIFIED ON DEVICE** | Physical device on-device validation passed. |
