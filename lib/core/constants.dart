// lib/core/constants.dart

class AppConstants {
  AppConstants._();

  static const String appName = 'DocScanner';
  static const String dbName = 'docscanner.db';

  // Default image quality for compression (0–100)
  static const int defaultJpegQuality = 88;

  // Thumbnail dimensions
  static const double thumbWidth = 120.0;
  static const double thumbHeight = 160.0;

  // Animation durations
  static const Duration fastAnim = Duration(milliseconds: 200);
  static const Duration normalAnim = Duration(milliseconds: 300);
}
