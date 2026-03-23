// lib/features/camera/camera_page.dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../shared/services/document_service.dart';
import '../../shared/widgets/app_loading.dart';
import 'camera_providers.dart';
import 'widgets/capture_button.dart';
import 'widgets/flash_toggle.dart';
import 'widgets/thumbnail_strip.dart';
import 'widgets/crop_enhance_sheet.dart';

class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key, this.existingDocId});
  final int? existingDocId;

  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends ConsumerState<CameraPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cameraControllerProvider.notifier).init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final notifier = ref.read(cameraControllerProvider.notifier);
    if (state == AppLifecycleState.inactive) {
      notifier.dispose();
    } else if (state == AppLifecycleState.resumed) {
      notifier.init();
    }
  }

  Future<void> _onCapture() async {
    await ref.read(cameraControllerProvider.notifier).capture();
  }

  Future<void> _onDone() async {
    final captured = ref.read(capturedImagesProvider);
    if (captured.isEmpty) {
      context.pop();
      return;
    }

    final title = await _promptTitle();
    if (title == null) return;

    final svc = ref.read(documentServiceProvider);
    try {
      if (widget.existingDocId != null) {
        await svc.appendPages(widget.existingDocId!, captured);
        if (mounted) context.pop();
      } else {
        final docId = await svc.createDocument(
          title: title,
          imagePaths: captured,
        );
        if (mounted) context.go('/viewer/$docId');
      }
    } catch (e) {
      if (mounted) showSnackBar(context, 'Error saving: $e', isError: true);
    }
  }

  Future<String?> _promptTitle() async {
    final ctrl = TextEditingController(
      text: 'Document ${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}',
    );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name your document'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Document name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrlAsync = ref.watch(cameraControllerProvider);
    final captured = ref.watch(capturedImagesProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: ctrlAsync.when(
        loading: () => const AppLoading(message: 'Starting camera…'),
        error: (e, _) => Center(
          child: Text('Camera error: $e',
              style: const TextStyle(color: Colors.white)),
        ),
        data: (controller) => Stack(
          fit: StackFit.expand,
          children: [
            // Preview
            CameraPreview(controller),

            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                      FlashToggle(controller: controller),
                      TextButton(
                        onPressed: captured.isNotEmpty ? _onDone : null,
                        child: Text(
                          'Done (${captured.length})',
                          style: TextStyle(
                            color: captured.isNotEmpty
                                ? Colors.white
                                : Colors.white38,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ThumbnailStrip(
                      imagePaths: captured,
                      onTap: (idx) async {
                        final updated = await showModalBottomSheet<String>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => CropEnhanceSheet(
                            imagePath: captured[idx],
                          ),
                        );
                        if (updated != null) {
                          ref
                              .read(capturedImagesProvider.notifier)
                              .replace(idx, updated);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    CaptureButton(onCapture: _onCapture),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
