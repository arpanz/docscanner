// lib/shared/utils/image_utils.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Rotate an image file 90° clockwise or counter-clockwise and overwrite it.
Future<bool> rotateImageFile(String imagePath, {bool clockwise = true}) async {
  try {
    return await compute(_rotateImage, _RotateArgs(
      inputPath: imagePath,
      clockwise: clockwise,
    ));
  } catch (e) {
    debugPrint('Rotate failed: $e');
    return false;
  }
}

class _RotateArgs {
  const _RotateArgs({required this.inputPath, required this.clockwise});
  final String inputPath;
  final bool clockwise;
}

bool _rotateImage(_RotateArgs args) {
  final file = File(args.inputPath);
  if (!file.existsSync()) return false;

  final bytes = file.readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return false;

  final rotated = args.clockwise
      ? img.copyRotate(decoded, angle: 90)
      : img.copyRotate(decoded, angle: -90);

  final ext = p.extension(args.inputPath).toLowerCase();
  List<int> encoded;
  if (ext == '.png') {
    encoded = img.encodePng(rotated);
  } else {
    encoded = img.encodeJpg(rotated, quality: 88);
  }

  file.writeAsBytesSync(encoded);
  return true;
}

/// Compute folder size by iterating all files.
Future<int> computeFolderSize(String folderPath) async {
  try {
    final folder = Directory(folderPath);
    if (!await folder.exists()) return 0;
    int total = 0;
    await for (final entity in folder.list()) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  } catch (_) {
    return 0;
  }
}

/// Sanitize a filename by removing special characters.
String sanitizeFileName(String name) =>
    name.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_');
