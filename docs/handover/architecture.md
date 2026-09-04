# SiteLens — Architecture
**Architecture Baseline:** v1.0 — FROZEN
**Status:** Approved baseline for Phase 1 implementation
**Change policy:** Do not modify this architecture during UI generation. Any architectural change requires an explicit architecture review and a new version.

> This file is the frozen technical baseline. UI generation and implementation must conform to it. Visual iteration must not alter architectural boundaries.

# SiteLens --- Architecture

## 1. Purpose

This document defines the technical architecture for SiteLens Phase 1.

It is derived from the approved SiteLens Phase 1 specification and
adapted for the selected implementation stack:

-   Flutter / Dart
-   Firebase Authentication
-   Cloud Firestore
-   Firebase Cloud Storage
-   SQLite/Drift for local-first data
-   Riverpod for application state

The Phase 1 specification remains the functional source of truth.

## 2. Phase 1 Scope

Phase 1 covers:

`capture → tag → store → find-nearby`

Primary flow:

`Login → Permission Onboarding → Site Setup → Camera → Review & Tag → Gallery ⇄ Media Detail → Nearby Search`

Settings and sync status are accessible from the application.

Explicitly deferred:

-   WIR builder
-   NCR builder
-   Excel/compliance export
-   full multi-user cloud synchronization as a product feature

Firebase provides the authentication, cloud persistence, media storage,
and synchronization foundation without making cloud connectivity a
prerequisite for capture.

## 3. Architectural Principles

### 3.1 Offline-first

Site engineers may work without reliable network connectivity.

Capture must not depend on Firebase availability.

The application must support local capture, GPS acquisition, media
processing, hashing, local persistence, gallery browsing, nearby search,
and queued synchronization while offline.

### 3.2 Local-first media workflow

The capture pipeline is:

`Camera → Local File → Geotag/Metadata → Thumbnail → SHA-256 → Local DB → Sync Queue`

Cloud synchronization is asynchronous and must never block capture.

### 3.3 Immutable original evidence

Original captured media must never be silently overwritten.

Preserve:

-   original media
-   SHA-256 hash
-   GPS metadata
-   capture timestamp
-   structured metadata

Future annotations must remain separate from the original.

### 3.4 Separation of concerns

Separate:

-   presentation
-   application/state
-   domain
-   local persistence
-   device services
-   Firebase services
-   synchronization

UI widgets must not contain direct SQLite or Firebase implementation
logic.

## 4. High-Level Architecture

``` text
┌──────────────────────────────────────────────────────────────┐
│                         Flutter App                          │
│                                                              │
│ Presentation                                                 │
│ ├── Screens / Widgets / Theme / Navigation                   │
│ │                                                            │
│ Application & State                                          │
│ ├── Riverpod Providers / Use Cases / Sync Coordination       │
│ │                                                            │
│ Domain                                                       │
│ ├── Site / Media / GPS / Observation / Sync State            │
│ │                                                            │
│ Data & Services                                               │
│ ├── Drift / SQLite                                           │
│ ├── Local Files                                              │
│ ├── Camera / Location / Image Processing / Hashing           │
│ └── Firebase: Auth / Firestore / Storage                     │
└──────────────────────────────────────────────────────────────┘
```

## 5. Flutter Layers

### Presentation

Responsible for screens, navigation, widgets, forms, camera controls,
gallery, maps, settings, permission UI, and loading/error/empty states.

### Application

Coordinates authentication, onboarding, site selection, capture,
review/tagging, gallery, nearby search, linking, synchronization, and
retry workflows.

### Domain

Contains business concepts and rules independent of Flutter and
Firebase.

Core concepts:

-   User
-   Site
-   Media
-   GPSPosition
-   ObservationType
-   ActivityTag
-   MediaLink
-   SyncStatus

Important rules:

-   no capture before the first GPS fix
-   low GPS accuracy is preserved
-   Before/After linking requires user confirmation
-   nearby results are grouped by observation type
-   original media is immutable
-   SHA-256 is calculated at save time

### Data

Contains local repositories, local files, Firebase repositories,
authentication, storage, and synchronization.

## 6. Authentication

Firebase Authentication provides login authentication.

Authentication state must remain separate from:

-   device permission state
-   active site
-   local onboarding state

Flow:

``` text
App Launch
    ↓
Firebase Session Check
    ↓
Authenticated?
 ┌──┴──┐
 No    Yes
 ↓      ↓
Login  Onboarding/Permission Check
        ↓
Site Setup
        ↓
Camera
```

