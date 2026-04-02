// lib/features/camera/camera_page_native.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../core/router.dart';
import '../../database/app_database.dart';
import '../../shared/services/document_service.dart';
import '../../shared/services/permission_service.dart';
import '../../shared/services/scanner_bridge.dart';
import 'widgets/crop_enhance_sheet.dart';
import 'widgets/native_camera_preview.dart';

/// Native camera page for Android using CameraX + OpenCV.
///
/// Capture flow:
///   1. [captureRaw] → full uncropped frame saved to disk
///   2. [ManualCropEditor] → user adjusts corner handles on the full image
///   3. [captureDocument] → perspective correction applied with confirmed corners
class CameraPageNative extends ConsumerStatefulWidget {
  const CameraPageNative({super.key, this.existingDocId});
  final int? existingDocId;

  @override
  ConsumerState<CameraPageNative> createState() => _CameraPageNativeState();
}

class _CameraPageNativeState extends ConsumerState<CameraPageNative>
    with SingleTickerProviderStateMixin {
  List<double> _corners = [];
  int _frameWidth = 1920;
  int _frameHeight = 1080;
  bool _hasLiveDetection = false;
  double _detectionConfidence = 0;
  bool _isCameraReady = false;
  bool _isProcessing = false;
  bool _buttonPressed = false;
  String? _error;
  bool _flashOn = false;
  final List<String> _capturedImages = [];

  // Auto-capture state
  bool _autoCaptureEnabled = true;
  List<double> _previousCorners = [];
  bool _autoCaptureTriggered = false;

  // Countdown animation for auto-capture
  late AnimationController _countdownCtrl;

  @override
  void initState() {
    super.initState();
    _countdownCtrl =
        AnimationController(vsync: this, duration: kAutoCaptureHoldDuration)
          ..addStatusListener((status) {
            if (status != AnimationStatus.completed ||
                !_autoCaptureEnabled ||
                _autoCaptureTriggered ||
                _isProcessing ||
                !_hasLiveDetection) {
              return;
            }
            _autoCaptureTriggered = true;
            unawaited(_capture(auto: true));
          });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _requestPermissionsAndStartCamera(),
    );
  }

  @override
  void dispose() {
    _countdownCtrl.dispose();
    ScannerBridge.stopCamera();
    super.dispose();
  }

  void _safePop() {
    if (mounted && context.canPop()) context.pop();
  }

  Future<void> _requestPermissionsAndStartCamera() async {
    final permissionService = ref.read(permissionServiceProvider);
    final hasCamera = await permissionService.requestCamera();
    if (!hasCamera) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text(
              'Camera permission is required to scan documents',
            ),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: () => permissionService.openSettings(),
            ),
          ),
        );
      _safePop();
      return;
    }
    if (mounted) await ScannerBridge.startCamera();
  }

  // ---------------------------------------------------------------------------
  // Corner update + auto-capture logic
  // ---------------------------------------------------------------------------

  void _onDetectionChanged(EdgeDetectionData data) {
    if (!mounted) return;

    final corners = data.corners;
    final frameWidth = data.frameWidth;
    final frameHeight = data.frameHeight;
    final cornersChanged =
        !listEquals(corners, _corners) ||
        frameWidth != _frameWidth ||
        frameHeight != _frameHeight ||
        _hasLiveDetection != data.isDetected ||
        _detectionConfidence != data.confidence;
    if (cornersChanged) {
      setState(() {
        _corners = corners;
        _frameWidth = frameWidth;
        _frameHeight = frameHeight;
        _hasLiveDetection = data.isDetected;
        _detectionConfidence = data.confidence;
      });
    }

    final hasReliableDetection =
        data.isDetected &&
        corners.length >= 8 &&
        data.confidence >= kMinimumLiveDetectionConfidence;

    if (!_autoCaptureEnabled || _isProcessing || !hasReliableDetection) {
      _resetStability();
      _previousCorners = data.isDetected ? List<double>.from(corners) : [];
      return;
    }

    if (_cornersAreStable(corners)) {
      if (!_countdownCtrl.isAnimating && _countdownCtrl.value == 0) {
        _countdownCtrl.forward(from: 0);
      }
    } else {
      _resetStability();
    }
    _previousCorners = List<double>.from(corners);
  }

  bool _cornersAreStable(List<double> corners) {
    if (_previousCorners.length != corners.length) return false;
    var totalDelta = 0.0;
    var maxDelta = 0.0;
    for (var i = 0; i < corners.length; i++) {
      final delta = (corners[i] - _previousCorners[i]).abs();
      totalDelta += delta;
      if (delta > maxDelta) maxDelta = delta;
      if (delta > kCornerStableThreshold) {
        return false;
      }
    }
    return maxDelta <= kCornerStableThreshold &&
        (totalDelta / corners.length) <= (kCornerStableThreshold * 0.55);
  }

  void _resetStability() {
    if (_countdownCtrl.value > 0) {
      _countdownCtrl.stop();
      _countdownCtrl.reset();
    }
    _autoCaptureTriggered = false;
  }

  void _onCameraReady() {
    setState(() {
      _isCameraReady = true;
      _error = null;
    });
  }

  void _onCameraError(String error) {
    setState(() {
      _error = error;
      _isCameraReady = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Capture + manual crop
  // ---------------------------------------------------------------------------

  Future<void> _capture({bool auto = false}) async {
    if (_isProcessing || !_isCameraReady) return;
    if (auto &&
        (!_hasLiveDetection ||
            _detectionConfidence < kMinimumLiveDetectionConfidence ||
            _corners.length < 8)) {
      _resetStability();
      return;
    }

    if (!auto) {
      HapticFeedback.mediumImpact();
      if (!_hasLiveDetection && mounted) {
        showSnackBar(
          context,
          'Capturing anyway. You can adjust the crop manually.',
        );
      }
    }

    setState(() => _isProcessing = true);
    _resetStability();

    try {
      // Step 1 — capture raw uncropped frame
      final rawPath = await ScannerBridge.captureRaw();
      if (!mounted) return;

      // Step 2 — get the actual EXIF-aware dimensions of the captured image
      // The raw JPEG may have EXIF rotation metadata (e.g. 90° when phone
      // is held in portrait). Flutter's Image.file auto-applies this, so
      // we need dimensions that match what the user sees.
      final dims = await ScannerBridge.getImageDimensions(rawPath);
      if (!mounted) return;

      final actualWidth = dims.width;
      final actualHeight = dims.height;

      // Step 3 — scale corners from analysis-frame coordinates to actual-image coordinates
      // Analysis frame is typically 1280×720 (rotated), actual image may be 4032×3024
      final initialCorners = _buildInitialCropCorners(
        actualWidth,
        actualHeight,
      );

      // Step 4 — open crop editor with actual image dimensions and scaled corners
      final adjustedCorners = await Navigator.of(context).push<List<double>>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ManualCropEditor(
            imagePath: rawPath,
            initialCorners: initialCorners,
            imageWidth: actualWidth,
            imageHeight: actualHeight,
          ),
        ),
      );

      if (!mounted) return;

      // User cancelled the crop editor — discard
      if (adjustedCorners == null) {
        await _deleteFileIfExists(rawPath);
        setState(() {
          _isProcessing = false;
          _autoCaptureTriggered = false;
        });
        return;
      }

      // Step 5 — apply perspective correction to the raw image using confirmed corners
      // Corners are already in actual-image coordinates, no further scaling needed
      var finalPath = await ScannerBridge.captureDocument(
        rawPath,
        adjustedCorners,
      );
      if (!mounted) return;

      final editOptions = await showModalBottomSheet<ImageEditOptions>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ImageEditSheet(
          imagePath: finalPath,
          title: 'Enhance scan',
          confirmLabel: 'Use scan',
          cancelLabel: 'Keep original',
        ),
      );
      if (!mounted) return;

      final croppedPath = finalPath;
      if (editOptions != null && !editOptions.isIdentity) {
        finalPath = await _applyEnhancementReview(finalPath, editOptions);
        if (finalPath != croppedPath) {
          await _deleteFileIfExists(croppedPath);
        }
      }

      setState(() {
        _capturedImages.add(finalPath);
        _isProcessing = false;
        _autoCaptureTriggered = false;
      });

      await _deleteFileIfExists(rawPath);

      if (auto) HapticFeedback.mediumImpact();

      if (_capturedImages.length >= AppConstants.maxPagesPerDocument) {
        await _finishScanning();
      } else {
        _showContinueScanningSnackbar();
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _autoCaptureTriggered = false;
      });
      if (mounted) {
        showSnackBar(context, 'Capture failed: ${e.toString()}', isError: true);
      }
    }
  }

  List<double> _buildInitialCropCorners(int actualWidth, int actualHeight) {
    if (_hasLiveDetection &&
        _corners.length >= 8 &&
        _frameWidth > 0 &&
        _frameHeight > 0) {
      final scaledCorners = <double>[];
      for (var i = 0; i < _corners.length; i += 2) {
        final mapped = _mapCoverPointFromAnalysisToImage(
          dx: _corners[i],
          dy: _corners[i + 1],
          analysisWidth: _frameWidth.toDouble(),
          analysisHeight: _frameHeight.toDouble(),
          imageWidth: actualWidth.toDouble(),
          imageHeight: actualHeight.toDouble(),
        );
        scaledCorners.add(mapped.dx);
        scaledCorners.add(mapped.dy);
      }
      if (_looksUsableQuad(scaledCorners, actualWidth, actualHeight)) {
        return scaledCorners;
      }
    }

    final insetX = actualWidth * 0.06;
    final insetY = actualHeight * 0.06;
    return [
      insetX,
      insetY,
      actualWidth - insetX,
      insetY,
      actualWidth - insetX,
      actualHeight - insetY,
      insetX,
      actualHeight - insetY,
    ];
  }

  bool _looksUsableQuad(List<double> corners, int width, int height) {
    if (corners.length < 8) return false;
    final xs = [corners[0], corners[2], corners[4], corners[6]];
    final ys = [corners[1], corners[3], corners[5], corners[7]];
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    return (maxX - minX) >= width * 0.2 && (maxY - minY) >= height * 0.2;
  }

  Offset _mapCoverPointFromAnalysisToImage({
    required double dx,
    required double dy,
    required double analysisWidth,
    required double analysisHeight,
    required double imageWidth,
    required double imageHeight,
  }) {
    final scale = [
      analysisWidth / imageWidth,
      analysisHeight / imageHeight,
    ].reduce((a, b) => a > b ? a : b);
    final fittedWidth = imageWidth * scale;
    final fittedHeight = imageHeight * scale;
    final offsetX = (analysisWidth - fittedWidth) / 2;
    final offsetY = (analysisHeight - fittedHeight) / 2;
    return Offset(
      ((dx - offsetX) / scale).clamp(0.0, imageWidth),
      ((dy - offsetY) / scale).clamp(0.0, imageHeight),
    );
  }

  Future<String> _applyEnhancementReview(
    String imagePath,
    ImageEditOptions options,
  ) {
    final outputPath = p.join(
      p.dirname(imagePath),
      'scan_review_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    return compute(
      applyImageEditsFromMap,
      ImageEditArgs(
        inputPath: imagePath,
        outputPath: outputPath,
        options: options,
      ).toMap(),
    );
  }

  Future<void> _deleteFileIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  void _showContinueScanningSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_capturedImages.length} page(s) captured'),
        action: SnackBarAction(label: 'Done', onPressed: _finishScanning),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _finishScanning() async {
    if (_capturedImages.isEmpty) {
      _safePop();
      return;
    }

    if (widget.existingDocId != null) {
      await _appendToExistingDocument();
      return;
    }

    final title = await _promptTitle();
    if (!mounted) return;

    final finalTitle = (title == null || title.isEmpty)
        ? 'Scan ${formatDate(DateTime.now())}'
        : title;

    try {
      final svc = ref.read(documentServiceProvider);
      final docId = await svc.createDocument(
        title: finalTitle,
        imagePaths: _capturedImages,
      );
      if (mounted) {
        HapticFeedback.lightImpact();
        context.pushReplacement(AppRoutes.folderPath(docId));
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to save document: $e', isError: true);
      }
    }
  }

  Future<void> _appendToExistingDocument() async {
    final doc = await ref
        .read(documentsDaoProvider)
        .getDocument(widget.existingDocId!);
    if (!mounted) return;
    if (doc == null) {
      showSnackBar(context, 'Document not found', isError: true);
      _safePop();
      return;
    }
    try {
      final svc = ref.read(documentServiceProvider);
      await svc.addImages(widget.existingDocId!, _capturedImages);
      final pageCount = _capturedImages.length;
      if (mounted) {
        showSnackBar(
          context,
          'Added $pageCount page${pageCount == 1 ? '' : 's'} to document',
        );
        _safePop();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to add pages: $e', isError: true);
        _safePop();
      }
    }
  }

  Future<String?> _promptTitle() async {
    List<Document> docs;
    try {
      docs = await ref
          .read(documentsDaoProvider)
          .watchAllDocuments()
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => []);
    } catch (_) {
      docs = [];
    }

    final baseTitle = 'Scan ${formatDate(DateTime.now())}';
    String title = baseTitle;
    int counter = 1;
    while (docs.any((d) => d.title == title)) {
      title = '$baseTitle ($counter)';
      counter++;
    }

    if (!mounted) return title;
    final ctrl = TextEditingController(text: title);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Name your document',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Document name',
            helperText: 'Leave empty to use default',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, title),
            child: const Text('Use Default'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result ?? title;
  }

  Widget _cameraIconButton({
    required Widget icon,
    required VoidCallback? onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.40),
        shape: BoxShape.circle,
      ),
      child: IconButton(onPressed: onPressed, icon: icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Native camera preview
          Positioned.fill(
            child: NativeCameraPreview(
              onDetectionChanged: _onDetectionChanged,
              onCameraReady: _onCameraReady,
              onError: _onCameraError,
            ),
          ),

          // Edge overlay with auto-capture countdown ring
          if (_corners.isNotEmpty)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _countdownCtrl,
                builder: (context, child) => CustomPaint(
                  painter: DocumentEdgeOverlayPainter(
                    corners: _corners,
                    frameWidth: _frameWidth,
                    frameHeight: _frameHeight,
                    strokeWidth: 2.5,
                    color: _getOverlayColor(),
                    fillColor: _getOverlayColor().withValues(alpha: 0.10),
                    captureProgress: _autoCaptureEnabled
                        ? _countdownCtrl.value
                        : 0,
                  ),
                ),
              ),
            ),

          // Document detection status chip
          if (_isCameraReady)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _isCameraReady ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _hasLiveDetection
                          ? const Color(0xFF5C4BF5).withValues(alpha: 0.88)
                          : Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      _hasLiveDetection
                          ? (_autoCaptureEnabled
                                ? 'Hold still...'
                                : 'Document detected')
                          : 'Align with a document',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Top app bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _cameraIconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _safePop,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _flashOn ? Icons.flash_on : Icons.flash_off,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              setState(() => _flashOn = !_flashOn);
                              ScannerBridge.setFlash(_flashOn);
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              _autoCaptureEnabled
                                  ? Icons.motion_photos_auto_rounded
                                  : Icons.motion_photos_off_rounded,
                              color: _autoCaptureEnabled
                                  ? const Color(0xFF7B6CF8)
                                  : Colors.white,
                            ),
                            tooltip: _autoCaptureEnabled
                                ? 'Auto-capture on'
                                : 'Auto-capture off',
                            onPressed: () {
                              setState(() {
                                _autoCaptureEnabled = !_autoCaptureEnabled;
                                _resetStability();
                              });
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.photo_library,
                              color: Colors.white,
                            ),
                            onPressed: _importFromGallery,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Error overlay
          if (_error != null)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Camera Error',
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () {
                          setState(() => _error = null);
                          ScannerBridge.startCamera();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_capturedImages.isNotEmpty)
                      SizedBox(
                        height: 60,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _capturedImages.length,
                          itemBuilder: (ctx, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(
                                  File(_capturedImages[index]),
                                  height: 44,
                                  width: 33,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [_buildCaptureButton()],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Processing overlay
          if (_isProcessing)
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF5C4BF5)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTapDown: (_) {
        if (_isProcessing) return;
        HapticFeedback.selectionClick();
        setState(() => _buttonPressed = true);
      },
      onTapUp: (_) {
        if (_isProcessing) return;
        setState(() => _buttonPressed = false);
        _capture();
      },
      onTapCancel: () {
        if (!mounted) return;
        setState(() => _buttonPressed = false);
      },
      child: AnimatedScale(
        scale: _buttonPressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            color: Colors.transparent,
          ),
          child: Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isProcessing ? Colors.grey : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getOverlayColor() {
    if (_corners.isEmpty || _corners.length < 8) {
      return Colors.white.withValues(alpha: 0.55);
    }
    if (!_hasLiveDetection) {
      return Colors.white.withValues(alpha: 0.72);
    }
    return const Color(0xFF5C4BF5);
  }

  Future<void> _importFromGallery() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 90);
    if (images.isEmpty || !mounted) return;
    final paths = images.map((x) => x.path).toList();
    setState(() => _capturedImages.addAll(paths));
    _showContinueScanningSnackbar();
  }
}
