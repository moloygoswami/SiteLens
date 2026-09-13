import 'package:flutter/material.dart';
import '../domain/models/media_item.dart';
import '../features/auth/session_router.dart';
import '../features/auth/welcome_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/onboarding/permission_onboarding_screen.dart';
import '../features/onboarding/permission_recovery_screen.dart';
import '../features/sites/site_setup_screen.dart';
import '../features/camera/camera_screen.dart';
import '../features/gallery/gallery_screen.dart';
import '../features/gallery/media_detail_screen.dart';
import '../features/nearby/nearby_search_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Observes [PageRoute] coverage so a screen can react to being covered by, or
/// revealed after, another page route. Only full-page routes are observed
/// (dialogs and bottom sheets are not [PageRoute]s), so modal UI does not
/// trigger coverage transitions.
///
/// Used by the camera screen to release CameraX while another page route
/// (video evidence / fullscreen / gallery / review / settings) is on top, and
/// to safely reacquire it when the camera screen becomes visible again.
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

class AppRoutes {
  static const String root = '/';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String onboarding = '/onboarding';
  static const String recovery = '/recovery';
  static const String siteSetup = '/site-setup';
  static const String camera = '/camera';
  static const String reviewTag = '/review-tag';
  static const String gallery = '/gallery';
  static const String mediaDetail = '/media-detail';
  static const String nearbySearch = '/nearby-search';
  static const String settings = '/settings';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case root:
        return MaterialPageRoute(builder: (_) => const SessionRouter());
      case welcome:
        return MaterialPageRoute(builder: (_) => const WelcomeScreen());
      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case onboarding:
        return MaterialPageRoute(builder: (_) => const PermissionOnboardingScreen());
      case recovery:
        return MaterialPageRoute(builder: (_) => const PermissionRecoveryScreen());
      case siteSetup:
        return MaterialPageRoute(builder: (_) => const SiteSetupScreen());
      case camera:
        return MaterialPageRoute(builder: (_) => const CameraScreen());
      case gallery:
        return MaterialPageRoute(builder: (_) => const GalleryScreen());
      case mediaDetail:
        final item = settings.arguments as MediaItem;
        return MaterialPageRoute(builder: (_) => MediaDetailScreen(mediaItem: item));
      case nearbySearch:
        final source = settings.arguments as MediaItem?;
        return MaterialPageRoute(builder: (_) => NearbySearchScreen(sourceMedia: source));
      default:
        return MaterialPageRoute(builder: (_) => const SessionRouter());
    }
  }
}