Authenticated identity does not automatically grant access to every
site. Site authorization must be enforced through the application's
access model and Firebase Security Rules.

## 7. First-Login Permission Onboarding

Permission onboarding is part of the product flow.

Handle:

-   camera
-   location
-   photos/media where required
-   microphone when required
-   notifications as optional

Represent:

-   not requested
-   requesting
-   granted
-   denied
-   denied but requestable
-   permanently denied
-   settings required

Re-check relevant permissions on launch, resume, entry to Camera,
capture initiation, and other permission-dependent workflows.

OS permission state is device state, not Firebase state.

## 8. Site Context

The active site provides:

-   Site ID
-   name
-   address
-   reference point

The active site context is required by:

-   camera
-   geotag overlay
-   review/tag
-   gallery
-   media detail
-   nearby search
-   synchronization

When offline, cached site data or the specified manual address path
should remain available.

## 9. Camera, Location & LIVE HUD Subsystem

The camera subsystem coordinates:
- Native camera viewfinder stream with tap-to-focus and aspect ratio modes (4:3, 16:9, 1:1)
- Orientation-responsive layout:
  - **Portrait**: Viewfinder over bottom shutter station with 5-row Live HUD anchored at viewfinder bottom.
  - **Landscape**: Viewfinder with right-hand 108px dedicated shutter grip station and zero control clipping.
- GNSS location stream with real-time accuracy categorization and reverse geocoding.

### LIVE Viewfinder HUD Architecture
The Live Viewfinder HUD (`lib/shared/widgets/evidence_metadata_hud_card.dart`) renders the live contextual provenance stamp from canonical `HudData`:
- **Row 1**: Site Name / Locality Headline (`10.5sp * fontScale`, bold 700) + Status Chip (`8.0sp * fontScale`, bold 900) (`VERIFIED`, `DEGRADED`, or `PENDING`).
- **Row 2**: `ADDR:` bold 700 identifier + resolved street address (`8.5sp * fontScale`, max 2 lines).
- **Row 3**: `UTC:` bold 700 + UTC timestamp ` • ` `Local:` bold 700 + local timestamp and timezone (`8.5sp * fontScale`, max 2 lines).
- **Row 4**: `Lat ` and `Long ` bold 700 + coordinates + elevation (`8.5sp * fontScale`, 1 line).
- **Row 5**: `SITE:` bold 700 + site code ` • ` `Integrity hash: Pending until saved` (or compact SHA) (`8.0sp * fontScale`, 1 line).
- **Minimap Integration**: 1.24:1 landscape-rectangular satellite map card with crosshair target pin and heading cone, matching metadata card container height and baseline, capped at 42% available width (`HudLayoutSpec.maxMinimapWidthFraction`).
- **Dynamic Font Scaling**: $\text{fontScale} = \operatorname{clamp}(\text{availableWidth} / 250.0, 0.82, 1.0)$, scaling down font size smoothly before allowing line wrapping.

## 10. Canonical Evidence Processing & HUD Architecture (Option B)

SiteLens uses **Option B: Canonical HUD Data + Canonical HUD Layout Specification + Separate Renderers**:
1. **Canonical `HudData` Contract** (`lib/features/camera/hud/hud_data.dart`):
   - Pure Dart, immutable data transfer object with zero Flutter/UI dependencies.
   - Isolate-transferable, upstream-only. Never persisted or reconstructed downstream.
2. **Canonical `HudLayoutSpec`** (`lib/features/camera/hud/hud_layout_spec.dart`):
   - Single source of truth for layout constants, dimensionless ratios (minimap aspect ratio 1.24:1, max width 42%, font scale curve), and reference design plane units (390×844 logical dp).
   - Canvas renderer scales design units to native target pixels via $s = \min(W/390, H/844)$; Flutter renderer uses $s = 1.0$.
3. **Canonical `HudFormatter`** (`lib/features/camera/hud/hud_formatter.dart`):
   - Pure-Dart formatter owning all timestamp string formatting, coordinate formatting, address fallbacks, status badge resolution, and SHA-256 truncation.
4. **Separate Renderers**:
   - **Flutter Presentation Renderer** (`EvidenceMetadataHudCard`): Reactive Flutter widgets for 60fps viewfinder overlay.
   - **Canvas Vector Renderer** (`WatermarkDrawer`): Native `dart:ui.Canvas` + `TextPainter` vector rendering for native-resolution evidence JPEGs.

