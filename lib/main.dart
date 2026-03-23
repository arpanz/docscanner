import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:docscanner/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clean up temp directory on app start
  await _cleanupTempDirectory();

  runApp(const ProviderScope(child: DocScannerApp()));
}

Future<void> _cleanupTempDirectory() async {
  try {
    final tempDir = await getTemporaryDirectory();
    if (await tempDir.exists()) {
      await for (final entity in tempDir.list()) {
        if (entity is File) {
          await entity.delete();
        } else if (entity is Directory) {
          await entity.delete(recursive: true);
        }
      }
    }
  } catch (e) {
    // Ignore cleanup errors
    debugPrint('Cleanup error: $e');
  }
}
