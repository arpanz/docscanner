import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:docscanner/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20; // 200 MB
  PaintingBinding.instance.imageCache.maximumSize = 200;

  // Only clean up scan_append_* temp files — NOT the whole temp dir.
  // Wiping everything would delete the pdf_thumbnails cache and any
  // in-progress append PNGs from a previous session.
  await _cleanupScanAppendTempFiles();

  runApp(const ProviderScope(child: DocScannerApp()));
}

Future<void> _cleanupScanAppendTempFiles() async {
  try {
    final tempDir = await getTemporaryDirectory();
    if (!await tempDir.exists()) return;
    await for (final entity in tempDir.list()) {
      if (entity is File &&
          p.basename(entity.path).startsWith('scan_append_')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  } catch (e) {
    debugPrint('Cleanup error: $e');
  }
}
