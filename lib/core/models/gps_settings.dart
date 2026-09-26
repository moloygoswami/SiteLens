import '../constants/app_constants.dart';

class GpsSettings {
  final double lowAccuracyThresholdMeters;
  final bool highAccuracyMode;

  const GpsSettings({
    this.lowAccuracyThresholdMeters = AppConstants.gpsDefaultLowAccuracyThresholdMeters,
    this.highAccuracyMode = true,
  });

  GpsSettings copyWith({
    double? lowAccuracyThresholdMeters,
    bool? highAccuracyMode,
  }) {
    return GpsSettings(
      lowAccuracyThresholdMeters:
          lowAccuracyThresholdMeters ?? this.lowAccuracyThresholdMeters,
      highAccuracyMode: highAccuracyMode ?? this.highAccuracyMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpsSettings &&
          runtimeType == other.runtimeType &&
          lowAccuracyThresholdMeters == other.lowAccuracyThresholdMeters &&
          highAccuracyMode == other.highAccuracyMode;

  @override
  int get hashCode => Object.hash(lowAccuracyThresholdMeters, highAccuracyMode);
}
