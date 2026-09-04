# SiteLens — Engineering-Grade GPS Field Evidence Camera

SiteLens is an enterprise-grade mobile application designed for construction engineers, site inspectors, land surveyors, and field auditors. It captures tamper-evident, geotagged photographic evidence with precise geolocation telemetry, live Google minimap tracking, and cryptographic provenance verification.

---

## Key Features & Capabilities

### 1. Precision Optical Viewfinder
- **Native Sensor Aspect Ratio**: Uncropped 4:3 / 3:4 viewfinder matching optical camera hardware sensors without distortion or digital crop.
- **Hardware Zoom Engine**:
  - **Rear Camera**: 0.5x Ultra-Wide, 1.0x Standard, and 2.0x Telephoto modes dynamically bound to Camera2 API optical capabilities.
  - **Front Camera**: 1.0x native fixed-focal-length optical resolution matching Google Camera specifications.
- **Resilient Lifecycle Management**: Camera stream stays live through Android `inactive` states (e.g. system screenshots, notification shade pull-down).

### 2. High-Clarity Google Minimap HUD
- **Three-Tier Minimap Architecture**:
  - **Tier 1 (Live Hybrid Map)**: Interactive `GoogleMap` widget with `MapType.hybrid` satellite overlay + crisp vector street networks at **Zoom 18.0** for precise property/building-level focus.
  - **Tier 2 (Cached Static Map)**: High-DPI 2x retina images (`300x300` @ `scale=2` / 600x600 px effective canvas) cached locally with `FilterQuality.high`.
  - **Tier 3 (Synthetic Offline Map)**: Zero-latency vector grid fallback with satellite offline indicators when connectivity is unavailable.
- **Butter-Smooth Transition**: Unified container bounds (`74x74` square) with `AnimatedSwitcher` cross-fade to eliminate initialization layout popping.

### 3. Cryptographic Provenance & Watermarking
- **Tamper-Evident SHA-256 Hash**: Every captured photo generates an SHA-256 integrity hash sealing the image bytes, GPS coordinates, altitude ASL, site ID, and UTC timestamp.
- **Enterprise Watermark HUD**: Industrial slate card (`#0D110F`) with green/amber verification badges (`🟢 VERIFIED` / `🟡 PENDING`), monospace telemetry, and physical reverse-geocoded address.
- **Quality Preservation**: 95% JPEG evidence capture quality with preserved EXIF metadata.

### 4. Authentication & Compliance
- **First-Time Sign Up with Email Verification**: Dedicated user onboarding with mandatory verification link dispatched to the user's work email address before permitting login.
- **Sign-In Verification Gate**: Compulsory verification verification on sign-in with instant inline "Resend Verification Email" trigger.
- **Self-Service Password Reset**: Direct "Forgot Password?" email reset link workflow.
- **Compliance Policy Enforcer**: Mandatory Terms of Service and Privacy Policy acceptance required before authentication.

### 5. Anti-Slop Industrial Design System
- **Strict 4-Tier Radii Scale**: `xs = 2px`, `sm = 4px`, `md = 8px`, `lg = 12px`, eliminating generic 9999px pill capsules.
- **Solar High-Contrast Neutrals**: Deep slate (`#0F172A`/`#475569`) with 1px hairline borders replacing diffuse box shadows for outdoor legibility.
- **Tabular Monospace Primitives**: Dedicated `TelemetryBadge` for GPS, timestamp, and forensic checksums.

---

## Architecture & Directory Structure

```text
lib/
├── app/
│   ├── app.dart                   # Root MaterialApp & routing configuration
│   └── theme.dart                 # Design tokens, AppColors, typography, radii
├── core/
│   ├── controllers/               # Global state controllers (MapType, Settings)
│   ├── models/                    # Shared data models & domain entities
│   └── services/
│       ├── geo_service.dart       # GPS fix acquisition & geofencing
│       ├── map_thumbnail_service.dart # High-DPI Static Maps cache engine
│       └── storage_service.dart   # Local persistence & evidence ledger
├── domain/
│   └── models/                    # Enums, GPS fixtures, evidence models
└── features/
    ├── auth/                      # Login, Signup, Email Verification, Terms
    ├── camera/                    # Optical viewfinder, HUD, GpsMapThumbnail
    │   ├── controllers/           # Camera hardware & capture state notifiers
    │   ├── services/              # Evidence processing & cryptographic hashing
    │   └── widgets/               # CameraViewfinder, ViewfinderControls, WatermarkPreview
    ├── gallery/                   # Evidence review, tamper verification, EXIF viewer
    └── sites/                     # Project & site context management
```

---

## Testing & Quality Assurance

SiteLens maintains a comprehensive test suite across unit, widget, and integration layers:

```bash
# Run all unit and widget tests
flutter test

# Run camera viewfinder and HUD tests
flutter test test/widget/camera_screen_test.dart

# Run authentication and milestone UI tests
flutter test test/widget/m1_screens_test.dart

# Build debug APK for physical device deployment
flutter build apk --debug

# Install to connected Android device
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

---

## Hardware & Environment Requirements

- **Flutter SDK**: `>= 3.24.0`
- **Android**: `minSdkVersion 24`, `targetSdkVersion 34` (Camera2 & Google Play Services Location enabled)
- **Google Maps API Key**: Configured in `AndroidManifest.xml` and `MapThumbnailService`
- **Tested Physical Device**: Motorola Edge 50 Fusion (Android 14)
