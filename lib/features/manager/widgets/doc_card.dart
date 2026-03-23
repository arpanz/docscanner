// lib/features/manager/widgets/doc_card.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/utils.dart';
import '../../../database/app_database.dart';

class DocCard extends StatelessWidget {
  const DocCard({
    super.key,
    required this.document,
    required this.onTap,
    this.onLongPress,
    this.heroTag,
  });

  final Document document;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Hero(
        tag: heroTag ?? 'doc_${document.id}',
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
            child: SizedBox(
              height: 280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cover image — takes remaining space
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Image or initials placeholder
                        document.coverImagePath != null
                            ? (document.coverImagePath!.toLowerCase().endsWith(
                                    '.pdf',
                                  )
                                  ? _PdfThumbnail(path: document.coverImagePath!)
                                  : Image.file(
                                      File(document.coverImagePath!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (ctx, err, _) => Container(
                                        color: cs.surfaceContainerHigh,
                                        child: Center(
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            color: cs.onSurfaceVariant,
                                          ),
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Favourite indicator
                              if (document.isFavourite)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.8),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.favorite_rounded,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              Container(
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
                                      '${document.imageCount}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
                        // Document metadata: pages and size
                        FutureBuilder<int>(
                          future: _getDocumentSize(document),
                          builder: (context, snapshot) {
                            final sizeStr = snapshot.hasData
                                ? formatBytes(snapshot.data!)
                                : '...';
                            return Text(
                              '${document.imageCount} pages · $sizeStr',
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.6),
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.1,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<int> _getDocumentSize(Document doc) async {
    if (doc.coverImagePath == null) return 0;
    return await fileSize(doc.coverImagePath!);
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
            child: const Center(child: Icon(Icons.picture_as_pdf_outlined)),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, _) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: const Center(child: Icon(Icons.broken_image_outlined)),
          ),
        );
      },
    );
  }

  Future<Uint8List?> _renderPdf() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final thumbDir = Directory(p.join(cacheDir.path, 'pdf_thumbnails'));

      // Clean up old thumbnails (older than 7 days)
      await _cleanupOldThumbnails(thumbDir);

      final safeName =
          '${path.hashCode}_${p.basenameWithoutExtension(path)}.png';
      final cacheFile = File(p.join(thumbDir.path, safeName));

      if (await cacheFile.exists()) {
        return await cacheFile.readAsBytes();
      }

      final bytes = await File(path).readAsBytes();
      final rasters = await Printing.raster(
        bytes,
        pages: [0],
        dpi: 72,
      ).toList();
      if (rasters.isNotEmpty) {
        final pngBytes = await rasters.first.toPng();

        if (!await thumbDir.exists()) {
          await thumbDir.create(recursive: true);
        }
        await cacheFile.writeAsBytes(pngBytes);

        return pngBytes;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  Future<void> _cleanupOldThumbnails(Directory thumbDir) async {
    try {
      if (!await thumbDir.exists()) return;

      final now = DateTime.now();
      await for (final entity in thumbDir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);
          if (age.inDays > 7) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }
}
