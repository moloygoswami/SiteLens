import 'package:integration_test/integration_test.dart';

import 'app_smoke_test.dart' as app_smoke;
import 'deterministic_state_test.dart' as deterministic_state;
import 'auth_session_boundary_e2e_test.dart' as auth_session_boundary;
import 'camera_navigation_test.dart' as camera_navigation;
import 'settings_navigation_test.dart' as settings_navigation;
import 'site_management_test.dart' as site_management;
import 'camera_viewfinder_e2e_test.dart' as camera_viewfinder;
import 'gps_watermark_e2e_test.dart' as gps_watermark;
import 'review_tag_e2e_test.dart' as review_tag;
import 'gallery_grid_e2e_test.dart' as gallery_grid;
import 'media_detail_e2e_test.dart' as media_detail;
import 'gallery_batch_export_e2e_test.dart' as gallery_batch_export;
import 'nearby_search_e2e_test.dart' as nearby_search;
import 'settings_sync_e2e_test.dart' as settings_sync;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // E2E-02: App Architecture & Bootstrap Smoke
  app_smoke.main();

  // E2E-03: Deterministic State & Auth Routing
  deterministic_state.main();

  // E2E-03-B: Dynamic Authentication & Session Boundary
  auth_session_boundary.main();

  // E2E-04: Core Navigation Smoke
  camera_navigation.main();
  settings_navigation.main();

  // E2E-05: Site Management & Context Selection
  site_management.main();

  // E2E-06: Camera Viewfinder & Optical Capture
  camera_viewfinder.main();

  // E2E-07: GPS Telemetry, Timestamp & Watermark Alignment
  gps_watermark.main();

  // E2E-08: Review, Tagging & Provenance Verification
  review_tag.main();

  // E2E-09: Gallery Lazy Grid & Filters
  gallery_grid.main();

  // E2E-10: Evidence Detail & Single Item Share / PDF Audit
  media_detail.main();

  // E2E-11: Batch Multi-Select & ZIP Package Export
  gallery_batch_export.main();

  // E2E-12: Spatial Nearby Search & Map Radar
  nearby_search.main();

  // E2E-13: Settings Hub, Storage Cleanup & Silent Sync
  settings_sync.main();
}
