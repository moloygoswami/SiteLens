# SiteLens --- Phase 1 Product Requirements Document

## Geo-tagged photo/video capture, gallery, and GPS-based nearby-media search

### 1. Product Scope

SiteLens Phase 1 provides:

**capture → tag → store → find-nearby → optional cloud synchronization**

The application is a **Flutter mobile application** designed for
field/site engineers.

Phase 1 includes:

-   Firebase Authentication
-   first-login permission onboarding
-   project/site selection
-   GPS-aware photo/video capture
-   visible burned-in geotagging
-   EXIF GPS metadata for photos
-   local-first media storage
-   local gallery
-   media detail
-   GPS-based nearby-media search
-   Before/After smart-linking
-   integrity hashing
-   Firebase cloud storage/data synchronization foundation
-   sync queue and status UI
-   settings

Explicitly deferred:

-   WIR builder
-   NCR builder
-   Excel/compliance export
-   full multi-user collaboration
-   advanced reporting workflows
-   server-side spatial search
-   full per-frame video geotag burn-in

The deferred capabilities can be added later as a
reporting/collaboration layer on top of the media captured in Phase 1.

------------------------------------------------------------------------

# 2. Platform and Technology Requirements

## 2.1 Mobile Application

The application MUST be implemented using:

-   **Flutter**
-   **Dart**

React Native and Expo are NOT part of the SiteLens implementation.

## 2.2 Backend

Use Firebase for cloud services:

-   **Firebase Authentication** --- user login/session
-   **Cloud Firestore** --- cloud metadata and application data
-   **Firebase Cloud Storage** --- original media and thumbnails
-   **Firebase Security Rules** --- cloud authorization
-   **Firebase Crashlytics** --- crash/error monitoring where enabled
-   **Firebase Analytics** --- optional and only where appropriate

Cloud services MUST NOT make offline capture dependent on network
availability.

## 2.3 Local-first data layer

Use:

-   **SQLite via Drift** for local structured data
-   local device file storage for original media and thumbnails
-   asynchronous synchronization to Firebase

The local database remains the operational data source for offline
capture and nearby-media search.

## 2.4 State management

Use **Riverpod** for application state unless an existing, sound
state-management implementation is already present in the codebase.

## 2.5 Device capabilities

The Flutter implementation must provide:

-   camera access
-   location/GPS
-   photo/video capture
-   image processing
-   file storage
-   SHA-256 hashing
-   maps
-   permission management
-   connectivity detection

------------------------------------------------------------------------

# 3. Screen Map

  ----------------------------------------------------------------------------
  \#                      Screen                  Purpose
  ----------------------- ----------------------- ----------------------------
  1                       Welcome / First Launch  Explain SiteLens and start
                                                  authentication

  2                       Login                   Firebase Authentication

  3                       Permission Onboarding   Explain and request required
                                                  device permissions

  4                       Permission Recovery     Handle denied/permanently
                                                  denied permissions

  5                       Site Setup              Select active project/site

  6                       Camera & Viewfinder     Photo/video capture with
                                                  live GPS/geotag stamp

  7                       Review & Tag            Confirm capture and classify
                                                  activity/observation

  8                       Gallery                 Browse/search local media
                                                  library

  9                       Media Detail            Full media, metadata and
                                                  nearby entry point

  10                      Nearby Media Search     Find nearby media and
                                                  Before/After pairs

  11                      Settings & Sync         GPS/watermark/storage/sync
                                                  configuration
  ----------------------------------------------------------------------------

Primary flow:

**Welcome → Login → Permission Onboarding → Site Setup → Camera → Review
& Tag → Gallery ⇄ Media Detail → Nearby Search**

Settings are reachable from the main application surfaces.

------------------------------------------------------------------------

# 4. First Launch and Authentication

## 4.1 Welcome

The first launch screen should:

-   introduce SiteLens
-   communicate that it creates GPS-tagged inspection evidence
-   provide a clear primary action to continue to authentication
-   use the industrial anti-slop design system (high-contrast neutrals, 1px hairline borders, 0 elevation)

## 4.2 Sign Up (First-Time User Registration)

For first-time users, the application provides a dedicated account creation workflow (`SignupScreen`):

-   **Fields**: Full Name, Work Email, Password, Confirm Password, and mandatory agreement to Terms of Service and Privacy Policy.
-   **Email Verification Dispatch**: Upon successful creation via `createUserWithEmailAndPassword()`, Firebase immediately dispatches an email verification link (`sendEmailVerification()`).
-   **Session Guard**: The newly created session is immediately signed out so unverified users cannot bypass the email verification gate.
-   **Verification Screen**: Displays explicit instructions showing the target email address and prompting the user to open their inbox and verify their email prior to signing in.

## 4.3 Login & Email Verification Enforcement

Authentication MUST use Firebase Authentication.

Supported authentication methods:

-   **Email/Password**
-   **Google Sign-In** (OAuth / Workspace)

The implementation must enforce:

-   **Mandatory Email Verification**: On email/password login attempts, the user record is reloaded to check `emailVerified`. If false, login is strictly blocked, the session is invalidated, and an `EmailNotVerifiedException` is raised.
-   **Inline Verification Resend**: When email verification is pending, the login UI presents a prominent warning banner with an inline **"Resend Verification Email"** action (`sendEmailVerificationForUser`).
-   **Security & Anti-Enumeration**: Uniform error messages for invalid credentials and non-existent accounts to prevent account enumeration attacks.
-   **Network Failure & Session Recovery**: Graceful offline handling and dynamic session routing (`SessionRouter`).

## 4.4 Forgot Password & Password Reset Email

If a user forgets their password:

-   **Tactile Trigger**: A dedicated "Forgot Password?" action adjacent to the Password field on the Login screen.
-   **Reset Modal**: Opens a modal dialog pre-filled with the user's work email address.
-   **Firebase Reset Link**: Submitting calls `sendPasswordResetEmail()` to dispatch a secure password reset link to their email ID, allowing the user to create a new password.
-   **User Feedback**: Displays confirmation upon dispatch or specific error feedback if the email format is invalid or network request fails.

------------------------------------------------------------------------

# 5. Permission Onboarding

Permission onboarding is a mandatory first-login workflow.

Do not immediately trigger OS permission dialogs without first
explaining the reason for each permission.

## 5.1 Camera

Purpose:

> Capture inspection photos and videos.

Required for capture functionality.

## 5.2 Location

Purpose:

> Attach accurate GPS coordinates to inspection evidence.

Required for GPS-dependent capture.

The application MUST NOT silently create inspection media without an
initial GPS fix.

## 5.3 Photos / Media

Request the platform-appropriate media permission where required for
reading, saving, or managing media.

## 5.4 Microphone

Request only when required for video/audio capture.

## 5.5 Notifications

Optional.

May be used for synchronization or important application events.

## 5.6 Permission states

The UI MUST support:

-   Not requested
-   Requesting
-   Granted
-   Denied
-   Denied but requestable
-   Permanently denied
-   Open Settings
-   Permission restored

Permissions must be rechecked when:

-   the application starts
-   the application resumes from background
-   the camera screen opens
-   capture begins
-   another permission-dependent workflow begins

OS permission state is device state and must not be treated as Firebase
data.

------------------------------------------------------------------------

# 6. Site Setup

After successful authentication and required permission onboarding:

-   Project picker → Site picker
-   populate active `Site ID`
-   display site name
-   display registered address
-   establish the reference point used for geotag stamping

The application should cache site information locally.

If the device is offline:

-   use cached site data where available
-   allow the specified manual address entry path where necessary

The active site context must be available to capture, gallery, media
detail, nearby search, and synchronization.

------------------------------------------------------------------------

# 7. Camera & Viewfinder

The Camera screen is the primary SiteLens workflow.

## 7.1 Top bar

