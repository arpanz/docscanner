// lib/features/manager/widgets/doc_card.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

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
    final tag = heroTag ?? 'doc_card_${document.id}';

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Hero(
        tag: tag,
        flightShuttleBuilder: (_, animation, __, ___, ____) {
          final coverPath = document.coverImagePath;
          Widget imageWidget = const SizedBox.shrink();
          if (coverPath != null) {
            if (coverPath.toLowerCase().endsWith('.pdf')) {
              imageWidget = _PdfThumbnail(path: coverPath);
            } else {
              imageWidget = Image.file(File(coverPath), fit: BoxFit.cover);
            }
          }
          return AnimatedBuilder(
            animation: animation,
            builder: (ctx, _) => ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: imageWidget,
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: cs.surfaceContainerLow,
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.08),
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
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
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
                                    cs.primary.withValues(alpha: 0.18),
                                    cs.secondary.withValues(alpha: 0.12),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  initials(document.title),
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary.withValues(alpha: 0.35),
                                  ),
                                ),
                              ),
                            ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 64,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                cs.scrim.withValues(alpha: 0.4),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (document.isFavourite)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: cs.error.withValues(alpha: 0.88),
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
                                color: cs.scrim.withValues(alpha: 0.62),
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
                      _DocCardFooter(document: document),
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

class _DocCardFooter extends StatelessWidget {
  const _DocCardFooter({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final count = document.imageCount;
    final pageLabel = '$count ${count == 1 ? 'page' : 'pages'}';
    final sizeStr = formatBytes(document.folderSizeBytes);
    return Text(
      '$pageLabel · $sizeStr',
      style: tt.labelSmall?.copyWith(
        color: cs.onSurface.withValues(alpha: 0.6),
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
    );
  }
}

class _PdfThumbnail extends StatefulWidget {
  const _PdfThumbnail({required this.path});

  final String path;

  @override
  State<_PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends State<_PdfThumbnail> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _renderPdf();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          final cs = Theme.of(context).colorScheme;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.surfaceContainerLow,
                  cs.surfaceContainer,
                  cs.surfaceContainerLow,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          );
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

      await _cleanupOldThumbnails(thumbDir);

      final safeName =
          '${widget.path.hashCode}_${p.basenameWithoutExtension(widget.path)}.png';
      final cacheFile = File(p.join(thumbDir.path, safeName));

      if (await cacheFile.exists()) {
        return await cacheFile.readAsBytes();
      }

      final bytes = await File(widget.path).readAsBytes();
      final rasters = await Printing.raster(
        bytes,
        pages: [0],
        dpi: 144,
      ).toList();
      if (rasters.isNotEmpty) {
        final pngBytes = await rasters.first.toPng();
        if (!await thumbDir.exists()) {
          await thumbDir.create(recursive: true);
        }
        await cacheFile.writeAsBytes(pngBytes);
        return pngBytes;
      }
    } catch (_) {
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
          if (now.difference(stat.modified).inDays > 7) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }
}
