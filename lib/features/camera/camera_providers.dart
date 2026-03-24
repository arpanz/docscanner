// lib/features/camera/camera_providers.dart
// This file is intentionally minimal.
// The captured-images flow is handled directly inside CameraPage
// via flutter_doc_scanner's getScannedDocumentAsPdf.
// These providers are kept as stubs in case a custom capture UI is
// added later, but they are not used by the current scan flow.
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CapturedImagesNotifier extends AutoDisposeNotifier<List<String>> {
  @override
  List<String> build() => [];

  void add(String path) => state = [...state, path];
  void replace(int index, String path) {
    final updated = [...state];
    updated[index] = path;
    state = updated;
  }
  void remove(int index) {
    final updated = [...state];
    updated.removeAt(index);
    state = updated;
  }
  void clear() => state = [];
}

final capturedImagesProvider =
    NotifierProvider.autoDispose<CapturedImagesNotifier, List<String>>(
        CapturedImagesNotifier.new);