Left:

-   Gallery shortcut
-   unsynced-count badge

Center:

-   GPS status badge

Right:

-   Flash control
-   Settings

## 7.2 GPS status

Display:

-   `GPS: High · ±2m` when accuracy ≤ 5 m
-   `GPS: Weak · ±12m` when accuracy is 5--20 m
-   `GPS: Poor · ±30m+` beyond that
-   `GPS: Searching…` before the first fix

The exact visual treatment is defined by `design.md`.

## 7.3 Viewfinder

-   full-bleed camera preview
-   center focus reticle
-   focus-lock feedback
-   tap-to-focus where supported

## 7.4 Geotag overlay (LIVE HUD & Canonical Metadata Card)

SiteLens employs the **Option B HUD Architecture**: a canonical semantic data model (`HudData`), a unified layout specification (`HudLayoutSpec`), and a centralized string formatter (`HudFormatter`), consumed by two separate specialized renderers:

```text
Raw GPS / Capture Data
        ↓
   HudFormatter
        ↓
      HudData
        +
  HudLayoutSpec
        ↓
 ┌──────┴──────┐
 ↓             ↓
Flutter       Canvas
Renderer      Renderer
 ↓             ↓
Preview     Native-resolution
HUD         Evidence HUD
                ↓
          evid_<id>.jpg
```

### Architectural Contracts & Renderer Separation
- **`HudData`**: Pure Dart immutable semantic data contract. Holds structured values (headlines, address, timestamps, coordinates, site code, hashes, badge statuses) with zero UI or framework dependencies, ensuring 100% isolate transferability.
- **`HudFormatter`**: Single source of truth for all HUD text formatting, eliminating duplicated string-assembly rules across renderers.
- **`HudLayoutSpec`**: Defines the canonical visual and spatial specification (proportions, dimensionless ratios, design plane tokens, color definitions, and dynamic font scaling curves).
- **Separate Renderers**:
  * **Flutter Viewfinder Renderer** (`EvidenceMetadataHudCard`): 60fps reactive screen overlay rendered in logical dp.
  * **Canvas Vector Renderer** (`WatermarkDrawer`): High-precision vector watermark rendered directly into the photograph's native pixel resolution via `dart:ui.Canvas` and `TextPainter`.
- **Visual Parity Requirement**:
  > The canonical native-resolution burned HUD must visually correspond to the HUD presented in the live Camera Preview, while allowing renderer-specific implementation mechanics appropriate to screen and native photograph coordinate spaces.
  Both renderers preserve the same semantic content, visual design, proportions, positioning, spacing, and layout relationships. Visual parity is a product requirement; the two renderers do not share implementation mechanics.
- **Native Resolution Invariant**: The canonical evidence HUD must be rendered at the photograph's native resolution. It must never be produced by screenshotting, upscaling, or otherwise rasterizing the Flutter preview.

### HUD Visual & Layout Specifications
Both renderers conform to the canonical layout specifications defined in `HudLayoutSpec`:

1. **5-Row Semantic Structure (Tactical Dark `#0D110F`)**:
   - **Row 1 (Site / Locality & Integrity Badge)**:
     * Site name / locality headline (`10.5sp * fontScale`, bold 700)
     * Status chip (`8.0sp * fontScale`, bold 900): `• VERIFIED` (Green), `• DEGRADED` (Amber), or `• PENDING` (Red/Yellow)
   - **Row 2 (Street Address)**:
     * `ADDR:` bold 700 identifier + full resolved street address (`8.5sp * fontScale`, max 2 lines)
   - **Row 3 (Capture Timestamps)**:
     * `UTC:` bold 700 + UTC timestamp ` • ` `Local:` bold 700 + local timestamp and timezone (`8.5sp * fontScale`, max 2 lines)
   - **Row 4 (Coordinates & Elevation)**:
     * `Lat ` bold 700 + latitude ` • ` `Long ` bold 700 + longitude + altitude suffix (`8.5sp * fontScale`, max 2 lines)
     * Coordinates and elevation occupy a maximum of 2 lines. Do **not** require ellipsis for coordinates/elevation. Do **not** solve wrapping by progressively degrading the font through arbitrary fitting/scaling.
   - **Row 5 (Site Code & Provenance Hash)**:
     * `SITE:` bold 700 + site code ` • ` `SHA:` bold 700 + compact 19-char SHA `02c7fd67...405661` (or `Integrity hash: Pending until saved` on Live HUD) (`8.0sp * fontScale`, 1 line)

2. **Minimap Geometric & Spatial Integration**:
   - **Minimap Aspect Ratio**: Strictly **1.24:1** (width:height = 1.24).
   - **Height Matching**: Minimap and metadata card share a strict equal-height relationship.
   - **Gap**: Exactly **4 design units** (`HudLayoutSpec.gap = 4.0`) between minimap and metadata card.
   - **Minimap Fidelity & Evidence Provenance Invariant (Authoritative)**:
     > **The Evidence JPEG MUST contain the same minimap map state/source that the user sees in the live Camera Capture minimap at shutter time. The map representation/state at shutter time must be burned into the JPEG. Photo Evidence Detail and Immersive Evidence Viewer must display those burned-in pixels and must not independently re-render the minimap.**
   - **Display Fallback vs. Evidence Provenance Architecture**:
     * **Display Fallback (Viewfinder Only)**: Live interactive `GoogleMap` widget (Zoom 18.0, active Normal/Satellite layer) is the primary Camera Capture minimap. Offline indicators and cached tiles serve strictly as non-blocking viewfinder presentation fallbacks during startup, compass updates, or network latency.
     * **Evidence Provenance (Evidence JPEG)**: The exact visual map representation and canonical state presented to the user at shutter time ($T_0$) is captured concurrently via `GoogleMapController.takeSnapshot()` and burned into the immutable Evidence JPEG together with the canonical HUD.
     * **Synthetic Vector Reticle Removed**: Synthetic vector reticles (fabricated roads, grid lines) are strictly prohibited from evidence content. They must never be used as evidence content or burned into the Evidence JPEG.
     * **Canonical Cache Fallback**: Cached/static imagery may remain as an evidence fallback *only* when it represents the exact same canonical map state (matching active `mapType`, center coordinate displacement $\le 20\text{m}$, and age $\le 5\text{min}$). If no canonical state is available, the minimap container retains its neutral background without fabricated geography.
     * **Downstream Viewers**: Photo Evidence Detail and Immersive Evidence Viewer display the burned-in JPEG pixels directly (`Image.file(File(displayPath))`) and must never fetch, query, or independently re-render the minimap.
   - **Documented PlatformView / Vector-Overlay Architecture & Limitation**:
     * In Flutter on Android, `GoogleMap` is rendered in a native PlatformView (`TextureView`/GL surface). `GoogleMapController.takeSnapshot()` returns only the underlying base map raster (tiles, labels, landmarks, terrain).
     * The Flutter widget overlays (red teardrop pin, orange radar circle, blue heading cone, Google attribution pill) reside in Flutter's widget tree above the platform view and cannot be composited into `takeSnapshot()`.
     * The evidence pipeline re-composites these overlays onto the native snapshot in `WatermarkDrawer` as vector graphics scaled to native photo resolution ($s = \text{width} / 400.0$).
     * This architecture guarantees **semantic visual provenance** (identical source imagery from $T_0$, matching vector overlays and heading angle at evidence resolution) rather than raw physical screen framebuffer capture.

3. **Dynamic Font-Size Scaling & Zero-Overflow Invariant**:
   - Font scale is dynamically calculated based on available metadata card width:
     $$\text{fontScale} = \operatorname{clamp}\left(\frac{\text{availableWidth}}{250.0}, 0.82, 1.0\right)$$
   - Proportional font reduction occurs **prior** to any line wrapping.
   - Zero container clipping, zero horizontal overflow, and zero orphaned lines across all supported portrait/landscape aspect ratios.

