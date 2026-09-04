# SiteLens — Session Handover Document

**Generated**: 2026-09-04T02:48:00+05:30  
**Current Milestones**: 
1. **Orientation Policy Changed to Fixed Portrait-Only** (Completed & Verified across app manifest, settings, controllers, camera, gallery detail, and tests).
2. **Canonical Live Minimap State Capture & Fidelity Alignment** (In Progress: Root-cause diagnosed, canonical teardrop pin & heading cone guards implemented in `WatermarkDrawer` and `GpsMapThumbnail`, tests passing).
**Active Test Device**: Motorola edge 50 fusion (`ZA222NBPPV` / Android 16 / API 36)

---

## 1. Executive Summary & Current State

```text
CURRENT VERIFIED BASELINE:

1. ORIENTATION POLICY CHANGE — PORTRAIT ONLY (COMPLETED & VERIFIED):
   - Architectural Policy: Portrait is the fixed, sole supported application orientation. Landscape is completely disabled.
   - Removed Orientation Settings & Persistence:
     * Completely removed "Camera Orientation", "Display Orientation", and the "CAMERA & DISPLAY ORIENTATION" settings card.
     * Deleted AppOrientationMode enum from lib/domain/models/enums.dart.
     * Deleted OrientationSettingsNotifier and orientationSettingsProvider from lib/core/controllers/orientation_settings_controller.dart.
     * Deleted test/unit/orientation_settings_controller_test.dart.
     * Cleaned up SharedPreferences key 'setting_app_orientation'.
   - Platform & Runtime Enforcement:
     * android/app/src/main/AndroidManifest.xml: Enforced android:screenOrientation="portrait" on MainActivity.
     * lib/main.dart: Locked SystemChrome.setPreferredOrientations to [DeviceOrientation.portraitUp].
   - Screen & Layout Simplification:
     * CameraScreen: Removed OrientationSettingsNotifier listeners, dynamic device rotation hooks, and the landscape Scaffold layout branch.
     * CameraShutterStation: Removed isLandscape parameter and horizontal/column grip station branching.
     * MediaDetailScreen: Removed landscape orientation overrides in fullscreen viewer; standardized viewport height to canonical portrait (screenHeight * 0.54).
     * ReviewMediaPreview: Fixed preview container to portrait bounds.
     * EvidenceProcessingService & JpegMetadataExtractor: Removed isLandscape parameters and sensor transposition logic.
   - Verification: All 467 tests passed; flutter analyze clean (0 issues).

2. CANONICAL LIVE MINIMAP STATE CAPTURE & FIDELITY ALIGNMENT (IN PROGRESS):
   - User Problem & Prompt:
     "Why does the same map content render differently inside the minimap container on Evidence Detail and Immersive Viewer compared with Camera Capture?
      Camera Capture's correctly rendered live minimap is the canonical source; at shutter time, its exact visual map state must be captured into the evidence JPEG, and Photo Evidence Detail and Immersive Evidence Viewer must subsequently display those exact burned-in pixels without independently re-rendering the map."
   - Critical Validation Invariants:
     1. The snapshot uses the currently active map type.
     2. The snapshot uses the same camera center.
     3. The snapshot uses the same zoom.
     4. The snapshot represents the same visible geographic framing.
     5. The snapshot dimensions/aspect ratio correspond correctly to the existing minimap viewport.
     6. No stale snapshot or cached mapTileBytes can be used.
     7. Snapshot capture occurs at shutter time, before the evidence is sealed.
     8. If the native GoogleMap snapshot does not include Flutter overlays such as the location pin or heading cone, explicitly document this and reproduce those elements using the exact same source state/geometry as Camera Capture.
     9. The existing minimap container geometry must NOT be changed (no change to width, height, position, aspect ratio, zoom, or arbitrary offsets).
   - Root-Cause Analysis:
     * GoogleMap Controller Snapshot: GoogleMap is an Android PlatformView (TextureView/SurfaceView). Its native takeSnapshot() returns only the underlying map canvas; Flutter widget overlays (Icons.location_on_rounded pin, heading cone, radar circle, Google attribution) are NOT present in the native bitmap.
     * WatermarkDrawer Mismatch: WatermarkDrawer previously re-drew overlays using a concentric circle bullseye target (canvas.drawCircle: red ring with white center dot) instead of the canonical teardrop pin (Icons.location_on_rounded). Furthermore, WatermarkDrawer had an unconditional heading cone (if (isGpsLocked)) drawing a forward-pointing fan (0°) even when headingDegrees == null, which appeared as a stark blue triangle on vector maps.
     * Layer / Snapshot Timing: At shutter time, takeLiveSnapshotForEvidence() was called serially after camera takePhoto(). If it timed out (1500ms), it fell back to cached tiles that were not validated for geographic distance (movementThresholdMeters) or timestamp freshness, potentially causing map layer or coordinate mismatches.
     * Passive Viewers Confirmed: Both MediaDetailScreen (line 444) and Immersive Evidence Viewer (line 107) strictly display Image.file(File(displayPath)) (the burned JPEG). They do not independently re-render the map. The observed discrepancy was entirely due to the burned-in watermark pixels differing from the live camera viewfinder.
   - Code Modifications Completed:
     * lib/features/camera/services/watermark_drawer.dart:
       - Replaced circular bullseye reticle with the canonical Google Maps teardrop location pin matching Icons.location_on_rounded (head center hx/hy, radius R, tangent lines to bottom tip tx/ty, drop shadow with blur, white inner cutout, and contact shadow oval).
       - Guarded heading cone with if (isGpsLocked && headingDegrees != null), preventing false directional cones when compass sensor data is unavailable.
     * lib/features/camera/widgets/gps_map_thumbnail.dart:
       - Guarded heading cone with if (widget.isLocked && widget.headingDegrees != null) for 1:1 parity with the evidence watermark.
     * lib/features/camera/controllers/map_thumbnail_controller.dart:
       - Increased takeLiveSnapshotForEvidence timeout to 3500ms.
       - Resolved Future<Uint8List?> generic type matching in onTimeout.
     * lib/features/camera/camera_screen.dart:
       - Initiated liveSnapshot concurrently at shutter press (T0) alongside hardware takePhoto().
       - Enforced strict cache freshness guards before using cachedTile fallback (matching currentMapType, age <= 5m, distance <= 20m).
       - Replaced speculative post-shutter network fetches with strict local canonical disk cache lookups.
     * lib/features/camera/models/evidence_metadata_snapshot.dart & lib/features/camera/services/evidence_processing_service.dart:
        - Added headingDegrees to EvidenceMetadataSnapshot and captured it at shutter time (T0).
        - Propagated headingDegrees into HudFormatter.fromSnapshot to ensure the heading cone is rendered in the Evidence JPEG.
     * lib/features/camera/services/watermark_drawer.dart:
        - Strictly removed synthetic vector reticle (fake roads and grid paths) from evidence content.
        - Guarded Google attribution so it is only painted when valid map tiles are present.
        - Synchronized heading cone drawing with snapshot.headingDegrees.
     * docs/handover/PRD.md & docs/handover/architecture.md:
        - Made the Evidence Provenance Invariant authoritative: Evidence JPEG MUST contain the same minimap map state/source that the user sees in live Camera Capture at shutter time.
        - Formally documented the PlatformView / Vector-Overlay architecture (semantic visual provenance vs. physical framebuffer capture).
    - Verification & Acceptance:
      * flutter analyze clean (0 issues).
      * All 476/476 tests passed (including 8 targeted provenance tests and downstream invariant tests).
      * Debug APK successfully compiled (build/app/outputs/flutter-apk/app-debug.apk) and installed on Motorola edge 50 fusion (ZA222NBPPV).
      * On-Device Physical Validation: Accepted by human tester; visual parity confirmed across Normal/Satellite map tiles, viewport, teardrop pin, radar circle, compass heading cone, and Google attribution without downstream map re-rendering.
```

