// lib/features/manager/document_folder_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:share_plus/share_plus.dart';
import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../shared/services/document_service.dart';
import '../../shared/services/pdf_service.dart';
import '../../core/utils.dart';
import '../../shared/widgets/app_empty_state.dart';

class DocumentFolderPage extends ConsumerStatefulWidget {
  const DocumentFolderPage({super.key, required this.docId});
  final int docId;

  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  @override
  ConsumerState<DocumentFolderPage> createState() =>
      _DocumentFolderPageState();
}

class _DocumentFolderPageState
    extends ConsumerState<DocumentFolderPage> with RouteAware {
  bool _selectMode = false;
  bool _reorderMode = false;
  final Set<String> _selectedImages = {};
  Document? _document;
  List<String> _cachedImagePaths = [];
  bool _imagesLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    DocumentFolderPage.routeObserver
        .subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    DocumentFolderPage.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() => _loadDocument();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadDocument());
  }

  Future<void> _loadDocument() async {
    final doc = await ref
        .read(documentsDaoProvider)
        .getDocument(widget.docId);
    if (!mounted) return;
    setState(() => _document = doc);
    if (doc != null) await _loadImages(doc.folderPath);
  }

  Future<void> _loadImages(String folderPath) async {
    final paths = await ref
        .read(documentServiceProvider)
        .getDocumentImages(folderPath);
    if (!mounted) return;
    setState(() {
      _cachedImagePaths = paths;
      _imagesLoaded = true;
    });
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _reorderMode = false;
      if (!_selectMode) _selectedImages.clear();
    });
  }

  void _toggleReorderMode() {
    setState(() {
      _reorderMode = !_reorderMode;
      _selectMode = false;
      _selectedImages.clear();
    });
  }

  void _toggleImageSelection(String imagePath) {
    setState(() {
      if (_selectedImages.contains(imagePath)) {
        _selectedImages.remove(imagePath);
      } else {
        _selectedImages.add(imagePath);
      }
    });
  }

  void _selectAll() =>
      setState(() => _selectedImages.addAll(_cachedImagePaths));

  void _deselectAll() =>
      setState(() => _selectedImages.clear());

  Future<void> _createPdf() async {
    if (_document == null || _selectedImages.isEmpty) return;

    final validPaths = _selectedImages
        .where((path) => File(path).existsSync())
        .toList();

    if (validPaths.isEmpty) {
      if (mounted) {
        showSnackBar(
            context,
            'No valid images selected — some may have been deleted',
            isError: true);
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create PDF'),
        content: Text(
          'Create a PDF from ${validPaths.length} selected image${validPaths.length == 1 ? '' : 's'}?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final pdfService = ref.read(pdfServiceProvider);
      final tempPdf = await pdfService.buildPdf(
        title: _document!.title,
        imagePaths: validPaths,
        pageFormat: PdfPageFormat.a4,
      );

      final savedPath = await ref
          .read(documentServiceProvider)
          .savePdfToDocumentFolder(widget.docId, tempPdf);

      if (mounted) {
        _toggleSelectMode();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('PDF created successfully'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              action: SnackBarAction(
                label: 'View',
                onPressed: () async {
                  await SharePlus.instance.share(
                    ShareParams(
                      files: [
                        XFile(savedPath,
                            mimeType: 'application/pdf')
                      ],
                      subject: _document?.title,
                    ),
                  );
                },
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to create PDF: $e',
            isError: true);
      }
    }
  }

  Future<void> _deleteSelected() async {
    if (_document == null || _selectedImages.isEmpty) return;

    final deleteCount = _selectedImages.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $deleteCount page${deleteCount == 1 ? '' : 's'}?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(documentServiceProvider)
          .deleteImages(
              widget.docId, _selectedImages.toList());

      if (_document != null)
        await _loadImages(_document!.folderPath);

      setState(() {
        _selectedImages.removeWhere(
            (path) => !_cachedImagePaths.contains(path));
      });

      if (mounted) {
        showSnackBar(
            context,
            'Deleted $deleteCount page${deleteCount == 1 ? '' : 's'}');
        _toggleSelectMode();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to delete: $e',
            isError: true);
      }
    }
  }

  Future<void> _shareSelected() async {
    if (_selectedImages.isEmpty) return;

    try {
      final xFiles = _selectedImages
          .map((path) =>
              XFile(path, mimeType: 'image/jpeg'))
          .toList();

      await SharePlus.instance.share(
        ShareParams(
          files: xFiles,
          subject: _document?.title ?? 'Shared Images',
        ),
      );

      if (mounted) _toggleSelectMode();
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to share: $e',
            isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final imagePaths = _cachedImagePaths;
    final hasImages = imagePaths.isNotEmpty;

    return PopScope(
      // Fix: if in reorder or select mode, back button exits the mode
      // instead of popping the page.
      canPop: !_reorderMode && !_selectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_reorderMode) _toggleReorderMode();
          else if (_selectMode) _toggleSelectMode();
        }
      },
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLow,
        appBar: AppBar(
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(
              (_reorderMode || _selectMode)
                  ? Icons.close
                  : Icons.arrow_back,
            ),
            onPressed: () {
              if (_reorderMode) {
                _toggleReorderMode();
              } else if (_selectMode) {
                _toggleSelectMode();
              } else if (context.canPop()) {
                context.pop();
              }
            },
          ),
          title: Text(_reorderMode
              ? 'Reorder pages'
              : _selectMode
                  ? '${_selectedImages.length} selected'
                  : (_document?.title ?? 'Document')),
          actions: [
            if (_selectMode) ...[
              IconButton(
                icon: const Icon(Icons.select_all),
                onPressed:
                    _selectedImages.length == imagePaths.length
                        ? _deselectAll
                        : _selectAll,
                tooltip:
                    _selectedImages.length == imagePaths.length
                        ? 'Deselect all'
                        : 'Select all',
              ),
            ] else if (_reorderMode) ...[
              IconButton(
                icon: const Icon(Icons.check_rounded),
                onPressed: _toggleReorderMode,
                tooltip: 'Done reordering',
              ),
            ] else ...[
              IconButton(
                icon: Icon(
                  _document?.isFavourite == true
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _document?.isFavourite == true
                      ? Colors.red
                      : null,
                ),
                tooltip: _document?.isFavourite == true
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                onPressed: _document == null
                    ? null
                    : () async {
                        await ref
                            .read(documentServiceProvider)
                            .toggleFavourite(
                              widget.docId,
                              !(_document!.isFavourite),
                            );
                        await _loadDocument();
                      },
              ),
              if (hasImages)
                IconButton(
                  icon: const Icon(Icons.checklist_rounded),
                  onPressed: _toggleSelectMode,
                  tooltip: 'Select pages',
                ),
              PopupMenuButton<_MenuAction>(
                onSelected: (action) => _handleMenu(action),
                itemBuilder: (_) => [
                  // Fix: only show Reorder when there are pages to reorder
                  if (hasImages)
                    const PopupMenuItem(
                        value: _MenuAction.reorder,
                        child: Text('Reorder pages')),
                  const PopupMenuItem(
                      value: _MenuAction.rename,
                      child: Text('Rename')),
                  const PopupMenuItem(
                      value: _MenuAction.delete,
                      child: Text('Delete document')),
                ],
              ),
            ],
          ],
        ),
        body: !_imagesLoaded
            ? const Center(child: CircularProgressIndicator())
            : imagePaths.isEmpty
                ? const AppEmptyState(
                    icon: Icons.photo_library_outlined,
                    title: 'No pages',
                    subtitle:
                        'Tap the button below to scan pages.',
                  )
                : _reorderMode
                    // ── Reorder mode: vertically reorderable list ──
                    ? ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8),
                        // Fix: disable default handles; we supply our own
                        // via ReorderableDragStartListener so there is
                        // only one handle per row, not two.
                        buildDefaultDragHandles: false,
                        itemCount: imagePaths.length,
                        onReorder: (oldIndex, newIndex) async {
                          if (newIndex > oldIndex) newIndex--;
                          final reordered =
                              List<String>.from(imagePaths);
                          final item =
                              reordered.removeAt(oldIndex);
                          reordered.insert(newIndex, item);
                          setState(() =>
                              _cachedImagePaths = reordered);
                          await ref
                              .read(documentServiceProvider)
                              .reorderImages(
                                  widget.docId, reordered);
                        },
                        itemBuilder: (context, index) {
                          return _ReorderTile(
                            key: ValueKey(
                                imagePaths[index]),
                            imagePath: imagePaths[index],
                            index: index,
                          );
                        },
                      )
                    // ── Normal / select mode: 3-column grid ──
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: imagePaths.length,
                        itemBuilder: (context, index) {
                          final imagePath = imagePaths[index];
                          return _ImageTile(
                            imagePath: imagePath,
                            isSelected: _selectedImages
                                .contains(imagePath),
                            selectMode: _selectMode,
                            onTap: () {
                              if (_selectMode) {
                                _toggleImageSelection(
                                    imagePath);
                              } else {
                                _openFullScreen(context,
                                    imagePaths, index);
                              }
                            },
                            onLongPress: () {
                              if (!_selectMode) {
                                _toggleSelectMode();
                                _toggleImageSelection(
                                    imagePath);
                              }
                            },
                          );
                        },
                      ),
        bottomNavigationBar:
            _selectMode && _selectedImages.isNotEmpty
                ? Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceEvenly,
                          children: [
                            _ActionChip(
                              icon: Icons.picture_as_pdf,
                              label: 'PDF',
                              color: Colors.deepOrange,
                              onPressed: _createPdf,
                            ),
                            _ActionChip(
                              icon: Icons.share,
                              label: 'Share',
                              color: cs.primary,
                              onPressed: _shareSelected,
                            ),
                            _ActionChip(
                              icon: Icons.delete_outline,
                              label: 'Delete',
                              color: Colors.red,
                              onPressed: _deleteSelected,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : null,
        floatingActionButton: _reorderMode
            ? null
            : FloatingActionButton.extended(
                onPressed: () async {
                  await context
                      .push('/camera?docId=${widget.docId}');
                  if (mounted) await _loadDocument();
                },
                icon: const Icon(Icons.add_a_photo),
                label: const Text('Scan Pages'),
              ),
      ),
    );
  }

  void _openFullScreen(BuildContext context,
      List<String> paths, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(
          imagePaths: paths,
          initialIndex: initialIndex,
          title: _document?.title ?? 'Document',
        ),
      ),
    );
  }

  Future<void> _handleMenu(_MenuAction action) async {
    if (_document == null) return;
    switch (action) {
      case _MenuAction.reorder:
        _toggleReorderMode();
      case _MenuAction.rename:
        await _renameDocument();
      case _MenuAction.delete:
        await _deleteDocument();
    }
  }

  Future<void> _renameDocument() async {
    final ctrl =
        TextEditingController(text: _document!.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename document'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Document name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Rename')),
        ],
      ),
    );

    if (newTitle == null || newTitle.isEmpty) return;
    try {
      await ref
          .read(documentServiceProvider)
          .renameDocument(widget.docId, newTitle);
      await _loadDocument();
      if (mounted) showSnackBar(context, 'Document renamed');
    } catch (e) {
      if (mounted)
        showSnackBar(context, 'Failed to rename: $e',
            isError: true);
    }
  }

  Future<void> _deleteDocument() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
          'Are you sure you want to delete "${_document!.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref
          .read(documentServiceProvider)
          .deleteDocument(widget.docId);
      if (mounted) {
        context.pop();
        showSnackBar(context, 'Document deleted');
      }
    } catch (e) {
      if (mounted)
        showSnackBar(context, 'Failed to delete: $e',
            isError: true);
    }
  }
}

