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

  /// Registered as a GoRouter observer in router.dart so didPopNext fires.
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  @override
  ConsumerState<DocumentFolderPage> createState() =>
      _DocumentFolderPageState();
}

class _DocumentFolderPageState extends ConsumerState<DocumentFolderPage>
    with RouteAware {
  bool _selectMode = false;
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

  /// Fires when user pops back to this page (e.g. from camera).
  @override
  void didPopNext() => _loadDocument();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadDocument());
  }

  Future<void> _loadDocument() async {
    final doc =
        await ref.read(documentsDaoProvider).getDocument(widget.docId);
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
      if (!_selectMode) _selectedImages.clear();
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
    if (_document == null || _selectedImages.isEmpty) return;

    // Filter to only paths that still exist on disk
    final validPaths = _selectedImages
        .where((path) => File(path).existsSync())
        .toList();

    if (validPaths.isEmpty) {
      if (mounted) {
        showSnackBar(context,
            'No valid images selected — some may have been deleted',
            isError: true);
      }
      return;
    }

    try {
      final pdfService = ref.read(pdfServiceProvider);
      final tempPdf = await pdfService.buildPdf(
        title: _document!.title,
        imagePaths: validPaths,
        pageFormat: PdfPageFormat.a4,
      );

      // Save into the document's own folder (not app root)
      await ref
          .read(documentServiceProvider)
          .savePdfToDocumentFolder(widget.docId, tempPdf);

      if (mounted) {
        showSnackBar(context, 'PDF created successfully');
        _toggleSelectMode();
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_selectedImages.length} image(s)?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(documentServiceProvider)
          .deleteImages(widget.docId, _selectedImages.toList());

      if (_document != null) await _loadImages(_document!.folderPath);

      // Remove deleted paths from selection so no stale refs remain
      setState(() {
        _selectedImages
            .removeWhere((p) => !_cachedImagePaths.contains(p));
      });

      if (mounted) {
        showSnackBar(context,
            'Deleted ${_selectedImages.length} image(s)');
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
          .map((path) => XFile(path, mimeType: 'image/jpeg'))
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

  String _sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imagePaths = _cachedImagePaths;

    return Scaffold(
      backgroundColor: const Color(0xFFE8E8E8),
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
          },
        ),
        title: Text(_document?.title ?? 'Document'),
        actions: [
          if (_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _selectedImages.length == imagePaths.length
                  ? _deselectAll
                  : _selectAll,
              tooltip:
                  _selectedImages.length == imagePaths.length
                      ? 'Deselect all'
                      : 'Select all',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleSelectMode,
              tooltip: 'Done',
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              onPressed: _toggleSelectMode,
              tooltip: 'Select images',
            ),
            PopupMenuButton<_MenuAction>(
              onSelected: (action) => _handleMenu(action),
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: _MenuAction.rename,
                    child: Text('Rename')),
                PopupMenuItem(
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
                  title: 'No images',
                  subtitle:
                      'Add images using the camera button below.',
                )
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
                      isSelected:
                          _selectedImages.contains(imagePath),
                      selectMode: _selectMode,
                      onTap: () {
                        if (_selectMode) {
                          _toggleImageSelection(imagePath);
                        } else {
                          _openFullScreen(
                              context, imagePaths, index);
                        }
                      },
                      onLongPress: () {
                        if (!_selectMode) {
                          _toggleSelectMode();
                          _toggleImageSelection(imagePath);
                        }
                      },
                    );
                  },
                ),
      bottomNavigationBar:
          _selectMode && _selectedImages.isNotEmpty
              ? Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
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
                            color: theme.colorScheme.primary,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context
            .push('/camera?docId=${widget.docId}')
            .then((_) => _loadDocument()),
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Add Images'),
      ),
    );
  }

  void _openFullScreen(
      BuildContext context, List<String> paths, int initialIndex) {
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
          decoration:
              const InputDecoration(hintText: 'Document name'),
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
    return Scaffold(
      backgroundColor: const Color(0xFFE8E8E8),
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
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
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: Image.file(
                    File(widget.imagePaths[i]),
                    fit: BoxFit.contain,
                    width: double.infinity,
                    errorBuilder: (ctx, err, _) => Center(
                      child: Text(
                        'Cannot load page ${i + 1}',
                        style: const TextStyle(
                            color: Colors.grey),
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
// Image Tile
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
                color: Colors.grey[300],
                child: const Icon(Icons.broken_image),
              ),
            ),
          ),
          if (selectMode)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                decoration: BoxDecoration(
                  color:
                      isSelected ? Colors.blue : Colors.black54,
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

enum _MenuAction { rename, delete }
