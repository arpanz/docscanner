// lib/core/constants.dart

class AppConstants {
  AppConstants._();

  static const String appName = 'DocScanner';
  static const String dbName = 'docscanner.db';

  // Supported export formats
  static const List<String> exportFormats = ['PDF', 'JPEG', 'PNG'];

  // Default image quality for compression (0–100)
  static const int defaultJpegQuality = 88;

  // Max pages per document
  static const int maxPagesPerDocument = 50;

  // Thumbnail dimensions
  static const double thumbWidth = 120.0;
  static const double thumbHeight = 160.0;

  // Doc card dimensions
  static const double cardAspectRatio = 0.75; // portrait A4-ish

  // Animation durations
  static const Duration fastAnim = Duration(milliseconds: 200);
  static const Duration normalAnim = Duration(milliseconds: 300);
}