### Validation & Acceptance State
- **Automated Verification**: Complete and passing (476/476 tests passing across repository, including targeted minimap provenance tests, geometry tests, evidence processing tests, and 0 `flutter analyze` issues).
- **Physical-Device Visual Validation (Accepted)**: Verified on physical Motorola edge 50 fusion (`ZA222NBPPV` / Android 16 / API 36). Live camera capture minimap at $T_0$ matched the burned minimap in Photo Evidence Detail and Immersive Viewer across Normal vector and Satellite imagery modes, with 1:1 visual correspondence across base tiles, center viewport, teardrop pin, radar circle, compass heading cone, and Google attribution. Downstream viewer displays burned JPEG without secondary map instantiation.

## 7.5 Capture controls

Photo mode:
- 72px circular shutter button with orange brand accent ring
- Gallery shortcut button with unreviewed media badge count
- Camera flip button

Video mode:
- Red recording control with duration badge
- Elapsed duration indicator during active recording

Mode switch:
`PHOTO | VIDEO`

## 7.6 GPS state logic

GPS status and geotag information update in real time from the active GNSS stream.
- Dedicated GPS status pill in top bar (`GPS: High • ±3m`, `GPS: Weak • ±12m`, etc.)
- Throttle visual updates approximately every 1–2 seconds to prevent UI jitter.
- If no GPS fix has ever been obtained: disable shutter and show `Waiting for GPS lock`.
- If accuracy is worse than threshold (20m default): allow capture with `DEGRADED` status and store `low_accuracy: true`.

------------------------------------------------------------------------

# 8. Review & Tag

Review & Tag appears immediately after every photo/video capture.

## Core Architectural Invariant: Single-HUD Rendering
- **The canonical Evidence JPEG (`evid_<id>.jpg`) already contains the complete Minimap + Metadata HUD permanently burned into its pixels.**
- Review & Tag renders the canonical Evidence JPEG itself (`BoxFit.contain`) and **MUST NOT render a secondary or external HUD card**.
- Exactly ONE HUD is visible on screen: the HUD physically burned into the Evidence JPEG.

## Review & Tag Components:
- Large captured Evidence JPEG preview (`BoxFit.contain` with zero edge cropping)
- Activity / Work Stage free-text input
- Observation Type single-select
- Optional Note / Reference code field
- Smart-link suggestion banner (when applicable)
- Action buttons: Retake and Confirm & Save

## 8.1 Activity / Work Stage

User input field (blank by default for custom entry):

- Free-text input where the inspector enters the relevant work stage / activity description (e.g. Excavation, Foundation, PCC, Rebar, Finishing, etc.)
- Allows custom inspector naming per project requirements

## 8.2 Observation Type

Single select:

-   Progress
-   Non-Conformity (silently treated as "Before" in smart-link)
-   Closed (silently treated as "After" in smart-link)
-   Material
-   General

Observation type drives nearby-search grouping.

## 8.3 Note / Reference

Optional free-text field for:

-   specification clause
-   drawing number
-   reference code
-   short observation

NCR numbering is outside Phase 1.

## 8.4 Smart-link

When the user records an observation as `Closed` (silently treated as `After`):

1.  search within default 10 m
2.  same site
3.  same activity
4.  observation type `Non-Conformity` (silently treated as `Before`)
5.  captured earlier
6.  prioritize nearest/recent plausible match

If a plausible match is found, show:

> Nearby Non-Conformity photo, 3.2 m away, taken 2 days ago --- link as Resolved?

Actions:

-   Link
-   Not now

The system MUST NOT automatically link evidence without user
confirmation.

## 8.5 Actions

Retake:

-   discard the current capture
-   return to camera

Save:

-   write media to local file storage
-   generate thumbnail
-   calculate SHA-256
-   write metadata to local database
-   add to sync queue
-   show in Gallery

------------------------------------------------------------------------

# 9. Gallery

The Gallery is a local media library designed for **1,000+ items**.

## 9.1 Rendering

Use virtualized/lazy rendering.

Never decode full-resolution originals for the entire grid.

Generate approximately 200 px thumbnails at capture time.

## 9.2 Filters

Provide:

-   date range
-   activity
-   observation type
-   sync status
-   low GPS accuracy only

## 9.3 Search

Search:

-   site name
-   note text
-   reference code

## 9.4 Context actions

Long-press a thumbnail to show:

-   Find Nearby
-   other appropriate media actions

## 9.5 Views

Provide:

-   Grid view
-   Map view

Map view shows media pins, with clustering where appropriate.

## 9.6 Sync state

Each media item should expose:

-   queued
-   syncing
-   synced
-   failed

------------------------------------------------------------------------

# 10. Media Detail

Display:

-   full photo/video
-   burned-in geotag stamp where applicable
-   capture time
-   coordinates
-   accuracy
-   activity
-   observation type
-   note
-   SHA-256 integrity hash
-   file size
-   synchronization status

Primary action:

**Find Nearby Media**

Secondary actions:

-   Edit Tags
-   Share
-   Delete from Device / Remove from Gallery

### Deletion & Cloud Recovery Policy (M7-02-II-B)

1. **Delete from Device**: Physically removes all local media files (`orig_*`, `evid_*`, `thumb_*` for photos; `orig_*`, `thumb_*` for videos) belonging to the media item from device storage to fully reclaim storage space. The SQLite database record is preserved (`is_deleted = 0`) to maintain cloud identity and enable subsequent on-demand recovery, while the immutable cloud backup remains intact.
2. **Remove from Gallery / Archive**: Physically removes all local media files belonging to the media item and marks the SQLite record as soft-deleted (`is_deleted = 1`) to remove/hide the item from the local Gallery/Archive presentation, while preserving the immutable cloud copy.
3. **Critical Invariant**: Neither local deletion operation may delete the cloud copy. Local deletion MUST NEVER delete Firebase Storage objects or Firestore documents. Cloud originals remain write-once immutable.
4. **Destructive Warning for Unsynced Media**: If media has not been synchronized to the cloud (`synced != 1`), deletion requires an explicit, prominent destructive warning confirming that the media is not backed up and will be permanently lost with no recovery option.
5. **Cloud Recovery**: Cloud-backed media whose local files were removed can be recovered on demand via forensically verified (`sha256_hash`) download from Firebase Cloud Storage.

------------------------------------------------------------------------

# 11. Nearby Media Search

Entry points:

-   Media Detail → Find Nearby
-   Gallery long-press → Find Nearby

## 11.1 Radius

Provide:

-   2 m
-   5 m
-   10 m
-   25 m
-   50 m
-   Custom

## 11.2 Filters

-   same site only --- default ON
-   activity
-   observation type
-   date range

## 11.3 Results

Group by:

-   Before
-   After
-   Progress / Material / General

Each row displays:

-   thumbnail
-   distance
-   timestamp
-   activity badge

Within each group:

1.  sort by distance
2.  then recency

## 11.4 Suggested pair

When source media is `Before` or `After`:

-   identify best opposite-type nearby match
-   display a prominent suggestion
-   provide one-tap Link action

## 11.5 Map

Display:

-   source pin
-   nearby media pins
-   radius circle
-   selected/source location

## 11.6 Location timeline

Provide:

**See full history at this point**

This ignores observation grouping and displays everything captured
within the selected radius from oldest to newest.

This supports lifecycle documentation such as:

`Excavation → Foundation → RCC → Masonry`

------------------------------------------------------------------------

# 12. Settings & Sync

## GPS

-   GPS accuracy threshold
-   high-accuracy mode

## Watermark

-   watermark template
-   displayed fields
-   address on/off

## Nearby Search

-   default radius

## Storage

-   cache size
-   thumbnail regeneration
-   clear synced originals locally

