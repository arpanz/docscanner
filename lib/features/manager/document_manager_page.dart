import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_prefs.dart';
import '../../core/router.dart';
import '../../core/utils.dart';
import '../../database/app_database.dart';
import '../../shared/services/document_service.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_loading.dart';
import 'manager_providers.dart';
import 'widgets/doc_card.dart';
import 'widgets/search_bar.dart';
import 'widgets/sort_bar.dart';

class DocumentManagerPage extends ConsumerStatefulWidget {
  const DocumentManagerPage({super.key});

  @override
  ConsumerState<DocumentManagerPage> createState() => _DocumentManagerPageState();
}

class _DocumentManagerPageState extends ConsumerState<DocumentManagerPage> {
  bool _didCheckOnboarding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didCheckOnboarding) return;
    _didCheckOnboarding = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowOnboarding());
  }

  Future<void> _maybeShowOnboarding() async {
    if (!mounted) return;
    final hasSeenOnboarding = ref.read(onboardingSeenProvider);
    final docs = await ref.read(documentsDaoProvider).getAllDocuments();
    if (hasSeenOnboarding || docs.isNotEmpty || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _OnboardingSheet(
        onScan: () {
          Navigator.pop(ctx);
          context.push(AppRoutes.camera);
        },
        onImport: () {
          Navigator.pop(ctx);
          _pickFromGallery(context, ref);
        },
      ),
    );

    await ref.read(onboardingSeenProvider.notifier).setValue(true);
  }

  Future<void> _refreshDocuments() async {
    await ref.read(documentServiceProvider).refreshAllDocumentsMeta();
    ref.invalidate(allDocumentsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(filteredDocumentsProvider);
    final query = ref.watch(searchQueryProvider);
    final isGrid = ref.watch(isGridViewProvider);
    final showFavs = ref.watch(showFavouritesOnlyProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: RefreshIndicator.adaptive(
        onRefresh: _refreshDocuments,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 116,
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
                    color: showFavs ? cs.error : null,
                  ),
                  tooltip:
                      showFavs ? 'Show all documents' : 'Show favourites only',
                  onPressed: () => ref
                      .read(favouritesPreferenceProvider.notifier)
                      .setValue(!showFavs),
                ),
                IconButton(
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'Settings',
                  onPressed: () => context.push(AppRoutes.settings),
                ),
                IconButton(
                  icon: Icon(
                    isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  ),
                  tooltip: isGrid ? 'Switch to list view' : 'Switch to grid view',
                  onPressed: () => ref
                      .read(gridPreferenceProvider.notifier)
                      .setValue(!isGrid),
                ),
                const SizedBox(width: 8),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(116),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: DocSearchBar(
                        initialValue: query,
                        onChanged: (v) =>
                            ref.read(searchQueryProvider.notifier).state = v,
                      ),
                    ),
                    const SortBar(),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            docsAsync.when(
              loading: () => const SliverFillRemaining(child: AppLoading()),
              error: (e, _) => SliverFillRemaining(
                child: Center(
                  child: Text(
                    'Unable to load documents right now.',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ),
              data: (docs) {
                if (docs.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: AppEmptyState(
                      icon: Icons.document_scanner_outlined,
                      title: showFavs
                          ? 'No favourites yet'
                          : query.isEmpty
                              ? 'No documents yet'
                              : 'No results for "$query"',
                      subtitle: showFavs
                          ? 'Mark a document as favourite to keep it close.'
                          : query.isEmpty
                              ? 'Scan paper docs or import photos from your gallery to get started.'
                              : null,
                      action: query.isEmpty ? () => context.push(AppRoutes.camera) : null,
                      actionLabel:
                          query.isEmpty ? 'Scan Your First Document' : null,
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
                            childAspectRatio: 0.75,
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
                            final doc = docs[i];
                            return ListTile(
                              minVerticalPadding: 12,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              leading: SizedBox(
                                width: 56,
                                height: 64,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: doc.coverImagePath != null
                                      ? Image.file(
                                          File(doc.coverImagePath!),
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            color: cs.primary.withOpacity(0.1),
                                            child: Icon(
                                              Icons.description_outlined,
                                              color: cs.primary,
                                            ),
                                          ),
                                        )
                                      : Container(
                                          color: cs.primary.withOpacity(0.1),
                                          child: Icon(
                                            Icons.description_outlined,
                                            color: cs.primary,
                                          ),
                                        ),
                                ),
                              ),
                              title: Text(
                                doc.title,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '${doc.imageCount} ${doc.imageCount == 1 ? 'page' : 'pages'} · ${formatBytes(doc.folderSizeBytes)}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  context.push(AppRoutes.folderPath(doc.id)),
                              onLongPress: () => _showDocOptions(context, ref, doc),
                            );
                          },
                        ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Import from gallery',
              child: FloatingActionButton.extended(
                heroTag: 'gallery_fab',
                backgroundColor: cs.surfaceContainerHigh,
                foregroundColor: cs.primary,
                elevation: 2,
                onPressed: () => _pickFromGallery(context, ref),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Import'),
              ),
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
        showSnackBar(
          context,
          userFacingError(e, fallback: 'Could not open your gallery.'),
          isError: true,
        );
      }
      return;
    }
    if (images.isEmpty || !context.mounted) return;

    final paths = images.map((x) => x.path).toList();
    final ctrl = TextEditingController(text: 'Scan ${formatDate(DateTime.now())}');
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

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Saving document...')),
          ],
        ),
      ),
    );

    try {
      final docId = await ref
          .read(documentServiceProvider)
          .createDocument(title: title, imagePaths: paths);
      if (context.mounted) {
        Navigator.pop(context);
        showSnackBar(context, 'Document created');
        context.push(AppRoutes.folderPath(docId));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        showSnackBar(
          context,
          userFacingError(e, fallback: 'Could not import those images.'),
          isError: true,
        );
      }
    }
  }

  void _showDocOptions(BuildContext context, WidgetRef ref, Document doc) {
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
                    await ref.read(documentServiceProvider).renameDocument(doc.id, name);
                    if (context.mounted) {
                      showSnackBar(context, 'Document renamed');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showSnackBar(
                        context,
                        userFacingError(e, fallback: 'Could not rename this document.'),
                        isError: true,
                      );
                    }
                  }
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
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
                    content: Text('Delete "${doc.title}"? This cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  HapticFeedback.mediumImpact();
                  try {
                    await ref.read(documentServiceProvider).deleteDocument(doc.id);
                    if (context.mounted) {
                      showSnackBar(context, 'Document deleted');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showSnackBar(
                        context,
                        userFacingError(e, fallback: 'Could not delete this document.'),
                        isError: true,
                      );
                    }
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
            Color.lerp(cs.primary, cs.tertiary, 0.55)!,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.35),
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

class _OnboardingSheet extends StatelessWidget {
  const _OnboardingSheet({
    required this.onScan,
    required this.onImport,
  });

  final VoidCallback onScan;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withOpacity(0.14),
                    cs.tertiary.withOpacity(0.16),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome to DocScanner',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan receipts, notes, and paperwork into clean documents. You can also import existing photos and export polished PDFs in one tap.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan a document'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Import from gallery'),
            ),
          ],
        ),
      ),
    );
  }
}
