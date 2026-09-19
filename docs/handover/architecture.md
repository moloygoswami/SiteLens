# SiteLens — Architecture
**Architecture Baseline:** v1.1 — RECONCILED WITH PRD v1.0  
**Status:** Approved baseline for Phase 1 implementation & Phase 2 remediation  
**Change policy:** Any architectural change requires an explicit architecture review.

> This file is the authoritative technical baseline. Implementation must conform strictly to it. Visual iteration and refactoring must not alter architectural boundaries.

# SiteLens --- Architecture

## 1. Purpose & Product Boundary

This document defines the technical architecture for SiteLens Phase 1.

It is derived from the approved SiteLens Product Requirements Document ([`docs/handover/PRD.md`](file:///home/moloy/workspace/products/SiteLens/docs/handover/PRD.md)) and defines HOW the approved PRD product boundary is technically enforced across the implementation stack:

-   Flutter / Dart
-   Firebase Authentication
-   Cloud Firestore
-   Firebase Cloud Storage
-   SQLite/Drift for local-first data
-   Riverpod for application state

The approved PRD remains the authoritative functional and product source of truth.

### 1.1 Authoritative V1 Product Model: Single-Tenant Creator Ownership

**SiteLens v1 is user-specific, creator-owned, location-independent, and non-collaborative.**

- **Independent Personal Data Domain**: Each authenticated user operates strictly within an independent, isolated personal SiteLens data domain.
- **Multi-Site Management**: A single user may independently create and manage multiple construction sites.
- **Physical Construction Site Reality**: Multiple independent users may work at the same physical construction site, project, or location.
- **Location Independence & Proximity Non-Authorization**: Physical co-location, shared site codes, matching site names, identical addresses, or shared GPS coordinates **never** grant access or authorization between users:
  $$\text{same physical site} \ne \text{shared data}$$
  $$\text{same site code} \ne \text{authorization}$$
  $$\text{same address} \ne \text{authorization}$$
  $$\text{same GPS} \ne \text{authorization}$$
- **Zero Cross-User Data Access**: User A must never access User B's SiteLens data under any circumstances. This non-accessibility invariant applies to all application resources:
  * sites
  * evidence / media records
  * original photos and videos (`orig_<id>`)
  * derived evidence photos (`evid_<id>`) and thumbnails (`thumb_<id>`)
  * local and cloud galleries
  * local SQLite / Drift database records
  * active-site selection context
  * pending captures and uncommitted work
  * synchronization queues and retry state
  * soft-delete tombstones
  * Cloud Firestore records and Cloud Storage media objects
- **Authorization Boundary**: In SiteLens v1, the authorization boundary is strictly the authenticated user's identity:
  $$\text{creator\_id} == \text{authenticated Firebase Auth UID}$$

## 2. Phase 1 Scope & Deferred Non-Goals

Phase 1 covers:

`capture → tag → store → find-nearby → optional cloud synchronization`

Primary flow:

`Login → Permission Onboarding → Site Setup → Camera → Review & Tag → Gallery ⇄ Media Detail → Nearby Search`

Settings, storage cleanup, cloud media recovery, and sync status are accessible from the application.

### 2.1 Non-Goals and Deferred Capabilities (FUTURE SCOPE — NOT IMPLEMENTED IN V1)

The following collaborative, multi-user, and enterprise capabilities are **NOT** implemented in v1 and are explicitly reserved for future product phases:

-   shared sites
-   site membership and member invitations
-   member roles and administrator roles
-   role-based access control (RBAC)
-   member-based authorization and evidence access
-   revoked-member access handling
-   successor-admin ownership and ownership transfers between users
-   shared-site account deletion retention
-   team workspaces and cross-user collaboration
-   WIR (Work Inspection Request) builder
-   NCR (Non-Conformance Report) builder
-   Excel / CSV compliance tabular exports
-   centralized web management dashboard
-   server-side spatial search
-   full per-frame video geotag burn-in
-   automated evidence linking without user confirmation

Firebase provides the authentication, cloud persistence, media storage, and synchronization foundation without making cloud connectivity a prerequisite for capture.

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

## 6. Authentication, Authorization & Session Transition Architecture

Firebase Authentication provides login and user session identity (`request.auth.uid`).

### 6.1 Authentication vs. Authorization Boundary

SiteLens strictly separates authentication from authorization:

- **Authentication Boundary**: Establishes cryptographic proof of user identity via Firebase Auth (Email/Password or Google Sign-In), yielding the unique authenticated identifier (`request.auth.uid`).
- **Authorization Boundary**: Governs whether the authenticated user has permission to read, write, or delete a resource. In SiteLens v1, authorization is strictly **single-tenant creator-owned**:
  $$\text{Authorized} \iff \text{resource.creator\_id} == \text{request.auth.uid}$$
  Authorization is never granted by site membership, admin status, site code, site name, street address, GPS coordinates, or physical proximity.

### 6.2 Distinct Architectural Roles & Non-Interchangeable Identities

To prevent provenance corruption, the architecture strictly distinguishes four non-interchangeable identities:

1. **Capture Creator (`creator_id`)**: The immutable UID of the authenticated user who initiated the capture at shutter time. Recorded at the shutter instant, permanently burned into evidence metadata, and cryptographically anchored in Firestore. Cannot be altered or rewritten by any downstream operation.
2. **Current Authenticated User (`request.auth.uid`)**: The user currently signed into the client session. Scopes local SQLite queries, controls sync worker authorization, and gates cloud write permissions.
3. **Viewer**: The user inspecting an evidence item in Media Detail or the Gallery. In v1, the viewer is always identical to the capture creator due to single-tenant isolation.
4. **Exporter**: The user triggering a PDF report, ZIP package, or Share action. The exporter's identity must NEVER overwrite the capture creator's identity on exported artifacts.

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
       Site Setup (Creator-Owned Sites Only)
        ↓
       Camera
```

### 6.3 Multi-User Session Transition Architecture (Session/Local Isolation; R04)

On shared physical mobile devices, User A may sign out and User B may sign in. The architecture enforces the **Multi-User Session Isolation Invariant**:

$$\text{User A Session Teardown} \implies \text{Zero User A Data Exposed to User B}$$

When a user signs out, `AuthController` triggers a synchronous and asynchronous teardown sequence across all architectural layers:

1. **Reactive Provider Invalidation**: All Riverpod stream providers and state notifiers (`siteControllerProvider`, `galleryControllerProvider`, `syncCoordinatorProvider`, `activeSiteProvider`) are invalidated (`ref.invalidate()`) and unsubscribed from local Drift streams.
2. **Session Generation Token Bump**: A monotonic session generation counter (`sessionGenerationToken`) is incremented. Any pending asynchronous callbacks, background image processing isolates, or in-flight HTTP responses tagged with the previous generation token are discarded immediately.
3. **Sync Queue Abort**: The background `SyncCoordinator` immediately aborts any in-flight uploads, cancels retry timers, and terminates worker threads.
4. **Active Site Preference Decoupling**: Active site selection is keyed by user UID in persistent storage (`sitelens_active_site_id_<uid>`). On sign-out, the in-memory active site state is cleared to null.
5. **Uncommitted Scratch Cleanup**: All temporary uncommitted capture artifacts (`media/tmp_*`) are deleted from the local sandbox.
6. **Local Cache Isolation Guarantee**: Local SQLite queries enforce fail-closed creator scoping (`where creator_id == currentUserId`). Because User B has a different UID, User B's queries return only User B's rows, guaranteeing complete local data isolation.

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

## 8. Site Context & Local-First Hydration Architecture

The active site provides:

-   Site ID (stable 20-character identifier)
-   name
-   address / location reference
-   reference point
-   creator ID

The active site context is required by:

-   camera (viewfinder HUD and forensic metadata snapshot)
-   geotag overlay (vector/canvas burning)
-   review/tag
-   gallery (site-scoped evidence listing)
-   media detail
-   nearby search
-   synchronization

### 8.1 Local-First Architecture & Data Flow

SiteLens operates strictly local-first:
1. **Startup / Session Initialization**:
   - `SiteController.loadSitesAndActiveContext()` immediately queries `LocalSiteRepository` for cached sites in Drift SQLite, scoped strictly by creator (`where creator_id == currentUserId`).
   - The user-scoped active site is restored from `SharedPreferences` (`sitelens_active_site_id_<uid>`) and validated against the user's creator-owned cached sites, or defaults to the first cached site.
   - UI renders immediately with local data without blocking on network or Firebase services.
2. **Asynchronous Remote Site Hydration**:
   - When authenticated and online, `SiteController` invokes `hydrateSites()` asynchronously.
   - `LocalSiteRepository.hydrateRemoteSites(userId)` queries Cloud Firestore strictly scoped to the creator:
     $$\text{Firestore Query: } \text{collection}(\text{'sites'}).\text{where}(\text{'creator\_id'}, \text{'=='}, userId)$$
     There is **NO** v1 hydration path using `members` collection groups, site membership, or admin roles.
   - Retrieved remote sites are upserted into Drift via `insertOnConflictUpdate`.
   - **Authoritative Remote Creator Invariant**: Remote hydration MUST NEVER overwrite or re-stamp an existing site's `creator_id` with the currently authenticated user's UID. The remote creator identity is authoritative.
   - The local site list is refreshed in state.
   - **Active-Site Invariant**: Remote hydration NEVER overrides, clears, or replaces an already active valid site. If no site was previously active, the newly hydrated sites populate the active selection.

### 8.2 Active Site Continuity Invariant

The active site context is strictly immutable with respect to network connectivity transitions:
- `Online → Offline`: Active site remains identical. No offline duplicate site is created.
- `Offline Capture`: `EvidenceMetadataSnapshot` records `siteId: activeSite.id`.
- `Offline → Online`: Network reconnection triggers media sync and background site hydration, but the active site remains untouched.
- Only an explicit user selection action via `SiteController.setActiveSite()` or user sign-out can alter the active site.

### 8.3 Evidence-to-Site Continuity

Captured evidence items (`MediaItem`) maintain an unbroken reference to `siteId`. Both online and offline captures store the identical `siteId`. Gallery queries (`watchAllMedia(siteId: activeSite.id, creatorId: currentUserId)`) naturally group online, offline, and post-reconnection captures under the same site without schema fragmentation.

### 8.4 Site Deletion Safety & Tombstone Lifecycle (Deletion Safety; R23 / Tombstone Retention/Purge; R24)

1. **Active Media Guard (R23)**: `deleteSite(siteId, creatorId)` is strictly blocked if the site contains active (non-tombstoned) media records (`hasMediaForSite`). Users must delete or reassign active media prior to site deletion.
2. **Tombstone Retention During Site Deletion (R24)**: If a site has soft-deleted media records whose cloud tombstones are pending synchronization (`is_deleted == 1`, `tombstone_reconciled == 0`), those tombstones must be preserved until cloud reconciliation succeeds.
3. **Atomic Purge (R24)**: Once all media tombstones for the site are reconciled, or for sites with zero media, the site record and associated reconciled tombstones are atomically purged in the Drift `deleteSite` transaction.

### 8.5 Source-of-Truth Model

- **Remote Authority**: Cloud Firestore (`sites/{siteId}` where `creator_id == request.auth.uid`).
- **Local Operational Cache**: Drift SQLite (`sites` table where `creator_id == currentUserId`).
- **Offline Operations**: Full operational autonomy backed by local Drift cache and app-private storage.
- **Online Reconciliation**: Deterministic, non-destructive upsert from Firestore into Drift.

## 9. Camera, Location & LIVE HUD Subsystem

The camera subsystem coordinates:
- Native camera viewfinder stream with tap-to-focus and aspect ratio modes (4:3, 16:9, 1:1)
- Orientation-responsive layout:
  - **Portrait**: Viewfinder over bottom shutter station with 5-row Live HUD anchored at viewfinder bottom.
  - **Landscape**: Viewfinder with right-hand 108px dedicated shutter grip station and zero control clipping.
- GNSS location stream with real-time accuracy categorization and reverse geocoding.

### 9.1 Capture Controls & Architectural State Locks

1. **Capture Mutex (Shutter Re-entrancy Lock; R12)**:
   - The shutter button enforces a strict re-entrancy mutex.
   - Once tapped, the shutter is immediately disabled until background isolate HUD processing, thumbnail generation, and atomic local persistence complete.
   - Prevents race conditions, corrupted multi-frame captures, or isolate worker starvation.
2. **GPS / Capture-Readiness Dependency (R02, R03)**:
   - The architecture strictly distinguishes three distinct operational readiness states:
     * **Camera Hardware Readiness**: The optical camera hardware sensor is initialized, optical preview frames are streaming, and the viewfinder surface is rendered.
     * **Evidence Capture Readiness (R02)**: All required forensic constraints are verified before capture can initiate. For inspection media requiring authoritative live GPS provenance, shutter activation is strictly gated on a valid live satellite fix:
       $$\text{Shutter Enabled} \iff \text{Camera Initialized} \land \text{hasLiveFix}$$
       If no live GPS fix has been obtained, the shutter button is disabled and displays `Waiting for GPS lock`. Camera hardware initialization does NOT imply evidence capture readiness.
     * **GPS Metadata Readiness**: Distinguishes an authoritative live GNSS fix (`hasLiveFix`) from cached/last-known seed coordinates or uninitialized receiver states. `hasLiveFix` (governed by R06) is the sole authority for live-fix readiness; cached location seeds must never unlock live evidence capture.
   - **Lifecycle Synchronization & Countdown Guard (R03)**:
     * Lifecycle synchronization between `CameraController` and `LocationService` ensures that upon app lifecycle transitions (e.g. `AppLifecycleState.resumed`), the GNSS location stream is resumed and a verified live fix is confirmed before the shutter is re-enabled.
     * **Timer Countdown GPS Loss**: If the live GPS fix is lost during an active timer countdown, the countdown is automatically paused or aborted and reverts immediately to `Waiting for GPS lock`.
3. **Video Recording Start-Time Authority ($T_0$; R07)**:
   - Authoritative video capture timestamp is anchored at the exact moment recording initiates ($T_0$).
   - This timestamp immutably governs all forensic metadata and must NEVER be overwritten or usurped by subsequent GNSS satellite fixes received during recording.
4. **Active Recording Camera/Telemetry Lock (R08)**:
   - During active video recording, the UI strictly locks camera flipping, shutter mode switching (Photo/Video), and aspect ratio toggles.
   - Prevents desynchronized video streams, corrupted aspect ratios, or broken hardware sessions.
5. **Audio Capability Disclosure (Audio Disclosure; R09)**:
   - Video evidence records explicitly record audio track presence/capability (`hasAudioTrack: bool`) in metadata.
   - Truthfully discloses whether audio was recorded rather than assuming microphone capture or leaving audio status ambiguous.

### 9.2 LIVE Viewfinder HUD Architecture
The Live Viewfinder HUD (`lib/shared/widgets/evidence_metadata_hud_card.dart`) renders the live contextual provenance stamp from canonical `HudData`:
- **Row 1**: Site Name / Locality Headline (`10.5sp * fontScale`, bold 700) + Status Chip (`8.0sp * fontScale`, bold 900) (`VERIFIED`, `DEGRADED`, or `PENDING`).
- **Row 2**: `ADDR:` bold 700 identifier + resolved street address (`8.5sp * fontScale`, max 2 lines).
- **Row 3**: `UTC:` bold 700 + UTC timestamp ` • ` `Local:` bold 700 + local timestamp and timezone (`8.5sp * fontScale`, max 2 lines).
- **Row 4**: `Lat ` and `Long ` bold 700 + coordinates + elevation (`8.5sp * fontScale`, 1 line).
- **Row 5**: `SITE:` bold 700 + site code ` • ` `Integrity hash: Pending until saved` (or compact SHA) (`8.0sp * fontScale`, 1 line).
- **Minimap Integration**: 1.24:1 landscape-rectangular satellite map card with crosshair target pin and heading cone, matching metadata card container height and baseline, capped at 42% available width (`HudLayoutSpec.maxMinimapWidthFraction`).
- **Dynamic Font Scaling**: $\text{fontScale} = \operatorname{clamp}(\text{availableWidth} / 250.0, 0.82, 1.0)$, scaling down font size smoothly before allowing line wrapping.

### 9.3 GPS Freshness & Sensor Provenance Architecture

- **Live GPS Fix / Cached GPS (R06)**: Shutter readiness strictly requires a live, verified fix (`hasLiveFix => hasValidFix && !isLastKnownSeed`). Stale cached location seeds from prior sessions or lifecycle pauses must never enable the shutter before a live GNSS fix is acquired.
- **Observed GNSS Coordinates**: Recorded coordinates represent observed GNSS receiver fixes, never synthetic, interpolated, or estimated coordinates.
- **Unknown Telemetry Semantics & Sensor Fallback (R10)**: Compass heading, altitude, and GNSS satellite telemetry are recorded when available from hardware sensors; when unestablished or unavailable, values remain explicitly null/unknown with graceful UI fallback, without synthetic fabrication (no zero-filling).
- **Minimap Race Guard (R11)**: Shutter-time minimap snapshot capture utilizes monotonic generational tokens to prevent race conditions or stale frame capture. Cached minimap imagery may serve as fallback only when displacement $\le 20\text{m}$, age $\le 5\text{min}$, and map type matches.

### 9.4 Video Handoff, Interrupted Recording Recovery & Playback Lifecycle Architecture (Video Handoff / Player Lifecycle; R13)

1. **Video Player Controller Lifecycle**:
   - Manages single-instance playback ownership (`EvidenceVideoPlayback`) to manage underlying hardware decoders and prevent platform view leaks or audio focus collisions across navigation transitions.
2. **In-Flight Recording Reference Cleanup**:
   - When a video recording stops, fails, or is cancelled, in-flight file descriptors, active camera stream locks, and temporary buffer handles are safely released and unlinked.
3. **Stop / Handoff Lifecycle**:
   - The transition from optical video recording to persistence executes as an atomic handoff: recording stop confirms file integrity and computes thumbnail before navigation to Review & Tag.
4. **Interrupted Recording Recovery**:
   - If the application is backgrounded, interrupted by an incoming phone call, or killed by the OS during active video recording, the initialization pipeline detects incomplete or interrupted video artifacts on subsequent launch.
5. **Keep for Later / Discard Recovery Semantics**:
   - Interrupted recordings prompt the user on app resume with explicit, non-destructive choices:
     * **Keep for Later**: Preserves the recorded video fragment, creates an uncommitted evidence record, and enqueues it for user tagging.
     * **Discard**: Safely unlinks the temporary file and cleans up all related resources.

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
   - Pure-Dart `package:image` decodes `originalBytes`, bakes EXIF orientation into the pixels, applies aspect-ratio center crop if requested, strips all EXIF metadata from the derived artifacts, alpha-composites `hudPngBytes`, encodes Evidence JPEG at quality 95, computes Evidence SHA-256, and generates 200px thumbnail.
4. **UI Isolate (Persistence Stage)**:
   - `_IsolateOutput` returned to UI isolate; `EvidenceStorageService` saves `orig_<id>.jpg`, `evid_<id>.jpg`, and `thumb_<id>.jpg` atomically.

### EXIF / Derived-Artifact Metadata Policy

- The immutable original (`orig_<id>`) is preserved exactly as captured,
  including whatever EXIF metadata the camera produced.
- Derived artifacts (`evid_<id>`, `thumb_<id>`) must not silently inherit
  camera EXIF: orientation is baked into the pixels first, then all EXIF
  metadata is stripped before encoding, so derived evidence cannot carry
  unverified device claims (device GPS, timestamps, make/model) that
  contradict the canonical capture-time metadata.
- Canonical evidence metadata lives in the capture-time snapshot, the
  local ledger, and the burned-in HUD — never in reconstructed EXIF.

### Capture-Time Metadata Authority

- A synchronous metadata snapshot taken at the shutter instant is the
  authoritative record for evidence: coordinates, accuracy, altitude and
  its datum (MSL/WGS84/unknown), verification status, GNSS satellite
  telemetry, GNSS fix timestamp, capture timestamp, resolved address, and
  the original/evidence SHA-256 hashes.
- Values that were not established at capture time remain unknown
  (persisted as null) and are never replaced with synthetic or default
  values. GPS positions are never fabricated: unavailable or stale
  location data keeps the corresponding fields unknown rather than
  producing a valid-looking position.
- Video recordings snapshot the GPS authority at recording start and
  resolve the capture-time state at stop from the same capture-window
  authority; a normal stop is never reclassified as an interruption.
- The burned-in HUD and all display surfaces are renderings of this
  snapshot, not independent metadata sources.

### 10.2 Review & Tag Lifecycle: PopScope & Temporary Artifact Cleanup (PopScope / Cleanup; R14)

1. **Back / Dismiss Handling via PopScope**:
   - The Review & Tag screen intercepts back navigation, hardware back buttons, and gesture pops using `PopScope(canPop: false, onPopInvokedWithResult: ...)` to protect newly captured, uncommitted media.
2. **Uncommitted Capture Protection**:
   - Navigating away from uncommitted media triggers an explicit confirmation dialog, preventing accidental loss of inspection photos or videos before metadata, activity tags, and notes are committed.
3. **Cleanup Lifecycle & Orphan File Prevention**:
   - If the user explicitly cancels or discards an uncommitted capture (e.g. selecting "Retake" or "Discard"), the cleanup lifecycle physically unlinks all associated temporary files (`orig_<id>`, `evid_<id>`, `thumb_<id>`, and any temporary isolate buffers) from the local filesystem.
   - This prevents silent disk bloat and ensures orphan uncommitted artifacts never accumulate in private app storage.
   - Atomic database commit occurs only when the user confirms "Save" or "Done", transitioning temporary files to canonical local storage.

## 11. Local Persistence & Fail-Closed Creator Scoping Architecture

Use SQLite through Drift. The verified schema version is v9 (Drift migration adding `creator_id` and safe tombstone lifecycle columns).

### 11.1 Local Data-Domain Isolation Invariant (Session/Local Isolation; R04)

The architecture guarantees strict physical and logical separation between independent user data domains:

$$\text{User A Local Data} \cap \text{User B Local Data} = \emptyset$$

To prevent cross-user leakage on shared devices or unauthenticated states, the repository layer enforces **Fail-Closed Creator Scoping**:

- **Fail-Closed Rule**: A null, empty, unresolved, or unavailable authenticated UID **MUST NEVER** fall back to an unscoped local query:
  ```dart
  if (creatorId == null || creatorId.isEmpty) {
    return []; // Fail closed: Never return records across users when unauthenticated
  }
  ```
- **Scope Enforcement Across All Local Datasets**:
  1. **Sites**: `select(sites)..where((tbl) => tbl.creatorId.equals(authenticatedUid))`
  2. **Media & Evidence**: `select(media)..where((tbl) => tbl.creatorId.equals(authenticatedUid))`
  3. **Active-Site State**: Persisted per-user in `SharedPreferences` (`sitelens_active_site_id_<uid>`) and validated against creator-owned sites.
  4. **Pending Captures & Uncommitted Work**: Temporary files (`media/tmp_*`) are tied to session tokens and purged upon sign-out.
  5. **Synchronization Queue**: `getUnsyncedMedia(creatorId: authenticatedUid)` processes only records owned by the active user.
  6. **Tombstones**: Soft-deleted records (`is_deleted == 1`) are scoped to `creator_id == authenticatedUid`.
  7. **Reactive Stream Queries**: `watchAllMedia(..., creatorId: authenticatedUid)` streams are filtered strictly by creator UID.
  8. **Cached Metadata & Geocodes**: Persisted metadata rows strictly bind to `creator_id`.

### 11.2 Sites Table Schema

``` sql
sites (
  id TEXT PRIMARY KEY,
  site_code TEXT,
  name TEXT,
  address TEXT,
  creator_id TEXT                        -- Creator user UID for per-user site scoping (Added in v7)
)
```

### 11.3 Media Table Schema

``` sql
media (
  id TEXT PRIMARY KEY,
  site_id TEXT REFERENCES sites(id),
  original_uri TEXT DEFAULT '',          -- relative path of the immutable original
  uri TEXT NOT NULL,                     -- derived evidence artifact
  thumb_uri TEXT,                        -- derived thumbnail
  type TEXT,                             -- 'photo' | 'video'
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  accuracy_m REAL,                       -- null = unknown
  low_accuracy INTEGER DEFAULT 0,
  altitude_m REAL,                       -- null = unknown
  activity_tag TEXT,
  observation_type TEXT,                 -- 'progress'|'nonConformity'|'closed'|'material'|'general'
  linked_media_id TEXT REFERENCES media(id),
  note TEXT,
  captured_at TEXT NOT NULL,
  sha256_hash TEXT,                      -- SHA-256 of the original artifact
  evidence_sha256_hash TEXT,             -- SHA-256 of the derived evidence artifact
  captured_address TEXT,                 -- reverse-geocoded address at capture time
  creator_id TEXT,                       -- creator user UID (sync authorization + isolation)
  verification_status TEXT,              -- 'verified'|'degraded'|'pending'; null = unknown
  is_altitude_msl INTEGER,               -- 1 = MSL, 0 = WGS84, null = unknown datum
  gnss_satellite_count INTEGER,
  gnss_satellites_used_in_fix INTEGER,
  gnss_fix_timestamp TEXT,
  synced INTEGER DEFAULT 0,              -- 0 pending, 2 syncing, 1 synced, 3 failed
  is_deleted INTEGER DEFAULT 0,          -- hidden tombstone state
  tombstone_reconciled INTEGER DEFAULT 0 -- 1 if remote tombstone propagated or never published
)
```

Nullable metadata columns mean "not established at capture time" and are never back-filled with synthetic values. Capture is gated on a first valid GPS fix (`hasLiveFix`), so coordinates are always real observed values.

## 12. Canonical Three-Tier Evidence File Model & R16 Architecture Decision

``` text
Camera Shutter
      │
      ├──> orig_<id>.jpg   (Pristine original capture, untouched with hardware EXIF)
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

### 12.1 The Single-HUD Downstream Invariant
> **Create HUD once → burn it once → store it once → display/export it without reconstructing another HUD.**

- **Review & Tag**: Renders canonical `evid_<id>.jpg` using `BoxFit.contain`. Zero external HUD card widgets.
- **Gallery**: Loads `thumb_<id>.jpg` (derived from canonical evidence) in virtualized grid.
- **Photo Evidence Detail**: Displays full `evid_<id>.jpg` with `BoxFit.contain` and interactive zoom.
- **Immersive Evidence Viewer**: Fullscreen darkroom viewport rendering `evid_<id>.jpg`.
- **Share Sheet**: Shares canonical `evid_<id>.jpg` file directly.
- **PDF Evidence Export**: Embeds canonical `evid_<id>.jpg` via `pw.BoxFit.contain` in `pw.Center`, ensuring 100% visible HUD with zero margin clipping.
- **ZIP Export**: Packages canonical `evid_<id>.jpg` with structured metadata JSON/CSV.

### 12.2 R16 Architecture Decision: Cloud Evidence Artifact Replication

**Decision**: **Option A — `evid_<id>.jpg` is replicated to Cloud Storage as a cloud-authoritative evidence artifact.**

#### Technical Evaluation & Rationale:

1. **Byte-Level Preservation of Capture-Time Content**:
   The finalized burned evidence artifact contains exact byte-level presentation content, including capture-time HUD/minimap content and JPEG encoding. Future client rendering, JPEG encoding, or external map imagery cannot be relied upon to reproduce identical bytes. Therefore replicating the finalized `evid_<id>.jpg` preserves the exact artifact and permits live byte verification against its stored `evidence_sha256_hash` without depending on future rendering behavior.
2. **Capture-Time Minimap Availability**:
   The burned HUD incorporates satellite minimap imagery captured at shutter time ($T_0$). If `evid_` were not stored in the cloud, reconstructing it on another device or after reinstallation would require re-fetching map imagery. In offline environments or if satellite tiles have changed since capture, the authentic visual context of the inspection is permanently lost.
3. **Two-Tier Cryptographic Verification**:
   Option A fully preserves two-tier verification semantics:
   - `sha256_hash` verifies the raw original camera bytes (`orig_<id>`).
   - `evidence_sha256_hash` verifies the burned canonical evidence artifact (`evid_<id>`).
   Both hashes are computed on the capture device at save time and verified against downloaded cloud artifacts.
4. **Export & Recovery Parity**:
   Recovered media can immediately produce valid PDF and ZIP compliance exports on any device without executing CPU-heavy isolate compositing pipelines or requiring high-bandwidth original image downloads.
5. **Storage Overhead Justification**:
   Storing compressed `evid_<id>.jpg` (~1–2 MB) alongside `orig_` (3–8 MB) incurs a modest incremental cloud storage cost that is technically justified by preserving the exact visual evidence without client rendering dependency.

#### Formal Architectural Contract for R16:

- **Authoritative Artifact**: Both `orig_<id>` (pristine hardware sensor capture with EXIF) and `evid_<id>.jpg` (authoritative burned evidence with stripped EXIF and burned HUD) are cloud-authoritative records.
- **Derived Artifact**: `thumb_<id>.jpg` (200px thumbnail generated from `evid_` for grid presentation).
- **Cloud Representation**:
  - `users/{uid}/originals/{siteId}/{mediaId}.jpg` (or `.mp4` for video)
  - `users/{uid}/evidence/{siteId}/{mediaId}.jpg`
  - `users/{uid}/thumbnails/{siteId}/{mediaId}.jpg`
- **Offline Behavior**:
  All three artifacts are written locally and atomically before the database row is committed. Offline gallery, detail inspection, and exports operate 100% autonomously on local `evid_`.
- **Export Behavior**:
  PDF reports, ZIP packages, and system share sheets directly embed the authentic `evid_<id>.jpg` file with its matching `evidence_sha256_hash`.
- **Verification Semantics (Hash Semantics; R15)**:
  Live byte verification reads local disk bytes, computes `SHA-256(evid_file)`, and asserts equality with `media.evidence_sha256_hash`.
- **Recovery Behavior**:
  `CloudMediaRecoveryService` can recover either `orig_` (for raw photo restoration) or `evid_` (for evidence viewing/export), forensically validating bytes against `sha256_hash` or `evidence_sha256_hash` prior to local promotion.

### 12.3 Export Attribution Architecture (Export Attribution; R21)

1. **Immutable Original Capture Creator Attribution**:
   - Every evidence record permanently binds to the UID of the user who captured the media at shutter time (`creator_id`).
   - Capture creator identity is write-once immutable and cannot be rewritten or replaced by any downstream viewer, editor, or exporter.
2. **PDF Report Attribution**:
   - Generated PDF evidence reports display the original capture inspector's identity and capture timestamp, never the exporting user's identity.
3. **ZIP Export Package Attribution**:
   - Structured metadata JSON and CSV manifests exported with media packages attribute each record strictly to its authentic `creator_id`.
4. **Detail-View Attribution**:
   - Media detail inspectors render the original capture creator's identity.
5. **Exporter Usurpation Prohibited**:
   - The user currently executing an export or sharing operation (`request.auth.uid`) must NEVER overwrite or replace the original capture creator's identity on exported artifacts. Exporter identity is strictly decoupled from capture creator provenance.

## 13. Nearby Media Search & Spatial Uncertainty Architecture

Nearby search operates strictly within the local Drift database in Phase 1.

### 13.1 Creator-Scoped Query Boundary

Nearby search is strictly scoped to the authenticated user's own data domain:

$$\text{NearbyCandidates}(lat, lon, r) = \{ m \in \text{media} \mid m.\text{creator\_id} == \text{currentUserId} \land \operatorname{dist}(m, (lat,lon)) \le r \}$$

Even if another user captured media at the exact same physical GPS coordinates, street address, or site code, cross-user evidence is **never** queried, indexed, or visible.

### 13.2 Two-Stage Search Algorithm & Spatial Uncertainty (R19)

``` text
Target Coordinate (lat0, lon0) & Search Radius (r)
      ↓
Stage 1: Indexed Bounding Box Pre-Filter (SQLite Indexed Query)
      [lat0 - Δlat, lat0 + Δlat] × [lon0 - Δlon, lon0 + Δlon]
      ↓
Stage 2: Exact Geodetic Haversine Distance Refinement
      d = 2R · arcsin(√(sin²(Δlat/2) + cos(lat1)·cos(lat2)·sin²(Δlon/2)))
      ↓
Filter: d ≤ r + candidate.accuracy_m (Spatial Uncertainty Bounds)
      ↓
Deterministic Sort: Distance Ascending → Recency Descending (R26)
      ↓
Group by Observation Type (Before / After / Progress / Material / General)
```

- **Spatial Uncertainty Display**: Displayed distance explicitly conveys GPS uncertainty margins (e.g. `12m (±4m)`), preventing misleading claims of sub-meter precision on standard mobile GNSS receivers.

## 14. Non-Conformity & Resolution (Smart-Link) Architecture

For linking an `After` / `Closed` observation to a preceding `Before` / `Non-Conformity` observation:

### 14.1 Normative Smart-Link Invariants

1. **Same Creator & Same Site**: Linking is restricted strictly to evidence sharing the same `site_id` and the same `creator_id`.
2. **Temporal Precedence (Smart-Link Temporal Semantics; R17)**:
   A candidate "Before" item must have been captured strictly earlier in time than the "After" observation:
   $$\text{candidate}.\text{captured\_at} < \text{current}.\text{captured\_at}$$
   A later observation can NEVER be linked as a "Before" defect, regardless of spatial proximity.
3. **Non-Destructive Lifecycle & Live Distance (R18)**:
   - Linking or unlinking Before/After pairs is strictly non-destructive. Unlinking an observation restores candidate status without modifying original media or other tags.
   - Proximity during pairing is evaluated using dynamic live-distance calculation from the current observation coordinates.
4. **Canonical Site Identity (R20)**:
   HUD stamps, Review & Tag interfaces, and link suggestion cards display the human-readable canonical site code / name rather than internal database UUIDs.
5. **Explicit Confirmation**:
   The system must NEVER link evidence automatically. Smart-link suggestions are advisory; user confirmation via dialog/button is mandatory before `linked_media_id` is persisted.

## 15. Gallery Architecture & Deterministic Sorting (R26)

The Gallery operates against the local database and supports 1,000+ items:
- **Virtualized Rendering**: Lazy grid loading `thumb_<id>.jpg` (derived from canonical evidence). Full-resolution images are never decoded for the gallery grid.
- **Deterministic Sort Invariant (R26)**:
  $$\text{ORDER BY } \text{captured\_at DESC}, \text{id DESC}$$
  Evidence items with identical capture timestamps enforce a deterministic secondary tie-breaker on unique record `id`, guaranteeing stable pagination and preventing jumpy grid re-renders.
- **Filters**: Date range, Activity tag, Observation type, Sync status, and Low GPS accuracy.

## 16. Firebase Cloud Architecture & Security Enforcement (Firebase/Cloud Enforcement; R05)

### 16.1 Authentication
Firebase Authentication establishes authenticated identity (`request.auth.uid`).

### 16.2 Firestore Data Model & Creator-Bound Security Rules

Authoritative conceptual structure for v1:

``` text
users/{uid}

sites/{siteId}                  (documents where creator_id == uid)

sites/{siteId}/media/{mediaId}  (documents where creator_id == uid)
```

> **Scope Clarification**: Subcollections such as `sites/{siteId}/members/{uid}` are **NOT** implemented in v1. Site membership, member roles, and cross-user collection group hydration are **FUTURE SCOPE — NOT IMPLEMENTED IN V1**.

#### Resource Authorization Matrix

| Resource | Ownership Field | Read Authorization | Create Authorization | Update Authorization | Delete Authorization | Immutable Fields |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Site Document** (`sites/{siteId}`) | `creator_id` | `creator_id == request.auth.uid` | `request.resource.data.creator_id == request.auth.uid` | `creator_id == request.auth.uid` | `creator_id == request.auth.uid` | `creator_id`, `id` |
| **Media Document** (`sites/{siteId}/media/{mediaId}`) | `creator_id` | `creator_id == request.auth.uid` | `request.resource.data.creator_id == request.auth.uid` | `creator_id == request.auth.uid` (soft-delete / tombstone only) | Disallowed (`allow delete: if false`) | `creator_id`, `site_id`, `captured_at`, `lat`, `lon`, `sha256_hash`, `evidence_sha256_hash` |

Firestore stores cloud metadata and synchronization state; it does not replace the local operational database.

An evidence ledger document carries the cloud representation of the capture-time metadata:
- Identity (`id`, `site_id`, `creator_id`)
- Storage paths (`original_path`, `evidence_path`, `thumbnail_path`)
- Spatial telemetry (`lat`, `lon`, `accuracy_m`, `low_accuracy`, `altitude_m`, `is_altitude_msl`)
- Integrity assertions (`sha256_hash`, `evidence_sha256_hash`)
- Environmental telemetry (`captured_address`, `gnss_satellite_count`, `gnss_satellites_used_in_fix`, `gnss_fix_timestamp`)
- Contextual tagging (`activity_tag`, `observation_type`, `linked_media_id`, `note`)
- Lifecycle flags (`captured_at`, `is_deleted`)

Ledger documents are published before artifact uploads (binding Storage artifacts to the document creator via Security Rules) and are reconciled against local authoritative values on every synchronization attempt; immutable forensic fields conflict rather than overwrite.

### 16.3 Cloud Storage Architecture & Creator Paths

Storage authorization is strictly tied to authenticated creator identity, NOT physical site identity or geographic location:

``` text
users/{uid}/originals/{siteId}/{mediaId}.jpg   (or .mp4)
users/{uid}/evidence/{siteId}/{mediaId}.jpg    (R16 Option A)
users/{uid}/thumbnails/{siteId}/{mediaId}.jpg
```

#### Storage Security Rules Contract:
- **Read**: Scoped strictly to `request.auth.uid == uid`. Even if User B discovers User A's `siteId`, `mediaId`, or storage URL, access is rejected.
- **Write / Create**: Permitted only when `request.auth.uid == uid` and matching Firestore ledger document verifies `creator_id == request.auth.uid`. Strict MIME boundaries (`image/jpeg`, `video/mp4`, `image/png`) and size limits ($\le 50\text{MB}$ for originals, $\le 5\text{MB}$ for evidence, $\le 1\text{MB}$ for thumbnails) are enforced.
- **Write-Once Immutability**: Existing storage objects can NEVER be overwritten or deleted by the client (`allow update, delete: if false`).

### 16.4 Atomicity & Failure Consistency

- Local artifact writes are atomic (temporary file + flush + rename), and persistence verifies that required artifacts physically exist before a database record is committed.
- If the processing or persistence pipeline fails, no misleading evidence record is committed: derived artifacts are cleaned up while the immutable original is preserved for photos; failed video persistence cleans up its unpersisted artifacts.
- Partial cloud publication (a ledger document without its Storage artifacts) is a recoverable transient state: uploads are retried idempotently and recovery downloads fail safely when an artifact is absent.

## 17. Synchronization Architecture & Queue Lifecycle

Synchronization is asynchronous, creator-owned, and session-gated: the coordinator exists only for an authenticated application session, and unauthenticated startup never initializes it.

``` text
Capture
    ↓
Local files (orig, evid, thumb) + local DB (pending)
    ↓
Sync Coordination (Authenticated Creator Session + Connectivity)
    ↓
1. Creator-owned site provisioned in Firestore (if created offline)
    ↓
2. Firestore evidence ledger document published (before artifact uploads)
    ↓
3. Upload original (idempotent; verified against sha256_hash)
    ↓
4. Upload burned evidence (R16 Option A; verified against evidence_sha256_hash)
    ↓
5. Upload thumbnail (idempotent; verified against thumbnail hash)
    ↓
6. Mark local record synced in Drift
```

### 17.1 Queue Ownership & Session Isolation

The synchronization queue is strictly creator-scoped:
$$\text{SyncQueue}(\text{user}) = \text{getUnsyncedMedia}(\text{creatorId: user.uid})$$
A sync worker operating under User A's session will never query, enqueue, or transmit User B's evidence. When User A logs out, the active sync coordinator aborts immediately.

### 17.2 Error Classification & Exponential Backoff (Sync Backoff/Error Classification; R25)

The sync coordinator classifies failures into two strict operational categories:

1. **Retryable Failures** (network disconnection, socket timeouts, transient Firebase 503 errors):
   - Automatically re-attempted using exponential backoff with randomized full jitter:
     $$\text{delay} = \min(\text{maxDelay}, \text{baseDelay} \cdot 2^{\text{attempt}}) \pm \operatorname{random}(\text{jitter})$$
   - Default: `baseDelay = 2s`, `maxDelay = 60s`, `maxAttempts = 5`.
   - Foreground app resume or manual network reconnect resets the backoff timer but does not reset the attempt counter unless explicitly intended.
2. **Permanent Failures** (schema corruption, storage quota exceeded, permission denial, missing creator ID):
   - Immediately marks the local record `failed` and halts automatic background retry for that item to prevent battery drain or infinite error loops.
   - Remains visible in the UI with an explicit failure badge, requiring explicit user manual retry.
3. **Permission Denial Resolution**:
   - Permission-denied errors verify the active session: if the session is expired or invalid, the session terminates and prompts login. If the session is valid, the operation is rejected as an unauthorized cross-tenant attempt.

### 17.3 Remote Tombstone Propagation (Tombstone Remote Propagation; R22)

- Soft-deleted records (`is_deleted == 1`) are synchronized through `syncTombstone`:
  * If the item was previously published to Firestore: updates the cloud ledger document to `is_deleted: true` and marks `tombstone_reconciled = 1` locally.
  * If the item was never published to Firestore: requires no remote write (no cloud deletion claim may exist for unpublished evidence) and marks `tombstone_reconciled = 1` locally.
- Cloud tombstones are metadata ledger entries only: they NEVER delete Cloud Storage objects. Cloud artifacts remain write-once immutable.

## 18. Data Authority & Hydration Isolation

### 18.1 Operational Authority
During offline operation:
**Local SQLite (Drift) + local media files are authoritative for the active authenticated user's operational working dataset.**
Local capture, Review & Tag metadata enrichment, Smart-Link associations, and gallery operations commit synchronously and atomically to the local filesystem and Drift database.

### 18.2 Cloud Synchronization Target & Permanence
Firebase Firestore and Firebase Cloud Storage are cloud synchronization targets and cloud-authoritative records for synchronized data:
- Once an evidence ledger document is committed to Firestore and its media artifacts (`orig_`, `evid_`, `thumb_`) are uploaded to Cloud Storage, the cloud records become immutable, write-once audit artifacts.
- Synchronization is non-destructive: remote records never overwrite newer local uncommitted edits, and client operations never physically delete cloud evidence records or Cloud Storage artifacts (`allow delete: if false`).

### 18.3 Non-Destructive Hydration & Invariant Authority
Remote-to-local hydration is creator-owned and strictly scoped:
$$\text{Hydrate}(\text{userId}) = \text{fetchRemoteSites}(\text{creator\_id} == \text{userId}) \to \text{upsertLocal}(\text{creator\_id} = \text{userId})$$
- **Authoritative Remote Creator Invariant**: Hydration MUST NEVER overwrite, re-stamp, or re-assign an existing `creator_id` with the currently authenticated UID. If a local or remote record belongs to User A, it cannot be claimed or adopted by User B.
- **Cross-User Hydration Prohibited**: A remote site belonging to User A is never imported into User B's local data domain. There is **NO** v1 hydration path using `members` collection groups, site membership, or admin roles.

## 19. Integrity / Chain of Custody & Media Integrity Architecture (Hash Semantics; R15)

### 19.1 Artifact Authority & Pipeline
Capture produces an immutable chain of custody across three distinct file artifacts:
1. **Raw Original Photo (`orig_<id>.jpg`) / Video (`orig_<id>.mp4`)**:
   - Pristine hardware sensor capture preserving full camera resolution and original EXIF tags.
   - Hashed immediately upon disk write: `sha256_hash = SHA-256(orig_bytes)`.
   - Stored in Cloud Storage at `users/{uid}/originals/{siteId}/{mediaId}.jpg` (or `.mp4`).
2. **Canonical Burned Evidence Photo (`evid_<id>.jpg`) (R16 Option A)**:
   - High-fidelity evidence photo generated by `BurnInService` running in a dedicated Dart background isolate.
   - Burns optical telemetry, site code/name, user-entered address, captured GPS coordinates (with uncertainty margin), captured timestamp, and the shutter-time satellite minimap snapshot directly into the pixel raster.
   - Strips original EXIF metadata to prevent contradictory sensor payloads or privacy leakage.
   - Hashed immediately upon generation: `evidence_sha256_hash = SHA-256(evid_bytes)`.
   - Stored in Cloud Storage at `users/{uid}/evidence/{siteId}/{mediaId}.jpg`.
3. **Gallery Thumbnail (`thumb_<id>.jpg`)**:
   - 200px thumbnail generated directly from `evid_<id>.jpg` for lazy virtualized gallery presentation.
   - Stored in Cloud Storage at `users/{uid}/thumbnails/{siteId}/{mediaId}.jpg`.

### 19.2 Stored Hash vs. Live Byte Verification (R15)
The architecture strictly distinguishes between an informational metadata assertion and forensic cryptographic verification:
- **Stored Hash**: A hexadecimal SHA-256 string stored in a Drift database column or Firestore ledger field. It represents the authoritative digest recorded at capture time. It is NOT proof that on-disk bytes remain unaltered.
- **Live Byte Verification**: An active cryptographic operation executing on demand:
  1. Reads physical bytes directly from disk or network stream.
  2. Computes the streaming digest `crypto.sha256.convert(bytes).toString()`.
  3. Asserts byte-level equality against the immutable stored hash (`sha256_hash` or `evidence_sha256_hash`).
- **Rule 5 Compliance Invariant**: An artifact, thumbnail, or local file must NEVER be labeled "verified" in the UI, logs, or exports merely because a stored hash string exists in database metadata. The "Verified" badge is rendered only after live byte verification has executed and succeeded.

### 19.3 Atomic Persistence & Failure Rollback
- Disk writes execute via temporary files (`.tmp`), flushed to disk (`flush: true`), and renamed atomically to canonical filenames before the Drift database transaction commits.
- If image compositing, HUD burning, or hashing fails, all temporary artifacts are unlinked, the raw original is preserved in safe quarantine, and no database record is committed.

## 20. State Management

Use Riverpod for reactive application state:
- **State Domains**: Authentication, Onboarding, Permissions, Active Site, GPS / GNSS telemetry, Camera Subsystem, Media Review & Tagging, Gallery Virtualization, Nearby Search, Media Detail Viewer, Synchronization Queue, and Settings.
- **Session-Bounded Lifecycles**: Domain providers listening to user-scoped data are invalidated and recreated upon session transitions (`sessionGenerationProvider`), preventing stale state from leaking across logins.
- **UI vs. Domain Separation**: Ephemeral UI state (e.g. scroll offsets, modal visibility, zoom scales) remains strictly decoupled from persistent domain state.

## 21. Navigation

``` text
Welcome
  ↓
Login
  ↓
Permission Onboarding
  ↓
Site Setup (Active Site Selection)
  ↓
Camera
  ├── Gallery (Virtualized Grid)
  │     └── Photo Evidence Detail / Immersive Viewer
  │            └── Nearby Search
  ├── Review & Tag (Canonical evid_ preview)
  └── Settings (Storage, Recovery, Account Deletion)
```

Navigation preserves the active site context across capture workflows and ensures immediate navigation to the unauthenticated Welcome/Login screen upon sign-out or account deletion.

## 22. Error Handling

Error handling must fail closed without compromising evidence integrity or leaking cross-tenant state:
- **Authentication Failures**: Force immediate session invalidation, clear in-memory caches, and route to Login.
- **GPS Unavailable / Degraded**: Retain camera capture readiness; record GPS state as `unavailable` or flag `low_accuracy = true`; never fabricate zero or default coordinates.
- **Hardware Camera / Storage Failures**: Abort capture transaction cleanly; unlink temporary scratch files; notify user with actionable diagnostics.
- **Network / Cloud Sync Failures**: Classify errors into retryable (jittered backoff) vs. permanent (halt background queue; flag UI for manual intervention).
- **Failure Preservation**: Errors must NEVER cause data loss or corruption of locally captured physical evidence files.

## 23. Security

### 23.1 Creator-Bound Cloud Authorization (Firebase/Cloud Enforcement; R05)
- Firebase Security Rules restrict cloud data strictly according to authenticated creator identity:
  $$\text{request.auth.uid} == \text{creator\_id}$$
- SiteLens v1 contains zero site membership, member invitations, member roles, admin roles, or RBAC.
- Physical proximity, matching site names, shared site codes, identical street addresses, or identical GPS coordinates NEVER grant authorization or data access between users:
  $$\text{same physical site} \ne \text{shared data}$$
  $$\text{same site code} \ne \text{authorization}$$
  $$\text{same GPS} \ne \text{authorization}$$

### 23.2 Defense in Depth
- The Flutter client is not the final authorization boundary: backend Firestore security rules and Cloud Storage security rules strictly reject unauthorized mutations even if the client is compromised or bypassed.
- No client-side secrets: API keys (such as `RESEND_API_KEY`) are stored exclusively in Google Cloud Secret Manager and accessed solely through App-Check-enforced serverless Cloud Functions.
- Secure local storage: Authentication tokens and session identifiers are stored in hardware-backed secure storage (`FlutterSecureStorage` with Android KeyStore / iOS Keychain).

## 24. Performance

For the Phase 1 target of 1,000+ media items:
- Generate 200px thumbnails at capture time; never decode full-resolution images for the gallery grid.
- Utilize virtualized grid rendering (`GridView.builder` with `itemExtent` / slivers).
- Index local search fields (`creator_id`, `site_id`, `captured_at`, `lat`, `lon`, `is_deleted`).
- Execute Stage-1 bounding-box filtering in SQLite prior to in-memory Haversine distance refinement.
- Execute image compositing, HUD burning, and SHA-256 computation in dedicated Dart background isolates to ensure zero UI frame drops.

## 25. Settings & Lifecycle Architecture

Settings include:
- GPS accuracy threshold
- High-accuracy GPS mode
- Watermark template configuration
- Captured address visibility toggle
- Cache / storage controls
- Thumbnail regeneration
- Clear synced originals locally (space reclamation)
- Physical local deletion (Remove from Gallery)
- Cloud media recovery & SHA-256 verification pipeline
- Sync queue monitoring & retry controls

### 25.1 Storage Lifecycle & Deletion Architecture (Local Deletion & Cloud Permanence; R22, R24)

1. **Local Media Artifacts**:
   - Photo: Raw original (`orig_{id}.jpg`), derived evidence with burned HUD (`evid_{id}.jpg`), and gallery thumbnail (`thumb_{id}.jpg`).
   - Video: Video file (`orig_{id}.mp4`) and first-frame thumbnail (`thumb_{id}.jpg`).
2. **User-Facing Deletion Operations**:
   - **Synced Media ("Remove from Gallery")**: Physically unlinks all local media files (`orig_`, `evid_`, `thumb_`) belonging to the item and marks the local Drift record as deleted (`is_deleted = 1`), hiding it immediately from the Gallery. The immutable cloud copy remains completely intact in Cloud Storage.
   - **Unsynced Media**: Requires an explicit destructive warning confirmation dialog before local files are unlinked, alerting the user that the item has no cloud backup. Upon confirmation, local files are removed and the Drift record is marked `is_deleted = 1`.
3. **Tombstone Propagation Lifecycle (R22, R24)**:
   - A soft-deleted record is retained in Drift as a hidden tombstone row (`is_deleted = 1, tombstone_reconciled = 0`) until its cloud ledger state is reconciled.
   - **Published Record**: If the item was previously published to Firestore, the synchronization worker executes `syncTombstone`, updating the Firestore evidence document to `is_deleted: true`, and marks `tombstone_reconciled = 1` in Drift.
   - **Never-Published Record**: If the item was never published to Firestore, no cloud write is issued (preventing invalid cloud deletion claims for uncommitted evidence), and `tombstone_reconciled = 1` is immediately marked.
   - **Cloud Permanence Invariant**: Local deletion never deletes or replaces Cloud Storage objects (`storage.rules` enforces `allow delete: if false`). Cloud artifacts remain write-once immutable.
4. **Storage Space Reclamation**:
   - Local raw originals of already-synchronized photos can be cleared on demand via `StorageCleanupService`, preserving the local canonical `evid_` and `thumb_` artifacts and all database metadata.
   - Cleared originals remain recoverable from the write-once cloud original.
5. **Cloud Recovery with Live Cryptographic Verification (R15)**:
   - `CloudMediaRecoveryService` downloads artifacts atomically from Cloud Storage (`users/{uid}/...`).
   - Performs live byte verification: calculates `SHA-256(downloaded_bytes)` and asserts equality against `MediaItem.sha256Hash` (for `orig_`) or `MediaItem.evidenceSha256Hash` (for `evid_`).
   - Promotes the verified file atomically to local app storage.

### 25.2 Single-Tenant Creator Account Deletion Architecture

SiteLens v1 operates on an exclusive single-tenant creator ownership model. There are NO shared sites, NO member rosters, and NO cross-user collaboration. Consequently, account deletion operates exclusively on the authenticated creator's personal data domain:
- **No Successor Admin**: There is no site successor administrator concept in v1.
- **No Ownership Transfer**: Sites and evidence cannot be transferred to another user.
- **No Shared-Site Retention**: No site or evidence record is retained for co-members, because co-membership does not exist in v1.

#### Coordinated Account Deletion Lifecycle:
1. **Server-Authoritative Invocation**:
   - Client invokes the Firebase 2nd-gen Cloud Function `deleteUserAccount` (App-Check enforced).
   - Identity is derived strictly from `context.auth.uid`. No client-supplied UID parameters are accepted.
2. **Cloud Storage Prefix Purge**:
   - Recursively deletes the entire Cloud Storage prefix belonging to the creator:
     $$\text{gs://sitelens.appspot.com/users/}\{uid\}/**$$
   - Purges all originals, evidence JPEGs, and thumbnails.
3. **Firestore Media & Site Document Purge**:
   - Queries and physically deletes all media ledger documents where `creator_id == uid`:
     $$\text{sites/}\{\text{siteId}\}/\text{media/}\{\text{mediaId}\} \quad (\text{where } \text{creator\_id} == uid)$$
   - Queries and physically deletes all site documents where `creator_id == uid`:
     $$\text{sites/}\{\text{siteId}\} \quad (\text{where } \text{creator\_id} == uid)$$
4. **Enquiry Anonymization & Rate Limit Purge**:
   - Purges rate limiting entries (`_system_rate_limits/enquiry_{uid}`).
   - Anonymizes support enquiries submitted by the user (`enquiries/{id}` sets submitter email to `anonymized@sitelens.app`).
5. **Firebase Authentication Account Deletion**:
   - Invokes `admin.auth().deleteUser(uid)` to revoke all refresh tokens and destroy the authentication principal.
6. **Client-Side Teardown & Local Data Wipe**:
   - Following server-side success confirmation:
     * Terminates all background sync tasks, camera streams, and active GPS subscriptions.
     * Physically purges all files in the local app documents directory (`originals/`, `evidence/`, `thumbnails/`, and scratch directories).
     * Physically closes and deletes the local SQLite Drift database file (`sitelens_v9.db`).
     * Purges local active-site preferences, cached geocodes, and secure storage credentials.
     * Increments the global session generation token ($\text{sessionGen} \gets \text{sessionGen} + 1$).
     * Signs out locally and routes the user to the unauthenticated Welcome / Login screen.

## 26. Testing

### Unit
Test:
- Haversine distance & geodetic bounding-box calculations
- Nearby spatial search with uncertainty tolerance ($d \le r + \text{accuracy}$)
- Smart-Link temporal precedence validation ($\text{candidate.captured\_at} < \text{current.captured\_at}$)
- Tri-state GPS accuracy classification & `hasLiveFix` logic
- Two-tier SHA-256 generation (`orig_` and `evid_`)
- Drift query fail-closed creator scoping with null/empty UID guards
- Tombstone reconciliation & sync queue state transitions

### Widget
Test:
- Authentication state rendering & session transition teardown
- Permission onboarding flows
- GPS status indicators (Live Fix vs. Cached vs. Unavailable)
- Camera controls & active video recording state lock
- Review & Tag screen with canonical `evid_` preview
- Smart-Link advisory suggestion card & confirmation dialog
- Gallery virtualized grid & deterministic secondary tie-breaker
- Settings screen storage cleanup & cloud recovery workflows

### Integration
Test:
- End-to-end capture → isolate HUD burn → local Drift commit
- Offline capture & autonomous local gallery browsing
- Remote site hydration without collection group queries
- Soft-delete → local file unlinking → tombstone cloud reconciliation
- Multi-user session transition: User A sign-out → User B sign-in → zero data leakage
- Failed synchronization → jittered exponential backoff retry → terminal failure handling
- Single-tenant account deletion complete lifecycle

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

This is a recommended target structure, not a requirement to rewrite an existing sound implementation.

## 28. Design Relationship

`design.md` is the visual design source of truth.
Google Stitch is used to generate and refine the visual design.
Flutter implements the approved designs.
The design system provides reusable:
- Colors & elevation tokens
- Typography & hierarchy scales
- Spacing & radii constants
- Buttons, cards, and status badges
- Media display & zoom components
- Permission onboarding components
- Camera controls & live HUD overlay widgets

## 29. Deferred Architecture (Future Scope — Not Implemented in V1)

To protect the simplicity, stability, and forensic integrity of SiteLens v1, the following capabilities are explicitly deferred to future releases:

1. **Multi-User Collaboration & Site Sharing**:
   - Shared construction sites, shared project workspaces, and multi-tenant organizations.
   - Member invitations, member rosters, member roles, and Role-Based Access Control (RBAC).
   - Successor-admin designation, administrator promotion, and site ownership transfer.
   - Cross-user collection group hydration and cross-user evidence visibility.
2. **Quality & Compliance Builders**:
   - Work Inspection Request (WIR) generator and multi-signoff workflow.
   - Non-Conformance Report (NCR) generator and closure tracking.
   - Tabular Excel (`.xlsx`) export and custom enterprise compliance reporting.
3. **Advanced Cloud & Synchronization Capabilities**:
   - Multi-device concurrent editing conflict resolution.
   - Server-side spatial querying (PostGIS / Cloud Spanner spatial extensions).
   - Full server-side video frame-by-frame telemetry burn-in.
   - Cross-device peer-to-peer evidence handoff.

## 30. Decision Summary

| Architectural Area | Decision / Invariant | Rationale / Reference |
| :--- | :--- | :--- |
| **Product Model** | User-specific, creator-owned, location-independent, non-collaborative | Approved PRD v1 model; strict data-domain isolation between users |
| **Mobile Framework** | Flutter | Cross-platform native camera, sensor, and isolate performance |
| **Language** | Dart | Null-safe language with strong typing and isolate concurrency |
| **Authentication** | Firebase Authentication | Establishes authenticated identity (`request.auth.uid == creator_id`) |
| **Cloud Database** | Cloud Firestore | Creator-bound documents (`creator_id == request.auth.uid`); no `members` subcollection in v1 |
| **Cloud Media Storage** | Firebase Cloud Storage | Creator-bound paths (`users/{uid}/...`); write-once immutability |
| **Local Database** | SQLite via Drift (Schema v9) | Local-first persistence; fail-closed creator scoping across all queries |
| **Local Isolation** | Fail-closed queries + session generation token + cache purge | Prevents cross-user local reads; empty UID fails closed |
| **Cloud Evidence Replication** | **Option A** (`evid_<id>.jpg` replicated to Cloud Storage) | R16 decision; preserves authentic HUD, minimap, and forensic non-repudiation |
| **State Management** | Riverpod | Reactive state management with clean session-level invalidation |
| **GPS State Machine** | Tri-state: Unknown / Service Off / Denied; `hasLiveFix` authority | Decouples capture readiness from services-off/unknown; cached GPS never unlocks capture |
| **Video Telemetry Authority** | Start-time authority ($T_0$); active recording lock | Stop-time cannot usurp $T_0$; locks lens, zoom, and telemetry during recording |
| **Nearby Search** | Local Drift query + bounding box + Haversine refinement | Creator-scoped local spatial search; displays GNSS uncertainty bounds |
| **Smart-Link (Before/After)** | Same creator, same site, temporal precedence ($T_{\text{candidate}} < T_{\text{current}}$) | Non-destructive linking; dynamic live distance; canonical site identity |
| **Integrity & Chain of Custody** | Two-tier SHA-256 (`sha256_hash` + `evidence_sha256_hash`) | Live byte verification on disk/recovery; distinguishes stored hash from live verification |
| **Deletion & Tombstones** | Local soft-delete tombstone + cloud permanence | Local deletion unlinks files, keeps cloud Storage intact; reconciles cloud ledger tombstone |
| **Account Deletion** | Single-tenant server-authoritative callable | Purges creator's Storage prefix, Firestore docs, Auth user, and local device data |
| **Synchronization** | Creator-owned asynchronous queue + exponential backoff | Isolates sync workers to active session; retryable errors backoff, permanent halt |
| **User Enquiries** | Serverless Cloud Function (`submitUserEnquiry`) + Resend | Zero client secrets; Secret Manager + App Check + rate limiting |

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

## 34. Authoritative R01–R26 Architecture Traceability Matrix

This matrix maps every accepted Phase 1 remediation item (R01–R26) to its governing Architecture section, canonical architectural invariant, and implementation impact.

| ID | Remediation (Phase 1 Canonical Name) | Architecture Section | Architecture Decision / Invariant | Implementation Impact |
| :--- | :--- | :--- | :--- | :--- |
| **R01** | Product/security model | §1, §2, §6, §8, §16, §23 | Single-tenant creator ownership (`creator_id == request.auth.uid`). Location, site code, address, or GPS coordinates never grant authorization. Membership, invitations, and RBAC removed from v1. | Purge all RBAC/membership schemas and authorization rules; enforce creator-only Firestore and Storage access across all operations. |
| **R02** | GPS/capture-readiness dependency | §9.1, §9.3 | Evidence capture readiness is strictly gated on `hasLiveFix`. Camera hardware readiness (preview streaming) is distinguished from evidence capture readiness. | Shutter button disabled (`Waiting for GPS lock`) until `hasLiveFix` is acquired. |
| **R03** | GPS/capture-readiness dependency | §9.1 | Lifecycle synchronization between camera and GPS providers on app resume; timer countdown abort/pause on GPS loss. | Re-synchronize camera and location streams upon `AppLifecycleState.resumed`; abort countdown if fix lost. |
| **R04** | Session/local isolation | §6.3, §11.1, §11.2 | Local queries fail closed if UID is null/empty. Session transition invalidates all providers, purges caches, aborts sync, and increments generation token. | Inject active `userId` into all Drift queries; implement `SessionManager.onSignOut()` teardown routine. |
| **R05** | Firebase/cloud enforcement | §16.2, §16.3, §23.1 | Cloud data enforced strictly via `request.auth.uid == creator_id`. Storage paths bound to `users/{uid}/...`. Write-once immutability. | Update `firestore.rules` and `storage.rules` to remove `members` checks; enforce creator-bound path rules. |
| **R06** | Live GPS fix / cached GPS | §9.3 | `hasLiveFix` is the capture-readiness authority. Cached/last-known GPS coordinates must never be substituted as a live fix. | Update `LocationService` to track live fix status independently from last-known seed coordinates. |
| **R07** | Video start-time authority | §9.1 | Video recording start timestamp ($T_0$) is immutable authority. Downstream stop-time metadata acquisition must never usurp $T_0$. | Persist $T_0$ at shutter trigger; use $T_0$ in video file naming, Drift metadata, and burned overlay. |
| **R08** | Active recording camera/telemetry lock | §9.1 | Optical camera lens, zoom controls, and telemetry capture parameters are locked during active video recording. | Disable lens switching and digital zoom gestures in `CameraPreview` while `isRecordingVideo` is true. |
| **R09** | Audio disclosure | §9.1 | Disclose audio recording status via `hasAudioTrack` flag. Microphone permission denial gracefully falls back to muted video with clear UI disclosure. | Add `has_audio_track` column to Drift media table; pass audio status to video capture controller. |
| **R10** | Unknown telemetry semantics | §9.3 | Sensor values that are unavailable or uncalibrated must remain null/unknown. Substituting zero/default values is prohibited. | Ensure Drift columns and JSON encoders preserve null for uncalibrated altitude, heading, and satellite count. |
| **R11** | Minimap race | §9.3, §32.2 | Generational token guards on minimap snapshots prevent stale map tiles from burning into evidence during fast shutter triggers. | Attach monotonic generation token to minimap controller; reject snapshot if token does not match shutter $T_0$. |
| **R12** | Capture mutex | §9.1 | Single-flight capture mutex prevents concurrent shutter presses and duplicate evidence record generation. | Wrap shutter trigger in an atomic lock (`_isCapturing`); ignore subsequent taps until persistence completes. |
| **R13** | Video handoff / player lifecycle | §9.4 | Single video playback ownership (`EvidenceVideoPlayback`), in-flight reference cleanup, atomic stop/handoff lifecycle, and interrupted recording recovery (Keep for Later / Discard). | Implement single playback controller manager; add uncommitted video recovery on app restart. |
| **R14** | PopScope / cleanup | §10.2 | Review & Tag back/dismiss handling via `PopScope`, uncommitted capture protection dialog, and cleanup lifecycle unlinking temporary files on discard/retake. | Wrap `ReviewTagScreen` in `PopScope`; unlink temporary `orig_`, `evid_`, `thumb_` files when discarded. |
| **R15** | Hash semantics | §12.2, §19.2 | Two-tier SHA-256 (`sha256_hash` for original, `evidence_sha256_hash` for burned evidence). Distinguish stored hash from live byte verification. | Store both hashes in Drift and Firestore; implement `verifyBytes()` method in recovery and audit services. |
| **R16** | Cloud evidence artifact replication (Option A vs Option B) | §12.2 | **Option A**: `evid_<id>.jpg` is replicated to Cloud Storage as a cloud-authoritative evidence artifact, ensuring exact byte preservation without client rendering dependency. | Upload `evid_<id>.jpg` to `users/{uid}/evidence/{siteId}/{mediaId}.jpg`; update sync coordinator. |
| **R17** | Smart-link temporal semantics | §14.1 | Temporal precedence: candidate "Before" item must be captured strictly earlier in time than the "After" observation ($\text{candidate.captured\_at} < \text{current.captured\_at}$). | Add `WHERE captured_at < current.capturedAt` constraint to smart-link candidate query in `MediaRepository`. |
| **R18** | Smart-link lifecycle & live distance | §14.1 | Non-destructive unlinking restores candidate status. Proximity evaluates dynamic live distance from current observation coordinates. | Ensure unlinking nulls `linked_media_id` without deleting records; compute dynamic Haversine distance in UI. |
| **R19** | Spatial uncertainty | §13.2 | Nearby search and HUD stamps display GNSS uncertainty margins explicitly (e.g. `12m (±4m)`). Sub-meter overclaiming prohibited. | Format displayed distance with candidate GPS accuracy bounds in `NearbySearchScreen` and HUD stamp. |
| **R20** | Canonical site identity | §14.1 | HUD stamps, Review & Tag interfaces, and link suggestion cards display human-readable canonical site code/name rather than database UUIDs. | Resolve and display `Site.code` / `Site.name` instead of `site_id` in all UI cards and stamp overlays. |
| **R21** | Export attribution | §6.2, §12.3 | Immutable original capture creator attribution across PDF reports, ZIP export packages, and detail views; exporter identity must never usurp capture creator. | Bind export generator metadata to `media.creator_id`; decouple exporting user from capture attribution. |
| **R22** | Tombstone remote propagation | §17.3, §25.1 | Soft-deleted records sync `is_deleted: true` to Firestore ledger. Unpublished evidence produces no remote deletion claim. | Add `syncTombstone` handler in sync worker; mark `tombstone_reconciled = 1` upon cloud update. |
| **R23** | Site deletion safety | §8.4 | Active media guard (`hasMediaForSite`) blocks site deletion if active (non-deleted) media items exist for that site. | Add validation query in `SiteRepository.deleteSite()`; prompt user to manage media before site deletion. |
| **R24** | Unreconciled tombstone retention & purge | §8.4, §25.1 | Retain tombstones locally until cloud reconciliation succeeds. Site deletion safely purges only reconciled tombstones. | Guard tombstone cleanup with `WHERE is_deleted = 1 AND tombstone_reconciled = 1`. |
| **R25** | Sync backoff / error classification | §17.2 | Error classification: retryable network errors use exponential backoff with full jitter; permanent errors halt background loop. | Implement `SyncRetryPolicy` with jittered exponential delay and terminal failure state for permanent errors. |
| **R26** | Gallery/nearby deterministic sorting | §13.2, §15 | Deterministic secondary tie-breaker: `ORDER BY captured_at DESC, id DESC`. Prevents pagination shifts on identical timestamps. | Update Drift query `orderBy` clauses in `MediaDao.watchAllMedia()` and nearby search candidate queries. |

