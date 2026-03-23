// lib/features/camera/camera_providers.dart
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Camera controller provider
// ---------------------------------------------------------------------------
class CameraControllerNotifier
    extends AsyncNotifier<CameraController> {
  CameraController? _ctrl;

  @override
  Future<CameraController> build() async {
    ref.onDispose(() => _ctrl?.dispose());
    return _init();
  }

  Future<CameraController> _init() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception('No cameras found');
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final ctrl = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await ctrl.initialize();
    _ctrl = ctrl;
    return ctrl;
  }

  Future<void> init() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_init);
  }

  Future<void> capture() async {
    final ctrl = state.valueOrNull;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    try {
      final file = await ctrl.takePicture();
      ref.read(capturedImagesProvider.notifier).add(file.path);
    } catch (e) {
      // Silently ignore capture errors — user can retry
    }
  }

  void dispose() => _ctrl?.dispose();
}

final cameraControllerProvider =
    AsyncNotifierProvider<CameraControllerNotifier, CameraController>(
  CameraControllerNotifier.new,
);

// ---------------------------------------------------------------------------
// Captured images list provider
// ---------------------------------------------------------------------------
class CapturedImagesNotifier extends Notifier<List<String>> {
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
    NotifierProvider<CapturedImagesNotifier, List<String>>(
  CapturedImagesNotifier.new,
);
