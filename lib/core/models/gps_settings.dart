import '../constants/app_constants.dart';

class GpsSettings {
  final double lowAccuracyThresholdMeters;

  const GpsSettings({
    this.lowAccuracyThresholdMeters = AppConstants.gpsDefaultLowAccuracyThresholdMeters,
  });

  GpsSettings copyWith({
    double? lowAccuracyThresholdMeters,
  }) {
    return GpsSettings(
      lowAccuracyThresholdMeters:
          lowAccuracyThresholdMeters ?? this.lowAccuracyThresholdMeters,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpsSettings &&
          runtimeType == other.runtimeType &&
          lowAccuracyThresholdMeters == other.lowAccuracyThresholdMeters;

  @override
  int get hashCode => lowAccuracyThresholdMeters.hashCode;
}
