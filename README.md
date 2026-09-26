# SiteLens — GPS-Tamper-Evident Field Evidence Camera

SiteLens is a mobile evidence-capture application for construction field inspection. It solves a specific trust problem: photographs taken on a construction site are only useful as inspection evidence if their location, time, and integrity can be trusted and cannot be quietly altered after the fact.

SiteLens turns a phone into a **GPS-tamper-evident evidence camera**: every capture is bound to a real-time GPS fix, stamped with a visible, permanently burned-in provenance record, cryptographically hashed at the moment of capture, and stored locally first so that field connectivity never blocks the inspector's work. Captured evidence can be organized by site, tagged by activity and observation type, searched by physical proximity to reveal how a location has changed over time, and optionally synchronized to the cloud for durable backup.

**The product never asserts a stronger evidence, GPS, timing, or integrity guarantee than it has actually established.** A displayed value, badge, or verification state always reflects a real, current, hardware- or system-verified fact — never an assumption, a synthetic default, or a stale value presented as current.

SiteLens v1 is **user-specific and creator-owned**, not collaborative. Each authenticated user operates within an independent, isolated personal data domain. Physical co-location — a shared site code, matching address, or identical GPS coordinates — never grants one user access to another user's data.

---

## Phase 1 — Product Scope

The complete Phase 1 loop: `capture → tag → store → find-nearby → optional cloud synchronization`

- Firebase Authentication (Email/Password and Google Sign-In) with mandatory email verification
- First-login permission onboarding (camera, location, microphone, notifications)
- Project/site selection, creation, and deletion (creator-owned)
- GPS-aware photo/video capture with a live GPS status indicator
- Visible burned-in geotagging (metadata + minimap HUD)
- An immutable original artifact plus a derived, privacy-safe evidence artifact with camera metadata stripped
- Local-first media storage and local gallery
- Review & Tag — classify activity, observation type, and notes before commit
- Media Detail with structured technical telemetry and integrity verification
- GPS-based nearby-media search with spatial-uncertainty-aware distance reporting
- Before/After smart-linking of related observations (requires explicit user confirmation)
- Local SQLite (Drift) database as the operational source of truth
- Firebase Cloud Firestore + Cloud Storage synchronization with a sync queue and status visibility
- Settings, storage cleanup, cloud media recovery, and creator-owned account deletion
- Optional Google Photos auto-sync as a strictly supplementary, non-authoritative channel

### Non-Goals (Deferred to Future Phases)

Shared sites, site membership, member invitations, member roles, administrator roles, RBAC, ownership transfer, team workspaces, WIR/NCR builders, Excel/CSV exports, a web management dashboard, server-side spatial search, full per-frame video geotag burn-in, and any automated evidence linking without explicit user confirmation.

---

## Architecture

| Layer | Technology |
|---|---|
| **Mobile client** | Flutter / Dart (Android and iOS) |
| **State management** | Riverpod (v2), with session-bounded provider lifecycles |
| **Local database** | SQLite via Drift (local-first source of truth) |
| **Cloud backend** | Firebase Authentication, Cloud Firestore, Cloud Storage, Security Rules |
| **Integrity hashing** | SHA-256 (crypto package) |
| **Server-side functions** | Firebase Cloud Functions (Node.js), behind App Check |
| **Package identity** | `com.sitelens.app` |

### Core architectural principles

- **Offline-first**: capture, GPS acquisition, media processing, hashing, local persistence, gallery browsing, nearby search, Before/After linking, and sync queuing all function without network connectivity. Firebase is an asynchronous cloud sync target — never a prerequisite for capture.
- **Creator-owned / fail-closed isolation**: every local query, Firestore rule, and Storage rule enforces `resource.creator_id == request.auth.uid`. A null or unresolved identity returns zero rows. Zero cross-user access holds without exception across every resource type.
- **Immutable original + single-HUD evidence**: every capture produces exactly three artifacts — the pristine original, the canonical evidence artifact (with HUD burned in at capture time), and a thumbnail. Downstream surfaces render the canonical evidence artifact directly; none regenerates a second HUD.
- **Two-tier integrity hashing**: independent SHA-256 hashes for the original and the evidence artifact, never substituted for one another. A "Verified" badge requires live re-hashing of on-disk bytes in the current session — a stored hash alone never justifies it.
- **Capture-time authority**: coordinates are always real observed GNSS receiver fixes — never synthetic, interpolated, or zero-filled. Unavailable telemetry (altitude, heading, satellite count) remains explicitly null. The shutter is disabled until a live fix is obtained; cached/last-known positions never unlock capture.
- **Cloud replication of the evidence artifact**: the canonical evidence artifact is replicated to cloud storage alongside the original as a write-once, independently verifiable replica — never a shift of operational authority away from local storage.

### Evidence file model

```
Camera shutter
      │
      ├──> Original file    (pristine capture, untouched, hardware metadata intact)
      │
      └──> Evidence processing (background isolate)
                 │
                 ├──> Canonical evidence artifact  (original + burned minimap/metadata HUD, stripped camera metadata)
                 │         │
                 │         └──> Thumbnail (derived directly from the canonical evidence artifact)
                 │
                 ▼
      Downstream surfaces & export
      [Single-HUD invariant: render the canonical evidence artifact directly; never reconstruct a second HUD]
```

### Cloud data model

```
sites/{siteId}                  (documents where creator_id == uid)
sites/{siteId}/media/{mediaId}  (documents where creator_id == uid)

users/{uid}/originals/{siteId}/{mediaId}.jpg   (or .mp4)
users/{uid}/evidence/{siteId}/{mediaId}.jpg
users/{uid}/thumbnails/{siteId}/{mediaId}.jpg
```

