# SiteLens --- Phase 1 Product Requirements Document

## Geo-tagged photo/video capture, gallery, and GPS-based nearby-media search

### 1. Product Scope

SiteLens Phase 1 provides:

**capture → tag → store → find-nearby → optional cloud synchronization**

The application is a **Flutter mobile application** designed for
field/site engineers.

#### 1.1 Authoritative V1 Product Model: Single-Tenant Creator Ownership (Product/Security Model; R01)

**SiteLens v1 is user-specific, not location-specific.**

- **Independent User Data Domain**: Each authenticated user operates within an independent, isolated personal SiteLens data domain.
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
  * original photos and videos
  * derived evidence photos and thumbnails
  * local and cloud galleries
  * local SQLite / Drift database records
  * active-site selection context
  * pending captures and uncommitted work
  * synchronization queues and retry state
  * soft-delete tombstones
  * Cloud Firestore records and Cloud Storage media objects
- **Authorization Boundary**: The v1 authorization boundary is strictly the authenticated user's identity (`creator_id == request.auth.uid`).

Phase 1 includes:

-   Firebase Authentication (Email/Password, Google Sign-In)
-   first-login permission onboarding
-   project/site selection (creator-owned)
-   GPS-aware photo/video capture
-   visible burned-in geotagging (Option B HUD Architecture)
-   immutable original artifact with derived, privacy-safe evidence artifacts
-   local-first media storage
-   local gallery
-   media detail with chunked technical telemetry
-   GPS-based nearby-media search
-   Before/After smart-linking
-   integrity hashing (capture-time SHA-256 and live byte verification)
-   Firebase cloud storage/data synchronization foundation (creator-bound)
-   sync queue and status UI
-   settings and creator-owned account deletion

#### 1.2 Non-Goals and Deferred Capabilities (FUTURE SCOPE — NOT IMPLEMENTED IN V1)

The following collaborative, multi-user, and enterprise capabilities are **NOT** implemented in v1 and are explicitly reserved for future product phases:

-   shared sites
-   site membership
-   member invitations
-   member roles and permissions
-   administrator roles
-   role-based access control (RBAC)
-   member-based authorization
-   member-based evidence access
-   revoked-member access handling
-   successor-admin ownership
-   ownership transfer between users
-   shared-site account deletion retention
-   team workspaces
-   cross-user collaboration
-   WIR (Work Inspection Request) builder
-   NCR (Non-Conformance Report) builder
-   Excel / CSV compliance tabular exports
-   centralized web management dashboard
-   server-side spatial search
-   full per-frame video geotag burn-in
-   automated evidence linking without user confirmation

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

## 4.5 Authentication vs. Authorization & Multi-User Session Isolation (Session/Local Isolation; R04)

The application strictly distinguishes between authentication and authorization:

- **Authentication**: Establishes user identity via Firebase Authentication (Email/Password or Google Sign-In), yielding the authenticated user's unique identifier (`request.auth.uid`).
- **Authorization**: Determines whether the authenticated user has permission to access, modify, or delete a specific resource. In SiteLens v1, authorization is strictly **creator-owned**:
  $$\text{User has access} \iff \text{resource.creator\_id} == \text{request.auth.uid}$$
  Authorization is never granted by site membership, admin status, site code, site name, street address, GPS coordinates, or physical proximity.

### Multi-User Session Isolation Invariant (Normative Requirement)

When User A signs out and User B signs in on the same physical device:
- User B **MUST NOT** see or gain access to User A's SiteLens data.
- This non-accessibility invariant applies to all visible and persisted application state, including:
  * sites
  * evidence and media records
  * gallery content
  * active site selection
  * pending captures and uncommitted work
  * synchronization queues and retry state
  * soft-delete tombstones
  * cached files and database records
- Each user's data domain remains completely isolated across sign-in/sign-out cycles.

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

# 6. Site Setup & Site Context Requirements

After successful authentication and required permission onboarding:

-   Project picker → Site picker
-   populate active `Site ID`
-   display site name
-   display registered address
-   establish the reference point used for geotag stamping

## 6.1 User Identity vs. Site Identity & Physical Construction Site Reality

