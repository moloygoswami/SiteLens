import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../core/services/auth_service.dart';
import '../../data/repositories/site_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/media_item.dart';
import '../camera/hud/hud_formatter.dart';
import 'controllers/nearby_search_controller.dart';
import 'models/nearby_search_state.dart';
import 'widgets/location_timeline_view.dart';
import 'widgets/nearby_filter_modal.dart';
import 'widgets/nearby_map_view.dart';
import 'widgets/nearby_media_card.dart';
import 'widgets/radius_selector_strip.dart';

class NearbySearchScreen extends ConsumerStatefulWidget {
  final MediaItem? sourceMedia;
  final double? initialLat;
  final double? initialLon;
  final String? initialSiteId;

  /// Canonical human-facing site code for [initialSiteId], when the caller
  /// already knows it. The internal site id is never rendered (R20).
  final String? initialSiteCode;
  final bool isPicker;
  final void Function(MediaItem)? onSelectCandidate;

  const NearbySearchScreen({
    super.key,
    this.sourceMedia,
    this.initialLat,
    this.initialLon,
    this.initialSiteId,
    this.initialSiteCode,
    this.isPicker = false,
    this.onSelectCandidate,
  });

  @override
  ConsumerState<NearbySearchScreen> createState() => _NearbySearchScreenState();
}

class _NearbySearchScreenState extends ConsumerState<NearbySearchScreen> {
  /// Canonical site code resolved for the search origin, or null when it could
  /// not be established (the internal id is never displayed in its place).
  String? _canonicalSiteLabel;

