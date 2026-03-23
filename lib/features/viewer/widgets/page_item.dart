// lib/features/viewer/widgets/page_item.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../database/app_database.dart' as db;

class PageItem extends StatelessWidget {
  const PageItem({
    super.key,
    required this.page,
    required this.index,
    required this.onDelete,
  });

  final db.Page page;
  final int index;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isPdf = page.imagePath.toLowerCase().endsWith('.pdf');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: isPdf ? _PdfPagePreview(path: page.imagePath) : _ImagePagePreview(path: page.imagePath),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Page ${index + 1}',
                style: const TextStyle(color: Colors.black45, fontSize: 12),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
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
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

class _PdfPagePreview extends StatelessWidget {
  const _PdfPagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _renderPdfPage(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.picture_as_pdf_outlined, size: 48, color: Colors.red),
                const SizedBox(height: 8),
                Text(
                  'PDF Preview',
                  style: TextStyle(color: Colors.grey[600]),
                ),
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

  Future<Uint8List?> _renderPdfPage() async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final rasters = await Printing.raster(bytes, pages: [0], dpi: 72).toList();

      if (rasters.isNotEmpty) {
        return await rasters.first.toPng();
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}