SiteLens strictly separates **User Identity** from **Site Identity**:

- **User Identity**: The authenticated user's Firebase Auth UID (`creator_id`). This identity defines the security boundary, ownership, and authorization for all sites, evidence items, files, and tombstones.
- **Site Identity**: Descriptive attributes of a construction project (`site_code`, `name`, `address`, GPS coordinates). These attributes describe a physical construction project. They do **not** determine authorization.
- **Physical Construction Site Reality**:
  * Multiple field engineers or subcontractors may independently work on the same physical construction site.
  * An individual user may create a local or remote site entry that shares the exact same site code, site name, physical address, or GPS coordinates as a site created by another user.
  * Shared site attributes describe physical reality; they do **not** create shared data or grant authorization:
    $$\text{same physical site} \ne \text{shared data}$$
    $$\text{same site code} \ne \text{authorization}$$
    $$\text{same address} \ne \text{authorization}$$
    $$\text{same GPS} \ne \text{authorization}$$
  * Two users working on the same project remain completely isolated in their respective personal data domains.

## 6.2 Normative Ownership Requirements

1. **Strict Creator Ownership of Sites**: Every v1 site belongs to exactly one creator (`creator_id`).
2. **Strict Creator Ownership of Evidence**: Every v1 evidence and media record belongs to exactly one creator (`creator_id`).
3. **Security Boundary Enforcement**: Creator ownership is an integral part of the security boundary across local storage, SQLite/Drift, Cloud Firestore, and Cloud Storage.
4. **Self-Domain Access Only**: Users can access only their own v1 data.
5. **Site Identity Non-Substitution**: Site identity (`site_code`, `name`, `address`, GPS) must never be used as a substitute for user identity or authorization.
6. **Proximity Non-Authorization**: Physical proximity or spatial co-location must never grant authorization.
7. **Same-Site Isolation**: Users documenting the same physical construction site remain completely isolated.
8. **Multi-Site Domains**: A single user's personal data domain may contain multiple sites.

## 6.3 Local-First Site Context

SiteLens must always load local site context first from the local Drift database.

Network connectivity must never be required for:

-   loading cached sites;
-   restoring the active site;
-   selecting a cached site;
-   opening the camera;
-   capturing evidence.

Network availability controls cloud synchronization and remote site hydration, NOT local operational capability.

## 6.4 Active Site Continuity — Critical Invariant

The last selected active site remains active during both online and offline operation.

The active site changes ONLY when the user explicitly selects another site.

Network loss must NOT:
-   clear the active site;
-   replace the active site;
-   create an offline duplicate;
-   switch the active site.

Network restoration must NOT:
-   change the active site;
-   replace it with a remotely returned site;
-   create a duplicate.

Application restart must restore the last selected active site when that site remains available locally in Drift.
Lifecycle background/foreground transitions must preserve active-site identity.

## 6.5 Evidence-to-Site Continuity

Evidence captures maintain unbroken association with the active site regardless of network state:

-   **Online capture**: Photo 1 → Site A
-   **Network lost**: Photo 2 → Site A
-   **Network restored**: Photo 3 → Site A

All three evidence items must remain associated with the SAME Site A stable identity (`MediaItem.siteId == Site A`).
Network state must never determine or alter evidence-to-site association.
The gallery, media detail, and inspection history must therefore continue to show online and offline evidence together under Site A.

## 6.6 Online Firestore → Drift Site Hydration

Cloud Firestore is the authoritative remote source for the authenticated user's sites. Local Drift is the local operational cache.

When authenticated and online:
-   Retrieve sites owned by the current user (`creator_id == request.auth.uid`);
-   Reconcile/upsert remote sites into local Drift (`insertOnConflictUpdate`);
-   Make newly hydrated sites immediately available in the site picker;
-   Preserve the locally persisted active site when it remains valid;
-   Do NOT automatically switch or replace the active site merely because remote data was hydrated.

The remote access query is scoped strictly to creator ownership:
- `sites` collection query scoped strictly by `creator_id == request.auth.uid`.
- No `members` collection group query or member-based hydration exists in v1.

## 6.7 Offline Site Behavior

