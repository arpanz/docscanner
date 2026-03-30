// lib/features/camera/widgets/native_camera_preview.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/scanner_bridge.dart';

/// Native Android camera preview using PlatformView.
/// 
/// This widget displays the native CameraX preview surface
/// and streams edge detection results to Flutter for overlay drawing.
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
        widget.onCornerDetected(data.corners, data.frameWidth, data.frameHeight);
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
    // On iOS or web, show a placeholder
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt, size: 64, color: Colors.white54),
              const SizedBox(height: 16),
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

    // On Android, use PlatformView for native camera preview
    return AndroidView(
      viewType: 'com.example.docscanner/camera_preview',
      onPlatformViewCreated: (id) {
        widget.onCameraReady?.call();
      },
    );
  }
}

/// Document edge overlay painter.
/// 
/// Draws a quadrilateral overlay on top of the camera preview
/// to show the detected document boundaries.
class DocumentEdgeOverlayPainter extends CustomPainter {
  DocumentEdgeOverlayPainter({
    required this.corners,
    required this.frameWidth,
    required this.frameHeight,
    this.strokeWidth = 3.0,
    this.color = const Color(0xFF00FF00),
    this.fillColor = const Color(0x4000FF00),
  });

  final List<double> corners;
  final int frameWidth;
  final int frameHeight;
  final double strokeWidth;
  final Color color;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 8 || frameWidth == 0 || frameHeight == 0) return;

    // Convert corners to Offset list with proper scaling
    final points = <Offset>[];
    for (var i = 0; i < corners.length; i += 2) {
      // Scale corners from image coordinates to screen coordinates
      final x = (corners[i] / frameWidth) * size.width;
      final y = (corners[i + 1] / frameHeight) * size.height;
      points.add(Offset(x, y));
    }

    if (points.length < 4) return;

    // Create path for the quadrilateral
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    path.lineTo(points[1].dx, points[1].dy);
    path.lineTo(points[2].dx, points[2].dy);
    path.lineTo(points[3].dx, points[3].dy);
    path.close();

    // Draw fill
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Draw stroke
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    // Draw corner handles
    final handlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final point in points) {
      canvas.drawCircle(point, 8.0, handlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant DocumentEdgeOverlayPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.frameWidth != frameWidth ||
        oldDelegate.frameHeight != frameHeight;
  }
}
