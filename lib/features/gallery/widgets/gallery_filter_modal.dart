import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../../../domain/models/enums.dart';
import '../../sites/site_controller.dart';
import '../controllers/gallery_controller.dart';

class GalleryFilterModal extends ConsumerStatefulWidget {
  const GalleryFilterModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const GalleryFilterModal(),
    );
  }

  @override
  ConsumerState<GalleryFilterModal> createState() => _GalleryFilterModalState();
}

class _GalleryFilterModalState extends ConsumerState<GalleryFilterModal> {
  late TextEditingController _activityController;
  DateTimeRange? _selectedDateRange;
  ObservationType? _selectedObservation;
  SyncStatusType? _selectedSync;
  bool _lowAccuracyOnly = false;
  String? _selectedSiteId;

  @override
  void initState() {
    super.initState();
    final filterState = ref.read(galleryFilterProvider);
    _activityController = TextEditingController(text: filterState.activityTag ?? '');
    _selectedDateRange = filterState.dateRange;
    _selectedObservation = filterState.observationType;
    _selectedSync = filterState.syncStatus;
    _lowAccuracyOnly = filterState.lowAccuracyOnly;
    _selectedSiteId = filterState.siteId;
  }

  @override
  void dispose() {
    _activityController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = _selectedDateRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              iconTheme: IconThemeData(color: Colors.white),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  void _applyFilters() {
    final notifier = ref.read(galleryFilterProvider.notifier);
    notifier.setActivityTag(_activityController.text.trim());
    notifier.setDateRange(_selectedDateRange);
    notifier.setObservationType(_selectedObservation);
    notifier.setSyncStatus(_selectedSync);
    notifier.setSiteId(_selectedSiteId);
    if (ref.read(galleryFilterProvider).lowAccuracyOnly != _lowAccuracyOnly) {
      notifier.toggleLowAccuracyOnly();
    }
    Navigator.of(context).pop();
  }

  void _resetFilters() {
    ref.read(galleryFilterProvider.notifier).resetFilters();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(siteControllerProvider).availableSites;
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'FILTER GALLERY',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.8,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(color: AppColors.border),
            const SizedBox(height: 12),

            // 1. Site Filter
            const Text(
              'INSPECTION SITE',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedSiteId,
                  isExpanded: true,
                  dropdownColor: AppColors.surfaceContainerHigh,
                  hint: const Text('All Sites / Active Context', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Sites', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    ),
                    ...sites.map((s) => DropdownMenuItem<String?>(
                          value: s.id,
                          child: Text('${s.siteCode} • ${s.name}', style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                        )),
                  ],
                  onChanged: (val) => setState(() => _selectedSiteId = val),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Date Range Picker
            const Text(
              'DATE RANGE',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.date_range_rounded, size: 16, color: AppColors.primaryLight),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedDateRange != null
                            ? '${dateFormat.format(_selectedDateRange!.start)} - ${dateFormat.format(_selectedDateRange!.end)}'
                            : 'Select date range...',
                        style: TextStyle(
                          fontSize: 13,
                          color: _selectedDateRange != null ? AppColors.textPrimary : AppColors.textMuted,
                        ),
                      ),
                    ),
                    if (_selectedDateRange != null)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textSecondary),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => setState(() => _selectedDateRange = null),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Activity Tag Filter
            const Text(
              'ACTIVITY / WORK STAGE',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _activityController,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Filter by activity (e.g. Excavation, Rebar)...',
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceContainer,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4. Sync Status Filter
            const Text(
              'SYNC STATUS',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SyncStatusType?>(
                  value: _selectedSync,
                  isExpanded: true,
                  dropdownColor: AppColors.surfaceContainerHigh,
                  hint: const Text('All Sync States', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  items: [
                    const DropdownMenuItem<SyncStatusType?>(
                      value: null,
                      child: Text('All Sync States', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    ),
                    ...SyncStatusType.values.map((status) => DropdownMenuItem<SyncStatusType?>(
                          value: status,
                          child: Text(
                            status.name[0].toUpperCase() + status.name.substring(1),
                            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          ),
                        )),
                  ],
                  onChanged: (val) => setState(() => _selectedSync = val),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 5. Low Accuracy Toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Low GPS Accuracy Only (>20m)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              subtitle: const Text(
                'Filter captures tagged with degraded GPS precision',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              value: _lowAccuracyOnly,
              activeThumbColor: AppColors.statusAmber,
              onChanged: (val) => setState(() => _lowAccuracyOnly = val),
            ),
            const SizedBox(height: 20),

            // Bottom Actions (Two-Pill layout: Reset & Apply)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _resetFilters,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      side: const BorderSide(color: AppColors.border, width: 1.5),
                    ),
                    child: const Text('Reset All', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _applyFilters,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                    ),
                    child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