  @override
  void initState() {
    super.initState();
    _resolveCanonicalSiteLabel();
    if (widget.sourceMedia == null &&
        (widget.initialLat != null || widget.initialSiteId != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final notifier = ref.read(
            nearbySearchControllerProvider(widget.sourceMedia).notifier);
        notifier.setTargetLocation(
          siteId: widget.initialSiteId,
          lat: widget.initialLat,
          lon: widget.initialLon,
        );
      });
    }
  }

  /// R20: resolves the canonical human-facing site identifier (site code) for
  /// the search origin. The internal database site id is never rendered.
  Future<void> _resolveCanonicalSiteLabel() async {
    final siteId = widget.sourceMedia?.siteId ?? widget.initialSiteId;
    if (siteId == null || siteId.isEmpty) return;

    String? code = widget.initialSiteCode;
    if (code == null || code.trim().isEmpty) {
      try {
        final repo = ref.read(siteRepositoryProvider);
        final uid = ref.read(authServiceProvider).currentUser?.uid;
        final site = await repo.getSiteById(siteId, creatorId: uid);
        code = site?.siteCode;
      } catch (_) {
        // Unresolvable: omit the identifier rather than showing an internal id.
        return;
      }
    }

    if (!mounted || code == null || code.trim().isEmpty) return;
    setState(() {
      _canonicalSiteLabel = HudFormatter.resolveSiteIdentifier(code);
    });
  }

  void _handleCandidateSelected(MediaItem item, NearbySearchState searchState) {
    if (!searchState.isEligibleCandidate(item)) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            item.observationType != ObservationType.nonConformity
                ? 'Only open Non-Conformity evidence can be selected for Closed observations.'
                : 'This Non-Conformity has already been resolved.',
          ),
          backgroundColor: AppColors.statusRed,
        ),
      );
      return;
    }

    if (widget.onSelectCandidate != null) {
      widget.onSelectCandidate!(item);
    }
    Navigator.of(context).pop(item);
  }
  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(nearbySearchControllerProvider(widget.sourceMedia));
    final controller = ref.read(nearbySearchControllerProvider(widget.sourceMedia).notifier);
    final filterCount = searchState.filters.activeFilterCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'NEARBY EVIDENCE SEARCH',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: 0.8,
          ),
        ),
        actions: [
          // Filter Modal Trigger with Active Count Badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: AppColors.textPrimary),
                tooltip: 'Filter Nearby Media',
                onPressed: () => NearbyFilterModal.show(context, widget.sourceMedia),
              ),
              if (filterCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$filterCount',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
            tooltip: 'Refresh Search',
            onPressed: searchState.isLoading ? null : () => controller.executeSearch(),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Source Anchor Card (if searching from an existing capture)
                if (widget.sourceMedia != null)
                  _buildSourceAnchorCard(widget.sourceMedia!)
                else
                  _buildCoordinateAnchorCard(searchState.centerLat, searchState.centerLon),

                if (widget.isPicker)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(25),
                      border: const Border(
                        bottom: BorderSide(color: AppColors.primary, width: 1),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.touch_app_rounded, size: 16, color: AppColors.primaryLight),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'PICKER MODE: Select an open Non-Conformity as BEFORE reference',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryLight,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 2. Dynamic Radius Selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SPATIAL RADIUS',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          '${searchState.radiusMeters.toStringAsFixed(0)}m Search Boundary',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                RadiusSelectorStrip(
                  selectedRadius: searchState.radiusMeters,
                  onRadiusSelected: (newRadius) => controller.setRadius(newRadius),
                ),

                // 2.5 Active Filter Chips Strip (if filters active)
                if (searchState.filters.hasActiveFilters)
                  _buildActiveFiltersStrip(searchState.filters, controller),

                // 3. 3-Way View Mode Toggle Strip: [Grouped] <-> [Timeline] <-> [Spatial Map]
                _buildViewModeToggle(searchState, controller),

                const Divider(height: 1, color: AppColors.border),

                // 4. Results Section Header with Count
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppColors.surfaceContainerHigh.withAlpha(120),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _getHeaderLabel(searchState.viewMode),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: searchState.results.isEmpty ? AppColors.textMuted : AppColors.primary,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(
                          '${searchState.totalCount} ITEMS',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 5. Main Body: Loading / Error / Empty / Grouped / Timeline / Map
                Expanded(
                  child: _buildResultsBody(searchState, controller),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getHeaderLabel(NearbyViewMode mode) {
    switch (mode) {
      case NearbyViewMode.grouped:
        return 'SPATIAL EVIDENCE FOUND';
      case NearbyViewMode.timeline:
        return 'CHRONOLOGICAL LIFECYCLE HISTORY';
      case NearbyViewMode.map:
        return 'SPATIAL MAP RADIUS CANVAS';
    }
  }

  Widget _buildActiveFiltersStrip(NearbySearchFilters filters, NearbySearchNotifier controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 1. Same Site: Off Chip
            if (!filters.sameSiteOnly)
              _buildActiveChip(
                label: 'Same Site: Off',
                onDeleted: () => controller.setSameSiteOnly(true),
              ),

            // 2. Observation Type Chip
            if (filters.observationType != null)
              _buildActiveChip(
                label: filters.observationType!.label,
                color: filters.observationType!.color,
                onDeleted: () => controller.clearObservationTypeFilter(),
              ),

            // 3. Activity Tag Chip
            if (filters.activityTag != null && filters.activityTag!.isNotEmpty)
              _buildActiveChip(
                label: 'Activity: ${filters.activityTag}',
                onDeleted: () => controller.clearActivityFilter(),
              ),

            // 4. Date Range Chip
            if (filters.startDate != null || filters.endDate != null)
              _buildActiveChip(
                label: 'Date Range',
                onDeleted: () => controller.clearDateRangeFilter(),
              ),

            // 5. Clear All Action
            GestureDetector(
              onTap: () => controller.resetFilters(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'Clear All',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveChip({
    required String label,
    required VoidCallback onDeleted,
    Color? color,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      child: InputChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color != null ? Colors.white : AppColors.textPrimary,
          ),
        ),
        backgroundColor: color ?? AppColors.surfaceContainerHigh,
        deleteIcon: Icon(
          Icons.close_rounded,
          size: 14,
          color: color != null ? Colors.white70 : AppColors.textSecondary,
        ),
        onDeleted: onDeleted,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          side: BorderSide(color: color ?? AppColors.border, width: 1),
        ),
      ),
    );
  }

  Widget _buildViewModeToggle(NearbySearchState state, NearbySearchNotifier controller) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildToggleItem(
              label: 'Grouped',
              icon: Icons.grid_view_rounded,
              isSelected: state.viewMode == NearbyViewMode.grouped,
              onTap: () => controller.setViewMode(NearbyViewMode.grouped),
            ),
          ),
          Expanded(
            child: _buildToggleItem(
              label: 'Timeline',
              icon: Icons.timeline_rounded,
              isSelected: state.viewMode == NearbyViewMode.timeline,
              onTap: () => controller.setViewMode(NearbyViewMode.timeline),
            ),
          ),
          Expanded(
            child: _buildToggleItem(
              label: 'Map View',
              icon: Icons.map_rounded,
              isSelected: state.viewMode == NearbyViewMode.map,
              onTap: () => controller.setViewMode(NearbyViewMode.map),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleItem({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(15),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceAnchorCard(MediaItem source) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        border: const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.my_location_rounded, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'SOURCE ANCHOR',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_canonicalSiteLabel != null)
                      Text(
                        '• $_canonicalSiteLabel',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'LAT: ${source.lat.toStringAsFixed(5)}  LON: ${source.lon.toStringAsFixed(5)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinateAnchorCard(double lat, double lon) {
    final siteStr =
        _canonicalSiteLabel != null ? ' • $_canonicalSiteLabel' : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        border: const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.my_location_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'SPATIAL ORIGIN: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}$siteStr',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsBody(NearbySearchState state, NearbySearchNotifier controller) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.primary,
        ),
      );
    }

    if (state.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.statusRed, size: 36),
              const SizedBox(height: 12),
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => controller.executeSearch(),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // View Mode Switch: Map View (PRD Section 11.7)
    if (state.viewMode == NearbyViewMode.map) {
      return NearbyMapView(
        centerLat: state.centerLat,
        centerLon: state.centerLon,
        radiusMeters: state.radiusMeters,
        sourceMedia: state.sourceMedia,
        results: state.results,
      );
    }

    if (state.results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  size: 40,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No Evidence Within ${state.radiusMeters.toStringAsFixed(0)}m',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Try expanding the spatial search radius to find nearby inspection media captured at adjacent locations.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => controller.setRadius(50.0),
                icon: const Icon(Icons.zoom_out_map_rounded, size: 16),
                label: const Text('Expand to 50m Radius'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // View Mode Switch: Timeline View (PRD Section 11.6)
    if (state.viewMode == NearbyViewMode.timeline) {
      return LocationTimelineView(items: state.chronologicalResults);
    }

    // View Mode Switch: Grouped Results List (PRD Section 11.3)
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Group 1: Before (Open Non-Conformities)
        if (state.beforeResults.isNotEmpty)
          _buildGroupSection(
            title: 'BEFORE / OPEN NON-CONFORMITY',
            color: AppColors.statusRed,
            items: state.beforeResults,
            searchState: state,
          ),

        // Group 2: After (Resolved Non-Conformities)
        if (state.afterResults.isNotEmpty)
          _buildGroupSection(
            title: 'AFTER / RESOLUTION',
            color: AppColors.statusGreen,
            items: state.afterResults,
            searchState: state,
          ),

        // Group 3: Progress Observations
        if (state.progressResults.isNotEmpty)
          _buildGroupSection(
            title: 'PROGRESS DOCUMENTATION',
            color: AppColors.primary,
            items: state.progressResults,
            searchState: state,
          ),

        // Group 4: Material & General
        if (state.otherResults.isNotEmpty)
          _buildGroupSection(
            title: 'MATERIAL & GENERAL',
            color: AppColors.textSecondary,
            items: state.otherResults,
            searchState: state,
          ),
      ],
    );
  }

  Widget _buildGroupSection({
    required String title,
    required Color color,
    required List<dynamic> items,
    required NearbySearchState searchState,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header with Count
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(${items.length})',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Cards list
          for (final result in items) ...[
            NearbyMediaCard(
              result: result,
              isPicker: widget.isPicker,
              isEligible: searchState.isEligibleCandidate(result.item),
              onSelect: widget.isPicker
                  ? () => _handleCandidateSelected(result.item, searchState)
                  : null,
              onTap: widget.isPicker
                  ? () => _handleCandidateSelected(result.item, searchState)
                  : null,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