If cached sites exist and network is unavailable:
-   use cached sites automatically;
-   restore the last selected active site;
-   allow capture normally;
-   do not require an "offline mode" action.

## 6.8 Zero Local Sites State

If zero local sites exist:
-   **ONLINE**: attempt remote Firestore hydration asynchronously; if creator-owned sites are found, cache and display them; if none exist in Firestore, show the site-creation empty state.
-   **OFFLINE**: provide the manual site creation path immediately.

## 6.9 "Add Offline Site" Semantics

"Add Offline Site" means creation of a brand-new inspection site locally in the Drift database by the current creator (`creator_id = current_user_uid`).
It does NOT mean:
-   enter offline mode;
-   convert an existing site into offline mode;
-   create an offline copy of an existing site.

## 6.10 Multi-Device Requirement

An existing Firestore site created by the authenticated user must become available locally when that user signs into another device while online.
This covers:
-   creator-owned sites created by the same authenticated user across devices;
-   newly provisioned creator-owned sites.
Shared-site and membership-based access do not exist in v1.

## 6.11 Site Deletion Safety & Tombstone Lifecycle (Deletion Safety; R23 / Tombstone Retention/Purge; R24)

1. **Active Media Guard (Deletion Safety; R23)**: Site deletion is strictly blocked if the site contains active (non-tombstoned) media records (`hasMediaForSite`). Users must delete or reassign active media prior to site deletion.
2. **Tombstone Retention During Site Deletion (Tombstone Retention/Purge; R24)**: If a site has soft-deleted media records whose cloud tombstones are pending synchronization (`is_deleted == 1`, `tombstone_reconciled == 0`), those tombstones must be preserved until cloud reconciliation succeeds.
3. **Atomic Purge (Tombstone Retention/Purge; R24)**: Once all media tombstones for the site are reconciled, or for sites with zero media, the site record and associated reconciled tombstones are atomically purged in the Drift `deleteSite` transaction.

## 6.12 Source-of-Truth Model

-   **Firestore**: authoritative remote repository for the user's creator-owned site and media state.
-   **Drift**: local operational cache.
-   **Offline**: Drift remains completely usable without waiting for network.
-   **Online**: remote creator-owned state reconciles into Drift without displacing active site context.

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

## 7.5 Capture controls & State Locks

Photo mode:
- 72px circular shutter button with orange brand accent ring
- Gallery shortcut button with unreviewed media badge count
- Camera flip button
- **Capture Mutex (Shutter Re-entrancy Mutex; R12)**: The shutter action must be strictly locked during background isolate HUD compositing and persistence to prevent duplicate or overlapping captures.

Video mode:
- Red recording control with duration badge
- Elapsed duration indicator during active recording
- **Video Start-Time Authority ($T_0$) (R07)**: The authoritative video capture timestamp is anchored at the exact moment of recording initiation ($T_0$) and persists immutably throughout recording. It must not be overwritten or usurped by subsequent GNSS satellite fix updates during recording.
- **Active Recording Camera/Telemetry Lock (R08)**: During active video recording, shutter mode switching, camera flipping, and aspect ratio controls are locked to prevent corrupted video streams or desynchronized telemetry.
- **Audio Disclosure (Audio Track Availability Disclosure; R09)**: Video evidence records must explicitly record audio track presence/capability (`hasAudioTrack`) in metadata, truthfully disclosing whether audio was captured rather than assuming microphone capture or leaving audio state ambiguous.

Mode switch:
`PHOTO | VIDEO`

## 7.6 GPS State Logic, Freshness & Sensor Provenance

