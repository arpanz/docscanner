// lib/features/camera/widgets/native_camera_preview.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/scanner_bridge.dart';

/// Number of consecutive stable frames required to trigger auto-capture.
/// Increased from 30 to 45 for more reliable auto-capture.
const int kAutoCaptureLockFrames = 45;

/// Pixel distance threshold within which corner points are considered "stable".
/// Increased from 10.0 to 12.0 for better tolerance of minor detection jitter.
const double kCornerStableThreshold = 12.0;

/// Native Android camera preview using PlatformView.
///
/// Streams edge detection results to Flutter and tracks corner stability
/// to support auto-capture.
class NativeCameraPreview extends ConsumerStatefulWidget {
  const NativeCameraPreview({
    super.key,
    required this.onCornerDetected,
    this.onCameraReady,
    this.onError,
  });

  final Function(List<double>, int, int) onCornerDetected;
  final VoidCallback? onCameraReady;
  final Function(String)? onError;

  @override
  ConsumerState<NativeCameraPreview> createState() =>
      _NativeCameraPreviewState();
}

class _NativeCameraPreviewState extends ConsumerState<NativeCameraPreview> {
  StreamSubscription? _edgeSubscription;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _setupEdgeStream();
  }

  void _setupEdgeStream() {
    if (_isListening) return;
    _isListening = true;

    _edgeSubscription = ScannerBridge.edgeStream.listen(
      (data) {
        widget.onCornerDetected(
          data.corners,
          data.frameWidth,
          data.frameHeight,
        );
      },
      onError: (error) {
        final platformError = error as PlatformException;
        final message = platformError.message ?? 'Unknown error';
        widget.onError?.call(message);
      },
      onDone: () {
        _isListening = false;
      },
    );
  }

  @override
  void dispose() {
    _edgeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt, size: 64, color: Colors.white54),
              SizedBox(height: 16),
              Text(
                'Native camera preview\n(Android only)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }

    return AndroidView(
      viewType: 'com.example.docscanner/camera_preview',
      onPlatformViewCreated: (id) {
        widget.onCameraReady?.call();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// DocumentEdgeOverlayPainter — now supports auto-capture countdown ring
// ---------------------------------------------------------------------------

/// Draws a quadrilateral overlay and optionally an auto-capture countdown ring.
///
/// [stableFrameCount] / [autoCaptureTotalFrames] drive the arc progress.
class DocumentEdgeOverlayPainter extends CustomPainter {
  DocumentEdgeOverlayPainter({
    required this.corners,
    required this.frameWidth,
    required this.frameHeight,
    this.strokeWidth = 3.0,
    this.color = const Color(0xFF5C4BF5),
    this.fillColor = const Color(0x205C4BF5),
    this.stableFrameCount = 0,
    this.autoCaptureTotalFrames = kAutoCaptureLockFrames,
  });

  final List<double> corners;
  final int frameWidth;
  final int frameHeight;
  final double strokeWidth;
  final Color color;
  final Color fillColor;
  final int stableFrameCount;
  final int autoCaptureTotalFrames;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 8 || frameWidth == 0 || frameHeight == 0) return;

    // Scale corners from image coords → screen coords
    final points = <Offset>[];
    for (var i = 0; i < corners.length; i += 2) {
      final x = (corners[i] / frameWidth) * size.width;
      final y = (corners[i + 1] / frameHeight) * size.height;
      points.add(Offset(x, y));
    }
    if (points.length < 4) return;

    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Corner circles
    final handleFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final handleRing = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final point in points) {
      canvas.drawCircle(point, 9.0, handleFill);
      canvas.drawCircle(point, 9.0, handleRing);
    }

    // Auto-capture countdown ring (drawn at centroid)
    if (stableFrameCount > 0 && autoCaptureTotalFrames > 0) {
      final progress = stableFrameCount / autoCaptureTotalFrames;
      final cx = points.map((p) => p.dx).reduce((a, b) => a + b) / 4;
      final cy = points.map((p) => p.dy).reduce((a, b) => a + b) / 4;

      // Background ring
      canvas.drawCircle(
        Offset(cx, cy),
        28,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );

      // Progress arc
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: 28);
      canvas.drawArc(
        rect,
        -3.14159 / 2, // start at top
        2 * 3.14159 * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DocumentEdgeOverlayPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.frameWidth != frameWidth ||
        oldDelegate.frameHeight != frameHeight ||
        oldDelegate.stableFrameCount != stableFrameCount;
  }
}

// ---------------------------------------------------------------------------
// ManualCropEditor — full-screen draggable 4-corner crop editor
// ---------------------------------------------------------------------------

/// Full-screen overlay that lets the user drag the 4 corner handles
/// of the detected document boundary before confirming the crop.
///
/// Returns the adjusted [List<double>] corners (8 values: x0,y0 … x3,y3)
/// in *image* coordinates, or null if cancelled.
class ManualCropEditor extends StatefulWidget {
  const ManualCropEditor({
    super.key,
    required this.imagePath,
    required this.initialCorners,
    required this.imageWidth,
    required this.imageHeight,
  });

  /// Path to the captured (pre-crop) image to display as background.
  final String imagePath;

  /// Initial corner positions in *image* pixel coordinates (8 values).
  final List<double> initialCorners;

  final int imageWidth;
  final int imageHeight;

  @override
  State<ManualCropEditor> createState() => _ManualCropEditorState();
}

class _ManualCropEditorState extends State<ManualCropEditor>
    with SingleTickerProviderStateMixin {
  /// Corners in *image* pixel coordinates.
  late List<double> _corners;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Index of the corner currently being dragged (-1 = none).
  int _draggingIndex = -1;

  // Render box of the image as displayed on screen.
  final GlobalKey _imageKey = GlobalKey();
  Size _displaySize = Size.zero;
  Offset _displayOffset = Offset.zero;
  
  // Track if display geometry has been initialized
  bool _displayGeometryReady = false;

  @override
  void initState() {
    super.initState();
    _corners = List<double>.from(widget.initialCorners);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.85,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    
    // Schedule display geometry initialization after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDisplayGeometry());
  }
  
  void _initDisplayGeometry() {
    if (!mounted) return;
    _updateDisplayGeometry();
    setState(() => _displayGeometryReady = true);
  }

  /// Calculate the rendered image size when using BoxFit.contain
  Size _calculateContainSize(
    double imageWidth,
    double imageHeight,
    double maxWidth,
    double maxHeight,
  ) {
    final imageAspect = imageWidth / imageHeight;
    final containerAspect = maxWidth / maxHeight;
    
    if (imageAspect > containerAspect) {
      // Image is wider than container - fit to width
      final width = maxWidth;
      final height = width / imageAspect;
      return Size(width, height);
    } else {
      // Image is taller than container - fit to height
      final height = maxHeight;
      final width = height * imageAspect;
      return Size(width, height);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  /// Convert image coords → screen coords within the display box.
  Offset _toScreen(double ix, double iy) {
    if (!_displayGeometryReady || widget.imageWidth == 0 || widget.imageHeight == 0) {
      return Offset.zero;
    }
    final sx =
        (ix / widget.imageWidth) * _displaySize.width + _displayOffset.dx;
    final sy =
        (iy / widget.imageHeight) * _displaySize.height + _displayOffset.dy;
    return Offset(sx, sy);
  }

  /// Convert screen coords → image coords.
  Offset _toImage(Offset screen) {
    if (!_displayGeometryReady || _displaySize == Size.zero) {
      return Offset.zero;
    }
    final ix =
        ((screen.dx - _displayOffset.dx) / _displaySize.width) *
        widget.imageWidth;
    final iy =
        ((screen.dy - _displayOffset.dy) / _displaySize.height) *
        widget.imageHeight;
    return Offset(
      ix.clamp(0.0, widget.imageWidth.toDouble()),
      iy.clamp(0.0, widget.imageHeight.toDouble()),
    );
  }

  void _updateDisplayGeometry() {
    final box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _displaySize = box.size;
    _displayOffset = box.localToGlobal(Offset.zero);
  }

  /// Find the corner index closest to [screenPos] within [hitRadius].
  int _findClosestCorner(Offset screenPos, {double hitRadius = 36.0}) {
    var best = -1;
    var bestDist = hitRadius;
    for (var i = 0; i < 4; i++) {
      final sx = _corners[i * 2];
      final sy = _corners[i * 2 + 1];
      final screenCorner = _toScreen(sx, sy);
      final d = (screenCorner - screenPos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  void _onPanStart(DragStartDetails details) {
    // Always update display geometry on pan start to ensure accuracy
    _updateDisplayGeometry();
    if (!_displayGeometryReady) {
      _displayGeometryReady = true;
    }
    final idx = _findClosestCorner(details.globalPosition);
    if (idx != -1) {
      setState(() => _draggingIndex = idx);
      HapticFeedback.selectionClick();
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_draggingIndex == -1) return;
    final imgPos = _toImage(details.globalPosition);
    setState(() {
      _corners[_draggingIndex * 2] = imgPos.dx;
      _corners[_draggingIndex * 2 + 1] = imgPos.dy;
    });
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() => _draggingIndex = -1);
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        title: const Text(
          'Adjust crop',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_corners),
            child: const Text(
              'Confirm',
              style: TextStyle(
                color: Color(0xFF7B6CF8),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Image background - centered with contain fit
          Center(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                // Calculate the actual rendered image size
                final imageSize = _calculateContainSize(
                  widget.imageWidth.toDouble(),
                  widget.imageHeight.toDouble(),
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                
                // Update display geometry on layout
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_displayGeometryReady) {
                    setState(() {
                      _displaySize = imageSize;
                      // For centered image, offset is the centering margin
                      _displayOffset = Offset(
                        (constraints.maxWidth - imageSize.width) / 2,
                        (constraints.maxHeight - imageSize.height) / 2,
                      );
                      _displayGeometryReady = true;
                    });
                  }
                });
                
                return Image.file(
                  key: _imageKey,
                  File(widget.imagePath),
                  fit: BoxFit.contain,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                );
              },
            ),
          ),

          // Quad + handles overlay - full screen but gestures work through
          Positioned.fill(
            child: CustomPaint(
              painter: _ManualCropPainter(
                corners: _corners,
                imageWidth: widget.imageWidth,
                imageHeight: widget.imageHeight,
                displaySize: _displaySize,
                displayOffset: _displayOffset,
                activeIndex: _draggingIndex,
                color: const Color(0xFF5C4BF5),
                pulseScale: _draggingIndex == -1 ? _pulseAnim.value : 1.0,
              ),
            ),
          ),

          // Invisible gesture detector over the entire area for dragging
          Positioned.fill(
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_outlined, color: Colors.white54, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Drag the corner handles to adjust the crop',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualCropPainter extends CustomPainter {
  _ManualCropPainter({
    required this.corners,
    required this.imageWidth,
    required this.imageHeight,
    required this.displaySize,
    required this.displayOffset,
    required this.activeIndex,
    required this.color,
    required this.pulseScale,
  });

  final List<double> corners;
  final int imageWidth;
  final int imageHeight;
  final Size displaySize;
  final Offset displayOffset;
  final int activeIndex;
  final Color color;
  final double pulseScale;

  Offset _toScreen(double ix, double iy, Size canvasSize) {
    // Use the displaySize/displayOffset passed from the widget state
    // These are the actual rendered image dimensions
    if (imageWidth == 0 || imageHeight == 0 || displaySize == Size.zero) {
      return Offset.zero;
    }
    // Scale from image coordinates to display coordinates
    final sx = (ix / imageWidth) * displaySize.width;
    final sy = (iy / imageHeight) * displaySize.height;
    // Add offset to position within the canvas
    return Offset(sx + displayOffset.dx, sy + displayOffset.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 8 || displaySize == Size.zero) return;

    final points = <Offset>[];
    for (var i = 0; i < 4; i++) {
      points.add(_toScreen(corners[i * 2], corners[i * 2 + 1], size));
    }

    // Dim area outside crop
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final cropPath = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();
    final outerPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(fullRect),
      cropPath,
    );
    canvas.drawPath(
      outerPath,
      Paint()..color = Colors.black.withValues(alpha: 0.52),
    );

    // Crop outline
    canvas.drawPath(
      cropPath,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Rule-of-thirds grid inside crop
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    // We draw a simple 3x3 grid by interpolating the quad
    for (var t = 1; t <= 2; t++) {
      final f = t / 3.0;
      // top-edge lerp → bottom-edge lerp
      final top = Offset.lerp(points[0], points[1], f)!;
      final bottom = Offset.lerp(points[3], points[2], f)!;
      canvas.drawLine(top, bottom, gridPaint);
      // left-edge lerp → right-edge lerp
      final left = Offset.lerp(points[0], points[3], f)!;
      final right = Offset.lerp(points[1], points[2], f)!;
      canvas.drawLine(left, right, gridPaint);
    }

    // Corner handles
    for (var i = 0; i < 4; i++) {
      final p = points[i];
      final isActive = i == activeIndex;
      final radius = isActive ? 14.0 : 11.0 * pulseScale;

      canvas.drawCircle(
        p,
        radius,
        Paint()
          ..color = isActive ? color : Colors.white.withValues(alpha: 0.92)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        p,
        radius,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );

      // L-shaped corner brackets
      const bracketLen = 18.0;
      final bPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final nextIdx = (i + 1) % 4;
      final prevIdx = (i + 3) % 4;
      final toNext = (points[nextIdx] - p);
      final toPrev = (points[prevIdx] - p);
      final toNextNorm = toNext / toNext.distance;
      final toPrevNorm = toPrev / toPrev.distance;
      canvas.drawLine(p, p + toNextNorm * bracketLen, bPaint);
      canvas.drawLine(p, p + toPrevNorm * bracketLen, bPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ManualCropPainter old) {
    return old.corners != corners ||
        old.activeIndex != activeIndex ||
        old.pulseScale != pulseScale ||
        old.displaySize != displaySize ||
        old.displayOffset != displayOffset;
  }
}
