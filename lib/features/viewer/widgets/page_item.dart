// lib/features/viewer/widgets/page_item.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class PageItem extends StatelessWidget {
  const PageItem({
    super.key,
    required this.imagePath,
    required this.index,
    required this.onDelete,
  });

  final String imagePath;
  final int index;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isPdf = imagePath.toLowerCase().endsWith('.pdf');
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: isPdf
                    ? _PdfPagePreview(path: imagePath)
                    : _ImagePagePreview(path: imagePath),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Page ${index + 1}',
                style: TextStyle(color: cs.onSurface.withOpacity(0.45), fontSize: 12),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: cs.error,
                    size: 20,
                  ),
                  onPressed: onDelete,
                  tooltip: 'Delete page',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePagePreview extends StatelessWidget {
  const _ImagePagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 4.0,
      child: Center(
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          width: double.infinity,
          errorBuilder: (ctx, err, _) => Center(
            child: Text(
              'Cannot load page',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

class _PdfPagePreview extends StatefulWidget {
  const _PdfPagePreview({required this.path});

  final String path;

  @override
  State<_PdfPagePreview> createState() => _PdfPagePreviewState();
}

class _PdfPagePreviewState extends State<_PdfPagePreview> {
  late Future<Uint8List?> _renderFuture;

  @override
  void initState() {
    super.initState();
    _renderFuture = _renderPdfPage();
  }

  Future<Uint8List?> _renderPdfPage() async {
    try {
      final file = File(widget.path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final rasters = await Printing.raster(
        bytes,
        pages: [0],
        dpi: 72,
      ).toList();

      if (rasters.isNotEmpty) {
        return await rasters.first.toPng();
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: _renderFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 48,
                  color: cs.error,
                ),
                const SizedBox(height: 8),
                Text('PDF Preview',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          );
        }
        return InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.0,
          child: Center(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              width: double.infinity,
            ),
          ),
        );
      },
    );
  }
}