## Sync

-   pending items
-   failed items
-   retry
-   sync status

The sync UI must be production-ready even when cloud synchronization is
unavailable.

------------------------------------------------------------------------

# 13. Geotagging

Two layers are required for photos.

## 13.1 EXIF

Write machine-readable GPS metadata where supported:

-   GPSLatitude
-   GPSLongitude
-   GPSAltitude
-   GPSTimeStamp

## 13.2 Canonical Evidence File Model & Pipeline

SiteLens implements a strict three-tier evidence artifact pipeline with an explicit isolate execution boundary:

```text
Camera Capture
      │
      ├──> orig_<id>.jpg   (Pristine original capture, untouched)
      │
      └──> UI Isolate
             ├─ resolve minimap (3-tier resolution)
             ├─ HudFormatter.fromSnapshot → HudData
             ├─ WatermarkDrawer.renderVectorHudPngFromData → hudPngBytes (~20ms via dart:ui engine)
             │
             └──── Isolate.run ────→
                   Background Worker Isolate (image: ^4.8.0)
                    ├─ JPEG decode
                    ├─ EXIF orientation baking
                    ├─ Aspect-ratio crop
                    ├─ HUD compositing
                    ├─ JPEG encode (95% quality)
                    ├─ SHA-256 integrity hash calculation
                    └─ 200px thumbnail generation
                          │
                          ├──> evid_<id>.jpg   (Canonical Evidence JPEG with burned HUD)
                          │         │
                          │         └──> thumb_<id>.jpg (Thumbnail derived directly from evid_<id>.jpg)
                          │
                          ▼
               Downstream Surfaces (Review & Tag, Gallery, Detail, Immersive, Share, PDF, ZIP, Sync)
               [Single-HUD Invariant: Render evid_<id>.jpg directly with ZERO secondary HUD reconstruction]
```

### Isolate Execution Boundary
- **UI Isolate Execution**: Lightweight vector HUD layout and rasterization (`WatermarkDrawer.renderVectorHudPngFromData`) executes on the main UI isolate (~20ms) using Flutter engine native bindings (`dart:ui.PictureRecorder`, `Canvas`, `TextPainter`).
- **Isolate Crossing (`Isolate.run`)**: Only resolved, self-contained raw byte buffers (`originalBytes`, `hudPngBytes`, and `targetAspectRatio`) cross the isolate boundary into the background worker isolate.
- **Worker Isolate Execution**: CPU-intensive pixel manipulation (pure Dart `package:image` decoding, orientation correction, cropping, compositing, JPEG encoding, SHA-256 computation, and thumbnail scaling) runs entirely in the background worker isolate.
- **Constraint**: The background worker isolate does not and cannot run `dart:ui`, Canvas, `PictureRecorder`, `TextPainter`, or Flutter font rendering.

### The Three Evidence Artifacts:
1. **`orig_<id>.jpg`**: Pristine original camera capture, stored untouched for non-repudiation and forensic verification.
2. **`evid_<id>.jpg`**: The authoritative **canonical Evidence JPEG**. Contains the full Minimap + Metadata HUD composite burned permanently into its pixels at native resolution.
3. **`thumb_<id>.jpg`**: Derived directly from `evid_<id>.jpg` for high-performance gallery browsing while preserving the burned HUD badge.

### Core Architectural Invariant: Single-HUD Rendering
> **Create HUD once → burn it once → store it once → downstream surfaces display the canonical `evid_<id>.jpg` without reconstructing another HUD.**

Downstream surfaces conform strictly to this invariant:
- **Review & Tag**: Displays `evid_<id>.jpg` with `BoxFit.contain`. Zero external HUD widgets.
- **Gallery**: Displays `thumb_<id>.jpg` (derived from canonical evidence) inside uniform aspect tiles.
- **Photo Evidence Detail**: Displays full `evid_<id>.jpg` via `BoxFit.contain` with interactive zoom and technical telemetry sheets.
- **Immersive Evidence Viewer**: Fullscreen darkroom viewport rendering `evid_<id>.jpg` with full zoom/pan capability.
- **Single-Item Share Sheet**: Shares canonical `evid_<id>.jpg` file directly to external apps.
- **PDF Evidence Export**: Embeds canonical `evid_<id>.jpg` via `pw.BoxFit.contain` wrapped in `pw.Center`, guaranteeing complete burned HUD visibility with zero edge clipping.
- **ZIP Evidence Export**: Bundles canonical `evid_<id>.jpg` alongside metadata JSON and CSV indexes.
- **Cloud Synchronization**: Uploads `orig_<id>.jpg` and `thumb_<id>.jpg` with metadata matching `evid_<id>.jpg`.

For video:
- Provide a static opening-frame stamp.
- Store equivalent structured metadata.
- Full per-frame video burn-in is deferred beyond Phase 1.

------------------------------------------------------------------------

# 14. Nearby Search Technical Requirement

For approximately 1,000 media items, nearby search MUST use the local
SQLite database.

Algorithm:

1.  Convert radius to a latitude/longitude bounding box.
2.  Query indexed `lat`/`lon` records.
3.  Apply optional site/activity/observation/date filters.
4.  Calculate exact Haversine distance.
5.  Remove candidates outside the true radius.
6.  Sort by distance then recency.
7.  Group by observation type.

Do not introduce PostGIS, R-Tree, or another spatial database for Phase
1 unless actual measured requirements justify it.

Future scaling may move the operation server-side.

------------------------------------------------------------------------

# 15. Data Model

## 15.1 Local sites

``` sql
CREATE TABLE sites (
  id TEXT PRIMARY KEY,
  site_code TEXT,
  name TEXT,
  address TEXT
);
```

## 15.2 Local media

``` sql
CREATE TABLE media (
  id TEXT PRIMARY KEY,
  site_id TEXT REFERENCES sites(id),
  uri TEXT NOT NULL,
  thumb_uri TEXT,
  type TEXT CHECK(type IN ('photo','video')),
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  accuracy_m REAL,
  low_accuracy INTEGER DEFAULT 0,
  activity_tag TEXT,
  observation_type TEXT CHECK(
    observation_type IN (
      'progress',
      'non-conformity',
      'closed',
      'material',
      'general'
    )
  ),
  linked_media_id TEXT REFERENCES media(id),
  note TEXT,
  captured_at TEXT NOT NULL,
  sha256_hash TEXT,
  synced INTEGER DEFAULT 0
);

CREATE INDEX idx_media_lat ON media(lat);
CREATE INDEX idx_media_lon ON media(lon);
CREATE INDEX idx_media_site ON media(site_id);
CREATE INDEX idx_media_obs ON media(observation_type);
CREATE INDEX idx_media_captured ON media(captured_at);
```

The implementation may add synchronization fields such as sync state,
error message, retry timestamp, and remote ID without changing the
functional data model.

------------------------------------------------------------------------

# 16. Firebase Data Model

Firebase is the cloud backend.

Recommended conceptual structure:

``` text
users/{uid}

sites/{siteId}

sites/{siteId}/members/{uid}

sites/{siteId}/media/{mediaId}
```

Media documents should contain the cloud representation of relevant
metadata, including:

-   media ID
-   site ID
-   storage paths
-   media type
-   latitude
-   longitude
-   accuracy
-   low-accuracy flag
-   activity
-   observation type
-   linked media ID
-   note
-   capture timestamp
-   SHA-256 hash
-   creator/user ID
-   synchronization metadata

Cloud Storage conceptual paths:

``` text
sites/{siteId}/media/{mediaId}/original
sites/{siteId}/media/{mediaId}/thumbnail
```

Firebase Security Rules MUST restrict access according to authenticated
user/site membership.

------------------------------------------------------------------------

# 17. Offline and Synchronization Requirements

The app MUST remain useful without network connectivity.

Offline operation must support:

-   active cached site
-   GPS
-   photo/video capture
-   local media processing
-   thumbnail generation
-   SHA-256
-   local database write
-   gallery
-   nearby search
-   Before/After linking
-   queued synchronization

Synchronization flow:

``` text
Capture
  ↓
Local file + local DB
  ↓
Sync queue
  ↓
Connectivity available
  ↓
Upload original
  ↓
Upload thumbnail
  ↓
Write Firestore metadata
  ↓
Confirm success
  ↓
Mark local item synced
```

If synchronization fails:

-   preserve local media
-   preserve local metadata
-   mark sync as failed
-   expose Retry

Firebase availability must never determine whether an inspection photo
is successfully captured locally.

------------------------------------------------------------------------

# 18. Chain of Custody / Integrity

Because SiteLens is intended for inspection evidence:

-   SHA-256 MUST be calculated immediately on save.
-   Original pixel data MUST remain immutable.
-   Annotations/markup MUST be stored separately.
-   The original plus hash must remain verifiable.
-   The burned-in geotag provides visible provenance.

A cloud copy must not silently replace or alter the local original.

------------------------------------------------------------------------

# 19. Flutter Implementation Requirements

The application MUST be implemented in Flutter.

Recommended implementation components:

  Capability         Recommended implementation
  ------------------ --------------------------------------------
  UI                 Flutter
  Language           Dart
  Authentication     Firebase Authentication
  Cloud database     Cloud Firestore
  Cloud files        Firebase Cloud Storage
  Local database     Drift / SQLite
  State management   Riverpod
  Camera             Flutter camera integration
  Location           Flutter location/geolocation integration
  Maps               Google Maps Flutter or approved equivalent
  Hashing            Dart SHA-256 implementation
  Local files        Flutter filesystem integration
  Image processing   Flutter-compatible image processing
  Crash reporting    Firebase Crashlytics
  Analytics          Firebase Analytics, optional

Exact package selection may be made during implementation based on
current Flutter compatibility and the existing project.

------------------------------------------------------------------------

# 20. Performance Requirements

For 1,000+ media items:

-   thumbnails must be generated at capture time
-   Gallery must use lazy/virtualized rendering
-   full-resolution images must not be loaded for the whole grid
-   nearby search must use indexed bounding-box filtering
-   Haversine refinement must operate only on candidates
-   capture must remain responsive
-   synchronization must run independently from capture
-   UI must not perform expensive full-library work on the main isolate (CPU-heavy JPEG decoding/encoding, orientation baking, cropping, SHA-256 calculation, and thumbnail generation execute in a background isolate via `Isolate.run`; lightweight vector HUD rasterization runs on the UI isolate using native engine bindings prior to crossing the boundary)

Future scale beyond approximately 20--50k items may justify a spatial
index or server-side spatial query, but this is not required for Phase
1.

------------------------------------------------------------------------

# 21. Security Requirements

-   Firebase Authentication must provide identity.
-   Firestore Security Rules must enforce authorized access.
-   Storage Rules must protect media.
-   No Firebase service-account credentials may be embedded in the
    Flutter application.
-   API keys/configuration must use the appropriate platform
    configuration and security controls.
-   Local evidence must remain protected by the device/application
    security model.
-   Cloud sync failures must never result in local evidence deletion.

------------------------------------------------------------------------

# 22. UI/UX Design Requirements

The visual design is defined in `design.md`.

Google Stitch is used to generate and refine the UI.

The supplied visual references establish:

-   premium mobile UI
-   strong visual hierarchy
-   rounded surfaces
-   orange/amber accent
-   light neutral backgrounds
-   dark typography
-   prominent visual media
-   polished controls
-   subtle elevation
-   consistent spacing and radii

The references must be translated into the construction/inspection
context.

Do not copy fitness/AI-coach content from the references.

The UI must include polished states for:

-   loading
-   empty
-   error
-   offline
-   permission denied
-   permission recovery
-   GPS searching
-   poor GPS
-   no nearby media
-   sync pending
-   sync failed
-   sync success

------------------------------------------------------------------------

# 23. Accessibility

The Flutter UI should provide:

-   readable typography
-   adequate contrast
-   appropriate touch targets
-   semantic labels
-   screen-reader support
-   state communication that does not rely solely on color
-   usable controls in outdoor/site conditions

------------------------------------------------------------------------

# 24. Testing Requirements

## Unit tests

Cover:

-   GPS accuracy classification
-   bounding-box calculation
-   Haversine distance
-   nearby filtering
-   Before/After matching
-   SHA-256 generation
-   synchronization state transitions

## Widget tests

Cover:

-   authentication states
-   permission onboarding
-   permission recovery
-   GPS status
-   camera controls
-   Review & Tag
-   smart-link prompt
-   gallery filtering
-   nearby grouping
-   settings
-   sync states

## Integration tests

Cover:

-   login → permission onboarding → site setup
-   offline session behavior where supported
-   capture → local save
-   offline capture
-   gallery
-   nearby search
-   Before/After linking
-   reconnect → Firebase synchronization
-   failed synchronization → retry
-   permission revocation and recovery

------------------------------------------------------------------------

# 25. Build Roadmap --- Phase 1

The Phase 1 build roadmap reflects the completed, tested (362/362 tests passing, 100%), and hardware-validated implementation baseline:

## M0 --- Project Foundation (Delivered & Accepted)

Deliver:

-   Flutter project structure (Dart 3.6.2, Flutter 3.27.4)
-   Firebase project configuration (`sitelens-prod-80e7b`)
-   Strict Firebase Authentication foundation (Email/Password, Google Sign-In)
-   Local SQLite / Drift data layer (schema v6: `Sites`, `Media`, and `GooglePhotosSyncEntries` tables + 5 custom SQLite indexes)
-   Riverpod state management architecture
-   Dynamic session routing & lifecycle observers
-   Safety Orange (`#F27A1A`) Design System tokens & responsive shared widgets
-   Hardware services (Camera, Location, Storage, Connectivity, Permission)
-   Forensic utility foundations: SHA-256 (`CryptoUtils`), Haversine distance, Bounding Box computation, GPS accuracy evaluation (`GPSUtils`)
-   Comprehensive automated unit & widget test harness

## M1 --- Onboarding & Site Setup (Delivered & Validated)

Deliver:

-   Welcome screen with value proposition & compliance framing
-   Login screen with strict Firebase Auth, password visibility toggle, and error handling
-   Mandatory Terms of Service & Privacy Policy agreement checkbox on Login & Settings
-   First-login detection & dynamic `SessionRouter`
-   First-login permission onboarding (Camera, Location, Photos, Microphone, Notifications)
-   Permission recovery screen for denied/permanently denied OS states
-   App resume lifecycle watcher (`WidgetsBindingObserver`) for automatic permission state restoration
-   Project picker & Site picker
-   Offline-first site creation and site card deletion
-   Active site local persistence & context propagation across all screens

## M2 --- Precision Optical Camera, Minimap & GPS (Delivered & Accepted)

Deliver:

-   Native uncropped 4:3 optical viewfinder aspect ratio preserving sensor bounds
-   Default 0.5x wide zoom (rear camera clamped to sensor minimum) and 1.0x fixed optical (front camera)
-   Expandable camera side controls: Aspect Ratio cycling (4:3, 16:9, 1:1) and Capture Timer presets (Off, 3s, 5s, 10s)
-   95% JPEG quality compression with preserved EXIF geotagging
-   Live GPS acquisition stream (`geolocator: ^13.0.2`) with reverse geocoding and offline fallback (`geocoding: ^4.0.0`)
-   User-configurable timestamp display preferences (Local/UTC, 24h/12h/ISO formats)
-   Combined shutter lock: Camera Ready + Valid GPS Fix (shutter blocked before first GPS lock)
-   GPS accuracy classification: High ($\le 5\text{m}$), Weak ($5\text{m}–20\text{m}$), Degraded ($>20\text{m}$), Searching
-   High-clarity Google Minimap engine: Live Hybrid GoogleMap at Zoom 18.0 (vector roads, yellow lines, boundary labels over aerial imagery), 300x300 @ 2x retina cached static map with `FilterQuality.high`, 1.24:1 aspect ratio container with 42% max width cap and equal-height metadata pairing, 250ms `AnimatedSwitcher` cross-fade, dynamic Normal (blueprint/vector) and Satellite map type switching
-   `AppLifecycleState.inactive` resilience (optical camera stream stays live during OS screenshots and notification drawer swipes)
-   Isolate-partitioned evidence processing pipeline: UI isolate vector HUD rendering (~20ms via engine bindings) + background worker isolate (`image: ^4.8.0`) for JPEG decoding/encoding, orientation baking, cropping, SHA-256 calculation, and thumbnail generation
-   Three-tier media storage model: immutable camera original (`orig_*.jpg`), derived full-width burned-in evidence (`evid_*.jpg`), derived 200px max thumbnail (`thumb_*.jpg`)
-   Option B HUD Architecture: canonical `HudData` semantic DTO, `HudLayoutSpec` layout specification, `HudFormatter` single source of truth for text formatting, Canvas vector renderer `WatermarkDrawer` with zero geometry delta, and Flutter live viewfinder renderer aligned to 0.42 max map width fraction
-   Non-circular SHA-256 provenance hashing (`CryptoUtils`), synchronous capture metadata snapshotting, atomic failure cleanup, Drift SQLite persistence

## M3 --- Video, Review & Tag, Smart-Link & Recovery (Delivered & Accepted)

Deliver:

-   Video capture with live duration badge, recording state machine, and clean stop affordance
-   Captured media review surface (photo zoom preview & video playback)
-   Clean custom text Activity input field (blank by default for project-specific flexibility)
-   Observation selector with 5 items: `Progress`, `Non-Conformity` (treated as Before), `Closed` (treated as After), `Material`, `General`
-   Single-row horizontal scroll observation selector with $\ge 46\text{dp}$ touch target ergonomics
-   Strict Closed observation business rule: Closed is strictly AFTER evidence requiring an eligible OPEN Non-Conformity within $\le 10.0\text{m}$ on same site (saving blocked if no match is linked or explicitly confirmed)
-   `SmartLinkCard` with explicit user confirmation for linking Before/After pairs
-   Expandable & copyable full SHA-256 forensic checksum
-   Model A pending artifact lifecycle with safe retake cleanup (zero DB row before commit)
-   In-flight video recording recovery on lifecycle interruption (`R1`): in-flight video preserved on interruption, genuine `MediaItem` persisted via "Keep for later", disk files cleaned up on explicit user "Discard"
-   Atomic Drift SQLite persistence upon save

## M4 --- Gallery, Media Detail, Forensic Export & Sharing (Delivered & Accepted)

Deliver:

-   Virtualized lazy grid supporting 1,000+ items with smooth 60fps scrolling
-   Thumbnail caching with 200px max capture-time downsampling
-   Multi-facet filtering: Date Range, Activity, Observation Type, Sync Status, Low GPS Accuracy
-   Search by site name, notes, and reference code
-   Grid and Map view toggle with clustered spatial pins
-   Media Detail screen with chunked telemetry architecture:
    -   `GEOGRAPHIC & SPATIAL` card (coordinates, accuracy, altitude, distance to site, reverse geocoded address)
    -   `TIMESTAMP & METADATA` card (capture time, device timezone, activity, observation type, notes)
    -   `FORENSIC INTEGRITY` card (full SHA-256 hash, file size, storage paths, sync state)
-   Full-screen `InteractiveViewer` photo inspector and local video player
-   M4-A mandatory physical address overlay & persistence (Drift v4 schema)
-   M4-B sensor aspect ratio & mode resolution switching (`ResolutionPreset.max` for Photo, `veryHigh` for Video)
-   M4-D single evidence share + stamped PDF audit report card + SHA-256 clipboard copy
-   M4-E batch multi-select gallery mode + batch file share + multi-page inspection PDF export + structured forensic ZIP package export (`manifest.json` + `inspection_report.pdf` + media files)
-   Soft delete semantics (`is_deleted = 1`) with sync-aware destructive warnings

## M5 --- Nearby Media Search, Spatial Map & Filters (Delivered & Accepted)

Deliver:

-   Entry points from Media Detail ("Find Nearby Media") and Gallery long-press
-   Radius selector with presets: 2m, 5m, 10m, 25m, 50m, and Custom radius
-   Fast local bounding-box query + exact Haversine distance refinement
-   Grouped results: Before, After, Progress / Material / General
-   Suggested Before/After pairing card with one-tap link action
-   Interactive GoogleMap spatial canvas with azure source pin, color-coded candidate markers, and radius boundary circle
-   Chronological location lifecycle timeline ("See full history at this point") showing complete site stage progression (e.g. Excavation → Foundation → RCC → Masonry)
-   Filter bottom sheet modal (Same Site, Activity, Observation Type, Date Range) with active filter badge and dismissible chip strip
-   Context-preserving reset maintaining selected radius

## M6 --- Firebase Cloud Synchronization & Security Hardening (Delivered & Validated)

Deliver:

-   M6-A Security Rules hardening: `firestore.rules` and `storage.rules` validated via Firebase MCP with active membership semantics, secure bootstrap flow, self-join elimination, forensic field immutability, soft-delete authorization, disaggregated original/thumbnail storage paths, UI credential sanitation
-   M6-B Asynchronous synchronization queue (`SyncCoordinator`) with exponential backoff and retry
-   Firebase Cloud Storage uploads (original + thumbnail)
-   Cloud Firestore metadata synchronization (`CloudSyncService` persisting `creator_id`, `captured_address`, `evidence_sha256_hash`)
-   Real-time `SyncStatusBadge` across Gallery, Media Detail, and Camera top bar
-   Automatic reconnection listener & background sync recovery
-   Deterministic cloud copy protection: cloud originals remain write-once immutable and are never deleted by local device deletions

## M7 --- Settings, Storage Cleanup, Cloud Recovery & Google Photos (Delivered & Validated)

Deliver:

-   Unified `SettingsScreen` hub with consistent section card geometry and padding rhythm
-   GPS accuracy threshold settings model & modal (`setting_gps_low_accuracy_threshold`, default 20.0m)
-   Watermark display preferences: `showAddress`, `showMapTile`, custom timestamp formats
-   Nearby search defaults (`nearbySettingsProvider` dynamically initializing `NearbySearchNotifier`)
-   Storage cleanup: "Clear Synced Photo Originals Locally" (`StorageCleanupService`) safely deleting local originals while preserving evidence/thumbnail files and Firestore metadata
-   Cloud media recovery: missing local files recovered on demand via `CloudMediaRecoveryService` with deterministic Cloud Storage path resolution and forensic SHA-256 verification against `MediaItem.sha256Hash`
-   Local media deletion semantics: synced media deletes local files + soft-deletes SQLite (`is_deleted = 1`); unsynced media deletes local files + hard-deletes SQLite with explicit destructive warning
-   Optional Google Photos Auto-Sync subsystem: Drift SQLite schema v6 (`google_photos_sync_entries`), least-privilege OAuth scope (`photoslibrary.appendonly`), application-owned `SiteLens Evidence` album management, background retry/backoff queue, Settings card UI, genuine `mediaItem.id` verification, startup un-queued media sweep, and strict decoupling from authoritative Firebase sync
-   Modernized full-width `WatermarkDrawer` layout with scale alignment and single-line clean character drawing (`_drawCleanText`)
-   Responsive & adaptive two-pane tablet/desktop layouts across all screens
-   Security & defensive hardening: path traversal sanitization in `EvidenceStorageService.resolveAbsolutePath()` and user enumeration mitigation in `LoginScreen._parseAuthError()`