### Isolate Execution Pipeline
1. **UI Isolate (Pre-Isolate Stage)**:
   - Shutter triggered -> Concurrent $T_0$ canonical minimap state capture (live GoogleMap snapshot or canonical state-matched cache; synthetic reticles strictly prohibited from evidence) resolves `Uint8List? mapTileBytes`.
   - `JpegMetadataExtractor` extracts target dimensions from EXIF header without full image decode.
   - `HudFormatter.fromSnapshot` generates canonical `HudData`.
   - `WatermarkDrawer.renderVectorHudPngFromData` executes on the UI isolate (~20ms) using `dart:ui.PictureRecorder` and `TextPainter` (requiring Flutter engine bindings), producing compressed `Uint8List hudPngBytes`.
2. **Boundary Crossing (`Isolate.run`)**:
   - Only `originalBytes`, `hudPngBytes`, and optional `targetAspectRatio` cross into the background isolate via `_IsolateInput`.
3. **Background Worker Isolate (CPU-Heavy Processing)**:
   - Pure-Dart `package:image` decodes `originalBytes`, bakes EXIF orientation, applies aspect-ratio center crop if requested, alpha-composites `hudPngBytes`, encodes Evidence JPEG at quality 95, computes Evidence SHA-256, and generates 200px thumbnail.
4. **UI Isolate (Persistence Stage)**:
   - `_IsolateOutput` returned to UI isolate; `EvidenceStorageService` saves `orig_<id>.jpg`, `evid_<id>.jpg`, and `thumb_<id>.jpg` atomically.

## 11. Local Persistence

Use SQLite through Drift.

### Sites

``` sql
sites (
  id TEXT PRIMARY KEY,
  site_code TEXT,
  name TEXT,
  address TEXT
)
```

### Media

``` sql
media (
  id TEXT PRIMARY KEY,
  site_id TEXT,
  uri TEXT NOT NULL,
  thumb_uri TEXT,
  type TEXT,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  accuracy_m REAL,
  low_accuracy INTEGER DEFAULT 0,
  activity_tag TEXT,
  observation_type TEXT,
  linked_media_id TEXT,
  note TEXT,
  captured_at TEXT NOT NULL,
  sha256_hash TEXT,
  synced INTEGER DEFAULT 0
)
```

## 12. Canonical Three-Tier Evidence File Model & Downstream Pipeline

``` text
Camera Shutter
      │
      ├──> orig_<id>.jpg   (Pristine original capture, untouched)
      │
      └──> EvidenceProcessingService (Isolate)
                 │
                 ├──> evid_<id>.jpg   (Canonical Evidence JPEG with burned Minimap + Metadata HUD)
                 │         │
                 │         └──> thumb_<id>.jpg (Thumbnail derived directly from evid_<id>.jpg)
                 │
                 ▼
      Downstream Surfaces & Export
      [Single-HUD Invariant: Render evid_<id>.jpg directly with ZERO secondary HUD reconstruction]
```

### The Single-HUD Downstream Invariant
> **Create HUD once → burn it once → store it once → display/export it without reconstructing another HUD.**

- **Review & Tag**: Renders canonical `evid_<id>.jpg` using `BoxFit.contain`. Zero external HUD card widgets.
- **Gallery**: Loads `thumb_<id>.jpg` (derived from canonical evidence) in virtualized grid.
- **Photo Evidence Detail**: Displays full `evid_<id>.jpg` with `BoxFit.contain` and interactive zoom.
- **Immersive Evidence Viewer**: Fullscreen darkroom viewport rendering `evid_<id>.jpg`.
- **Share Sheet**: Shares canonical `evid_<id>.jpg` file directly.
- **PDF Evidence Export**: Embeds canonical `evid_<id>.jpg` via `pw.BoxFit.contain` in `pw.Center`, ensuring 100% visible HUD with zero margin clipping.
- **ZIP Export**: Packages canonical `evid_<id>.jpg` with structured metadata JSON/CSV.

## 13. Nearby Media Search

Nearby search is local in Phase 1.

Algorithm:

``` text
Target coordinate
      ↓
Bounding box
      ↓
Indexed SQLite query
      ↓
Candidate records
      ↓
Haversine distance
      ↓
Radius filtering
      ↓
Sort by distance
      ↓
Group by observation type
```

Filters:

-   same site
-   activity
-   observation type
-   date range
-   radius

Results are sorted by distance, then recency.

