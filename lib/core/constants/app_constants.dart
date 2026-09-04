class AppConstants {
  static const String appName = 'SiteLens';
  static const String appTagline = 'GPS-Verified Construction Evidence';

  // GPS Thresholds
  static const double gpsHighAccuracyThresholdMeters = 5.0;
  static const double gpsDefaultLowAccuracyThresholdMeters = 20.0;
  static const int gpsStreamThrottleSeconds = 1;

  // Nearby Search Defaults
  static const double defaultNearbyRadiusMeters = 10.0;
  static const List<double> presetRadiiMeters = [2.0, 5.0, 10.0, 25.0, 50.0];

  // Thumbnail Size
  static const int thumbnailWidthPx = 200;

  // Activities / Work Stages (PRD Section 8.1 - Blank by default for user entry)
  static const List<String> defaultActivities = [];

  // Observation Types (PRD Section 8.2)
  static const List<String> observationTypes = [
    'Progress',
    'Non-Conformity',
    'Closed',
    'Material',
    'General',
  ];
}