GPS status and geotag information update in real time from the active GNSS stream:
- Dedicated GPS status pill in top bar (`GPS: High • ±3m`, `GPS: Weak • ±12m`, etc.)
- Throttle visual updates approximately every 1–2 seconds to prevent UI jitter.
- **Live GPS Fix / Cached GPS (GPS Fix Freshness & Stream Recovery; R06)**: Shutter readiness strictly requires a live, verified fix (`hasLiveFix => hasValidFix && !isLastKnownSeed`). Stale cached location seeds from prior sessions or lifecycle pauses must never enable the shutter before a live GNSS fix is acquired.
- If no live GPS fix has been obtained: disable shutter and show `Waiting for GPS lock` (GPS/capture-readiness dependency; R02). Lifecycle synchronization and service initialization states between camera and GPS providers are tracked for architecture and implementation (R03; no direct PRD requirement change).
- If accuracy is worse than threshold (20m default): allow capture with `DEGRADED` status and store `low_accuracy: true`.
- **Observed GNSS Coordinates**: Recorded coordinates represent observed GNSS receiver fixes, never synthetic, interpolated, or estimated coordinates.
- **Unknown Telemetry Semantics & Sensor Fallback (R10)**: Compass heading, altitude, and GNSS satellite telemetry are recorded when available from hardware sensors; when unestablished or unavailable, values remain explicitly null/unknown with graceful UI fallback, without synthetic fabrication.
- **Minimap Race Guard (R11)**: The shutter-time minimap snapshot uses generational tokens to prevent race conditions (implementation/architecture implication tracked). Cached minimap imagery may serve as fallback only when displacement $\le 20\text{m}$, age $\le 5\text{min}$, and map type matches.

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

## 8.4 Smart-link & Reciprocal Link Invariants

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

**Smart-Link Invariants**:
- **Creator & Site Isolation**: Linking is restricted strictly to evidence within the same site in the authenticated user's own data domain. Evidence from other users or across different sites can never be linked.
- **Smart-Link Temporal Semantics (R17)**: Candidate "Before" / Non-Conformity evidence must have been captured earlier in time than the "After" / Closed observation.
- **Smart-Link Non-Destructive/Live-Distance (R18)**: Linking or unlinking Before/After pairs is non-destructive to candidate evidence records, and candidate proximity is evaluated using live distance calculation.
- **Canonical Identity (R20)**: Review & Tag surfaces display the human-readable canonical site code / name rather than internal database UUIDs.
- **Strict Closed Observation Rule**: A `Closed` observation must be linked to an eligible open `Non-Conformity` on the same site before it can be saved.

## 8.5 Actions, Navigation Confirmation & Video Handoff

Retake:
-   discard the current capture files safely
-   return to camera with zero orphaned database rows

Dismiss / Back Navigation Confirmation (PopScope/Cleanup; R14):
-   Navigating back from Review & Tag or tapping dismiss with pending uncommitted capture triggers an explicit confirmation prompt ("Discard this capture? Unsaved evidence will be permanently lost").
-   Prevents accidental evidence destruction from inadvertent back gestures.

Video Handoff & Playback (Video Handoff/Player; R13):
-   Review & Tag provides immediate video playback preview and seamless player handoff. In-flight video recordings interrupted by app lifecycle transitions are recovered safely (Keep for Later / Discard). Video player controller lifecycle, in-flight reference cleanup, and temporary recording recovery are tracked for implementation/architecture (no direct PRD requirement change).

Save:
-   write media to local file storage
-   generate thumbnail
-   calculate SHA-256
-   write metadata to local database
-   add to sync queue
-   show in Gallery

### Export Attribution Truthfulness & Provenance Invariant (Export Attribution; R21)

Every saved evidence record permanently binds the original capturing user's UID as `creator_id`. Downstream viewers, session handovers, PDF report generators, ZIP forensic exporters, and cloud synchronization services **MUST NOT** substitute the current session user for the original capture creator. Attribution is forensic and immutable.

------------------------------------------------------------------------

# 9. Gallery

The Gallery is a local media library designed for **1,000+ items**.

## 9.1 Rendering & Deterministic Sorting (Deterministic Gallery Sort; R26)

Use virtualized/lazy rendering.

Never decode full-resolution originals for the entire grid.

Generate approximately 200 px thumbnails at capture time.

Gallery sorting is strictly deterministic: ordered by capture timestamp descending, with secondary sorting by record ID to ensure stable pagination.

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

-   pending
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
-   SHA-256 integrity hash (with explicit verification semantics)
-   file size
-   synchronization status

Primary action:

**Find Nearby Media**

Secondary actions:

-   Edit Tags
-   Share
-   Delete from Device / Remove from Gallery

### 10.1 Live SHA-256 Byte Verification Semantics (Hash Semantics; R15)