No spatial database extension is required for the approximately
1,000-item Phase 1 target.

## 14. Non-Conformity & Resolution (Before/After) Linking

For a `Closed` observation (silently treated as `After`):

``` text
Closed observation capture
    ↓
Nearby local search
    ↓
Same site
    ↓
Same activity
    ↓
Observation = Non-Conformity (silently treated as Before)
    ↓
Captured earlier
    ↓
Default radius = 10m
    ↓
Nearest plausible result
    ↓
User confirmation
    ↓
Create media link
```

The system must never create the link without user confirmation.

## 15. Gallery

The Gallery operates against the local database and must support:

-   1,000+ items
-   virtualized rendering
-   thumbnail-first loading
-   filters
-   search
-   grid/map views
-   sync status
-   low-accuracy filtering

Do not decode full-resolution images for the entire grid.

## 16. Firebase

### Authentication

Firebase Authentication provides login and session identity.

### Firestore

Recommended conceptual structure:

``` text
users/{uid}

sites/{siteId}

sites/{siteId}/members/{uid}

sites/{siteId}/media/{mediaId}
```

Firestore stores cloud metadata and synchronization state; it does not
replace the local operational database.

### Cloud Storage

Recommended conceptual paths:

``` text
sites/{siteId}/media/{mediaId}/original
sites/{siteId}/media/{mediaId}/thumbnail
```

Exact conventions can be refined during implementation.

## 17. Synchronization

Synchronization is asynchronous.

``` text
Local Media
    ↓
Sync Queue
    ↓
Connectivity?
 ┌──┴──┐
 No    Yes
 ↓      ↓
Queue  Upload original
        ↓
     Upload thumbnail
        ↓
     Firestore metadata
        ↓
     Confirm success
        ↓
     Mark local record synced
```

Support:

-   pending
-   uploading
-   synced
-   failed
-   retrying

A failed upload must never delete or invalidate the local original.

## 18. Data Authority

During offline operation:

**Local SQLite + local media files are authoritative for the device's
working dataset.**

Firebase is the cloud synchronization target.

Avoid destructive synchronization.

Future multi-device conflict resolution is outside Phase 1 scope.

## 19. Integrity / Chain of Custody

SHA-256 is calculated immediately when media is saved.

The architecture must preserve:

-   immutable original pixels
-   corresponding SHA-256 hash
-   GPS metadata
-   visible geotag
-   separate annotation layers

## 20. State Management

Use Riverpod unless the existing project already has a sound equivalent.

Important state domains:

-   authentication
-   onboarding
-   permissions
-   active site
-   GPS
-   camera
-   capture
-   review/tag
-   gallery filters
-   nearby search
-   media detail
-   sync queue
-   settings

Transient UI state should remain separate from persistent domain state.

## 21. Navigation

``` text
Welcome
  ↓
Login
  ↓
Permission Onboarding
  ↓
Site Setup
  ↓
Camera
  ├── Gallery
  │     └── Media Detail
  │            └── Nearby Search
  ├── Review & Tag
  └── Settings
```

Navigation must preserve active site and relevant media context.

## 22. Error Handling

Handle at minimum:

-   authentication failure
-   offline authentication/session issues
-   denied/permanently denied permissions
-   GPS unavailable
-   poor GPS accuracy
-   camera failure
-   storage failure
-   media processing failure
-   hash failure
-   Firebase upload failure
-   Firestore failure
-   synchronization failure

Errors must never cause loss of locally captured evidence.

## 23. Security

Firebase Security Rules must restrict cloud data according to
authenticated identity and site membership.

The Flutter client is not the final authorization boundary.

Do not embed service-account credentials or other privileged secrets in
the application.

## 24. Performance

For the Phase 1 target of approximately 1,000 media items:

-   generate thumbnails at capture
-   use lazy/virtualized gallery rendering
-   index local search fields
-   use bounding-box filtering before Haversine refinement
-   avoid full-resolution gallery decoding
-   avoid unnecessary processing during capture

Do not introduce a spatial database prematurely.

## 25. Settings

Settings include:

-   GPS accuracy threshold
-   high-accuracy GPS mode
-   watermark template
-   address visibility
-   cache/storage controls
-   thumbnail regeneration
-   clear synced originals locally
-   physical local deletion (Delete from Device / Remove from Gallery)
-   cloud media recovery & SHA-256 verification pipeline
-   sync queue

### Storage Lifecycle & Deletion Architecture (M7-02-II-B)

