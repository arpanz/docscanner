// lib/features/manager/document_folder_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
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

  @override
  ConsumerState<DocumentFolderPage> createState() => _DocumentFolderPageState();
}

class _DocumentFolderPageState extends ConsumerState<DocumentFolderPage> {
  bool _selectMode = false;
  final Set<String> _selectedImages = {};
  Document? _document;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDocument();
    });
  }

  Future<void> _loadDocument() async {
    final doc = await ref.read(documentsDaoProvider).getDocument(widget.docId);
    if (mounted) {
      setState(() => _document = doc);
    }
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) {
        _selectedImages.clear();
      }
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

  void _selectAll() {
    if (_document == null) return;
    setState(() {
      _selectedImages.addAll(_imagePaths);
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedImages.clear();
    });
  }

  List<String> get _imagePaths {
    if (_document == null) return [];
    final folder = Directory(_document!.folderPath);
    if (!folder.existsSync()) return [];
    return folder
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.toLowerCase().endsWith('.jpg') ||
            f.path.toLowerCase().endsWith('.jpeg') ||
            f.path.toLowerCase().endsWith('.png'))
        .map((f) => f.path)
        .toList()
      ..sort((a, b) => a.compareTo(b));
  }

  Future<void> _createPdf() async {
    if (_document == null || _selectedImages.isEmpty) return;

    try {
      final pdfService = ref.read(pdfServiceProvider);
      final docService = ref.read(documentServiceProvider);

      // Build PDF
      final pdfFile = await pdfService.buildPdf(
        title: _document!.title,
        imagePaths: _selectedImages.toList(),
        pageFormat: PdfPageFormat.a4,
      );

      // Save PDF to documents directory
      final docsDir = await getApplicationDocumentsDirectory();
      final savedPdf = await pdfFile.copy(
        '${docsDir.path}/${_sanitizeFileName(_document!.title)}.pdf',
      );

      // Update document with PDF path
      await docService.renameDocument(widget.docId, _document!.title);
      await ref.read(documentsDaoProvider).updateDocument(
            DocumentsCompanion(
              id: Value(widget.docId),
              pdfPath: Value(savedPdf.path),
            ),
          );

      if (mounted) {
        showSnackBar(context, 'PDF created successfully');
        _toggleSelectMode();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to create PDF: $e', isError: true);
      }
    }
  }

  Future<void> _deleteSelected() async {
    if (_document == null || _selectedImages.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_selectedImages.length} image(s)?'),
        content: Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final docService = ref.read(documentServiceProvider);
      await docService.deleteImages(widget.docId, _selectedImages.toList());
      await _loadDocument();

      if (mounted) {
        showSnackBar(context, 'Deleted ${_selectedImages.length} image(s)');
        _toggleSelectMode();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to delete: $e', isError: true);
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

      if (mounted) {
        _toggleSelectMode();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to share: $e', isError: true);
      }
    }
  }

  String _sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imagePaths = _imagePaths;

    return Scaffold(
      backgroundColor: const Color(0xFFE8E8E8),
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
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
              tooltip: _selectedImages.length == imagePaths.length
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
              icon: const Icon(Icons.select_all),
              onPressed: _toggleSelectMode,
              tooltip: 'Select images',
            ),
            PopupMenuButton<_MenuAction>(
              onSelected: (action) => _handleMenu(action),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _MenuAction.rename,
                  child: Text('Rename'),
                ),
                PopupMenuItem(
                  value: _MenuAction.delete,
                  child: Text('Delete document'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: imagePaths.isEmpty
          ? const AppEmptyState(
              icon: Icons.photo_library_outlined,
              title: 'No images',
              subtitle: 'Add images using the camera button below.',
            )
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
      bottomNavigationBar: _selectMode && _selectedImages.isNotEmpty
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ActionChip(
                        icon: Icons.picture_as_pdf,
                        label: 'PDF',
                        color: Colors.red,
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
        onPressed: () => context.push('/camera?docId=${widget.docId}'),
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Add Images'),
      ),
    );
  }

  Future<void> _handleMenu(_MenuAction action) async {
    if (_document == null) return;

    switch (action) {
      case _MenuAction.rename:
        await _renameDocument();
        break;
      case _MenuAction.delete:
        await _deleteDocument();
        break;
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
          decoration: const InputDecoration(
            hintText: 'Document name',
          ),
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
      final docService = ref.read(documentServiceProvider);
      await docService.renameDocument(widget.docId, newTitle);
      await _loadDocument();
      if (mounted) {
        showSnackBar(context, 'Document renamed');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to rename: $e', isError: true);
      }
    }
  }

  Future<void> _deleteDocument() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
          'Are you sure you want to delete "${_document!.title}"? This will remove all images and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final docService = ref.read(documentServiceProvider);
      await docService.deleteDocument(widget.docId);
      if (mounted) {
        context.pop(); // Go back to manager
        showSnackBar(context, 'Document deleted');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to delete: $e', isError: true);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Image Tile Widget
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
                  color: isSelected ? Colors.blue : Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
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
// Action Chip Widget
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

// ---------------------------------------------------------------------------
// Menu Action Enum
// ---------------------------------------------------------------------------
enum _MenuAction { rename, delete }
