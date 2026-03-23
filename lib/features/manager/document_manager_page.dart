// lib/features/manager/document_manager_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/router.dart';
import '../../core/utils.dart';
import '../../database/app_database.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_loading.dart';
import '../../shared/services/document_service.dart';
import '../../shared/services/pdf_service.dart';
import '../../shared/services/permission_service.dart';
import 'manager_providers.dart';
import 'widgets/doc_card.dart';
import 'widgets/sort_bar.dart';
import 'widgets/search_bar.dart';

class DocumentManagerPage extends ConsumerStatefulWidget {
  const DocumentManagerPage({super.key});

  @override
  ConsumerState<DocumentManagerPage> createState() => _DocumentManagerPageState();
}

class _DocumentManagerPageState extends ConsumerState<DocumentManagerPage> {
  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(filteredDocumentsProvider);
    final allDocsAsync = ref.watch(allDocumentsProvider);
    final query = ref.watch(searchQueryProvider);
    final isGrid = ref.watch(isGridViewProvider);
    final showFavourites = ref.watch(showFavouritesOnlyProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Expanding app bar with gradient background
          SliverAppBar(
            expandedHeight: 150,
            pinned: true,
            backgroundColor: theme.colorScheme.surface,
            scrolledUnderElevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary.withOpacity(0.12),
                      theme.colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DocScanner',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                // Document count stats
                allDocsAsync.valueOrNull != null
                    ? Text(
                        '${allDocsAsync.value!.length} document${allDocsAsync.value!.length != 1 ? 's' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    : const SizedBox.shrink(),
              ],
            ),
            actions: [
              // Favourites filter toggle
              IconButton(
                icon: Icon(
                  showFavourites ? Icons.favorite_rounded : Icons.favorite_border,
                  color: showFavourites ? theme.colorScheme.error : null,
                ),
                onPressed: () => ref.read(showFavouritesOnlyProvider.notifier).state = !showFavourites,
                tooltip: showFavourites ? 'Show all' : 'Show favourites',
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => context.push(AppRoutes.settings),
              ),
              IconButton(
                icon: Icon(isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded),
                onPressed: () => ref.read(isGridViewProvider.notifier).state = !isGrid,
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(112),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: DocSearchBar(
                      initialValue: query,
                      onChanged: (v) =>
                          ref.read(searchQueryProvider.notifier).state = v,
                    ),
                  ),
                  const SortBar(),
                ],
              ),
            ),
          ),

          // Document grid
          docsAsync.when(
            loading: () => const SliverFillRemaining(child: AppLoading()),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Error: $e')),
            ),
            data: (docs) {
              if (docs.isEmpty) {
                return SliverFillRemaining(
                  child: AppEmptyState(
                    icon: Icons.document_scanner_outlined,
                    title: query.isEmpty
                        ? 'No documents yet'
                        : 'No results for "$query"',
                    subtitle: query.isEmpty
                        ? 'Tap the Scan button to create your first document'
                        : null,
                    action: query.isEmpty ? () => context.push(AppRoutes.camera) : null,
                    actionLabel: query.isEmpty ? 'Scan Document' : null,
                  ),
                );
              }

              // Recent documents section (only when not searching/filtering)
              final showRecent = query.isEmpty && !showFavourites && docs.length > 3;
              
              return SliverList.builder(
                itemCount: (showRecent ? 1 : 0) + docs.length,
                itemBuilder: (ctx, i) {
                  // Recent section header
                  if (showRecent && i == 0) {
                    return _buildRecentSection(context, ref, docs.take(3).toList());
                  }
                  
                  // Document list/grid
                  final docIndex = showRecent ? i - 1 : i;
                  if (docIndex >= docs.length) return const SizedBox.shrink();
                  
                  final doc = docs[docIndex];
                  
                  if (isGrid) {
                    return Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, docIndex == docs.length - 1 ? 100 : 0),
                      child: DocCard(
                        document: doc,
                        onTap: () => context.push(AppRoutes.viewerPath(doc.id)),
                        onLongPress: () => _showDocOptions(context, ref, doc),
                      ),
                    );
                  }
                  
                  return ListTile(
                    leading: SizedBox(
                      width: 72,
                      height: 88,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            doc.coverPagePath != null
                                ? Image.file(File(doc.coverPagePath!), fit: BoxFit.cover)
                                : Container(
                                    color: theme.colorScheme.primary.withOpacity(0.1),
                                    child: Icon(Icons.description_outlined, color: theme.colorScheme.primary, size: 32),
                                  ),
                            if (doc.isFavourite)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.favorite_rounded,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: FutureBuilder<int>(
                      future: _getDocSize(doc),
                      builder: (context, snapshot) {
                        final sizeStr = snapshot.hasData
                            ? formatBytes(snapshot.data!)
                            : '...';
                        return Text('${doc.pageCount} pages · $sizeStr');
                      },
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.viewerPath(doc.id)),
                    onLongPress: () => _showDocOptions(context, ref, doc),
                  );
                },
              );
            },
          ),
        ],
      ),

      // Floating Action Buttons - Scan + Gallery
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gallery button - more prominent
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.surfaceContainerHigh,
                    theme.colorScheme.surfaceContainerHighest,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => _pickFromGallery(context, ref),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_library_outlined, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Gallery',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Scan button (main) - gradient FAB
            _GradientFAB(
              onPressed: () => context.push(AppRoutes.camera),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Future<void> _pickFromGallery(BuildContext context, WidgetRef ref) async {
    // Request storage permission first
    final permissionService = ref.read(permissionServiceProvider);
    final hasStorage = await permissionService.requestStorage();
    
    if (!hasStorage) {
      if (!context.mounted) return;
      showSnackBar(
        context,
        'Storage permission is required to access photos',
        isError: true,
      );
      return;
    }
    
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 90);
    if (images.isEmpty || !context.mounted) return;

    final paths = images.map((x) => x.path).toList();
    
    // Check for duplicate title
    final docs = await ref.read(documentsDaoProvider).watchAllDocuments().first;
    final baseTitle = 'Document ${formatDate(DateTime.now())}';
    String title = baseTitle;
    int counter = 1;
    
    while (docs.any((d) => d.title == title)) {
      title = '$baseTitle ($counter)';
      counter++;
    }
    
    final ctrl = TextEditingController(text: title);
    final titleResult = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Name your document'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isEmpty ? title : ctrl.text.trim()),
            child: const Text('Use Default'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Use default title if cancelled or empty
    final finalTitle = titleResult == null || titleResult.isEmpty ? title : titleResult;
    if (!context.mounted) return;

    final docId = await ref.read(documentServiceProvider).createDocument(
      title: finalTitle,
      imagePaths: paths,
    );
    if (context.mounted) context.push(AppRoutes.viewerPath(docId));
  }

  Future<int> _getDocSize(Document doc) async {
    if (doc.coverPagePath == null) return 0;
    return await fileSize(doc.coverPagePath!);
  }

  Widget _buildRecentSection(BuildContext context, WidgetRef ref, List<Document> recentDocs) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Recent Documents',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => ref.read(sortOptionProvider.notifier).state = SortOption.dateDesc,
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        // Horizontal scrollable cards
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: recentDocs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (ctx, i) => SizedBox(
              width: 160,
              child: DocCard(
                document: recentDocs[i],
                onTap: () => context.push(AppRoutes.viewerPath(recentDocs[i].id)),
                onLongPress: () => _showDocOptions(context, ref, recentDocs[i]),
              ),
            ),
          ),
        ),
        // Divider before main list
        const Divider(height: 32),
      ],
    );
  }

  void _showDocOptions(BuildContext context, WidgetRef ref, Document doc) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Favourite toggle
            ListTile(
              leading: Icon(
                doc.isFavourite ? Icons.favorite_rounded : Icons.favorite_border,
                color: doc.isFavourite ? theme.colorScheme.error : null,
              ),
              title: Text(doc.isFavourite ? 'Remove from favourites' : 'Add to favourites'),
              onTap: () async {
                Navigator.pop(ctx);
                await ref
                    .read(documentsDaoProvider)
                    .toggleFavourite(doc.id, !doc.isFavourite);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(ctx);
                final ctrl = TextEditingController(text: doc.title);
                final name = await showDialog<String>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Rename document'),
                    content: TextField(controller: ctrl, autofocus: true),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(d),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () =>
                              Navigator.pop(d, ctrl.text.trim()),
                          child: const Text('Rename')),
                    ],
                  ),
                );
                if (name != null && name.isNotEmpty && context.mounted) {
                  await ref
                      .read(documentServiceProvider)
                      .renameDocument(doc.id, name);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () async {
                Navigator.pop(ctx);
                await _shareDocument(context, ref, doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Export PDF'),
              onTap: () async {
                Navigator.pop(ctx);
                await _exportPdf(context, ref, doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Duplicate'),
              onTap: () async {
                Navigator.pop(ctx);
                await _duplicateDocument(context, ref, doc);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await confirmDialog(
                  context,
                  title: 'Delete document',
                  message: 'Delete "${doc.title}"? This cannot be undone.',
                );
                if (ok && context.mounted) {
                  await ref
                      .read(documentServiceProvider)
                      .deleteDocument(doc.id);
                  
                  if (context.mounted) {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Document deleted'),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () async {
                            // Note: Full undo would require keeping the files
                            // For now, just inform user
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Undo not available - files were deleted'),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareDocument(
    BuildContext context,
    WidgetRef ref,
    Document doc,
  ) async {
    try {
      final pages = await ref
          .read(pagesDaoProvider)
          .getPagesForDocument(doc.id);
      final paths = pages.map((p) => p.imagePath).toList();

      // Check if it's a PDF-based document
      final isPdf = paths.length == 1 && paths.first.toLowerCase().endsWith('.pdf');

      if (isPdf) {
        // Share the PDF file directly
        final pdfService = ref.read(pdfServiceProvider);
        await pdfService.sharePdf(File(paths.first), subject: doc.title);
      } else {
        // Share as images
        final pdfService = ref.read(pdfServiceProvider);
        await pdfService.shareImages(paths, subject: doc.title);
      }
    } catch (e) {
      if (context.mounted) {
        showSnackBar(context, 'Share failed: $e', isError: true);
      }
    }
  }

  Future<void> _exportPdf(
    BuildContext context,
    WidgetRef ref,
    Document doc,
  ) async {
    try {
      final pages = await ref
          .read(pagesDaoProvider)
          .getPagesForDocument(doc.id);
      final paths = pages.map((p) => p.imagePath).toList();

      // Check if it's already a PDF-based document
      final isPdf = paths.length == 1 && paths.first.toLowerCase().endsWith('.pdf');

      if (isPdf) {
        // Share the existing PDF
        final pdfService = ref.read(pdfServiceProvider);
        await pdfService.sharePdf(File(paths.first), subject: doc.title);
      } else {
        // Build PDF from images
        final pdfService = ref.read(pdfServiceProvider);
        final pdfFile = await pdfService.buildPdf(
          title: doc.title,
          imagePaths: paths,
        );
        await pdfService.sharePdf(pdfFile, subject: doc.title);
      }
    } catch (e) {
      if (context.mounted) {
        showSnackBar(context, 'Export failed: $e', isError: true);
      }
    }
  }

  Future<void> _duplicateDocument(
    BuildContext context,
    WidgetRef ref,
    Document doc,
  ) async {
    try {
      final pages = await ref
          .read(pagesDaoProvider)
          .getPagesForDocument(doc.id);
      final paths = pages.map((p) => p.imagePath).toList();

      // Check if it's a PDF-based document
      final isPdf = paths.length == 1 && paths.first.toLowerCase().endsWith('.pdf');

      if (isPdf) {
        // Duplicate PDF document
        final cleanPath = cleanFilePath(paths.first);

        final base = await getApplicationDocumentsDirectory();
        final dir = Directory(p.join(base.path, 'pages'));
        if (!await dir.exists()) await dir.create(recursive: true);

        final dest = p.join(
          dir.path,
          '${doc.id}_dup_${DateTime.now().microsecondsSinceEpoch}.pdf',
        );
        await File(cleanPath).copy(dest);

        final newDocId = await ref.read(documentServiceProvider).createDocumentFromPdf(
          title: '${doc.title} (Copy)',
          pdfPath: dest,
          pageCount: 1,
        );

        if (context.mounted) {
          showSnackBar(context, 'Document duplicated');
          context.push(AppRoutes.viewerPath(newDocId));
        }
      } else {
        // Duplicate image-based document
        final newDocId = await ref.read(documentServiceProvider).createDocument(
          title: '${doc.title} (Copy)',
          imagePaths: paths,
        );

        if (context.mounted) {
          showSnackBar(context, 'Document duplicated');
          context.push(AppRoutes.viewerPath(newDocId));
        }
      }
    } catch (e) {
      if (context.mounted) {
        showSnackBar(context, 'Duplicate failed: $e', isError: true);
      }
    }
  }
}

// ── Gradient FAB ─────────────────────────────────────────────────────────────

class _GradientFAB extends StatelessWidget {
  const _GradientFAB({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary,
            Color.lerp(cs.primary, Colors.purpleAccent, 0.5)!,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.document_scanner_outlined,
                    color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text(
                  'Scan Document',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.3,
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