1. **Local Media Artifacts**:
   - Photo: Raw original (`orig_{id}.jpg`), derived evidence with stamp (`evid_{id}.jpg`), and gallery thumbnail (`thumb_{id}.jpg`).
   - Video: Video file (`orig_{id}.mp4`) and first-frame thumbnail (`thumb_{id}.jpg`).
2. **Delete from Device**: Physically removes all local media files (`orig_*`, `evid_*`, `thumb_*` for photos; `orig_*`, `thumb_*` for videos) belonging to the item from device storage to fully reclaim storage space. The SQLite database record is preserved (`is_deleted = 0`) to maintain cloud identity and enable subsequent on-demand recovery, while the immutable cloud backup remains intact.
3. **Remove from Gallery / Archive**: Physically removes all local media files belonging to the item and marks the SQLite record as soft-deleted (`is_deleted = 1`) to remove/hide the item from the local Gallery/Archive presentation, while preserving the immutable cloud copy.
4. **Cloud Permanence Invariant**: Neither local deletion operation deletes the cloud copy. Local deletion NEVER invokes Firebase Storage deletion (`storage.rules` enforces `allow delete: if false;`) or Firestore document deletion. Cloud copies remain write-once immutable.
5. **Destructive Warning**: Unsynced media deletion strictly requires an explicit destructive warning dialog before local files are unlinked.
6. **Cloud Recovery**: `CloudMediaRecoveryService` provides atomic download from Firebase Cloud Storage, SHA-256 validation against `MediaItem.sha256Hash`, and atomic promotion to local storage for both photos and videos.

Device/application settings are local unless future requirements justify
cloud preferences.

## 26. Testing

### Unit

Test:

-   Haversine distance
-   bounding-box calculation
-   nearby filtering
-   Before/After matching
-   GPS accuracy classification
-   SHA-256 generation
-   synchronization state transitions

### Widget

Test:

-   authentication states
-   permission onboarding
-   GPS states
-   camera controls
-   review/tagging
-   smart-link prompt
-   gallery filtering
-   nearby grouping
-   settings
-   sync status

### Integration

Test:

-   login → onboarding → site setup
-   capture → local save
-   offline capture
-   gallery
-   nearby search
-   Before/After linking
-   reconnect → synchronization
-   failed synchronization → retry

## 27. Recommended Flutter Structure

``` text
lib/
├── app/
│   ├── app.dart
│   ├── router/
│   └── theme/
│
├── core/
│   ├── errors/
│   ├── permissions/
│   ├── connectivity/
│   ├── utilities/
│   └── constants/
│
├── features/
│   ├── auth/
│   ├── onboarding/
│   ├── sites/
│   ├── camera/
│   ├── media_review/
│   ├── gallery/
│   ├── media_detail/
│   ├── nearby_search/
│   ├── settings/
│   └── sync/
│
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── services/
│
├── data/
│   ├── local/
│   │   ├── database/
│   │   └── files/
│   ├── firebase/
│   │   ├── auth/
│   │   ├── firestore/
│   │   └── storage/
│   └── repositories/
│
└── shared/
    ├── widgets/
    ├── models/
    └── extensions/
```

This is a recommended target structure, not a requirement to rewrite an
existing sound implementation.

## 28. Design Relationship

`design.md` is the visual design source of truth.

Google Stitch is used to generate and refine the visual design.

Flutter implements the approved designs.

The design system should provide reusable:

-   colors
-   typography
-   spacing
-   radii
-   elevation
-   buttons
-   cards
-   badges
-   media components
-   permission components
-   camera controls

## 29. Deferred Architecture

Do not implement unnecessary Phase 2 complexity.

Deferred capabilities include:

-   WIR generation
-   NCR generation
-   Excel/compliance export
-   full reporting layer
-   server-side spatial search
-   multi-device conflict resolution
-   full server-side video frame burn-in
-   advanced spatial indexing

The Phase 1 media model retains the metadata needed by future reporting
functionality.

## 30. Decision Summary

  Area                Decision
  ------------------- ------------------------------------------------
  Mobile              Flutter
  Language            Dart
  Authentication      Firebase Authentication
  Cloud database      Cloud Firestore
  Cloud media         Firebase Cloud Storage
  Local database      SQLite via Drift
  State               Riverpod
  Architecture        Layered, feature-oriented Flutter architecture
  Offline strategy    Local-first
  Nearby search       Local SQLite + bounding box + Haversine
  Media               Local originals + thumbnails
  Integrity           SHA-256
  UI design           Google Stitch + design.md
  Functional source   SiteLens Phase 1 specification
  Cloud sync          Asynchronous local queue

