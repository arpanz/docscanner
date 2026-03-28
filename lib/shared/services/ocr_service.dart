import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  Future<String> extractTextFromPaths(List<String> imagePaths) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final buffer = StringBuffer();

    try {
      for (final path in imagePaths) {
        final file = File(path);
        if (!await file.exists()) continue;
        final result = await recognizer.processImage(InputImage.fromFilePath(path));
        final text = result.text.trim();
        if (text.isEmpty) continue;
        if (buffer.isNotEmpty) {
          buffer.writeln();
          buffer.writeln('---');
          buffer.writeln();
        }
        buffer.writeln(text);
      }
    } finally {
      await recognizer.close();
    }

    return buffer.toString().trim();
  }
}

final ocrServiceProvider = Provider<OcrService>((ref) => OcrService());
