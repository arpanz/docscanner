// lib/features/camera/camera_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Captured images list provider
// ---------------------------------------------------------------------------
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
      CapturedImagesNotifier.new,
    );

// Error provider for capture failures
final captureErrorProvider = StateProvider.autoDispose<String?>((ref) => null);