Media Detail must strictly distinguish between displaying a stored hash record and performing live byte verification:
- **Stored SHA-256 Hash**: The hash computed at capture time and stored in SQLite/Firestore metadata. It represents the historical integrity assertion.
- **Live Byte Verification ("Verified" State)**: Requires reading the actual local file bytes from disk storage, recomputing the SHA-256 digest, and comparing it against the stored hash. Only a successful recomputed match qualifies for a "Verified" badge. If file bytes are missing or altered, the state must display as unverified or corrupted.

### 10.2 Deletion, Storage Cleanup & Cloud Recovery Policy

1. **Synced media — Remove from Gallery**: permanently deletes the local media files (original, evidence, thumbnail; video + thumbnail) and tombstones the local record (hidden from the Gallery). The immutable cloud copy remains intact, and the cloud evidence ledger is reconciled to a deleted state through synchronization (`syncTombstone`).
2. **Unsynced media — permanent deletion**: because unsynced media has no cloud backup, deletion requires an explicit, prominent destructive warning confirming the media will be permanently lost with no recovery option. After confirmation, local files are deleted and the record is tombstoned locally.
3. **Tombstone Semantics & Remote Propagation (Tombstone Remote Propagation; R22)**: a locally deleted record is retained locally as a hidden tombstone until its cloud ledger state is reconciled. For a previously published cloud evidence item, synchronization propagates `is_deleted: true` to Firestore via `syncTombstone`. An item that was never published produces no cloud deletion claim and is marked reconciled locally. A cloud tombstone is a metadata ledger state only — it never deletes or alters cloud storage artifacts.
4. **Critical Invariant**: local deletion MUST NEVER delete Firebase Storage objects or Firestore documents. Cloud originals remain write-once immutable.
5. **Storage Cleanup**: raw originals of already-synchronized photos can be cleared locally on demand to reclaim device space, while the derived evidence, thumbnail, and all metadata are preserved and the original remains recoverable from cloud storage.
6. **Cloud Recovery**: cloud-backed media whose local files were removed can be recovered on demand via forensically verified (`sha256_hash`) download from Firebase Cloud Storage.

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

## 11.2 Filters & User Isolation Invariant

-   same site only --- default ON
-   activity
-   observation type
-   date range

**User Data Domain Isolation Invariant**: Nearby Media Search operates strictly within the authenticated user's own creator-owned data domain. Media captured by another user at the exact same physical coordinates or construction site is never queried, indexed, or visible.

## 11.3 Results & Spatial Uncertainty (Nearby-Search Spatial Uncertainty; R19)

Group by:

-   Before
-   After
-   Progress / Material / General

Each row displays:

-   thumbnail
-   distance (exact Haversine refinement accounting for GPS spatial uncertainty)
-   timestamp
-   activity badge

Within each group:

1.  sort by distance
2.  then recency (deterministic secondary sort; R26)

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

## Account Deletion (Creator-Owned Lifecycle)

Account deletion is a coordinated lifecycle available directly in
Settings for the authenticated creator:

-   **Identity Re-authentication**: Explicit password or OAuth re-authentication is mandatory before deletion is initiated.
-   **Server-Side Destruction of Creator Data**: All Cloud Firestore documents (sites and media ledgers) and Firebase Cloud Storage objects (originals and thumbnails) where `creator_id == request.auth.uid` are permanently deleted.
-   **Client-Side Purge**: Local Drift SQLite records, cached media files, pending sync queues, and active site preferences are purged from the device.
-   **Session Termination**: The authenticated session is terminated, and the user is routed to the unauthenticated welcome screen.
-   **Future Scope Note**: In SiteLens v1, all sites and media are strictly creator-owned. Shared-site evidence retention policies, organizational workspace retention, and successor administrator designations are **FUTURE SCOPE — NOT IMPLEMENTED IN V1**.

------------------------------------------------------------------------

# 13. Geotagging

Two layers are required for photos.

## 13.1 EXIF & Metadata Policy

The authoritative evidence metadata is the capture-time snapshot
(coordinates, accuracy, altitude and datum, verification status, GNSS
telemetry, capture timestamp, address, integrity hashes). It is persisted
in the local evidence record and the cloud ledger, and rendered as the
burned-in geotag stamp.