Cloud artifacts are write-once: they can never be overwritten or physically deleted by the client. Local deletion produces soft-delete tombstones that reconcile asynchronously — the cloud copy is never touched.

---

## Directory Structure

```text
lib/
├── app/            — root widget, routing, theme, Firebase options
├── core/           — cross-cutting: errors, permissions, connectivity, utilities, constants
├── data/           — local (Drift database, files), Firebase repositories, repository implementations
├── domain/         — entities, repository interfaces, framework-free services
├── features/       — one directory per feature:
│   ├── auth/           — login, sign-up, email verification, password reset
│   ├── onboarding/     — permission onboarding and recovery
│   ├── sites/          — project/site selection, creation, deletion
│   ├── camera/         — viewfinder, live HUD, capture, evidence processing (HUD data/layout/formatter, isolate pipeline)
│   ├── review/         — Review & Tag, video handoff/recovery
│   ├── gallery/        — local media library, virtualization, maps, media detail, export
│   ├── nearby/         — nearby-media search, spatial uncertainty, before/after pairing
│   ├── sync/           — Firebase sync coordination, queue lifecycle, cloud recovery
│   ├── google_photos/  — optional auxiliary backup channel (independent OAuth scope)
│   ├── settings/       — GPS, watermark, storage, sync, account deletion
│   └── support/        — user enquiry submission (App Check-gated Cloud Function)
├── shared/         — shared widgets, models, extensions
└── main.dart       — entrypoint (Firebase, App Check, Riverpod)
```

---

## Specification Documents

SiteLens's normative specification is organized as a layered set of documents under `docs/specification/`. No single document duplicates another's authority:

| Document | Defines |
|---|---|
| `01_PRD.MD` | **WHAT** the product is and **WHY** it exists — product scope, user workflow, functional requirements |
| `02_ARCHITECTURE.MD` | **HOW** the product is technically built — stack, layering, data model, subsystem contracts |
| `03_DESIGN.MD` | **HOW** the product should look and feel — visual design system, interaction patterns, accessibility |
| `04_SECURITY.MD` | The threat model, security invariants, and control set an implementation must satisfy |
| `05_ACCEPTANCE.MD` | Objective pass/fail conditions for Phase 1 completion |
| `06_TESTING.MD` | The verification strategy mapping each acceptance criterion to a test level |

`01_PRD.MD` is the primary authority for product behavior and scope. A fresh implementation team can build SiteLens from scratch using these documents alone.

---

## Verification & Testing

All automated verification gates are passing on the current codebase baseline:

| Verification Layer | Status | Notes |
|---|---|---|
| Flutter unit & widget tests | 843 / 843 PASS | Models, repositories, isolate formatting, GPS utilities, HUD, camera, gallery, detail |
| Static analysis (`flutter analyze`) | 0 issues | Strict zero-warning / zero-lint policy |
| Security rules test suite | 89 / 89 PASS | Firestore isolation, write-once storage rules, token checks |
| Cloud Functions (`functions/`) | 43 / 43 PASS | Enquiry submission, rate-limiting, account deletion |
| On-device E2E integration | 20 test groups | Real GNSS + camera on physical Android hardware |

### Running tests

```bash
# Run all unit and widget tests
flutter test

# Static analysis
flutter analyze

# Run a specific test file
flutter test test/unit/gps_status_test.dart
flutter test test/widget/camera_screen_test.dart

# Run the full on-device E2E suite (requires a physical Android device)
flutter test integration_test/all_e2e_tests.dart -d <device-id>
```

---

## Hardware & Environment Requirements

- **Flutter SDK**: `>= 3.24.0` (developed on Flutter 3.47.1, stable channel)
- **Android**: `minSdkVersion 24`, `targetSdkVersion 36` (Camera2, Google Play Services Location, App Check — Play Integrity)
- **Google Maps API Key**: Configured in `android/app/build.gradle` via the `MAPS_API_KEY` local property and in `MapThumbnailService`
- **Tested physical device**: Motorola Edge 50 Fusion (Android 16 / API 36)
- **Firebase**: a configured Firebase project with Authentication (Email/Password + Google Sign-In), Cloud Firestore, Cloud Storage, App Check (Play Integrity), and Cloud Functions. See `firebase.json.example` for the expected configuration.

### Development setup

```bash
# Install Flutter dependencies
flutter pub get

# Copy Firebase config from the example and fill in your project values
cp firebase.json.example firebase.json
# -> configure your google-services.json and firebase_options.dart

# Run the app on a connected device
flutter run
```

---

## Security Posture

- **Client is never the authorization boundary** — Firestore and Cloud Storage Security Rules independently enforce every access decision the client also enforces.
- **No client-held secrets** — any secret required by a Cloud Function lives only in a managed server-side secret store, accessed only from App-Check-enforced functions.
- **Hardware-backed secure storage** for authentication tokens and session identifiers.
- **Evidence files and the local database** exist exclusively within OS-provided private application storage — never a world-readable or media-library-shared location.
- **No development bypass flags** are reachable from release builds; debuggability is disabled and code shrinking (R8) is enabled in release.
- **No root/jailbreak or OS-spoofing defense** — GPS-tamper-evidence guarantees protection against post-capture alteration of the artifact only, never against a compromised device feeding spoofed location data. This limitation is stated honestly, never implied away.

A full threat model and control set is defined in `docs/specification/04_SECURITY.MD`.
