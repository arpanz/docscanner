// lib/features/camera/camera_page_native.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../core/router.dart';
import '../../database/app_database.dart';
import '../../shared/services/document_service.dart';
import '../../shared/services/permission_service.dart';
import '../../shared/services/scanner_bridge.dart';
import 'widgets/native_camera_preview.dart';

/// Native camera page for Android using CameraX + OpenCV.
///
/// Features:
/// - Live edge detection overlay
/// - Custom capture button
/// - Flash toggle
/// - Gallery import
/// - Real-time corner tracking
class CameraPageNative extends ConsumerStatefulWidget {
  const CameraPageNative({super.key, this.existingDocId});
  final int? existingDocId;

  @override
  ConsumerState<CameraPageNative> createState() => _CameraPageNativeState();
}

class _CameraPageNativeState extends ConsumerState<CameraPageNative> {
  List<double> _corners = [];
  int _frameWidth = 1920;
  int _frameHeight = 1080;
  bool _isCameraReady = false;
  bool _isProcessing = false;
  bool _buttonPressed = false;
  String? _error;
  bool _flashOn = false;
  final List<String> _capturedImages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _requestPermissionsAndStartCamera(),
    );
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

    if (mounted) {
      await ScannerBridge.startCamera();
    }
  }

  @override
  void dispose() {
    ScannerBridge.stopCamera();
    super.dispose();
  }

  void _onCornerDetected(
    List<double> corners,
    int frameWidth,
    int frameHeight,
  ) {
    setState(() {
      _corners = corners;
      _frameWidth = frameWidth;
      _frameHeight = frameHeight;
    });
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

  Future<void> _capture() async {
    if (_isProcessing || !_isCameraReady) return;
    if (_corners.length < 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No document detected. Try adjusting the angle.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      HapticFeedback.mediumImpact();

      // Capture with perspective correction
      final imagePath = await ScannerBridge.captureDocument(_corners);

      if (!mounted) return;

      setState(() {
        _capturedImages.add(imagePath);
        _isProcessing = false;
      });

      // If we have enough pages or user wants to finish
      if (_capturedImages.length >= AppConstants.maxPagesPerDocument) {
        await _finishScanning();
      } else {
        // Show continue scanning snackbar
        _showContinueScanningSnackbar();
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
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

    // Prompt for title
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
        title: Text('Name your document', style: const TextStyle(fontWeight: FontWeight.w800)),
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

          // Edge overlay
          if (_corners.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: DocumentEdgeOverlayPainter(
                  corners: _corners,
                  frameWidth: _frameWidth,
                  frameHeight: _frameHeight,
                  strokeWidth: 2.5,
                  color: _getOverlayColor(),
                  fillColor: _getOverlayColor().withValues(alpha: 0.10),
                ),
              ),
            ),

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
                          ? 'Document detected'
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
                              setState(() {
                                _flashOn = !_flashOn;
                              });
                              ScannerBridge.setFlash(_flashOn);
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
                          setState(() {
                            _error = null;
                          });
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
      return Colors.white.withValues(alpha: 0.55); // soft white = searching
    }
    return const Color(0xFF5C4BF5); // brand indigo = locked on
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