---

## 2. Completed Milestones & Verification Ledger

| Milestone / Task | Component | Status | Verification Evidence |
| :--- | :--- | :---: | :--- |
| **Orientation Policy Change — Portrait Only** | `AndroidManifest.xml`, `main.dart`, `camera_screen.dart`, `settings_screen.dart`, `media_detail_screen.dart`, `evidence_processing_service.dart` | **COMPLETED & VERIFIED** | Landscape disabled; all orientation settings removed; 467/467 tests passed; APK installed on `ZA222NBPPV`. |
| **Root-Cause Investigation: Minimap Discrepancy** | `gps_map_thumbnail.dart`, `watermark_drawer.dart`, `map_thumbnail_controller.dart`, `media_detail_screen.dart` | **COMPLETED** | Proved passive viewer behavior; identified missing overlay capture from PlatformView and WatermarkDrawer shape/cone mismatches. |
| **Teardrop Location Pin & Heading Cone Alignment** | `watermark_drawer.dart`, `gps_map_thumbnail.dart` | **COMPLETED & TESTED** | Canonical `Icons.location_on_rounded` teardrop vector path + shadow implemented; heading cone strictly guarded by `headingDegrees != null`. 32/32 `watermark_drawer_test.dart` unit tests passed. |
| **Authoritative Minimap Evidence Provenance Invariant** | `camera_screen.dart`, `watermark_drawer.dart`, `PRD.md`, `architecture.md` | **COMPLETED & VERIFIED** | Concurrent $T_0$ snapshot capture wired; synthetic vector reticle deleted from evidence; cache freshness guarded; PRD & architecture docs updated; 476/476 tests passed. |
| **Visual-Provenance Heading Cone Fix** | `evidence_metadata_snapshot.dart`, `evidence_processing_service.dart`, `watermark_drawer.dart` | **COMPLETED & VERIFIED** | `headingDegrees` added to `EvidenceMetadataSnapshot`, captured at $T_0$, passed to `HudFormatter.fromSnapshot`, and rendered in Evidence JPEG. 8/8 targeted provenance tests passed. |
| **Physical-Device Visual Verification & Acceptance** | `ZA222NBPPV` (Motorola edge 50 fusion), `MediaDetailScreen`, Immersive Viewer | **ACCEPTED & CLOSED** | Human verified real captures in Normal & Satellite modes. 1:1 visual match across base tiles, viewport, pin, radar, heading cone, attribution; downstream JPEG-only viewing confirmed. |

