# SiteLens — On-Device Master E2E Integration Suite

The complete on-device integration test suite lives in `integration_test/`.

## Prerequisites

- Flutter toolchain (3.27.x stable) with the Android SDK
- Physical Android test device connected via ADB (e.g. Motorola Moto G85 / Edge 50 Fusion `ZA222NBPPV`), or emulator

## Running the Full Master E2E Suite

Run the consolidated master runner (executes all 20 test groups in a single APK install session):

```sh
flutter test integration_test/all_e2e_tests.dart -d ZA222NBPPV
```

Or run individual targeted suites:

```sh
flutter test integration_test/auth_session_boundary_e2e_test.dart -d ZA222NBPPV
flutter test integration_test/camera_viewfinder_e2e_test.dart -d ZA222NBPPV
flutter test integration_test/nearby_search_e2e_test.dart -d ZA222NBPPV
```

## Test Inventory & Coverage (20 / 20 Test Groups)

1. **`app_smoke_test.dart`** (E2E-02): Root application bootstrap and Riverpod container initialization.
2. **`deterministic_state_test.dart`** (E2E-03): Deterministic authenticated & unauthenticated bootstrap routing.
3. **`auth_session_boundary_e2e_test.dart`** (E2E-03-B):
   - Sign-out cancellation preserves active session on `SiteSetupScreen`.
   - Confirmed sign-out from `SiteSetupScreen` wipes session and resets to `WelcomeScreen`.
   - Confirmed sign-out from deep navigation stack (`SettingsScreen`) invalidates route history.
   - Android system Back after confirmed sign-out cannot restore authenticated routes.
   - Duplicate confirm on Sign Out dialog yields exactly one clean transition.
4. **`camera_navigation_test.dart`** (E2E-04): SiteSetup $\rightarrow$ Camera $\rightarrow$ Back transition.
5. **`settings_navigation_test.dart`** (E2E-04): Settings hub transitions & tap debouncing.
6. **`site_management_test.dart`** (E2E-05): Custom offline site creation and active site switching.
7. **`camera_viewfinder_e2e_test.dart`** (E2E-06): Viewfinder controls, flash cycling, grid overlay, 0.5x zoom, PHOTO/VIDEO modes.
8. **`gps_watermark_e2e_test.dart`** (E2E-07): Top HUD GPS pill, timestamp format modal, and live watermark preview.
9. **`review_tag_e2e_test.dart`** (E2E-08): Tagging form, observation chip selector, and instant retake discard.
10. **`gallery_grid_e2e_test.dart`** (E2E-09): Gallery empty view, filter bar chips, search query input.
11. **`media_detail_e2e_test.dart`** (E2E-10): Metadata telemetry, SHA-256 copy, delete confirmation dialog.
12. **`gallery_batch_export_e2e_test.dart`** (E2E-11): Batch multi-select mode, select all / deselect all, action bar.
13. **`nearby_search_e2e_test.dart`** (E2E-12): Spatial radius presets (2m–50m), filter modal, radar mode toggle.
14. **`settings_sync_e2e_test.dart`** (E2E-13): Settings sections, GPS threshold modal, storage cleanup modal.

## Test Isolation & Safety

- Uses isolated, test-scoped `ProviderContainer` overrides with `FakeAuthService`, `FakePermissionService`, `FakeSiteRepository`, and `FakeSyncCoordinator`.
- Zero modification to production Firebase authentication or live user databases.
- Full `dispose()` lifecycle management for clean test teardowns.