EXIF handling follows a strict original/derived boundary:

-   The immutable original artifact is preserved exactly as captured,
    including whatever EXIF metadata the camera produced.
-   Derived evidence artifacts (evidence JPEG, thumbnail) MUST NOT
    silently inherit camera EXIF. Orientation is baked into the pixels
    first; all EXIF metadata is then stripped before encoding so derived
    evidence cannot carry unverified device claims (device GPS, device
    timestamps, make/model) that contradict the authoritative
    capture-time metadata.
-   Missing or unavailable capture-time values remain explicitly unknown
    and are never reconstructed synthetically into EXIF or any other
    metadata layer.

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
                    ├─ EXIF orientation baking (into pixels)
                    ├─ EXIF metadata stripping (derived artifacts carry no camera EXIF)
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
- **Cloud Synchronization**: Uploads original and thumbnail artifacts alongside structured metadata matching the evidence artifact. Whether the canonical burned evidence file (`evid_<id>.jpg`) is replicated directly to Cloud Storage as a cloud-authoritative artifact or remains client-derived/reproducible on demand requires an Architecture Decision (evid_ cloud architecture decision; R16) and is not pre-selected at the PRD level (no direct PRD requirement change; implementation/architecture implication tracked).

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
  address TEXT,
  creator_id TEXT NOT NULL
);
```

`creator_id` is mandatory and bound to the authenticated Firebase Auth UID.

## 15.2 Local media

``` sql
CREATE TABLE media (
  id TEXT PRIMARY KEY,
  site_id TEXT REFERENCES sites(id),
  original_uri TEXT,
  uri TEXT NOT NULL,
  thumb_uri TEXT,
  type TEXT CHECK(type IN ('photo','video')),
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  accuracy_m REAL,
  low_accuracy INTEGER DEFAULT 0,
  altitude_m REAL,
  activity_tag TEXT,
  observation_type TEXT CHECK(
    observation_type IN (
      'progress',
      'nonConformity',
      'closed',
      'material',
      'general'
    )
  ),
  linked_media_id TEXT REFERENCES media(id),
  note TEXT,
  captured_at TEXT NOT NULL,
  sha256_hash TEXT,
  evidence_sha256_hash TEXT,
  captured_address TEXT,
  creator_id TEXT NOT NULL,
  verification_status TEXT,
  is_altitude_msl INTEGER,
  gnss_satellite_count INTEGER,
  gnss_satellites_used_in_fix INTEGER,
  gnss_fix_timestamp TEXT,
  synced INTEGER DEFAULT 0,
  is_deleted INTEGER DEFAULT 0
);

CREATE INDEX idx_media_lat ON media(lat);
CREATE INDEX idx_media_lon ON media(lon);
CREATE INDEX idx_media_site ON media(site_id);
CREATE INDEX idx_media_obs ON media(observation_type);
CREATE INDEX idx_media_captured ON media(captured_at);
```

`creator_id` is mandatory, immutable, and permanently records the original capturing user UID (Export Attribution; R21). Video evidence records disclose audio capability via metadata (Audio Disclosure; R09). `sha256_hash` is the integrity hash of the immutable original artifact; `evidence_sha256_hash` is the integrity hash of the derived evidence artifact. Nullable metadata columns (`accuracy_m`, `altitude_m`, `verification_status`, `is_altitude_msl`, GNSS telemetry) mean the value was not established at capture time and must remain unknown rather than being filled with synthetic values. Capture is gated on a first valid GPS fix, so recorded coordinates are real observed values.

------------------------------------------------------------------------

# 16. Firebase Data Model & Cloud Authorization

Firebase is the cloud backend.

Authoritative conceptual structure for v1:

``` text
users/{uid}

sites/{siteId}                  (documents where creator_id == uid)