// ---------------------------------------------------------------------------
// Reorder mode tile — drag handle via ReorderableDragStartListener
// Fix: buildDefaultDragHandles is false so this is the ONLY handle,
// avoiding the double-handle overlap from the previous implementation.
// ---------------------------------------------------------------------------
class _ReorderTile extends StatelessWidget {
  const _ReorderTile({
    super.key,
    required this.imagePath,
    required this.index,
  });

  final String imagePath;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 72,
      margin: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
            child: SizedBox(
              width: 56,
              height: 72,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.broken_image_outlined,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Page ${index + 1}',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          // Single drag handle via ReorderableDragStartListener
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.drag_handle_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen image viewer
// ---------------------------------------------------------------------------
class _FullScreenImageViewer extends StatefulWidget {
  const _FullScreenImageViewer({
    required this.imagePaths,
    required this.initialIndex,
    required this.title,
  });
  final List<String> imagePaths;
  final int initialIndex;
  final String title;

  @override
  State<_FullScreenImageViewer> createState() =>
      _FullScreenImageViewerState();
}

class _FullScreenImageViewerState
    extends State<_FullScreenImageViewer> {
  late int _currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController =
        PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_currentIndex + 1} / ${widget.imagePaths.length}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imagePaths.length,
        onPageChanged: (i) =>
            setState(() => _currentIndex = i),
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
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
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.file(
                    File(widget.imagePaths[i]),
                    fit: BoxFit.contain,
                    width: double.infinity,
                    errorBuilder: (ctx, err, _) => Center(
                      child: Text(
                        'Cannot load page ${i + 1}',
                        style: TextStyle(
                            color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Image Tile (3-col grid)
// ---------------------------------------------------------------------------
class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.imagePath,
    required this.isSelected,
    required this.selectMode,
    required this.onTap,
    required this.onLongPress,
  });

  final String imagePath;
  final bool isSelected;
  final bool selectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, _) => Container(
                color: cs.surfaceContainerHigh,
                child: Icon(Icons.broken_image,
                    color: cs.onSurfaceVariant),
              ),
            ),
          ),
          if (selectMode)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.blue
                      : Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action Chip
// ---------------------------------------------------------------------------
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MenuAction { reorder, rename, delete }
