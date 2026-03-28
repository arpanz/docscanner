// lib/features/manager/document_folder_page.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:share_plus/share_plus.dart';

import '../../database/app_database.dart';
import '../camera/widgets/crop_enhance_sheet.dart';
import '../../shared/services/document_service.dart';
import '../../shared/services/pdf_service.dart';
import '../../core/router.dart';
import '../../core/utils.dart';
import '../../shared/widgets/app_empty_state.dart';

class DocumentFolderPage extends ConsumerStatefulWidget {
  const DocumentFolderPage({super.key, required this.docId});
  final int docId;

  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  @override
  ConsumerState<DocumentFolderPage> createState() => _DocumentFolderPageState();
}

class _DocumentFolderPageState extends ConsumerState<DocumentFolderPage>
    with RouteAware {
  bool _selectMode = false;
  bool _reorderMode = false;
  final Set<String> _selectedImages = {};
  Document? _document;
  List<String> _cachedImagePaths = [];
  bool _imagesLoaded = false;
  bool _isEditing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    DocumentFolderPage.routeObserver.subscribe(this, ModalRoute.of(context)!);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDocument());
  }

  Future<void> _loadDocument() async {
    final doc = await ref.read(documentsDaoProvider).getDocument(widget.docId);
    if (!mounted) return;
    setState(() => _document = doc);
    if (doc != null) await _loadImages(doc);
  }

  Future<void> _loadImages(Document doc) async {
    final paths = await ref
        .read(documentServiceProvider)
        .getDocumentImages(doc.folderPath);
    if (!mounted) return;

    if (paths.isEmpty &&
        doc.pdfPath != null &&
        File(doc.pdfPath!).existsSync()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.replace(AppRoutes.viewerPath(widget.docId));
        }
      });
      return;
    }

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

  void _deselectAll() => setState(() => _selectedImages.clear());

  Future<void> _createPdf() async {
    await _createPdfForPaths(
      _selectedImages.toList(),
      scopeLabel: 'selected',
      exitSelectMode: true,
    );
  }

  Future<void> _createPdfForPaths(
    List<String> sourcePaths, {
    required String scopeLabel,
    bool exitSelectMode = false,
  }) async {
    if (_document == null || sourcePaths.isEmpty) return;

    final validPaths = sourcePaths
        .where((path) => File(path).existsSync())
        .toList();
    if (validPaths.isEmpty) {
      if (mounted) {
        showSnackBar(
          context,
          'No valid images found — some may have been deleted',
          isError: true,
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create PDF'),
        content: Text(
          'Create a PDF from ${validPaths.length} $scopeLabel image${validPaths.length == 1 ? '' : 's'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
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

      if (!mounted) return;
      if (exitSelectMode && _selectMode) {
        _toggleSelectMode();
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('PDF created successfully'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                context.push(AppRoutes.viewerPath(widget.docId));
              },
            ),
          ),
        );
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to create PDF: $e', isError: true);
      }
    }
  }

  Future<void> _createPdfAll() async {
    await _createPdfForPaths(_cachedImagePaths, scopeLabel: 'all');
  }

  Future<void> _deleteSelected() async {
    await _deletePaths(
      _selectedImages.toList(),
      scopeLabel: 'selected',
      exitSelectMode: true,
    );
  }

  Future<void> _deleteAll() async {
    await _deletePaths(_cachedImagePaths, scopeLabel: 'all');
  }

  Future<void> _deletePaths(
    List<String> paths, {
    required String scopeLabel,
    bool exitSelectMode = false,
  }) async {
    if (_document == null || paths.isEmpty) return;

    final validPaths = paths.where((path) => File(path).existsSync()).toList();
    if (validPaths.isEmpty) return;

    final deleteCount = validPaths.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $deleteCount image${deleteCount == 1 ? '' : 's'}?'),
        content: Text(
          'This will delete $scopeLabel image${deleteCount == 1 ? '' : 's'} permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(documentServiceProvider)
          .deleteImages(widget.docId, validPaths);
      if (_document != null) {
        await _loadImages(_document!);
      }

      setState(() {
        _selectedImages.removeWhere((path) => validPaths.contains(path));
      });

      if (!mounted) return;
      showSnackBar(
        context,
        'Deleted $deleteCount image${deleteCount == 1 ? '' : 's'}',
      );
      if (exitSelectMode && _selectMode) {
        _toggleSelectMode();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to delete: $e', isError: true);
      }
    }
  }

  Future<void> _shareSelected() async {
    await _sharePaths(
      _selectedImages.toList(),
      scopeLabel: 'selected images',
      exitSelectMode: true,
    );
  }

  Future<void> _shareAll() async {
    await _sharePaths(_cachedImagePaths, scopeLabel: 'all images');
  }

  Future<void> _sharePaths(
    List<String> paths, {
    required String scopeLabel,
    bool exitSelectMode = false,
  }) async {
    if (paths.isEmpty) return;

    try {
      final xFiles = paths
          .where((path) => File(path).existsSync())
          .map(XFile.new)
          .toList();
      if (xFiles.isEmpty) return;

      await SharePlus.instance.share(
        ShareParams(
          files: xFiles,
          subject: _document?.title ?? 'Shared Images',
          text: 'Sharing $scopeLabel',
        ),
      );

      if (mounted && exitSelectMode && _selectMode) {
        _toggleSelectMode();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to share: $e', isError: true);
      }
    }
  }

  Future<void> _editSelected() async {
    await _editImages(
      _selectedImages.toList(),
      applyToAll: false,
      pickerTitle: 'Edit selected images',
      successScope: 'selected pages',
    );
    if (_selectedImages.isNotEmpty && mounted) {
      _toggleSelectMode();
    }
  }

  Future<void> _editAllPages() async {
    await _editImages(
      _cachedImagePaths,
      applyToAll: true,
      pickerTitle: 'Edit all images',
      successScope: 'all pages',
    );
  }

  Future<void> _editImages(
    List<String> paths, {
    required bool applyToAll,
    String? pickerTitle,
    String? successScope,
  }) async {
    if (_document == null || paths.isEmpty || _isEditing) return;

    final mode = await _pickFilterMode(
      title:
          pickerTitle ??
          (applyToAll ? 'Edit all pages' : 'Edit selected pages'),
    );
    if (mode == null) return;

    setState(() => _isEditing = true);
    var edited = 0;
    var failed = 0;

    try {
      for (final path in paths) {
        final ok = await _applyFilterToImage(path, mode);
        if (ok) {
          edited++;
        } else {
          failed++;
        }
      }

      if (_document != null) {
        await _loadImages(_document!);
      }

      if (!mounted) return;
      if (edited > 0) {
        final scope =
            successScope ?? (applyToAll ? 'all pages' : 'selected pages');
        final failNote = failed > 0 ? ' ($failed failed)' : '';
        showSnackBar(context, 'Edited $scope with ${mode.label}$failNote');
      } else {
        showSnackBar(context, 'No pages could be edited', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isEditing = false);
      }
    }
  }

  Future<void> _showSingleImageActions(String imagePath) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_fix_high_rounded),
              title: const Text('Edit this image'),
              onTap: () {
                Navigator.pop(ctx);
                _editImages(
                  [imagePath],
                  applyToAll: false,
                  pickerTitle: 'Edit this image',
                  successScope: 'image',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Create PDF from this image'),
              onTap: () {
                Navigator.pop(ctx);
                _createPdfForPaths([imagePath], scopeLabel: 'this');
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share this image'),
              onTap: () {
                Navigator.pop(ctx);
                _sharePaths([imagePath], scopeLabel: 'this image');
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: const Text('Delete this image'),
              onTap: () {
                Navigator.pop(ctx);
                _deletePaths([imagePath], scopeLabel: 'this');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<FilterMode?> _pickFilterMode({required String title}) async {
    if (!mounted) return null;
    return showModalBottomSheet<FilterMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            ...FilterMode.values
                .where((mode) => mode != FilterMode.original)
                .map(
                  (mode) => ListTile(
                    leading: Icon(mode.icon),
                    title: Text(mode.label),
                    onTap: () => Navigator.pop(ctx, mode),
                  ),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<bool> _applyFilterToImage(String imagePath, FilterMode mode) async {
    if (!File(imagePath).existsSync()) return false;

    final tempPath = p.join(
      p.dirname(imagePath),
      '.edit_${DateTime.now().microsecondsSinceEpoch}_${p.basenameWithoutExtension(imagePath)}.jpg',
    );

    try {
      final processedPath = await compute(
        applyFilter,
        FilterArgs(
          inputPath: imagePath,
          outputPath: tempPath,
          filterName: mode.name,
        ),
      );

      await File(processedPath).copy(imagePath);
      final tempFile = File(processedPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return true;
    } catch (_) {
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return false;
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
          if (_reorderMode)
            _toggleReorderMode();
          else if (_selectMode)
            _toggleSelectMode();
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
              (_reorderMode || _selectMode) ? Icons.close : Icons.arrow_back,
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
          title: Text(
            _reorderMode
                ? 'Reorder pages'
                : _selectMode
                ? '${_selectedImages.length} selected'
                : (_document?.title ?? 'Document'),
          ),
          actions: [
            if (_selectMode) ...[
              IconButton(
                icon: const Icon(Icons.select_all),
                onPressed: _selectedImages.length == imagePaths.length
                    ? _deselectAll
                    : _selectAll,
                tooltip: _selectedImages.length == imagePaths.length
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
                  color: _document?.isFavourite == true ? cs.error : null,
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
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  onPressed: _isEditing ? null : _editAllPages,
                  tooltip: 'Edit all pages',
                ),
              if (hasImages)
                IconButton(
                  icon: const Icon(Icons.checklist_rounded),
                  onPressed: _isEditing ? null : _toggleSelectMode,
                  tooltip: 'Select pages',
                ),
              if (_document?.pdfPath != null)
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  onPressed: () =>
                      context.push(AppRoutes.viewerPath(widget.docId)),
                  tooltip: 'View PDF',
                ),
              PopupMenuButton<_MenuAction>(
                onSelected: (action) => _handleMenu(action),
                itemBuilder: (_) => [
                  // Fix: only show Reorder when there are pages to reorder
                  if (hasImages)
                    const PopupMenuItem(
                      value: _MenuAction.reorder,
                      child: Text('Reorder pages'),
                    ),
                  const PopupMenuItem(
                    value: _MenuAction.rename,
                    child: Text('Rename'),
                  ),
                  const PopupMenuItem(
                    value: _MenuAction.delete,
                    child: Text('Delete document'),
                  ),
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
                subtitle: 'Tap the button below to scan pages.',
              )
            : _reorderMode
            // ── Reorder mode: vertically reorderable list ──
            ? ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                // Fix: disable default handles; we supply our own
                // via ReorderableDragStartListener so there is
                // only one handle per row, not two.
                buildDefaultDragHandles: false,
                itemCount: imagePaths.length,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) newIndex--;
                  final reordered = List<String>.from(imagePaths);
                  final item = reordered.removeAt(oldIndex);
                  reordered.insert(newIndex, item);
                  setState(() => _cachedImagePaths = reordered);
                  await ref
                      .read(documentServiceProvider)
                      .reorderImages(widget.docId, reordered);
                },
                itemBuilder: (context, index) {
                  return _ReorderTile(
                    key: ValueKey(imagePaths[index]),
                    imagePath: imagePaths[index],
                    index: index,
                  );
                },
              )
            // ── Normal / select mode: 3-column grid ──
            : GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: imagePaths.length,
                itemBuilder: (context, index) {
                  final imagePath = imagePaths[index];
                  return _ImageTile(
                    imagePath: imagePath,
                    isSelected: _selectedImages.contains(imagePath),
                    selectMode: _selectMode,
                    onTap: () {
                      if (_selectMode) {
                        _toggleImageSelection(imagePath);
                      } else {
                        _openFullScreen(context, imagePaths, index);
                      }
                    },
                    onLongPress: () {
                      if (_selectMode) {
                        _toggleImageSelection(imagePath);
                      } else {
                        _showSingleImageActions(imagePath);
                      }
                    },
                  );
                },
              ),
        persistentFooterButtons: _isEditing
            ? const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                      SizedBox(width: 10),
                      Text('Applying edits...'),
                    ],
                  ),
                ),
              ]
            : null,
        bottomNavigationBar: hasImages && !_reorderMode
            ? Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ActionChip(
                          icon: Icons.auto_fix_high_rounded,
                          label: _selectMode ? 'Edit Selected' : 'Edit All',
                          color: cs.tertiary,
                          onPressed: _isEditing
                              ? null
                              : (_selectMode ? _editSelected : _editAllPages),
                        ),
                        _ActionChip(
                          icon: Icons.picture_as_pdf,
                          label: _selectMode ? 'PDF Selected' : 'PDF All',
                          color: cs.secondary,
                          onPressed: _isEditing
                              ? null
                              : (_selectMode ? _createPdf : _createPdfAll),
                        ),
                        _ActionChip(
                          icon: Icons.share,
                          label: _selectMode ? 'Share Selected' : 'Share All',
                          color: cs.primary,
                          onPressed: _isEditing
                              ? null
                              : (_selectMode ? _shareSelected : _shareAll),
                        ),
                        _ActionChip(
                          icon: Icons.delete_outline,
                          label: _selectMode ? 'Delete Selected' : 'Delete All',
                          color: cs.error,
                          onPressed: _isEditing
                              ? null
                              : (_selectMode ? _deleteSelected : _deleteAll),
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
                  await context.push('/camera?docId=${widget.docId}');
                  if (mounted) await _loadDocument();
                },
                icon: const Icon(Icons.add_a_photo),
                label: const Text('Scan Pages'),
              ),
      ),
    );
  }

  void _openFullScreen(
    BuildContext context,
    List<String> paths,
    int initialIndex,
  ) {
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (_) => _FullScreenImageViewer(
              imagePaths: paths,
              initialIndex: initialIndex,
              title: _document?.title ?? 'Document',
            ),
          ),
        )
        .then((wasEdited) async {
          if (wasEdited == true && _document != null && mounted) {
            await _loadImages(_document!);
          }
        });
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
    final ctrl = TextEditingController(text: _document!.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename document'),
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
            child: const Text('Rename'),
          ),
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
      if (mounted) showSnackBar(context, 'Failed to rename: $e', isError: true);
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref.read(documentServiceProvider).deleteDocument(widget.docId);
      if (mounted) {
        context.pop();
        showSnackBar(context, 'Document deleted');
      }
    } catch (e) {
      if (mounted) showSnackBar(context, 'Failed to delete: $e', isError: true);
    }
  }
}