------------------------------------------------------------------------

# 26. Acceptance Criteria

Phase 1 is complete only when:

### Authentication & Compliance

-   user can authenticate through Firebase Authentication (Email/Password, Google Sign-In)
-   mandatory email verification is enforced where applicable
-   mandatory Terms of Service & Privacy Policy agreement checkbox is verified on Login & Settings
-   authenticated sessions are restored appropriately across app restarts
-   authentication failures and network errors are gracefully handled without account enumeration leakage

### Permissions

-   first-login permission onboarding explains and requests Camera, Location, Photos, Mic, and Notifications
-   denied and permanently denied states are handled with clear recovery CTAs to OS Settings
-   permissions are automatically rechecked when the application resumes from background (`AppLifecycleState.resumed`)

### Site Setup

-   user can select active project and site
-   user can create new sites offline-first and delete obsolete sites
-   site ID, site name, physical address, and reference location are immediately available to capture
-   cached site information works fully offline

### Precision Capture & Minimap

-   photo and video capture work reliably
-   optical viewfinder provides native 4:3 uncropped sensor preview with default 0.5x wide zoom
-   expandable side controls support aspect ratio cycling and capture timer presets
-   live GPS status badge is visible with accuracy classification
-   capture is strictly blocked before first valid GPS fix
-   low-accuracy capture is visually flagged and tagged in metadata
-   geotag HUD card is permanently burned into saved evidence photo pixels
-   photo EXIF GPS metadata is written with 95% JPEG quality
-   Google Minimap provides crisp Hybrid satellite/vector overlay at Zoom 18.0 with smooth 250ms cross-fade in a 1.24:1 aspect ratio container with 42% max width cap and equal-height metadata pairing
-   `AppLifecycleState.inactive` preserves optical camera stream during OS screenshots

### Review & Tag

-   activity stage can be entered via custom text
-   observation type can be selected from 5 items with $\ge 46\text{dp}$ touch ergonomics
-   strict Closed observation rule enforces linking to an eligible OPEN Non-Conformity within $\le 10\text{m}$
-   `SmartLinkCard` requires explicit user confirmation before linking
-   full SHA-256 hash is viewable and copyable
-   Retake discards pending files safely without orphan SQLite records
-   in-flight video recordings interrupted by OS events can be kept for later or discarded
-   Save writes atomically to local file storage and SQLite

### Gallery & Media Detail

-   1,000+ items can be browsed with smooth virtualized rendering
-   thumbnails (200px max) are generated at capture time and cached
-   multi-facet filters (date, activity, observation, sync, low GPS) and search work correctly
-   Grid and Map views display accurate media pins
-   Media Detail displays chunked telemetry cards (Geographic & Spatial, Timestamp & Metadata, Forensic Integrity)
-   full-screen `InteractiveViewer` supports inspection of burned-in evidence photos and video playback
-   single evidence share, stamped PDF audit report card, and SHA-256 clipboard copy work reliably
-   batch multi-select supports batch sharing, multi-page inspection PDF export, and structured forensic ZIP package export (`manifest.json` + `inspection_report.pdf` + media)

### Nearby Search & Timeline

-   radius selector (2m–50m / Custom) filters results using fast bounding-box + exact Haversine distance
-   results are grouped by Before, After, and Progress/Material/General, sorted by distance then recency
-   suggested Before/After pairing displays prominent link action
-   interactive GoogleMap canvas displays source pin, candidate markers, and radius boundary
-   location lifecycle timeline displays full historical progression from oldest to newest

### Offline & Cloud Synchronization

-   capture, gallery, nearby search, and local storage work completely offline without network
-   `SyncCoordinator` automatically enqueues and uploads media and metadata when connectivity returns
-   failed sync items can be retried manually or via exponential backoff
-   Firebase Security Rules strictly restrict unauthorized cloud access
-   local original clearing frees storage space while preserving evidence/thumbnail files
-   cloud media recovery downloads missing files on demand with forensic SHA-256 verification
-   local deletion operations never delete write-once immutable Cloud Storage or Firestore records

### Google Photos Integration

-   optional Google Photos auto-sync uploads captured evidence to a dedicated `SiteLens Evidence` album
-   zero-loss startup sweep discovers and uploads any un-queued media items
-   Google Photos sync operates independently and decoupled from authoritative Firebase sync

### Forensic Integrity

-   non-circular SHA-256 hash is generated synchronously on save
-   original camera pixels remain immutable (`orig_*`)
-   derived evidence (`evid_*`) contains visible burned-in provenance watermark
-   exported PDFs and ZIP packages contain complete chain-of-custody metadata

------------------------------------------------------------------------

# 27. Explicit Non-Goals

Do NOT implement as part of Phase 1:

-   WIR (Work Inspection Request) document generator
-   NCR (Non-Conformance Report) document generator
-   Excel / CSV compliance tabular exports
-   full enterprise multi-user role-based access control (RBAC)
-   centralized web management dashboard
-   server-side spatial search
-   PostGIS / R-Tree spatial indexing unless measured requirements justify it
-   full per-frame video geotag burn-in
-   automated evidence linking without user confirmation

------------------------------------------------------------------------

# 28. Relationship With Project Documents

The SiteLens project uses three primary engineering documents:

### `PRD.md`

Functional/product requirements, user experience specifications, and acceptance criteria.

### `architecture.md`

Technical architecture, data models, service interfaces, and implementation boundaries (**FROZEN v1.0**).

### `design.md`

Visual design system, typography, color palettes, and Stitch design loop guidance.

Source-of-truth rules:

``` text
PRD.md
  ↓ defines WHAT
architecture.md
  ↓ defines HOW
design.md
  ↓ defines HOW IT SHOULD LOOK
Stitch
  ↓ generates/refines visual implementation
Flutter
  ↓ implements the approved product
```

No implementation should remove a requirement from `PRD.md` merely because it is inconvenient to implement.

No Stitch design should redefine product behavior.

No architectural decision should unnecessarily expand Phase 1 scope.

------------------------------------------------------------------------

# 29. Feature Alignment & Implementation Roadmap

## 29.1 Phase 1 Implemented & Validated Baseline (Production Ready)

The following E2E features are fully implemented, covered by 457/457 passing automated tests (100%), and validated on physical hardware (**Motorola edge 50 fusion / Moto G85 5G**):