---

## 3. Physical Device Inspection Summary

- **Target Hardware**: Motorola edge 50 fusion (`ZA222NBPPV` / Android 16 / API 36).
- **Physical Verification Result**:
  - Tested real captures in both Normal (vector) and Satellite (raster imagery) modes.
  - Live minimap at $T_0$ matched burned minimap in Photo Evidence Detail and Immersive Viewer.
  - Zero discrepancies observed across all 7 evaluation dimensions (map tiles/layer, viewport, pin, radar, heading cone, attribution, downstream JPEG viewing).
  - Implementation accepted with documented PlatformView/vector-overlay architecture.

---

## 4. Key Files & Reference Paths

* **Watermark Drawer**: [`lib/features/camera/services/watermark_drawer.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/services/watermark_drawer.dart)
* **Camera Viewfinder Minimap Widget**: [`lib/features/camera/widgets/gps_map_thumbnail.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/widgets/gps_map_thumbnail.dart)
* **Map Thumbnail Controller**: [`lib/features/camera/controllers/map_thumbnail_controller.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/controllers/map_thumbnail_controller.dart)
* **Camera Screen**: [`lib/features/camera/camera_screen.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/camera_screen.dart)
* **Photo Evidence Detail Screen**: [`lib/features/gallery/media_detail_screen.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/gallery/media_detail_screen.dart)
* **Canonical HUD Layout Specification**: [`lib/features/camera/hud/hud_layout_spec.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/hud/hud_layout_spec.dart)
* **Evidence Processing Service**: [`lib/features/camera/services/evidence_processing_service.dart`](file:///home/moloy/workspace/products/SiteLens/lib/features/camera/services/evidence_processing_service.dart)
* **Implementation Plan**: [`implementation_plan.md`](file:///home/moloy/.gemini/antigravity-ide/brain/308436fe-621f-44ac-b48b-70d53f13d3b9/implementation_plan.md)