// ---------------------------------------------------------------------------
// Reorder mode tile — drag handle via ReorderableDragStartListener
// Fix: buildDefaultDragHandles is false so this is the ONLY handle,
// avoiding the double-handle overlap from the previous implementation.
// ---------------------------------------------------------------------------
class _ReorderTile extends StatelessWidget {
  const _ReorderTile({super.key, required this.imagePath, required this.index});

  final String imagePath;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 72,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late int _currentIndex;
  late PageController _pageController;
  bool _isEditing = false;
  bool _editedAny = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_editedAny),
        ),
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high_rounded),
            tooltip: 'Edit page',
            onPressed: _isEditing ? null : _editCurrentPage,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_currentIndex + 1} / ${widget.imagePaths.length}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imagePaths.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
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
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: _isEditing
          ? const SizedBox(
              width: 56,
              height: 56,
              child: Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          : null,
    );
  }

  Future<void> _editCurrentPage() async {
    final mode = await _pickFilterMode(context);
    if (mode == null) return;

    setState(() => _isEditing = true);
    final imagePath = widget.imagePaths[_currentIndex];
    final edited = await _applyFilterToImage(imagePath, mode);

    if (!mounted) return;
    setState(() {
      _isEditing = false;
      _editedAny = _editedAny || edited;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          edited ? 'Page edited with ${mode.label}' : 'Failed to edit page',
        ),
      ),
    );
  }

  Future<FilterMode?> _pickFilterMode(BuildContext context) {
    return showModalBottomSheet<FilterMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Edit this page',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ...FilterMode.values
                .where((mode) => mode != FilterMode.original)
                .map(
                  (mode) => ListTile(
                    leading: Icon(mode.icon),
                    title: Text(mode.label),
                    onTap: () => Navigator.pop(ctx, mode),
                  ),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<bool> _applyFilterToImage(String imagePath, FilterMode mode) async {
    if (!File(imagePath).existsSync()) return false;

    final tempPath = p.join(
      p.dirname(imagePath),
      '.edit_${DateTime.now().microsecondsSinceEpoch}_${p.basenameWithoutExtension(imagePath)}.jpg',
    );

    try {
      final processedPath = await compute(
        applyFilter,
        FilterArgs(
          inputPath: imagePath,
          outputPath: tempPath,
          filterName: mode.name,
        ),
      );

      await File(processedPath).copy(imagePath);
      final tempFile = File(processedPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return true;
    } catch (_) {
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return false;
    }
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
                child: Icon(Icons.broken_image, color: cs.onSurfaceVariant),
              ),
            ),
          ),
          if (selectMode)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary : cs.onSurface.withOpacity(0.54),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: cs.onPrimary,
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
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: (onPressed == null ? Colors.grey : color).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: onPressed == null ? Colors.grey : color,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: onPressed == null ? Colors.grey : color,
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
