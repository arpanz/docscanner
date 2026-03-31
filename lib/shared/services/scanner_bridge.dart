// lib/shared/services/scanner_bridge.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// Native scanner bridge for Android.
///
/// Provides access to CameraX + OpenCV powered document scanning.
/// Falls back to no-op on iOS (use flutter_doc_scanner for iOS).
class ScannerBridge {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.example.docscanner/scanner',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.example.docscanner/edges',
  );

  /// Stream of detected document corners from OpenCV.
  /// Returns [EdgeDetectionData] with corners and frame dimensions.
  static Stream<EdgeDetectionData> get edgeStream =>
      _eventChannel.receiveBroadcastStream().map((event) {
        final data = Map<String, dynamic>.from(event);
        final corners = List<double>.from(data['corners'] ?? []);
        final frameWidth = (data['frameWidth'] ?? 0).toInt();
        final frameHeight = (data['frameHeight'] ?? 0).toInt();
        return EdgeDetectionData(corners, frameWidth, frameHeight);
      });

  /// Start the native camera preview with edge detection.
  static Future<void> startCamera() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('ScannerBridge is only available on Android');
    }
    await _methodChannel.invokeMethod('startCamera');
  }

  /// Stop the camera preview.
  static Future<void> stopCamera() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('ScannerBridge is only available on Android');
    }
    await _methodChannel.invokeMethod('stopCamera');
  }

  /// Set flash torch on or off.
  static Future<void> setFlash(bool enabled) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('ScannerBridge is only available on Android');
    }
    await _methodChannel.invokeMethod('setFlash', {'enabled': enabled});
  }

  /// Capture a raw (uncropped) high-resolution frame.
  ///
  /// Use this to get the full image for [ManualCropEditor] before applying
  /// perspective correction. Follow up with [captureDocument] after the user
  /// confirms the adjusted corners.
  static Future<String> captureRaw() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('ScannerBridge is only available on Android');
    }
    final result = await _methodChannel.invokeMethod<String>('captureRaw');
    return result ?? '';
  }

  /// Capture a document with perspective correction applied.
  ///
  /// [corners] The 4 corner points of the document to extract (in analysis
  /// frame coordinates). Corners are automatically scaled to the capture
  /// resolution on the native side.
  /// Returns the file path of the perspective-corrected image.
  static Future<String> captureDocument(List<double> corners) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('ScannerBridge is only available on Android');
    }
    final result = await _methodChannel.invokeMethod<String>(
      'captureDocument',
      {'corners': corners},
    );
    return result ?? '';
  }

  /// Crop an existing image using the provided quadrilateral corners.
  ///
  /// [corners] The 4 corner points of the document to extract.
  /// Returns the path to the cropped image.
  static Future<String> cropImage(String path, List<double> corners) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('ScannerBridge is only available on Android');
    }
    final result = await _methodChannel.invokeMethod<String>('cropImage', {
      'path': path,
      'corners': corners,
    });
    return (result == null || result.isEmpty) ? path : result;
  }

  /// Apply an enhancement filter to an image.
  ///
  /// [path] Path to the input image.
  /// [mode] One of: 'photo', 'magic_color', 'grayscale', 'black_white', 'whiteboard'.
  /// Returns the path to the enhanced image.
  static Future<String> enhanceImage(String path, String mode) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('ScannerBridge is only available on Android');
    }
    final result = await _methodChannel.invokeMethod<String>('enhanceImage', {
      'path': path,
      'mode': mode,
    });
    return (result == null || result.isEmpty) ? path : result;
  }

  /// Build a PDF from a list of image paths.
  ///
  /// [images] List of image file paths.
  /// [title] Document title for the PDF filename.
  /// Returns the path to the generated PDF.
  static Future<String> buildPdf(List<String> images, String title) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('ScannerBridge is only available on Android');
    }
    final result = await _methodChannel.invokeMethod<String>('buildPdf', {
      'images': images,
      'title': title,
    });
    return result ?? '';
  }

  /// Extract text from an image using ML Kit OCR.
  ///
  /// [path] Path to the image file.
  /// Returns the extracted text.
  static Future<String> extractText(String path) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('ScannerBridge is only available on Android');
    }
    final result = await _methodChannel.invokeMethod<String>('extractText', {
      'path': path,
    });
    return result ?? '';
  }
}

/// Enhancement modes available for document processing.
enum EnhancementMode { photo, magicColor, grayscale, blackWhite, whiteboard }

extension EnhancementModeExtension on EnhancementMode {
  String get nativeName {
    switch (this) {
      case EnhancementMode.photo:
        return 'photo';
      case EnhancementMode.magicColor:
        return 'magic_color';
      case EnhancementMode.grayscale:
        return 'grayscale';
      case EnhancementMode.blackWhite:
        return 'black_white';
      case EnhancementMode.whiteboard:
        return 'whiteboard';
    }
  }
}

/// Data class holding edge detection results from native side.
class EdgeDetectionData {
  final List<double> corners;
  final int frameWidth;
  final int frameHeight;

  EdgeDetectionData(this.corners, this.frameWidth, this.frameHeight);
}
