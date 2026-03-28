// lib/features/manager/document_manager_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/utils.dart';
import '../../database/app_database.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_loading.dart';
import '../../shared/services/document_service.dart';
import '../../shared/utils/image_utils.dart';
import 'manager_providers.dart';
import 'widgets/doc_card.dart';
import 'widgets/sort_bar.dart';
import 'widgets/search_bar.dart';

class DocumentManagerPage extends ConsumerWidget {
  const DocumentManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(filteredDocumentsProvider);
    final query = ref.watch(searchQueryProvider);
    final isGrid = ref.watch(isGridViewProvider);
    final showFavs = ref.watch(showFavouritesOnlyProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            pinned: true,
            backgroundColor: theme.colorScheme.surface,
            scrolledUnderElevation: 0,
            title: Text(
              'DocScanner',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  showFavs
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: showFavs ? theme.colorScheme.error : null,
                ),
                tooltip: showFavs
                    ? 'Show all documents'
                    : 'Show favourites only',
                onPressed: () =>
                    ref.read(showFavouritesOnlyProvider.notifier).toggle(),
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => context.push(AppRoutes.settings),
              ),
              IconButton(
                icon: Icon(
                  isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                ),
                onPressed: () =>
                    ref.read(isGridViewProvider.notifier).toggle(),
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
          docsAsync.when(
            loading: () => const SliverFillRemaining(child: AppLoading()),
            error: (e, _) =>
                const SliverFillRemaining(child: Center(child: Text('Something went wrong'))),
            data: (docs) {
              if (docs.isEmpty) {
                return SliverFillRemaining(
                  child: AppEmptyState(
                    icon: Icons.document_scanner_outlined,
                    title: showFavs
                        ? 'No favourites yet'
                        : query.isEmpty
                        ? 'No documents yet'
                        : 'No results for "$query"',
                    subtitle: showFavs
                        ? 'Tap the heart icon on a document to favourite it.'
                        : query.isEmpty
                        ? 'Tap the button below to scan your first document.'
                        : null,
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                sliver: isGrid
                    ? SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              childAspectRatio: 0.68,
                            ),
                        itemCount: docs.length,
                        itemBuilder: (ctx, i) => DocCard(
                          document: docs[i],
                          heroTag: 'manager_doc_${docs[i].id}',
                          onTap: () =>
                              context.push(AppRoutes.folderPath(docs[i].id)),
                          onLongPress: () =>
                              _showDocOptions(context, ref, docs[i]),
                        ),
                      )
                    : SliverList.builder(
                        itemCount: docs.length,
                        itemBuilder: (ctx, i) {
                          return ListTile(
                            leading: SizedBox(
                              width: 56,
                              height: 64,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: docs[i].coverImagePath != null
                                    ? Image.file(
                                        File(docs[i].coverImagePath!),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: theme.colorScheme.primary
                                              .withOpacity(0.1),
                                          child: Icon(
                                            Icons.description_outlined,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: theme.colorScheme.primary
                                            .withOpacity(0.1),
                                        child: Icon(
                                          Icons.description_outlined,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                              ),
                            ),
                            title: Text(
                              docs[i].title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // Fix: list view now shows size like grid card
                            // footer does, keeping both views consistent.
                            subtitle: _ListTileSubtitle(document: docs[i]),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                context.push(AppRoutes.folderPath(docs[i].id)),
                            onLongPress: () =>
                                _showDocOptions(context, ref, docs[i]),
                          );
                        },
                      ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton(
              heroTag: 'gallery_fab',
              mini: true,
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
              foregroundColor: theme.colorScheme.primary,
              elevation: 2,
              onPressed: () => _pickFromGallery(context, ref),
              child: const Icon(Icons.photo_library_outlined),
            ),
            const SizedBox(width: 12),
            _GradientFAB(onPressed: () => context.push(AppRoutes.camera)),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Future<void> _pickFromGallery(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    List<XFile> images;
    try {
      images = await picker.pickMultiImage(imageQuality: 90);
    } on PlatformException catch (e) {
      if (context.mounted) {
        final message = (e.message?.isNotEmpty ?? false)
            ? e.message!
            : 'Gallery access was denied. Please allow Photos/Media access in app settings and try again.';
        showSnackBar(context, message, isError: true);
      }
      return;
    } catch (e) {
      if (context.mounted) {
        debugPrint('Failed to open gallery: $e');
        showSnackBar(context, 'Could not open gallery. Please try again.', isError: true);
      }
      return;
    }
    if (images.isEmpty || !context.mounted) return;

    final paths = images.map((x) => x.path).toList();
    final ctrl = TextEditingController(
      text: 'Scan ${formatDate(DateTime.now())}',
    );
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name your document'),
        content: TextField(controller: ctrl, autofocus: true),
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
    if (title == null || title.isEmpty || !context.mounted) return;

    try {
      final docId = await ref
          .read(documentServiceProvider)
          .createDocument(title: title, imagePaths: paths);
      if (context.mounted) {
        context.push(AppRoutes.folderPath(docId));
      }
    } catch (e) {
      if (context.mounted) {
        debugPrint('Failed to import images: $e');
        showSnackBar(context, 'Could not import images. Please try again.', isError: true);
      }
    }
  }

  void _showDocOptions(BuildContext context, WidgetRef ref, Document doc) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final ctrl = TextEditingController(text: doc.title);
                final name = await showDialog<String>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Rename document'),
                    content: TextField(controller: ctrl, autofocus: true),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(d),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(d, ctrl.text.trim()),
                        child: const Text('Rename'),
                      ),
                    ],
                  ),
                );
                if (name != null && name.isNotEmpty) {
                  try {
                    await ref
                        .read(documentServiceProvider)
                        .renameDocument(doc.id, name);
                  } catch (e) {
                    debugPrint('Failed to rename: $e');
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text('Could not rename document. Please try again.'),
                        backgroundColor: theme.colorScheme.error,
                      ),
                    );
                  }
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete document?'),
                    content: Text(
                      'Delete "${doc.title}"? This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                        ),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  try {
                    await ref
                        .read(documentServiceProvider)
                        .deleteDocument(doc.id);
                  } catch (e) {
                    debugPrint('Failed to delete: $e');
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text('Could not delete document. Please try again.'),
                        backgroundColor: theme.colorScheme.error,
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
}

// ---------------------------------------------------------------------------
// List tile subtitle — shows page count + folder size (matches grid card)
// ---------------------------------------------------------------------------
class _ListTileSubtitle extends StatefulWidget {
  const _ListTileSubtitle({required this.document});
  final Document document;

  @override
  State<_ListTileSubtitle> createState() => _ListTileSubtitleState();
}

class _ListTileSubtitleState extends State<_ListTileSubtitle> {
  late Future<int> _sizeFuture;

  @override
  void initState() {
    super.initState();
    _sizeFuture = computeFolderSize(widget.document.folderPath);
  }

  @override
  void didUpdateWidget(_ListTileSubtitle old) {
    super.didUpdateWidget(old);
    if (old.document.folderPath != widget.document.folderPath ||
        old.document.updatedAt != widget.document.updatedAt) {
      _sizeFuture = computeFolderSize(widget.document.folderPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.document.imageCount;
    final pageLabel = '$count ${count == 1 ? 'page' : 'pages'}';
    return FutureBuilder<int>(
      future: _sizeFuture,
      builder: (context, snapshot) {
        final sizeStr = snapshot.hasData
            ? formatBytes(snapshot.data!)
            : '\u2026';
        return Text('$pageLabel · $sizeStr');
      },
    );
  }
}

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
                Icon(
                  Icons.document_scanner_outlined,
                  color: Colors.white,
                  size: 22,
                ),
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
