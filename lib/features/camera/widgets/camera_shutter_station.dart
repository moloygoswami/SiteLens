import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../models/camera_hardware_state.dart';
import '../models/camera_ui_state.dart';

class CameraShutterStation extends StatelessWidget {
  final CameraUiState state;
  final CameraStatus cameraStatus;
  final bool isCapturePermitted;
  final bool hasAuthenticatedCreator;
  final bool hasActiveSite;
  final bool isRecordingVideo;
  final String recordingDurationFormatted;
  final bool? recordingHasAudioTrack;
  final bool isExecutingCapture;
  final VoidCallback onShutterPressed;
  final VoidCallback onGalleryPressed;
  final ValueChanged<CameraCaptureMode> onModeChanged;
  final VoidCallback onFlipCameraPressed;

  const CameraShutterStation({
    super.key,
    required this.state,
    this.cameraStatus = CameraStatus.ready,
    this.isCapturePermitted = true,
    this.hasAuthenticatedCreator = true,
    this.hasActiveSite = true,
    this.isRecordingVideo = false,
    this.recordingDurationFormatted = '00:00',
    this.recordingHasAudioTrack,
    this.isExecutingCapture = false,
    required this.onShutterPressed,
    required this.onGalleryPressed,
    required this.onModeChanged,
    required this.onFlipCameraPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isShutterDisabled = (!isCapturePermitted && !isRecordingVideo) ||
        cameraStatus == CameraStatus.unavailable ||
        cameraStatus == CameraStatus.capturing ||
        cameraStatus == CameraStatus.initializing ||
        cameraStatus == CameraStatus.error ||
        cameraStatus == CameraStatus.permissionDenied ||
        cameraStatus == CameraStatus.permissionPermanentlyDenied ||
        cameraStatus == CameraStatus.permissionRestricted ||
        isExecutingCapture;

    return Container(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Shutter Readiness / Hardware & GPS Status Banner
          if (isRecordingVideo)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              color: AppColors.statusRed.withAlpha(40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.statusRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'RECORDING VIDEO • $recordingDurationFormatted',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.statusRed,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (recordingHasAudioTrack == false) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.mic_off, size: 12, color: AppColors.statusAmber),
                    const SizedBox(width: 4),
                    const Text(
                      'MUTED (NO MIC)',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.statusAmber,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            ReadinessBanner(
              gps: state.gps,
              cameraStatus: cameraStatus,
              isCapturePermitted: isCapturePermitted,
              hasAuthenticatedCreator: hasAuthenticatedCreator,
              hasActiveSite: hasActiveSite,
            ),

          const Divider(height: 1, color: AppColors.border),

          // 2. Primary Controls: Balanced 3-Column Layout with Dead-Center Shutter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left Column (flex 1): Gallery Shortcut
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GalleryShortcut(
                      cachedCount: state.cachedGalleryCount,
                      onTap: onGalleryPressed,
                    ),
                  ),
                ),

                // Center Column (flex 2): Mode Switcher + Dual-Ring Shutter Button
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Photo / Video Mode Switcher Pill (hidden during active video recording)
                      if (!isRecordingVideo)
                        ModeSwitcher(
                          currentMode: state.captureMode,
                          onModeChanged: onModeChanged,
                        )
                      else
                        const SizedBox(height: 28),
                      const SizedBox(height: 10),
                      // Shutter Trigger
                      ShutterButton(
                        isLocked: isShutterDisabled,
                        isDegraded: state.gps.isDegraded,
                        isRecording: isRecordingVideo,
                        captureMode: state.captureMode,
                        onPressed: isExecutingCapture ? null : onShutterPressed,
                      ),
                    ],
                  ),
                ),

                // Right Column (flex 1): Camera Switcher / Flip Lens Action
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: CameraSwitcher(
                      isFrontCamera: state.isFrontCamera,
                      isLocked: isRecordingVideo,
                      onTap: onFlipCameraPressed,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReadinessBanner extends StatelessWidget {
  final GpsUiFixture gps;
  final CameraStatus cameraStatus;
  final bool isCapturePermitted;
  final bool hasAuthenticatedCreator;
  final bool hasActiveSite;

  const ReadinessBanner({
    super.key,
    required this.gps,
    required this.cameraStatus,
    required this.isCapturePermitted,
    this.hasAuthenticatedCreator = true,
    this.hasActiveSite = true,
  });

  @override
  Widget build(BuildContext context) {
    final String text;
    final Color dotColor;
    final Color bgColor;

    if (cameraStatus == CameraStatus.initializing) {
      text = 'Initializing camera…';
      dotColor = AppColors.statusAmber;
      bgColor = AppColors.surfaceContainerHigh;
    } else if (cameraStatus == CameraStatus.permissionDenied) {
      text = 'Camera permission required — grant access to capture evidence.';
      dotColor = AppColors.statusAmber;
      bgColor = AppColors.surfaceContainerHigh;
    } else if (cameraStatus == CameraStatus.permissionPermanentlyDenied) {
      text = 'Camera permission blocked — enable in settings to capture evidence.';
      dotColor = AppColors.statusRed;
      bgColor = AppColors.statusRedLight;
    } else if (cameraStatus == CameraStatus.permissionRestricted) {
      text = 'Camera access restricted by device policy.';
      dotColor = AppColors.statusRed;
      bgColor = AppColors.surfaceContainerHigh;
    } else if (cameraStatus == CameraStatus.unavailable) {
      text = 'Optical sensor unavailable — evidence capture disabled.';
      dotColor = AppColors.statusRed;
      bgColor = AppColors.statusRedLight;
    } else if (cameraStatus == CameraStatus.error) {
      text = 'Camera error — capture unavailable. Restore camera to continue.';
      dotColor = AppColors.statusRed;
      bgColor = AppColors.surfaceContainerHigh;
    } else if (cameraStatus == CameraStatus.capturing) {
      text = 'Capturing evidence frame…';
      dotColor = AppColors.primary;
      bgColor = AppColors.surfaceContainerHigh;
    } else if (!hasAuthenticatedCreator) {
      text = 'Authentication required to capture evidence';
      dotColor = AppColors.statusRed;
      bgColor = AppColors.surfaceContainerHigh;
    } else if (!hasActiveSite) {
      text = 'Active site required — select a site to capture evidence';
      dotColor = AppColors.statusRed;
      bgColor = AppColors.surfaceContainerHigh;
    } else if (!isCapturePermitted) {
      // Cause-specific GPS guidance lives on the GPS pill; the banner stays
      // concise and never claims a stronger state than the system holds.
      text = 'Shutter locked — GPS required for evidence';
      dotColor = AppColors.statusRed;
      bgColor = AppColors.surfaceContainerHigh;
    } else if (gps.isDegraded) {
      text = 'Low GPS precision — capture will be flagged low accuracy';
      dotColor = AppColors.statusAmber;
      bgColor = AppColors.surfaceContainerHigh;
    } else {
      text = 'Ready for evidence capture';
      dotColor = AppColors.statusGreen;
      bgColor = AppColors.surfaceContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      color: bgColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class ModeSwitcher extends StatelessWidget {
  final CameraCaptureMode currentMode;
  final ValueChanged<CameraCaptureMode> onModeChanged;
  final bool isDark;
  final bool isLocked;

  const ModeSwitcher({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    this.isDark = false,
    this.isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222620) : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(
          color: isDark ? Colors.white24 : AppColors.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: CameraCaptureMode.values.map((mode) {
          final isSelected = mode == currentMode;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: isDark ? 1 : 2),
            child: Semantics(
              button: true,
              enabled: !isLocked,
              selected: isSelected,
              label: '${mode.label} capture mode',
              hint: isLocked
                  ? 'Disabled during video recording'
                  : (isSelected ? 'Currently active' : 'Switch to ${mode.label} capture mode'),
              child: InkWell(
                onTap: isLocked ? null : () => onModeChanged(mode),
                borderRadius: BorderRadius.circular(AppRadii.xs),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(
                    horizontal: isDark ? 5 : 14,
                    vertical: isDark ? 3.5 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? const Color(0xFF383F34) : AppColors.surface)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                    border: isSelected
                        ? Border.all(color: isDark ? Colors.white30 : AppColors.border, width: 1)
                        : null,
                  ),
                  child: Text(
                    mode.label,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: isDark ? 9.5 : 12,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected
                          ? (isDark ? Colors.white : AppColors.textPrimary)
                          : (isDark ? Colors.white60 : AppColors.textMuted),
                      letterSpacing: isDark ? 0.2 : 0.5,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class ShutterButton extends StatefulWidget {
  final bool isLocked;
  final bool isDegraded;
  final bool isRecording;
  final CameraCaptureMode captureMode;
  final VoidCallback? onPressed;

  const ShutterButton({
    super.key,
    required this.isLocked,
    required this.isDegraded,
    this.isRecording = false,
    this.captureMode = CameraCaptureMode.photo,
    this.onPressed,
  });

  @override
  State<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<ShutterButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    const outerSize = 72.0;
    const innerSize = 56.0;

    final ringColor = widget.isRecording
        ? AppColors.statusRed
        : (widget.isLocked
            ? AppColors.border
            : (widget.isDegraded ? const Color(0xFFD97706) : AppColors.textPrimary));

    final isVideo = widget.captureMode == CameraCaptureMode.video || widget.isRecording;
    final coreColor = widget.isLocked
        ? AppColors.surfaceContainerHigh
        : (isVideo
            ? (_isPressed || widget.isRecording ? const Color(0xFFB71C1C) : AppColors.statusRed)
            : (_isPressed ? AppColors.primaryDark : AppColors.primary));

    String semanticLabel;
    String? semanticHint;
    if (widget.isLocked) {
      semanticLabel = isVideo ? 'Record video button locked' : 'Capture photo button locked';
      semanticHint = 'GPS position fix required before evidence capture';
    } else if (widget.isRecording) {
      semanticLabel = 'Stop video recording';
      semanticHint = 'Stops recording and opens evidence review';
    } else if (isVideo) {
      semanticLabel = 'Start video recording';
      semanticHint = 'Begins recording GPS-verified video evidence';
    } else {
      semanticLabel = 'Capture evidence photo';
      semanticHint = 'Takes GPS-verified inspection photo';
    }

    return Semantics(
      button: true,
      enabled: !widget.isLocked && widget.onPressed != null,
      label: semanticLabel,
      hint: semanticHint,
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: widget.onPressed == null
            ? null
            : (_) {
                setState(() => _isPressed = true);
              },
        onTapUp: widget.onPressed == null
            ? null
            : (_) {
                setState(() => _isPressed = false);
              },
        onTapCancel: () {
          setState(() => _isPressed = false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: outerSize,
          height: outerSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ringColor, width: 3.5),
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: widget.isRecording ? 28 : (_isPressed ? innerSize - 4 : innerSize),
              height: widget.isRecording ? 28 : (_isPressed ? innerSize - 4 : innerSize),
              decoration: BoxDecoration(
                color: coreColor,
                shape: widget.isRecording ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: widget.isRecording ? BorderRadius.circular(4) : null,
              ),
              child: Center(
                child: Icon(
                  widget.isLocked
                      ? Icons.lock_rounded
                      : (widget.isRecording
                          ? Icons.stop_rounded
                          : (isVideo ? Icons.videocam_rounded : Icons.camera_alt_rounded)),
                  size: widget.isRecording ? 22 : 26,
                  color: widget.isLocked ? AppColors.textMuted : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GalleryShortcut extends StatelessWidget {
  final int cachedCount;
  final VoidCallback onTap;
  final bool isDark;

  const GalleryShortcut({
    super.key,
    required this.cachedCount,
    required this.onTap,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: cachedCount > 0 ? 'Gallery, $cachedCount evidence items' : 'Gallery, empty',
      hint: 'Open evidence gallery',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF222620) : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: isDark ? Colors.white24 : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.photo_library_outlined,
                color: isDark ? Colors.white : AppColors.textSecondary,
                size: 22,
              ),
            ),
            if (cachedCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                    border: Border.all(
                      color: isDark ? const Color(0xFF131512) : AppColors.surface,
                      width: 1.5,
                    ),
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Center(
                    child: Text(
                      cachedCount > 99 ? '99+' : '$cachedCount',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CameraSwitcher extends StatelessWidget {
  final bool isFrontCamera;
  final VoidCallback onTap;
  final bool isDark;
  final bool isLocked;

  const CameraSwitcher({
    super.key,
    required this.isFrontCamera,
    required this.onTap,
    this.isDark = false,
    this.isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !isLocked,
      label: isFrontCamera ? 'Switch to rear camera' : 'Switch to front camera',
      hint: isLocked ? 'Disabled during video recording' : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLocked ? null : onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF222620) : AppColors.surfaceContainerHigh,
              border: Border.all(
                color: isDark ? Colors.white24 : AppColors.border,
                width: 1.5,
              ),
            ),
            child: AnimatedRotation(
              turns: isFrontCamera ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Icon(
                Icons.flip_camera_android_rounded,
                color: isLocked
                    ? (isDark ? Colors.white24 : AppColors.textMuted)
                    : (isDark ? Colors.white : AppColors.textSecondary),
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
