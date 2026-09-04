class WatermarkSettings {
  final bool showAddress;
  final bool showMapTile;

  const WatermarkSettings({
    this.showAddress = true,
    this.showMapTile = true,
  });

  WatermarkSettings copyWith({
    bool? showAddress,
    bool? showMapTile,
  }) {
    return WatermarkSettings(
      showAddress: showAddress ?? this.showAddress,
      showMapTile: showMapTile ?? this.showMapTile,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatermarkSettings &&
          runtimeType == other.runtimeType &&
          showAddress == other.showAddress &&
          showMapTile == other.showMapTile;

  @override
  int get hashCode => showAddress.hashCode ^ showMapTile.hashCode;
}
