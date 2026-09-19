import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../core/services/auth_service.dart';
import '../../data/repositories/media_repository.dart';
import '../../data/repositories/site_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/media_item.dart';
import '../../shared/utils/responsive_layout.dart';
import '../../shared/widgets/confirmation_dialog.dart';
import '../sites/site_controller.dart';
import 'controllers/gallery_controller.dart';
import 'media_detail_screen.dart';
import 'models/gallery_selection_state.dart';
import 'models/gallery_view_mode.dart';
import 'services/evidence_export_service.dart';
import 'widgets/gallery_empty_view.dart';
import 'widgets/gallery_filter_bar.dart';
import 'widgets/gallery_filter_modal.dart';
import 'widgets/gallery_media_tile.dart';
import 'widgets/single_item_share_sheet.dart';
import '../nearby/nearby_search_screen.dart';
import '../sync/widgets/sync_status_badge.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    final filter = ref.read(galleryFilterProvider);
    _searchController = TextEditingController(text: filter.searchQuery ?? '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCamera() {
    Navigator.of(context).pop();
  }

  void _navigateToDetail(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaDetailScreen(mediaItem: item),
      ),
    );
  }

  // ==========================================
  // BATCH ACTION HANDLERS
  // ==========================================

  Future<void> _handleBatchShareFiles(List<MediaItem> selectedItems) async {
    final exportService = ref.read(evidenceExportServiceProvider);
    try {
      await exportService.shareBatchFiles(selectedItems);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share files: $e'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    }
  }

  Future<({String? siteCode, String? siteName})> _resolveBatchSiteContext(
    List<MediaItem> selectedItems,
  ) async {
    final siteIds = selectedItems
        .map((item) => item.siteId.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    // If multiple sites or no site: neutral site context rather than
    // assigning one site's identity to all evidence.
    if (siteIds.length != 1) {
      return (siteCode: null, siteName: null);
    }

    final singleSiteId = siteIds.first;

    // 1. Check in-memory availableSites
    final availableSites = ref.read(siteControllerProvider).availableSites;
    for (final s in availableSites) {
      if (s.id == singleSiteId) {
        return (siteCode: s.siteCode, siteName: s.name);
      }
    }

    // 2. Query SiteRepository
    AuthUser? currentUser;
    try {
      currentUser = ref.read(authServiceProvider).currentUser;
    } catch (_) {}
    final effectiveCreatorId = selectedItems.first.creatorId ?? currentUser?.uid;

    try {
      final siteRepo = ref.read(siteRepositoryProvider);
      final site =
          await siteRepo.getSiteById(singleSiteId, creatorId: effectiveCreatorId);
      if (site != null) {
        return (siteCode: site.siteCode, siteName: site.name);
      }
    } catch (_) {}

    return (siteCode: null, siteName: null);
  }

  Future<void> _handleBatchExportPdf(List<MediaItem> selectedItems) async {
    final exportService = ref.read(evidenceExportServiceProvider);
    final (:siteCode, :siteName) = await _resolveBatchSiteContext(selectedItems);
    AuthUser? exporter;
    try {
      exporter = ref.read(authServiceProvider).currentUser;
    } catch (_) {}

    try {
      await exportService.exportBatchPdf(
        selectedItems,
        siteCode: siteCode,
        siteName: siteName,
        exporterEmail: exporter?.email,
        exporterUid: exporter?.uid,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate batch PDF: $e'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    }
  }

  Future<void> _handleBatchExportZip(List<MediaItem> selectedItems) async {
    final exportService = ref.read(evidenceExportServiceProvider);
    final (:siteCode, :siteName) = await _resolveBatchSiteContext(selectedItems);
    AuthUser? exporter;
    try {
      exporter = ref.read(authServiceProvider).currentUser;
    } catch (_) {}

    try {
      await exportService.exportBatchZip(
        selectedItems,
        siteCode: siteCode,
        siteName: siteName,
        exporterEmail: exporter?.email,
        exporterUid: exporter?.uid,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate ZIP archive: $e'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeSite = ref.watch(siteControllerProvider).activeSite;
    final filterState = ref.watch(galleryFilterProvider);
    final viewMode = ref.watch(galleryViewModeProvider);
    final mediaAsync = ref.watch(filteredGalleryMediaProvider);
    final selectionState = ref.watch(gallerySelectionProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: selectionState.isSelectMode
            ? IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
                tooltip: 'Exit Select Mode',
                onPressed: () {
                  ref.read(gallerySelectionProvider.notifier).exitSelectMode();
                },
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                onPressed: _openCamera,
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectionState.isSelectMode
                  ? '${selectionState.selectedCount} SELECTED'
                  : 'EVIDENCE GALLERY',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: 0.8,
              ),
            ),
            if (selectionState.isSelectMode)
              const Text(
                'Tap items to toggle selection',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.primaryLight,
                ),
              )
            else if (activeSite != null)
              Text(
                '${activeSite.siteCode} • ${activeSite.name}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          if (selectionState.isSelectMode)
            mediaAsync.maybeWhen(
              data: (items) {
                final allSelected = items.isNotEmpty &&
                    items.every((item) => selectionState.isSelected(item.id));
                return TextButton(
                  onPressed: () {
                    if (allSelected) {
                      ref.read(gallerySelectionProvider.notifier).clearSelection();
                    } else {
                      ref.read(gallerySelectionProvider.notifier).selectAll(
                            items.map((i) => i.id).toList(),
                          );
                    }
                  },
                  child: Text(
                    allSelected ? 'DESELECT ALL' : 'SELECT ALL',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryLight,
                    ),
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            )
          else ...[
            const SyncStatusBadge(compact: true),
            // Select Mode Toggle Button
            IconButton(
              icon: const Icon(Icons.checklist_rounded, color: AppColors.textPrimary),
              tooltip: 'Select Evidence',
              onPressed: () {
                ref.read(gallerySelectionProvider.notifier).enterSelectMode();
              },
            ),
            // View Mode Switcher (2-col vs 3-col)
            IconButton(
              icon: Icon(
                viewMode == GalleryViewMode.grid3x3
                    ? Icons.grid_view_rounded
                    : Icons.view_comfy_alt_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
              tooltip: 'Toggle Grid Columns',
              onPressed: () {
                ref.read(galleryViewModeProvider.notifier).state =
                    viewMode == GalleryViewMode.grid3x3
                        ? GalleryViewMode.grid2x2
                        : GalleryViewMode.grid3x3;
              },
            ),
            // Filter Modal Trigger with Badge
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.tune_rounded, color: AppColors.textPrimary),
                  tooltip: 'Filter Gallery',
                  onPressed: () => GalleryFilterModal.show(context),
                ),
                if (filterState.hasActiveFilters)
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
                        '${filterState.activeFilterCount}',
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
          ],
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: Column(
        children: [
          // 1. Search Bar (hidden during select mode for maximum clarity)
          if (!selectionState.isSelectMode)
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search notes, activity, or site...',
                  hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textSecondary),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textSecondary),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(galleryFilterProvider.notifier).clearSearchQuery();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    borderSide: const BorderSide(color: AppColors.border, width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    borderSide: const BorderSide(color: AppColors.border, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                onChanged: (val) {
                  ref.read(galleryFilterProvider.notifier).setSearchQuery(val);
                },
              ),
            ),

          // 2. Quick Filter Bar
          if (!selectionState.isSelectMode) ...[
            Container(
              color: AppColors.surface,
              child: const GalleryFilterBar(),
            ),
            const Divider(height: 1, color: AppColors.border),
          ],

          // 3. Virtualized Grid
          Expanded(
            child: mediaAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
              error: (err, stack) => Center(
                child: Text(
                  'Error loading gallery: $err',
                  style: const TextStyle(color: AppColors.statusRed, fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return GalleryEmptyView(
                    hasActiveFilters: filterState.hasActiveFilters,
                    onResetFilters: () {
                      _searchController.clear();
                      ref.read(galleryFilterProvider.notifier).resetFilters();
                    },
                    onOpenCamera: _openCamera,
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    int crossAxisCount;
                    if (viewMode == GalleryViewMode.list) {
                      crossAxisCount = 1;
                    } else if (constraints.maxWidth >= ResponsiveBreakpoints.expandedMin) {
                      crossAxisCount = viewMode == GalleryViewMode.grid2x2 ? 4 : 6;
                    } else if (constraints.maxWidth >= ResponsiveBreakpoints.compactMax) {
                      crossAxisCount = viewMode == GalleryViewMode.grid2x2 ? 3 : 4;
                    } else {
                      crossAxisCount = viewMode.crossAxisCount;
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: viewMode == GalleryViewMode.list ? 3.2 : 1.0,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isSelected = selectionState.isSelected(item.id);

                        return GalleryMediaTile(
                          item: item,
                          isSelectMode: selectionState.isSelectMode,
                          isSelected: isSelected,
                          onTap: () {
                            if (selectionState.isSelectMode) {
                              ref.read(gallerySelectionProvider.notifier).toggleSelection(item.id);
                            } else {
                              _navigateToDetail(item);
                            }
                          },
                          onLongPress: () {
                            if (selectionState.isSelectMode) {
                              ref.read(gallerySelectionProvider.notifier).toggleSelection(item.id);
                            } else {
                              _showItemContextMenu(item);
                            }
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: selectionState.isSelectMode
          ? _buildBatchActionBar(selectionState, mediaAsync.value ?? [])
          : null,
    );
  }

  void _showItemContextMenu(MediaItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header with Item Info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        item.observationType.icon,
                        color: item.observationType.color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.activityTag ?? item.observationType.label,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                          ),
                          Text(
                            item.capturedAddress ?? 'LAT: ${item.lat.toStringAsFixed(4)}, LON: ${item.lon.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: AppColors.border),

              // 1. Find Nearby Evidence Action (PRD Section 11)
              ListTile(
                leading: const Icon(Icons.near_me_rounded, color: AppColors.primary),
                title: const Text('Find Nearby Evidence', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                subtitle: const Text('Search spatial cluster around this GPS capture', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NearbySearchScreen(sourceMedia: item),
                    ),
                  );
                },
              ),

              // 2. View Evidence Details
              ListTile(
                leading: const Icon(Icons.visibility_rounded, color: AppColors.textPrimary),
                title: const Text('View Evidence Details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                subtitle: const Text('Inspect high-res photo, metadata & SHA-256 hash', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _navigateToDetail(item);
                },
              ),

              // 3. Multi-Select Mode (M4-E)
              ListTile(
                leading: const Icon(Icons.checklist_rounded, color: AppColors.textPrimary),
                title: const Text('Select Evidence (Multi-Select)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                subtitle: const Text('Select multiple items for batch PDF or ZIP export', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref.read(gallerySelectionProvider.notifier).enterSelectMode(item.id);
                },
              ),

              // 4. Share & Export Single File (M4-D)
              ListTile(
                leading: const Icon(Icons.share_rounded, color: AppColors.textPrimary),
                title: const Text('Share & Export Single File', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                subtitle: const Text('Share stamped PDF audit card or image file', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  SingleItemShareSheet.show(context, item);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleBatchDelete(List<MediaItem> selectedItems) async {
    if (selectedItems.isEmpty) return;

    final count = selectedItems.length;
    final message = count == 1
        ? 'Are you sure you want to delete this 1 selected media item?'
        : 'Are you sure you want to delete these $count selected media items?';

    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Delete Selected',
      message: message,
      confirmLabel: 'Delete',
    );

    if (confirmed == true && mounted) {
      final repo = ref.read(mediaRepositoryProvider);
      for (final item in selectedItems) {
        if (item.syncStatus == SyncStatusType.synced) {
          await repo.removeFromGallery(item.id);
        } else {
          await repo.deletePermanently(item.id);
        }
      }
      if (mounted) {
        ref.read(gallerySelectionProvider.notifier).exitSelectMode();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count item${count == 1 ? '' : 's'} deleted'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildBatchActionBar(GallerySelectionState selectionState, List<MediaItem> allItems) {
    final selectedItems = allItems.where((i) => selectionState.isSelected(i.id)).toList();
    final hasSelection = selectedItems.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 1. Share Files Button
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text('Share', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasSelection ? AppColors.primary : AppColors.surfaceContainer,
                  foregroundColor: hasSelection ? Colors.white : AppColors.textMuted,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: hasSelection ? () => _handleBatchShareFiles(selectedItems) : null,
              ),
            ),
            const SizedBox(width: 8),

            // 2. Export Multi-Page PDF Report
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text('PDF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasSelection ? AppColors.statusAmber : AppColors.surfaceContainer,
                  foregroundColor: hasSelection ? Colors.black : AppColors.textMuted,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: hasSelection ? () => _handleBatchExportPdf(selectedItems) : null,
              ),
            ),
            const SizedBox(width: 8),

            // 3. Export ZIP Archive (Files + Manifest + PDF)
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.archive_rounded, size: 16),
                label: const Text('ZIP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasSelection ? const Color(0xFF00897B) : AppColors.surfaceContainer,
                  foregroundColor: hasSelection ? Colors.white : AppColors.textMuted,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: hasSelection ? () => _handleBatchExportZip(selectedItems) : null,
              ),
            ),
            const SizedBox(width: 8),

            // 4. Batch Delete
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Delete', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasSelection ? AppColors.statusRed : AppColors.surfaceContainer,
                  foregroundColor: hasSelection ? Colors.white : AppColors.textMuted,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: hasSelection ? () => _handleBatchDelete(selectedItems) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
