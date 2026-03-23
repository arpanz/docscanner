// lib/features/camera/camera_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../shared/services/document_service.dart';
import 'camera_providers.dart';
import 'widgets/thumbnail_strip.dart';
import 'widgets/crop_enhance_sheet.dart';

class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key, this.existingDocId});
  final int? existingDocId;

  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends ConsumerState<CameraPage> {
  static const _brand = Color(0xFF5C4BF5);
  static const _brandLight = Color(0xFF9B59F5);

  Future<void> _onCapture() async {
    try {
      final dynamic result = await FlutterDocScanner()
          .getScannedDocumentAsImages();
      if (result != null && result is Iterable && result.isNotEmpty) {
        final notifier = ref.read(capturedImagesProvider.notifier);
        for (final path in result) {
          notifier.add(path.toString());
        }
        ref.read(captureErrorProvider.notifier).state = null;
      }
    } catch (e) {
      ref.read(captureErrorProvider.notifier).state = 'Scan failed: $e';
    }
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
      text: 'Document ${formatDate(DateTime.now())}',
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final captured = ref.watch(capturedImagesProvider);

    ref.listen<String?>(captureErrorProvider, (_, error) {
      if (error != null && mounted) {
        showSnackBar(context, error, isError: true);
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Radial glow background
          Center(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [_brand.withOpacity(0.18), Colors.transparent],
                ),
              ),
            ),
          ),

          // Center — scan frame with corner accents
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CustomPaint(
                  painter: _CornerPainter(color: _brand.withOpacity(0.7)),
                  child: Container(
                    width: 220,
                    height: 280,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _brand.withOpacity(0.25),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.document_scanner_outlined,
                          size: 48,
                          color: Colors.white.withOpacity(0.15),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Position document\nwithin frame',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.25),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                      onPressed: () => context.pop(),
                    ),
                    const Spacer(),
                    if (captured.isNotEmpty)
                      FilledButton.tonal(
                        onPressed: _onDone,
                        style: FilledButton.styleFrom(
                          backgroundColor: _brand.withOpacity(0.25),
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          'Save  ${captured.length}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),

          // Bottom — thumbnail strip + glowing scan button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (captured.isNotEmpty)
                    ThumbnailStrip(
                      imagePaths: captured,
                      onTap: (idx) async {
                        final updated = await showModalBottomSheet<String>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) =>
                              CropEnhanceSheet(imagePath: captured[idx]),
                        );
                        if (updated != null) {
                          ref
                              .read(capturedImagesProvider.notifier)
                              .replace(idx, updated);
                        }
                      },
                    ),
                  const SizedBox(height: 24),
                  // Glowing scan button
                  GestureDetector(
                    onTap: _onCapture,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [_brand, _brandLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _brand.withOpacity(0.55),
                            blurRadius: 28,
                            spreadRadius: 2,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.document_scanner_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Corner accent painter ─────────────────────────────────────────────────────

class _CornerPainter extends CustomPainter {
  final Color color;
  _CornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const len = 24.0;

    // top-left
    canvas.drawLine(Offset(0, len), Offset.zero, p);
    canvas.drawLine(Offset.zero, Offset(len, 0), p);
    // top-right
    canvas.drawLine(Offset(size.width - len, 0), Offset(size.width, 0), p);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, len), p);
    // bottom-left
    canvas.drawLine(Offset(0, size.height - len), Offset(0, size.height), p);
    canvas.drawLine(Offset(0, size.height), Offset(len, size.height), p);
    // bottom-right
    canvas.drawLine(
      Offset(size.width - len, size.height),
      Offset(size.width, size.height),
      p,
    );
    canvas.drawLine(
      Offset(size.width, size.height - len),
      Offset(size.width, size.height),
      p,
    );
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}