sites/{siteId}/media/{mediaId}  (documents where creator_id == uid)
```

> **Scope Clarification**: Subcollections such as `sites/{siteId}/members/{uid}` are **NOT** implemented in v1. Site membership, member roles, and cross-user collection group hydration are **FUTURE SCOPE — NOT IMPLEMENTED IN V1**.

Media documents contain the cloud representation of relevant metadata, including:

-   media ID
-   site ID
-   storage paths
-   media type
-   latitude
-   longitude
-   accuracy
-   low-accuracy flag
-   altitude and altitude datum
-   verification status
-   GNSS satellite telemetry and fix timestamp
-   activity
-   observation type
-   linked media ID
-   note
-   capture timestamp
-   SHA-256 hash of the original artifact
-   SHA-256 hash of the derived evidence artifact
-   captured address
-   creator/user ID (`creator_id`)
-   deletion flag (`is_deleted` tombstone state)

Cloud Storage conceptual paths:

``` text
sites/{siteId}/media/{mediaId}/original
sites/{siteId}/media/{mediaId}/thumbnail
```

Firebase Security Rules MUST restrict read, write, and delete operations strictly according to authenticated creator ownership (`creator_id == request.auth.uid`). Site membership, shared-site authorization, and role-based access control do not exist in v1.

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
Local file + local DB (pending)
  ↓
Sync coordination (authenticated session, connectivity available)
  ↓
Publish cloud evidence ledger document
  ↓
Upload original (write-once, idempotent)
  ↓
Upload thumbnail (write-once, idempotent)
  ↓
Confirm success
  ↓
Mark local item synced
```

Synchronization is session-gated and independent of Gallery visibility:
records are processed according to the queue lifecycle regardless of
their presentation state, and cloud publication (ledger document plus
Storage artifacts) is distinct from local persistence.

If synchronization fails:

-   preserve local media
-   preserve local metadata
-   **Sync Backoff & Error Classification (R25)**: classify the failure: retryable failures re-attempt automatically with exponential backoff; permanent failures mark the item failed and remain available for explicit manual retry
-   failed attempts must never delete or invalidate the local original

Locally deleted evidence is reconciled with the cloud through tombstone
propagation: a previously published cloud evidence item is reconciled to
a deleted ledger state with the same retry/session protections, while an
item that was never published produces no cloud deletion claim.

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

## 21.1 Authentication vs. Authorization

-   **Authentication**: Firebase Authentication establishes user identity and produces the authenticated `request.auth.uid`.
-   **Authorization**: Strictly creator-owned. An authenticated user is authorized to read, write, or delete resources if and only if `resource.data.creator_id == request.auth.uid`.
-   **Non-Authorization by Site Identity or Location**: Physical co-location, shared site codes, matching site names, identical addresses, or shared GPS coordinates **never** grant access or authorization between users.
-   Site membership, admin roles, and RBAC do not exist in v1.

## 21.2 Multi-User Session Isolation

-   When User A signs out and User B signs in on the same device, User B must have zero access to User A's data domain.
-   Applies to all local SQLite records, cached files, active site context, sync queues, and soft-delete tombstones.

## 21.3 Cloud Security Rules Enforcement (Firebase/Cloud Enforcement; R05)

-   `firestore.rules` and `storage.rules` enforce creator-bound reads, writes, and deletes (`creator_id == request.auth.uid`).
-   `creator_id` field is immutable after creation.
-   Storage rules validate paths against creator ownership.
-   Soft-delete tombstones propagate via metadata without deleting cloud storage objects.

## 21.4 Defensive Hardening & System Hygiene