## 31. Implementation Rule

When a decision is unclear:

1.  Follow the Phase 1 specification.
2.  Preserve offline-first behavior.
3.  Preserve inspection evidence integrity.
4.  Reuse the existing Flutter architecture when it is sound.
5.  Keep Firebase behind repository/service boundaries.
6.  Keep UI concerns out of data/services.
7.  Prefer the simplest architecture that satisfies Phase 1.
8.  Do not introduce future-phase complexity prematurely.

## 32. Camera Optical Subsystem & Hybrid Minimap Architecture

### 32.1 Optical Viewfinder & Sensor Fidelity
- **Native 4:3 Sensor Aspect Ratio**: Viewfinder framing strictly preserves native optical sensor dimensions without digital crop or letterboxing distortion.
- **Hardware Zoom Boundaries**:
  - Rear Camera: Default 0.5x wide angle clamped dynamically to Camera2 optical sensor minimum.
  - Front Camera: Default 1.0x native fixed-focal-length optical resolution.
- **Lifecycle Resilience**: `AppLifecycleState.inactive` maintains active optical stream during OS screenshots and notification drawer events.

### 32.2 Minimap Engine: Display Fallback vs. Evidence Provenance
- **Authoritative Invariant**: The Evidence JPEG MUST contain the same minimap map state/source that the user sees in the live Camera Capture minimap at shutter time. The map representation/state at shutter time must be burned into the JPEG. Downstream viewers (Photo Evidence Detail and Immersive Evidence Viewer) display those burned-in pixels and do not independently re-render or fetch the minimap.
- **Viewfinder Display Fallback**:
  * **Primary Surface**: Interactive `GoogleMap` widget with Normal (vector) or Satellite layer at Zoom 18.0.
  * **Display Fallbacks**: High-DPI disk cache (`300x300` @ `scale=2`) or offline indicator used strictly in viewfinder presentation to prevent UI shift while acquiring map tiles.
- **Evidence Provenance Pipeline**:
  * **Concurrent $T_0$ Snapshot**: Native live map snapshot taken at shutter time concurrently with optical camera capture.
  * **Canonical State-Matched Cache Fallback**: Used only when matching active `mapType`, displacement $\le 20\text{m}$, and age $\le 5\text{min}$.
  * **Synthetic Vector Reticle Prohibited**: Synthetic vector reticles (fabricated roads/grids) are completely removed from evidence content and never burned into evidence JPEGs.
- **Layout Stability**: Locked container bounds (1.24:1 aspect ratio, $\le 42\%$ HUD width) with `AnimatedSwitcher` 250ms cross-fade.

## 33. Support & User Enquiry Subsystem (Resend Integration)

### 33.1 Serverless Cloud Architecture
- **Callable Endpoint**: Firebase 2nd-gen Cloud Function `submitUserEnquiry` (`functions/index.js`) deployed in `us-central1`.
- **Zero Client Secrets**: `RESEND_API_KEY` is stored exclusively in **Google Cloud Secret Manager** and bound solely to `submitUserEnquiry`.
- **App Check Verification**: Enforces Firebase App Check (`enforceAppCheck: true`) to block non-app / bot automated traffic.
- **Persistent Rate Limiting**: Firestore-backed rate limiter (`_system_rate_limits/enquiry_<uid|ip>`) enforcing a strict maximum of 5 submissions per 10-minute sliding window.
- **Idempotency & Duplicate Protection**: Client generates a unique UUID `submissionId` sent in the payload and forwarded to Resend as the `Idempotency-Key` header, with completed records cached in Firestore `enquiries/{submissionId}`.

### 33.2 Email Dispatch & Sanitization
- **HTTP Transport**: Node.js native `fetch` calling `https://api.resend.com/emails` (no external SDK or CLI dependencies).
- **Sanitization**: Strict server-side validation and HTML entity escaping (`escapeHtml`) on all user inputs before email assembly.
- **Email Routing**:
  - `From`: Verified SiteLens sender (`support@sitelens.app`)
  - `To`: SiteLens support inbox (`support@sitelens.app`)
  - `Reply-To`: Submitter's email address for direct engineering replies
  - `Body`: Formatted HTML card + plain-text fallback containing Category, Submitter details, and Message.
