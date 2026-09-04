import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/media_item.dart';
import '../controllers/nearby_search_controller.dart';
import '../models/nearby_search_state.dart';

class NearbyFilterModal extends ConsumerStatefulWidget {
  final MediaItem? sourceMedia;

  const NearbyFilterModal({
    super.key,
    this.sourceMedia,
  });

  static Future<void> show(BuildContext context, MediaItem? sourceMedia) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => NearbyFilterModal(sourceMedia: sourceMedia),
    );
  }

  @override
  ConsumerState<NearbyFilterModal> createState() => _NearbyFilterModalState();
}

class _NearbyFilterModalState extends ConsumerState<NearbyFilterModal> {
  late bool _sameSiteOnly;
  late TextEditingController _activityController;
  ObservationType? _selectedObservation;
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    final searchState = ref.read(nearbySearchControllerProvider(widget.sourceMedia));
    final filters = searchState.filters;

    _sameSiteOnly = filters.sameSiteOnly;
    _activityController = TextEditingController(text: filters.activityTag ?? '');
    _selectedObservation = filters.observationType;
    if (filters.startDate != null && filters.endDate != null) {
      _selectedDateRange = DateTimeRange(
        start: filters.startDate!,
        end: filters.endDate!,
      );
    }
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
    final controller = ref.read(nearbySearchControllerProvider(widget.sourceMedia).notifier);
    final cleanActivity = _activityController.text.trim();

    final newFilters = NearbySearchFilters(
      sameSiteOnly: _sameSiteOnly,
      activityTag: cleanActivity.isNotEmpty ? cleanActivity : null,
      observationType: _selectedObservation,
      startDate: _selectedDateRange?.start,
      endDate: _selectedDateRange?.end,
    );

    controller.setFilters(newFilters);
    Navigator.of(context).pop();
  }

  void _resetAllFilters() {
    final controller = ref.read(nearbySearchControllerProvider(widget.sourceMedia).notifier);
    controller.resetFilters();
    setState(() {
      _sameSiteOnly = true;
      _activityController.clear();
      _selectedObservation = null;
      _selectedDateRange = null;
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'FILTER NEARBY MEDIA',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  TextButton(
                    onPressed: _resetAllFilters,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      'Reset All',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 1. SAME SITE ONLY TOGGLE
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _sameSiteOnly = !_sameSiteOnly),
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.apartment_rounded, color: AppColors.primaryDark, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Same Site Only',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                widget.sourceMedia != null
                                    ? 'Limit to site of source capture'
                                    : 'Limit to selected site context',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _sameSiteOnly,
                          activeThumbColor: AppColors.primary,
                          onChanged: (val) => setState(() => _sameSiteOnly = val),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 2. ACTIVITY / WORK STAGE FILTER
              const Text(
                'ACTIVITY / WORK STAGE',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _activityController,
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g. Rebar, Concrete, Excavation',
                  hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.work_outline_rounded, size: 18, color: AppColors.textSecondary),
                  suffixIcon: _activityController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textSecondary),
                          onPressed: () {
                            _activityController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              // 3. OBSERVATION TYPE FILTER
              const Text(
                'OBSERVATION TYPE',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildObservationChip(null, 'All Types'),
                  ...ObservationType.values.map((type) => _buildObservationChip(type, type.label)),
                ],
              ),
              const SizedBox(height: 16),

              // 4. DATE RANGE PICKER
              const Text(
                'DATE RANGE',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickDateRange,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedDateRange != null ? AppColors.primary : AppColors.border,
                      width: _selectedDateRange != null ? 1.2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: _selectedDateRange != null ? AppColors.primary : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedDateRange != null
                              ? '${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start)}  →  ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end)}'
                              : 'All Capture Dates',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _selectedDateRange != null ? FontWeight.w700 : FontWeight.normal,
                            color: _selectedDateRange != null ? AppColors.textPrimary : AppColors.textMuted,
                          ),
                        ),
                      ),
                      if (_selectedDateRange != null)
                        GestureDetector(
                          onTap: () => setState(() => _selectedDateRange = null),
                          child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textSecondary),
                        )
                      else
                        const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // APPLY ACTION BUTTON
              ElevatedButton(
                onPressed: _applyFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Apply Filters',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildObservationChip(ObservationType? type, String label) {
    final isSelected = _selectedObservation == type;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? Colors.white : AppColors.textPrimary,
        ),
      ),
      selected: isSelected,
      selectedColor: type?.color ?? AppColors.primary,
      backgroundColor: AppColors.surface,
      side: BorderSide(
        color: isSelected ? (type?.color ?? AppColors.primary) : AppColors.border,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
      onSelected: (_) => setState(() => _selectedObservation = type),
    );
  }
}