-   No Firebase service-account credentials may be embedded in the Flutter application.
-   User account enumeration mitigation: Authentication error messages must remain generic across invalid credentials and non-existent accounts.
-   Path traversal sanitization: File resolution paths must sanitize sequence characters (`../`, `..\`) to prevent directory traversal.
-   API keys and configuration must use appropriate platform security controls.
-   Local evidence files and database records must remain protected by OS application sandbox isolation.
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
-   95% JPEG quality compression; camera EXIF is preserved only on the immutable original artifact, while derived evidence artifacts carry no camera EXIF
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

-   M6-A Security Rules hardening: `firestore.rules` and `storage.rules` validated via Firebase MCP with strict creator-ownership authorization (`creator_id == request.auth.uid`), secure bootstrap flow, forensic field immutability, soft-delete authorization, disaggregated original/thumbnail storage paths, and UI credential sanitation. (Note: historical membership-rule artifacts are superseded by the creator-ownership boundary; membership is classified as future scope).
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
-   Local media deletion semantics: synced media deletes local files + tombstones SQLite (`is_deleted = 1`); unsynced media requires an explicit destructive warning and deletes local files + tombstones SQLite, with the cloud ledger reconciled through tombstone propagation for any previously published item
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
-   the immutable original keeps its capture-time camera metadata; derived evidence artifacts carry no camera EXIF and are encoded at 95% JPEG quality
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
-   Firebase Security Rules strictly restrict cloud access to creator-owned resources (`creator_id == request.auth.uid`)
-   cross-user data isolation is maintained across all local and cloud surfaces
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

The following capabilities are explicitly deferred from Phase 1 and classified as **FUTURE SCOPE — NOT IMPLEMENTED IN V1**:

-   shared sites
-   site membership and member invitations
-   member roles and administrator roles
-   role-based access control (RBAC)
-   member-based authorization and evidence access
-   revoked-member access handling
-   successor-admin ownership and ownership transfers between users
-   shared-site account deletion retention
-   team workspaces and cross-user collaboration
-   WIR (Work Inspection Request) document generator
-   NCR (Non-Conformance Report) document generator
-   Excel / CSV compliance tabular exports
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
| **Cloud Sync & Security** | Asynchronous `SyncCoordinator` queue with retry/backoff, Cloud Storage uploads (original + thumbnail), Firestore metadata synchronization (`creator_id`, `captured_address`, `evidence_sha256_hash`), `SyncStatusBadge` UI, declarative security rules (`firestore.rules`, `storage.rules`) with strict creator-ownership authorization and forensic field immutability. | Complete M6 | **DELIVERED & GATED** |
| **Settings, Storage Cleanup & Recovery** | Unified `SettingsScreen` hub, GPS accuracy threshold modal (`setting_gps_low_accuracy_threshold`, default 20.0m), watermark settings (`showAddress`, `showMapTile`), nearby search settings (`nearbySettingsProvider` wiring), storage cleanup ("Clear Synced Photo Originals Locally" via `StorageCleanupService`), on-demand cloud media recovery (`CloudMediaRecoveryService`) with deterministic path resolution and forensic SHA-256 verification, sync-aware destructive local deletion warnings. | Complete M7 | **DELIVERED & GATED** |
| **Google Photos Auto-Sync** | Optional OAuth auto-upload to dedicated `SiteLens Evidence` album (`photoslibrary.appendonly` least-privilege scope), Drift SQLite schema v6 (`google_photos_sync_entries`), background retry/backoff queue, Settings card UI, genuine `mediaItem.id` verification, zero-loss startup un-queued media sweep, strict decoupling from authoritative Firebase sync. | Complete M7 | **DELIVERED & GATED** |
| **Responsive UI & Security Hardening** | Responsive layout framework (`ResponsiveBreakpoints`, `ResponsiveTwoPane`) supporting phones, tablets, and desktop foldables, path traversal sequence sanitization (`../`, `..\`) in `EvidenceStorageService.resolveAbsolutePath()`, user account enumeration mitigation in `LoginScreen._parseAuthError()`. | Complete Cross-Cutting | **DELIVERED & GATED** |

## 29.2 Phase 2 & Future Horizons (Commercial & Enterprise Scale)

Building on the verified Phase 1 media capture and forensic evidence foundation:

1. **Phase 2.1 — Formal Compliance & Audit Package Engine**:
   - **Automated WIR (Work Inspection Request) Generator**: Standardized engineering inspection request forms populated automatically with site telemetry, activity codes, specification references, and paired Before/After evidence photos.
   - **Automated NCR (Non-Conformance Report) Generator**: Formal construction non-conformance documents linking open Non-Conformity items, severity classifications, root-cause notes, corrective action deadlines, and verified Closed resolution evidence.
   - **Direct Excel / CSV Compliance Export**: Tabular spreadsheet exports with embedded high-resolution thumbnail images, geolocation hyper-links, inspector signatures, and verifiable SHA-256 hash ledgers.

2. **Phase 2.2 — Team Collaboration & Enterprise Multi-User (FUTURE SCOPE — NOT IMPLEMENTED IN V1)**:
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
