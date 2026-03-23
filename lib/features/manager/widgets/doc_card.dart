// lib/features/manager/widgets/doc_card.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../core/utils.dart';
import '../../../database/app_database.dart';

class DocCard extends StatelessWidget {
  const DocCard({
    super.key,
    required this.document,
    required this.onTap,
    this.onLongPress,
  });

  final Document document;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Hero(
        tag: 'doc_${document.id}',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: cs.surfaceContainerLow,
            border: Border.all(
              color: cs.outlineVariant.withOpacity(0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF5C4BF5).withOpacity(0.04),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cover image — takes remaining space
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Image or initials placeholder
                      document.coverPagePath != null
                          ? (document.coverPagePath!.toLowerCase().endsWith('.pdf')
                              ? _PdfThumbnail(path: document.coverPagePath!)
                              : Image.file(
                                  File(document.coverPagePath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (ctx, err, _) => Container(
                                    color: cs.surfaceContainerHigh,
                                    child: Center(
                                      child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
                                    ),
                                  ),
                                ))
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    cs.primary.withOpacity(0.18),
                                    cs.primary.withOpacity(0.06),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  initials(document.title),
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary.withOpacity(0.35),
                                  ),
                                ),
                              ),
                            ),

                      // Bottom gradient overlay
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 60,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.45),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Page count badge
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.layers_rounded,
                                size: 11,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${document.pageCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Footer — sizes precisely to content
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        document.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        relativeDate(document.updatedAt),
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.6),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PdfThumbnail extends StatelessWidget {
  const _PdfThumbnail({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _renderPdf(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: const Center(
              child: Icon(Icons.picture_as_pdf_outlined),
            ),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, _) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: const Center(
              child: Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
  }

  Future<Uint8List?> _renderPdf() async {
    try {
      final bytes = await File(path).readAsBytes();
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

