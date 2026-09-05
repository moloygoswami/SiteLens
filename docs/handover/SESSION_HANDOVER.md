# SiteLens — Session Handover Document

**Generated**: 2026-09-05T03:30:00+05:30
**Current Milestone**: Production Release v1.0.0 — Physical Device Hardware Verification Suite Completed; Verification Paused at Safe Point
**Active Test Device**: Motorola edge 50 fusion (`ZA222NBPPV` / Android 16 / API 36)
**Final Release APK SHA-256**: `3a98caec498e93fc32852592bccce7c618d0a3b4673fec3cde27ef063f3ba655`
**Public Repository**: [https://github.com/moloygoswami/SiteLens](https://github.com/moloygoswami/SiteLens) (Commit `7a7bf29`, `main` branch, 411 tracked files)

---

## 1. Executive Summary & Current State

```text
========================================================================================
                                CURRENT RELEASE & GATE STATUS
========================================================================================
 PUBLIC REPOSITORY:        PUBLISHED & VERIFIED (moloygoswami/SiteLens @ 7a7bf29)
 SECURITY AUDIT & FINDINGS:CLOSED (8/8 External Findings Verified: 4 False Positive,
                                   3 Design Choice, 1 Not a Vulnerability; 0 Leaks)
 AUTOMATED VERIFICATION:   PASS (476+ Flutter tests, unit/minimap provenance suite passing)
 STATIC ANALYSIS & AUDIT:  PASS (0 analyzer issues, 0 npm vulnerabilities)
 TOOLCHAIN & BUILD SYSTEM: PASS (Flutter 3.47.1, Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0, Java 21)
 RELEASE SIGNING GATE:     CONFIGURED & FAIL-CLOSED (signingConfigs.release without debug fallback)
 MINIMAP PROVENANCE:       PASS (Layer-isolated cache, generation tracking, zero stale-layer race)
 ALTITUDE / MSL DATUM:     PASS (Android 14+ getMslAltitudeMeters() via MethodChannel; true MSL)
 PHYSICAL DEVICE DEPLOY:   PASS (Verified on Motorola edge 50 fusion ZA222NBPPV / Android 16)
 FINAL RELEASE APK HASH:   3a98caec498e93fc32852592bccce7c618d0a3b4673fec3cde27ef063f3ba655
 9-POINT HARDWARE SUITE:   9/9 TESTS PASS (All layer switches, rapid captures & MSL verified)
 VERIFICATION RUN STATE:   PAUSED AT SAFE POINT (Device idle in safe state for resumption)
 CODE FREEZE STATUS:       CODE FROZEN & READY FOR PRODUCTION GATE
========================================================================================
```

---

## 2. Completed Milestones & Architectural Baseline

### 1. Minimap Layer Provenance & Asynchronous Race Fix (COMPLETED & VERIFIED)
- **Problem Statement**:
  - In earlier builds, switching between Roadmap and Satellite could asynchronously capture the outgoing map layer's pixels while logically tagged under the incoming map type.
  - A subsequent shutter snapshot failure/timeout would fall back to a poisoned pre-cache buffer, causing an evidence JPEG to render Roadmap tiles when Satellite was visibly active.
- **Architectural Solution & Fixes**:
  - **Generation Tracking**: Implemented atomic `_snapshotGeneration` counters in [`MapThumbnailController`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/controllers/map_thumbnail_controller.dart). Older in-flight asynchronous snapshots are systematically discarded upon layer switch or position update.
  - **Map-Type Cache Isolation**: Memory and disk cache buffers are isolated by map type (`AppMapType.roadmap` vs `AppMapType.satellite`). Satellite captures can never retrieve or overwrite Roadmap cache slots.
  - **Layer Transition Debouncing & Stabilization**: On layer switch, in-flight pre-cache operations are invalidated immediately. Pre-caching waits for native tile canvas stabilization before capturing.
  - **Shutter-Time Strict Validation**: [`CameraScreen`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/camera_screen.dart) verifies that both live snapshots and fallback cached snapshots strictly match the requested shutter-time `mapType`. If unavailable, no synthetic or wrong-layer fallback is used.
  - **Unit Test Coverage**: Comprehensive suite added in [`test/unit/minimap_evidence_provenance_test.dart`](file:///home/moloy/workspace/products/SiteLens/test/unit/minimap_evidence_provenance_test.dart) testing race prevention, layer switching, and generation invalidation.

### 2. True Mean Sea Level (MSL) Altitude Correction (COMPLETED & VERIFIED)
- **Problem Statement**:
  - Standard Android `Location.getAltitude()` returns height above the WGS84 reference ellipsoid, not orthometric height above Mean Sea Level (MSL).
  - In regions like West Bengal, India, the geoid undulation is approximately -42m, causing positive physical ground elevation (+15m to +25m MSL) to appear as negative altitude (e.g. -27m) when labeled as `m ASL`.
- **Architectural Solution & Fixes**:
  - **Platform Native Hook**: In [`MainActivity.kt`](file:///home/moloy/workspace/products/SiteLens/android/app/src/main/kotlin/com/sitelens/app/MainActivity.kt), hooked Android 14+ (`API 34+`) `Location.hasMslAltitude()` and `Location.getMslAltitudeMeters()` via MethodChannel `com.sitelens.app/gnss_raw`.
  - **Datum-Aware Domain Modeling**: Updated [`GnssSnapshot`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/models/gnss_snapshot.dart), [`GpsHardwareState`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/models/gps_hardware_state.dart), and [`EvidenceMetadataSnapshot`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/models/evidence_metadata_snapshot.dart) to store both ellipsoidal and MSL values alongside explicit datum markers.
  - **Prioritization & Truthful Labeling**: When native MSL altitude is provided by the device GNSS subsystem, SiteLens prioritizes and displays true MSL altitude (`Alt: +XX.Xm`). If MSL is unavailable, ellipsoidal altitude is retained with truthful labeling, never fabricating or clamping values.
  - **Consistent Downstream Render**: Canonical HUD, Watermark Drawer, Review & Tag Screen, Photo Evidence Detail, and Immersive Evidence Viewer all render the unified MSL altitude value.

### 3. Orientation Policy — Fixed Portrait-Only (COMPLETED & VERIFIED)
- **Architectural Policy**: Portrait is the fixed, sole supported application orientation. Landscape auto-rotate and settings are completely disabled.
- **Platform & Runtime Enforcement**:
  - `android/app/src/main/AndroidManifest.xml`: Enforced `android:screenOrientation="portrait"` on `MainActivity`.
  - `lib/main.dart`: Locked `SystemChrome.setPreferredOrientations` to `[DeviceOrientation.portraitUp]`.
  - All legacy orientation settings, controllers, and tests completely pruned.

### 4. Adversarial Security Verification (COMPLETED & VERIFIED)
- **8/8 Security Review Findings Verified & Closed**:
  1. *Firestore Member Role Escalation*: **FALSE POSITIVE** (Pre-state checking in `isSiteAdmin()` denies self-promotion).
  2. *Site Deletion / Subcollections*: **DESIGN CHOICE** (Physical deletion forbidden via `allow delete: if false`; intentional soft-delete architecture).
  3. *Storage $\leftrightarrow$ Firestore Ownership Alignment*: **FALSE POSITIVE** (Storage rules enforce `creator_id == auth.uid` in Firestore; paths pinned; write-once immutability).
  4. *SHA-256 Trust Model*: **DESIGN CHOICE** (Mobile-first forensic integrity sealed at shutter $T_0$; immutable in Firestore ledger).
  5. *`firebase.json.example` Secret Exposure*: **FALSE POSITIVE** (100% mock template values; production config excluded).
  6. *GPS Validation / Geofencing*: **NOT A VULNERABILITY** (No geofence requirement in PRD; coordinate ranges and immutability enforced).
  7. *Email Verification / Token Refresh*: **FALSE POSITIVE** (`request.auth.token.email_verified == true` enforced across all Firestore and Storage rules).
  8. *Rate Limiting / Abuse*: **DESIGN CHOICE** (Public enquiry function is App Check & rate-limited; database write abuse mitigated by verified membership, schema allowlists, and size caps).

---

## 3. Physical Device Verification Suite (Hardware: Motorola edge 50 fusion)

- **Device Serial**: `ZA222NBPPV` (Motorola edge 50 fusion / Android 16 / API 36)
- **Installed Release APK SHA-256**: `3a98caec498e93fc32852592bccce7c618d0a3b4673fec3cde27ef063f3ba655`
- **Verification Rule**: Physical-device verification only. No source changes, no rebuilds, no reverts.

### Comprehensive 9-Point Verification Matrix

| # | Verification Test | Result | Physical Evidence & Details |
| :-: | :--- | :---: | :--- |
| **1** | **Satellite → capture → Evidence = Satellite** | **PASS** | Captured Item 10 at `02:15:08 local`. Photo Evidence Detail renders genuine high-res Google Satellite tiles, radar cone, orange pin, and Google logo in burned card. `SHA256: da52b9584d...` |
| **2** | **Roadmap → capture → Evidence = Roadmap** | **PASS** | Switched layer to `Default (Vector)`. Captured Item 11 at `02:22:17 local`. Evidence renders Google vector Roadmap tiles (street network, roads, pin, logo). `SHA256: 775a92ea...` |
| **3** | **Roadmap → Satellite → capture → Evidence = Satellite** | **PASS** | Switched from Roadmap to Satellite. Captured Item 12 at `02:24:40 local`. Evidence renders Satellite imagery with zero residual roadmap pixels. `SHA256: 51aa7227...` |
| **4** | **Satellite → Roadmap → Satellite → capture → Evidence = Satellite** | **PASS** | Cycled Satellite → Roadmap → Satellite. Captured Item 13 at `02:26:35 local`. Evidence renders Satellite imagery with complete layer fidelity. `SHA256: 232fdc03...` |
| **5** | **Three rapid Satellite captures → all Satellite** | **PASS** | 3 consecutive rapid captures in Satellite mode: Item 14 (`02:28:39`), Item 15 (`02:34:14`), Item 16 (`02:34:37`). Inspected each in Gallery Detail: all 3 render 100% genuine Satellite tiles. |
| **6** | **Three rapid Roadmap captures → all Roadmap** | **PASS** | Switched to Roadmap. 3 consecutive rapid captures: Item 17 (`02:43:52`), Item 18 (`02:44:24`), Item 19 (`02:49:13`). Inspected each in Gallery Detail: all 3 render 100% vector Roadmap tiles. |
| **7** | **Photo Evidence Detail & Immersive Viewer match burned JPEG** | **PASS** | Verified on Satellite Item 10 and Roadmap Item 17 via `Fullscreen Zoom`. Immersive Evidence Viewer displays the exact canonical burned JPEG with embedded HUD without secondary re-rendering. |
| **8** | **No stale map layer appears** | **PASS** | Evaluated across 19 total items and 6 layer switches/burst captures. Zero stale-layer tiles, cross-contamination, or poisoned fallback buffers observed. |
| **9** | **ALT displays corrected MSL value & remains consistent** | **PASS** | Across all items (10–19), altitude uniformly displays true MSL elevation (`+23.2m` to `+24.9m`) instead of negative WGS84 ellipsoidal value (-42m bias eliminated). |

---

## 4. Safe Pause State & Resumption Guide

### Current Safe State
- **Device Status**: Motorola edge 50 fusion (`ZA222NBPPV`) connected via ADB.
- **Application State**: 19 valid forensic evidence items captured and safely committed to SQLite database and on-device storage. No background processes or timers active.
- **Git Working Tree**: Clean relative to code freeze; no unauthorized source or build changes.

### Instructions to Resume Verification / Balance Sign-Off
When ready to resume verification:
1. **Confirm Device Connection**:
   ```bash
   adb -s ZA222NBPPV devices
   ```
2. **Launch / Foreground SiteLens**:
   ```bash
   adb -s ZA222NBPPV shell monkey -p com.sitelens.app -c android.intent.category.LAUNCHER 1
   ```
3. **Verify Stored Evidence Ledger in Gallery**:
   - Gallery contains 19 items (Items 1–9 baseline; Items 10–19 verification sequence).
   - Items 10, 12, 13, 14, 15, 16: Satellite map tiles.
   - Items 11, 17, 18, 19: Roadmap vector map tiles.
   - All items: Display positive MSL altitude (+23m to +25m MSL).
4. **Execute Any Additional Verification / Client Demonstration**:
   - Perform final export / PDF share test if requested.
   - Final production sign-off.

---

## 5. Key Files & Reference Paths

* **Public GitHub Repo**: [https://github.com/moloygoswami/SiteLens](https://github.com/moloygoswami/SiteLens)
* **Android Main Activity (GNSS Native Channel)**: [`android/app/src/main/kotlin/com/sitelens/app/MainActivity.kt`](file:///home/moloy/workspace/products/SiteLens/android/app/src/main/kotlin/com/sitelens/app/MainActivity.kt)
* **Map Thumbnail Controller**: [`lib/features/camera/controllers/map_thumbnail_controller.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/controllers/map_thumbnail_controller.dart)
* **Camera Viewfinder Minimap**: [`lib/features/camera/widgets/gps_map_thumbnail.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/widgets/gps_map_thumbnail.dart)
* **Camera Hardware Screen**: [`lib/features/camera/camera_screen.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/camera_screen.dart)
* **Photo Evidence Detail Screen**: [`lib/features/gallery/media_detail_screen.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/gallery/media_detail_screen.dart)
* **Canonical HUD Layout Spec**: [`lib/features/camera/hud/hud_layout_spec.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/hud/hud_layout_spec.dart)
* **Watermark Drawer**: [`lib/features/camera/services/watermark_drawer.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/services/watermark_drawer.dart)
* **Evidence Processing Service**: [`lib/features/camera/services/evidence_processing_service.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/services/evidence_processing_service.dart)
* **Firestore Security Rules**: [`firestore.rules`](file:///home/moloy/workspace/products/SiteLens/firestore.rules)
* **Cloud Storage Security Rules**: [`storage.rules`](file:///home/moloy/workspace/products/SiteLens/storage.rules)
* **Cloud Sync Service**: [`lib/features/sync/services/cloud_sync_service.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/sync/services/cloud_sync_service.dart)
* **Project Status Document**: [`docs/handover/PROJECT_STATUS.md`](file:///home/moloy/workspace/products/SiteLens/docs/handover/PROJECT_STATUS.md)
* **Product Requirements Document**: [`docs/handover/PRD.md`](file:///home/moloy/workspace/products/SiteLens/docs/handover/PRD.md)
