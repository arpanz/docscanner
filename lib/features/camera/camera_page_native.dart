// lib/features/camera/camera_page_native.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../core/router.dart';
import '../../database/app_database.dart';
import '../../shared/services/document_service.dart';
import '../../shared/services/permission_service.dart';
import '../../shared/services/scanner_bridge.dart';
import 'widgets/native_camera_preview.dart';

// Reduced smoothing for more responsive overlay (was 0.22)
const double kCornerOverlaySmoothing = 0.35;

/// Native camera page for Android using CameraX + OpenCV.
///
/// Features:
/// - Live edge detection overlay
/// - Auto-capture when document is stable for [kAutoCaptureLockFrames] frames
/// - Custom capture button
/// - Flash toggle
/// - Gallery import
/// - Real-time corner tracking
/// - Manual crop editor after each capture
class CameraPageNative extends ConsumerStatefulWidget {
  const CameraPageNative({super.key, this.existingDocId});
  final int? existingDocId;

  @override
  ConsumerState<CameraPageNative> createState() => _CameraPageNativeState();
}

class _CameraPageNativeState extends ConsumerState<CameraPageNative>
    with SingleTickerProviderStateMixin {
  List<double> _corners = [];
  List<double> _displayCorners = [];
  int _frameWidth = 1920;
  int _frameHeight = 1080;
  bool _isCameraReady = false;
  bool _isProcessing = false;
  bool _buttonPressed = false;
  String? _error;
  bool _flashOn = false;
  final List<String> _capturedImages = [];

  // Auto-capture state
  bool _autoCaptureEnabled = true;
  int _stableFrameCount = 0;
  List<double> _previousCorners = [];
  bool _autoCaptureTriggered = false;

  // Countdown animation for auto-capture
  late AnimationController _countdownCtrl;

  @override
  void initState() {
    super.initState();
    _countdownCtrl = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (kAutoCaptureLockFrames * (1000 / 30)).round(), // ~30 fps
      ),
    );
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

  void _onCornerDetected(
    List<double> corners,
    int frameWidth,
    int frameHeight,
  ) {
    if (!mounted) return;

    final cornersChanged =
        !listEquals(corners, _corners) ||
        frameWidth != _frameWidth ||
        frameHeight != _frameHeight;
    if (cornersChanged) {
      setState(() {
        _corners = corners;
        _frameWidth = frameWidth;
        _frameHeight = frameHeight;
        // Blend display corners toward the new target for silky-smooth overlay
        _displayCorners = _blendCorners(_displayCorners, corners);
      });
    }

    if (!_autoCaptureEnabled || _isProcessing || corners.length < 8) {
      _resetStability();
      return;
    }

    if (_cornersAreStable(corners)) {
      _stableFrameCount++;
      if (_stableFrameCount == 1) {
        _countdownCtrl.forward(from: 0);
      }
      if (_stableFrameCount >= kAutoCaptureLockFrames &&
          !_autoCaptureTriggered) {
        _autoCaptureTriggered = true;
        _capture(auto: true);
      }
    } else {
      _resetStability();
      _previousCorners = List.from(corners);
    }
  }

  bool _cornersAreStable(List<double> corners) {
    if (_previousCorners.length != corners.length) return false;
    for (var i = 0; i < corners.length; i++) {
      if ((corners[i] - _previousCorners[i]).abs() > kCornerStableThreshold) {
        return false;
      }
    }
    return true;
  }

  /// Lerp display corners toward target for silky-smooth overlay animation.
  List<double> _blendCorners(List<double> current, List<double> target) {
    if (current.length != target.length || current.length < 8) {
      return List<double>.from(target);
    }
    return List<double>.generate(target.length, (i) {
      return current[i] +
          ((target[i] - current[i]) * kCornerOverlaySmoothing);
    });
  }

  void _resetStability() {
    if (_stableFrameCount > 0) {
      _countdownCtrl.stop();
      _countdownCtrl.reset();
    }
    _stableFrameCount = 0;
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
    if (_corners.length < 8) {
      if (!auto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No document detected. Try adjusting the angle.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);
    _resetStability();

    try {
      if (!auto) HapticFeedback.mediumImpact();

      // Capture the page from native using the latest detected corners.
      final capturedPath = await ScannerBridge.captureDocument(
        List<double>.from(_corners),
      );
      if (!mounted) return;

      final capturedSize = await _getImageSize(capturedPath);
      if (!mounted) return;

      final initialCorners = _fullImageCorners(capturedSize);

      // Open the crop editor so the user can refine the captured page.
      final adjustedCorners = await Navigator.of(context).push<List<double>>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ManualCropEditor(
            imagePath: capturedPath,
            initialCorners: initialCorners,
            imageWidth: capturedSize.width.round(),
            imageHeight: capturedSize.height.round(),
          ),
        ),
      );

      if (!mounted) return;

      // If the user cancelled the crop editor, discard this capture.
      if (adjustedCorners == null) {
        await _deleteFileIfExists(capturedPath);
        setState(() {
          _isProcessing = false;
          _autoCaptureTriggered = false;
        });
        return;
      }

      // If corners were adjusted, re-run perspective correction with new corners
      final cornersUnchanged = listEquals(adjustedCorners, _corners);
      final finalPath = cornersUnchanged
          ? capturedPath
          : await ScannerBridge.captureDocument(adjustedCorners);

      setState(() {
        _capturedImages.add(finalPath);
        _isProcessing = false;
        _autoCaptureTriggered = false;
      });

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

  Future<Size> _getImageSize(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Failed to decode captured image');
    }
    return Size(decoded.width.toDouble(), decoded.height.toDouble());
  }

  List<double> _fullImageCorners(Size size) {
    return <double>[
      0.0,
      0.0,
      size.width,
      0.0,
      size.width,
      size.height,
      0.0,
      size.height,
    ];
  }

  Future<void> _deleteFileIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
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
              onCornerDetected: _onCornerDetected,
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
                    corners: _displayCorners,
                    frameWidth: _frameWidth,
                    frameHeight: _frameHeight,
                    strokeWidth: 2.5,
                    color: _getOverlayColor(),
                    fillColor: _getOverlayColor().withValues(alpha: 0.10),
                    stableFrameCount: _autoCaptureEnabled
                        ? _stableFrameCount
                        : 0,
                    autoCaptureTotalFrames: kAutoCaptureLockFrames,
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
                      color: _corners.length >= 8
                          ? const Color(0xFF5C4BF5).withValues(alpha: 0.88)
                          : Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      _corners.length >= 8
                          ? (_autoCaptureEnabled
                                ? 'Hold still…'
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
                          // Flash toggle
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
                          // Auto-capture toggle
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
                          // Gallery import
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
                    // Thumbnail strip
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
                    // Capture button
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