| Feature Area | Implemented Capabilities & E2E Experience | Delivered Scope | Milestone Status |
| :--- | :--- | :--- | :--- |
| **Authentication & Compliance** | Strict Firebase Auth (Email/Password, Google Sign-In with least-privilege scopes), mandatory email verification, mandatory Terms of Service & Privacy Policy agreement checkbox on Login & Settings, dedicated legal modals, first-login detection, dynamic `SessionRouter`, generic credential error handling mitigating user account enumeration. | Complete M1 | **DELIVERED & GATED** |
| **Project & Site Context** | Multi-site management, offline-first site creation, site deletion with cascade safety, active site persistence, contextual site metadata propagation to camera watermark and media records. | Complete M1 | **DELIVERED & GATED** |
| **Precision Optical Camera** | Native uncropped 4:3 optical viewfinder, default 0.5x wide zoom (rear) / 1.0x fixed optical (front), expandable side controls (Aspect Ratio 4:3/16:9/1:1, Capture Timer Off/3s/5s/10s), 95% JPEG quality, EXIF geotagging, combined shutter lock (Camera Ready + Valid GPS Fix), `AppLifecycleState.inactive` screenshot resilience. | Complete M2 | **DELIVERED & GATED** |
| **High-Clarity Google Minimap** | Live GoogleMap at Zoom 18.0 as primary Camera Capture minimap with active Normal/Satellite layer switching; concurrent $T_0$ shutter-time snapshot capture; canonical state-matching cache fallback (same map type, $\le 20\text{m}$ displacement, $\le 5\text{m}$ age); synthetic vector reticle strictly prohibited from evidence content; burned-in JPEG evidence provenance invariant (Photo Evidence Detail & Immersive Viewer display burned pixels without map re-rendering); 1.24:1 aspect ratio container with 42% max width cap and equal-height metadata pairing. | Complete M2 | **DELIVERED & GATED** |
| **Evidence Processing & Watermark** | Option B HUD Architecture: canonical `HudData` semantic DTO, `HudLayoutSpec` layout specification, `HudFormatter` single source of truth for text formatting, Canvas vector renderer `WatermarkDrawer` with zero geometry delta, and Flutter live viewfinder renderer aligned to 0.42 max map width fraction. Isolate-partitioned pipeline: UI isolate vector HUD rendering (~20ms via engine bindings) + background worker isolate (`image: ^4.8.0`) for JPEG decoding/encoding, orientation baking, cropping, SHA-256 calculation, and thumbnail generation. Three-tier file model (`orig_*`, `evid_*`, `thumb_*`). Single-HUD downstream invariant (zero secondary HUD reconstruction). 457/457 automated tests passing; physical-device visual validation is the next outstanding validation phase. | Complete M2 | **DELIVERED & GATED** |
| **Review & Smart-Link** | Photo & video review, clean custom text Activity input, 5 Observation types (Progress, Non-Conformity, Closed, Material, General) with $\ge 46\text{dp}$ touch ergonomics, strict Closed observation rule ($\le 10\text{m}$ proximity to open Non-Conformity on same site), `SmartLinkCard` with explicit user confirmation, copyable full SHA-256 hash, safe retake cleanup, in-flight video recording interruption recovery (`R1` with Keep for Later / Discard). | Complete M3 | **DELIVERED & GATED** |
| **Gallery & Media Detail** | Virtualized lazy grid (1,000+ items), thumbnail caching, multi-facet filtering (Date Range, Activity, Observation Type, Sync Status, Low GPS), search (site, notes, reference), Grid/Map view toggle, Media Detail chunked telemetry architecture (`GEOGRAPHIC & SPATIAL`, `TIMESTAMP & METADATA`, `FORENSIC INTEGRITY`), full-screen `InteractiveViewer` photo inspector and local video player, soft delete semantics (`is_deleted = 1`). | Complete M4 | **DELIVERED & GATED** |
| **Forensic Export & Sharing** | Single evidence share + stamped PDF audit report card + SHA-256 clipboard copy, batch multi-select gallery mode + batch file share + multi-page inspection PDF export + structured forensic ZIP package export (`manifest.json` + `inspection_report.pdf` + media files). | Complete M4 | **DELIVERED & GATED** |
| **Nearby Spatial Search** | Local bounding-box + Haversine search (2m–50m presets / Custom), interactive GoogleMap canvas with azure source pin and color-coded candidate markers, grouped results (Before, After, Progress/Material/General), suggested Before/After pairing card, chronological location lifecycle timeline ("See full history at this point"), filter modal with active filter count badge and dismissible chip strip. | Complete M5 | **DELIVERED & GATED** |
| **Cloud Sync & Security** | Asynchronous `SyncCoordinator` queue with retry/backoff, Cloud Storage uploads (original + thumbnail), Firestore metadata synchronization (`creator_id`, `captured_address`, `evidence_sha256_hash`), `SyncStatusBadge` UI, declarative security rules (`firestore.rules`, `storage.rules`) with active membership semantics and forensic field immutability. | Complete M6 | **DELIVERED & GATED** |
| **Settings, Storage Cleanup & Recovery** | Unified `SettingsScreen` hub, GPS accuracy threshold modal (`setting_gps_low_accuracy_threshold`, default 20.0m), watermark settings (`showAddress`, `showMapTile`), nearby search settings (`nearbySettingsProvider` wiring), storage cleanup ("Clear Synced Photo Originals Locally" via `StorageCleanupService`), on-demand cloud media recovery (`CloudMediaRecoveryService`) with deterministic path resolution and forensic SHA-256 verification, sync-aware destructive local deletion warnings. | Complete M7 | **DELIVERED & GATED** |
| **Google Photos Auto-Sync** | Optional OAuth auto-upload to dedicated `SiteLens Evidence` album (`photoslibrary.appendonly` least-privilege scope), Drift SQLite schema v6 (`google_photos_sync_entries`), background retry/backoff queue, Settings card UI, genuine `mediaItem.id` verification, zero-loss startup un-queued media sweep, strict decoupling from authoritative Firebase sync. | Complete M7 | **DELIVERED & GATED** |
| **Responsive UI & Security Hardening** | Responsive layout framework (`ResponsiveBreakpoints`, `ResponsiveTwoPane`) supporting phones, tablets, and desktop foldables, path traversal sequence sanitization (`../`, `..\`) in `EvidenceStorageService.resolveAbsolutePath()`, user account enumeration mitigation in `LoginScreen._parseAuthError()`. | Complete Cross-Cutting | **DELIVERED & GATED** |

## 29.2 Phase 2 & Future Horizons (Commercial & Enterprise Scale)

Building on the verified Phase 1 media capture and forensic evidence foundation:

1. **Phase 2.1 — Formal Compliance & Audit Package Engine**:
   - **Automated WIR (Work Inspection Request) Generator**: Standardized engineering inspection request forms populated automatically with site telemetry, activity codes, specification references, and paired Before/After evidence photos.
   - **Automated NCR (Non-Conformance Report) Generator**: Formal construction non-conformance documents linking open Non-Conformity items, severity classifications, root-cause notes, corrective action deadlines, and verified Closed resolution evidence.
   - **Direct Excel / CSV Compliance Export**: Tabular spreadsheet exports with embedded high-resolution thumbnail images, geolocation hyper-links, inspector signatures, and verifiable SHA-256 hash ledgers.

2. **Phase 2.2 — Team Collaboration & Enterprise Multi-User**:
   - **Multi-Inspector Project Synchronization**: Real-time Firestore synchronization of open site observations across multi-disciplinary inspection teams (e.g. Structural, MEP, Geotechnical, Safety).
   - **Role-Based Access Control (RBAC)**: Fine-grained permissions for Field Inspectors (capture and tag), Lead Quality Auditors (approve and close NCRs), Subcontractor Representatives (view assigned tasks and upload resolution proof), and Project Managers (read-only audit dashboard).
   - **Real-Time Team Review & Approval Queues**: In-app workflow for reviewing, approving, or requesting retakes on submitted inspection evidence.

3. **Phase 2.3 — Web Management & Spatial Asset Portal**:
   - **Centralized Web Dashboard**: Browser-based enterprise portal for high-level site portfolio monitoring, KPI tracking (open vs closed NCRs), and bulk media export.
   - **Interactive Web Spatial Map**: Desktop GIS map viewer displaying all site evidence pins, drone/satellite CAD overlays, and chronological construction stage sliders.
   - **External Read-Only Verification Links**: Secure, time-limited, cryptographic verification URLs allowing external auditors, municipal inspectors, and insurance underwriters to verify evidence provenance and SHA-256 integrity without account creation.

4. **Phase 2.4 — Scaled Spatial Analytics & Server-Side Geo-Search**:
   - **Cloud Geohash & Spatial Indexing**: Server-side spatial query engine for enterprise projects with 50,000+ evidence items across expansive infrastructure corridors (highways, railways, utility pipelines).
   - **Automated 3D Construction Timeline Reconstruction**: Automated spatio-temporal clustering of inspection photos to render 3D timeline reconstructions of structural progress.
