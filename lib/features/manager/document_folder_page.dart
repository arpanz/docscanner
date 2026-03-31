// lib/features/manager/document_folder_page.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_prefs.dart';
import '../../core/router.dart';
import '../../core/utils.dart';
import '../../database/app_database.dart';
import '../../shared/services/document_service.dart';
import '../../shared/services/ocr_service.dart';
import '../../shared/services/pdf_service.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../camera/widgets/crop_enhance_sheet.dart';

final Map<String, _ImageItemDetails> _imageDetailsCache = {};

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
  Map<String, _ImageItemDetails> _imageDetailsByPath = {};
  bool _imagesLoaded = false;
  bool _isEditing = false;
  String? _editProgressText;

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
          context.push(AppRoutes.viewerPath(widget.docId));
        }
      });
      return;
    }

    final retainedDetails = <String, _ImageItemDetails>{
      for (final path in paths)
        if (_imageDetailsByPath[path] != null) path: _imageDetailsByPath[path]!,
    };

    for (final path in paths) {
      final cachedDetails = _getCachedImageDetails(path);
      if (cachedDetails != null) {
        retainedDetails[path] = cachedDetails;
      }
    }

    setState(() {
      _cachedImagePaths = paths;
      _imageDetailsByPath = retainedDetails;
      _imagesLoaded = true;
    });

    final missingPaths = paths
        .where((path) => !retainedDetails.containsKey(path))
        .toList();
    if (missingPaths.isEmpty) return;

    final rawDetails = await compute(_readImageDetails, missingPaths);
    if (!mounted || !listEquals(paths, _cachedImagePaths)) return;

    final computedDetails = {
      for (final raw in rawDetails)
        raw['path']! as String: _ImageItemDetails.fromMap(raw),
    };
    _imageDetailsCache.addAll(computedDetails);

    setState(() {
      _imageDetailsByPath = {..._imageDetailsByPath, ...computedDetails};
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
        title: Text(
          'Create PDF',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
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
    HapticFeedback.mediumImpact();

    try {
      final pageSize = PdfPageSizeOption.values.firstWhere(
        (option) => option.name == ref.read(pageSizePreferenceProvider),
        orElse: () => PdfPageSizeOption.a4,
      );
      final pdfService = ref.read(pdfServiceProvider);
      final tempPdf = await pdfService.buildPdf(
        title: _document!.title,
        imagePaths: validPaths,
        pageFormat: pageSize == PdfPageSizeOption.letter
            ? PdfPageFormat.letter
            : PdfPageFormat.a4,
      );

      await ref
          .read(documentServiceProvider)
          .savePdfToDocumentFolder(widget.docId, tempPdf);
      await _loadDocument();

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
            action: SnackBarAction(label: 'View', onPressed: _viewPdf),
          ),
        );
    } catch (e, st) {
      debugPrint('PDF creation failed for doc ${widget.docId}: $e');
      debugPrintStack(stackTrace: st);
      if (mounted) {
        showSnackBar(
          context,
          userFacingError(e, fallback: 'Could not create that PDF.'),
          isError: true,
        );
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
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
      for (final path in validPaths) {
        _imageDetailsCache.remove(path);
      }
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
        showSnackBar(
          context,
          userFacingError(e, fallback: 'Could not delete those pages.'),
          isError: true,
        );
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
        showSnackBar(
          context,
          userFacingError(e, fallback: 'Could not share those pages.'),
          isError: true,
        );
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

    final options = await _pickEditOptions(
      title:
          pickerTitle ??
          (applyToAll ? 'Edit all pages' : 'Edit selected pages'),
      previewImagePath: paths.first,
    );
    if (options == null) return;

    setState(() {
      _isEditing = true;
      _editProgressText = 'Applying edits... (0/${paths.length})';
    });
    var edited = 0;
    var failed = 0;

    try {
      for (var i = 0; i < paths.length; i++) {
        if (mounted) {
          setState(() {
            _editProgressText = 'Applying edits... (${i + 1}/${paths.length})';
          });
        }
        final ok = await _applyEditsToImage(paths[i], options);
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
        showSnackBar(context, 'Updated $scope$failNote');
      } else {
        showSnackBar(context, 'No pages could be edited', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEditing = false;
          _editProgressText = null;
        });
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
              title: Text(
                'Edit this image',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
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
              title: Text(
                'Create PDF from this image',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _createPdfForPaths([imagePath], scopeLabel: 'this');
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: Text(
                'Share this image',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _sharePaths([imagePath], scopeLabel: 'this image');
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: Text(
                'Extract text from this image',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _extractTextForPaths([
                  imagePath,
                ], noPagesMessage: 'This image is no longer available.');
              },
            ),
            if (_document?.pdfPath != null)
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(
                  'View current PDF',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _viewPdf();
                },
              ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                'Delete this image',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
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

  Future<ImageEditOptions?> _pickEditOptions({
    required String title,
    required String previewImagePath,
  }) async {
    if (!mounted) return null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: const Text(
          'Edits overwrite the current page. We will keep a one-time backup so you can restore the original later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return null;

    return showModalBottomSheet<ImageEditOptions>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ImageEditSheet(imagePath: previewImagePath),
    );
  }

  Future<bool> _applyEditsToImage(
    String imagePath,
    ImageEditOptions options,
  ) async {
    if (!File(imagePath).existsSync()) return false;

    final tempPath = p.join(
      p.dirname(imagePath),
      '.edit_${DateTime.now().microsecondsSinceEpoch}_${p.basenameWithoutExtension(imagePath)}.jpg',
    );

    try {
      await ref.read(documentServiceProvider).backupOriginalImage(imagePath);
      final processedPath = await compute(
        applyImageEditsFromMap,
        ImageEditArgs(
          inputPath: imagePath,
          outputPath: tempPath,
          options: options,
        ).toMap(),
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

  Future<void> _restoreOriginals() async {
    if (_document == null) return;
    final restored = await ref
        .read(documentServiceProvider)
        .restoreBackups(widget.docId, _document!.folderPath);
    await _loadDocument();
    if (!mounted) return;
    showSnackBar(
      context,
      restored == 0
          ? 'No saved originals were found.'
          : 'Restored $restored original page${restored == 1 ? '' : 's'}',
    );
  }

  Future<void> _extractText({bool useSelected = false}) async {
    if (_document == null) return;
    List<String> sourcePaths;
    if (useSelected && _selectedImages.isNotEmpty) {
      sourcePaths = _selectedImages.toList();
    } else {
      sourcePaths = _cachedImagePaths.isNotEmpty
          ? _cachedImagePaths
          : [if (_document?.coverImagePath != null) _document!.coverImagePath!];
    }
    await _extractTextForPaths(sourcePaths);
  }

  Future<void> _extractTextForPaths(
    List<String> sourcePaths, {
    String noPagesMessage = 'No pages available for text extraction.',
  }) async {
    if (sourcePaths.isEmpty) {
      showSnackBar(context, noPagesMessage, isError: true);
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AppProgressOverlay(message: 'Extracting text...'),
    );

    try {
      final text = await ref
          .read(ocrServiceProvider)
          .extractTextFromPaths(sourcePaths);
      if (!mounted) return;
      Navigator.pop(context);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => _OcrSheet(text: text),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showSnackBar(
        context,
        userFacingError(
          e,
          fallback: 'Could not extract text from these pages.',
        ),
        isError: true,
      );
    }
  }

  void _viewPdf() {
    if (_document?.pdfPath == null) return;
    context.push(AppRoutes.viewerPath(widget.docId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final imagePaths = _cachedImagePaths;
    final hasImages = imagePaths.isNotEmpty;
    final isListView = ref.watch(folderListPreferenceProvider);

    return PopScope(
      // Fix: if in reorder or select mode, back button exits the mode
      // instead of popping the page.
      canPop: !_reorderMode && !_selectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_reorderMode) {
            _toggleReorderMode();
          } else if (_selectMode) {
            _toggleSelectMode();
          }
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
                        if (!context.mounted) return;
                        showSnackBar(
                          context,
                          _document?.isFavourite == true
                              ? 'Added to favourites'
                              : 'Removed from favourites',
                        );
                      },
              ),
              if (hasImages)
                IconButton(
                  icon: Icon(
                    isListView
                        ? Icons.grid_view_rounded
                        : Icons.view_list_rounded,
                  ),
                  tooltip: isListView
                      ? 'Switch to grid view'
                      : 'Switch to list view',
                  onPressed: () => ref
                      .read(folderListPreferenceProvider.notifier)
                      .setValue(!isListView),
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
              PopupMenuButton<_MenuAction>(
                onSelected: (action) => _handleMenu(action),
                itemBuilder: (_) => [
                  // Fix: only show Reorder when there are pages to reorder
                  if (hasImages)
                    const PopupMenuItem(
                      value: _MenuAction.reorder,
                      child: Text('Reorder pages'),
                    ),
                  if (hasImages)
                    const PopupMenuItem(
                      value: _MenuAction.extractText,
                      child: Text('Extract text'),
                    ),
                  if (_document?.pdfPath != null)
                    const PopupMenuItem(
                      value: _MenuAction.viewPdf,
                      child: Text('View PDF'),
                    ),
                  const PopupMenuItem(
                    value: _MenuAction.restoreOriginals,
                    child: Text('Restore originals'),
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
                  HapticFeedback.mediumImpact();
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
            : isListView
            ? ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: imagePaths.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final imagePath = imagePaths[index];
                  return _ImageListTile(
                    imagePath: imagePath,
                    pageNumber: index + 1,
                    details: _imageDetailsByPath[imagePath],
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
            ? [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                      const SizedBox(width: 10),
                      Text(_editProgressText ?? 'Applying edits...'),
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
                      color: cs.shadow.withValues(alpha: 0.08),
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
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.05, 0.95, 1.0],
                      ).createShader(bounds),
                      blendMode: BlendMode.dstIn,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _ActionChip(
                              icon: Icons.auto_fix_high_rounded,
                              label: _selectMode ? 'Edit Selected' : 'Edit All',
                              color: cs.tertiary,
                              onPressed:
                                  (_isEditing ||
                                      (_selectMode && _selectedImages.isEmpty))
                                  ? null
                                  : (_selectMode
                                        ? _editSelected
                                        : _editAllPages),
                            ),
                            const SizedBox(width: 10),
                            _ActionChip(
                              icon: Icons.picture_as_pdf,
                              label: _selectMode ? 'PDF Selected' : 'PDF All',
                              color: cs.secondary,
                              onPressed:
                                  (_isEditing ||
                                      (_selectMode && _selectedImages.isEmpty))
                                  ? null
                                  : (_selectMode ? _createPdf : _createPdfAll),
                            ),
                            const SizedBox(width: 10),
                            _ActionChip(
                              icon: Icons.share,
                              label: _selectMode
                                  ? 'Share Selected'
                                  : 'Share All',
                              color: cs.primary,
                              onPressed:
                                  (_isEditing ||
                                      (_selectMode && _selectedImages.isEmpty))
                                  ? null
                                  : (_selectMode ? _shareSelected : _shareAll),
                            ),
                            if (_document?.pdfPath != null) ...[
                              const SizedBox(width: 10),
                              _ActionChip(
                                icon: Icons.visibility_outlined,
                                label: 'View PDF',
                                color: cs.primary,
                                onPressed: _viewPdf,
                              ),
                            ],
                            const SizedBox(width: 10),
                            _ActionChip(
                              icon: Icons.text_snippet_outlined,
                              label: _selectMode ? 'OCR Selected' : 'OCR All',
                              color: cs.primary,
                              onPressed:
                                  (_isEditing ||
                                      (_selectMode && _selectedImages.isEmpty))
                                  ? null
                                  : () =>
                                        _extractText(useSelected: _selectMode),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed:
                                  (_isEditing ||
                                      (_selectMode && _selectedImages.isEmpty))
                                  ? null
                                  : (_selectMode
                                        ? _deleteSelected
                                        : _deleteAll),
                              icon: Icon(Icons.delete_outline, color: cs.error),
                              label: Text(
                                _selectMode ? 'Delete Selected' : 'Delete All',
                                style: TextStyle(color: cs.error),
                              ),
                            ),
                          ],
                        ),
                      ),
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
              docId: widget.docId,
              imagePaths: paths,
              initialImageDetailsByPath: {
                for (final path in paths)
                  if (_imageDetailsByPath[path] != null)
                    path: _imageDetailsByPath[path]!,
              },
              initialIndex: initialIndex,
              title: _document?.title ?? 'Document',
              hasPdf: _document?.pdfPath != null,
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
        return;
      case _MenuAction.extractText:
        await _extractText();
        return;
      case _MenuAction.viewPdf:
        _viewPdf();
        return;
      case _MenuAction.restoreOriginals:
        await _restoreOriginals();
        return;
      case _MenuAction.rename:
        await _renameDocument();
        return;
      case _MenuAction.delete:
        await _deleteDocument();
        return;
    }
  }

  Future<void> _renameDocument() async {
    final ctrl = TextEditingController(text: _document!.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Rename document',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
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
      if (mounted) {
        showSnackBar(
          context,
          userFacingError(e, fallback: 'Could not rename this document.'),
          isError: true,
        );
      }
    }
  }

  Future<void> _deleteDocument() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete document?',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    HapticFeedback.mediumImpact();
    try {
      await ref.read(documentServiceProvider).deleteDocument(widget.docId);
      if (mounted) {
        context.pop();
        showSnackBar(context, 'Document deleted');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
          context,
          userFacingError(e, fallback: 'Could not delete this document.'),
          isError: true,
        );
      }
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
                errorBuilder: (context, error, stackTrace) => Icon(
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
class _FullScreenImageViewer extends ConsumerStatefulWidget {
  const _FullScreenImageViewer({
    required this.docId,
    required this.imagePaths,
    required this.initialImageDetailsByPath,
    required this.initialIndex,
    required this.title,
    required this.hasPdf,
  });

  final int docId;
  final List<String> imagePaths;
  final Map<String, _ImageItemDetails> initialImageDetailsByPath;
  final int initialIndex;
  final String title;
  final bool hasPdf;

  @override
  ConsumerState<_FullScreenImageViewer> createState() =>
      _FullScreenImageViewerState();
}

class _FullScreenImageViewerState
    extends ConsumerState<_FullScreenImageViewer> {
  late int _currentIndex;
  late PageController _pageController;
  late List<String> _imagePaths;
  late Map<String, _ImageItemDetails> _imageDetailsByPath;
  late bool _hasPdf;
  bool _isEditing = false;
  bool _editedAny = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _imagePaths = List<String>.from(widget.imagePaths);
    _imageDetailsByPath = Map<String, _ImageItemDetails>.from(
      widget.initialImageDetailsByPath,
    );
    _hasPdf = widget.hasPdf;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    final currentPath = _imagePaths.isEmpty ? null : _imagePaths[_currentIndex];
    final currentDetails = currentPath == null
        ? null
        : _imageDetailsByPath[currentPath];

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_editedAny),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title),
            Text(
              'Page ${_currentIndex + 1} of ${_imagePaths.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: _ViewerPageSummary(
              pageNumber: _currentIndex + 1,
              details: currentDetails,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.surface, cs.surfaceContainerLow],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.65),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.08),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _imagePaths.length,
                    onPageChanged: (i) => setState(() => _currentIndex = i),
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.all(18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: cs.shadow.withValues(alpha: 0.08),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 4.0,
                            child: Center(
                              child: Image.file(
                                File(_imagePaths[i]),
                                fit: BoxFit.contain,
                                width: double.infinity,
                                filterQuality: FilterQuality.high,
                                errorBuilder: (ctx, err, _) => Center(
                                  child: Text(
                                    'Cannot load page ${i + 1}',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _imagePaths.isEmpty
          ? null
          : Container(
              decoration: BoxDecoration(
                color: cs.surface,
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_imagePaths.length > 1)
                      SizedBox(
                        height: 102,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          scrollDirection: Axis.horizontal,
                          itemCount: _imagePaths.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final imagePath = _imagePaths[index];
                            return _ViewerThumbnail(
                              imagePath: imagePath,
                              pageNumber: index + 1,
                              isActive: index == _currentIndex,
                              onTap: () => _jumpToPage(index),
                            );
                          },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.05, 0.95, 1.0],
                        ).createShader(bounds),
                        blendMode: BlendMode.dstIn,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _ActionChip(
                                icon: Icons.auto_fix_high_rounded,
                                label: 'Edit',
                                color: cs.tertiary,
                                onPressed: _isEditing ? null : _editCurrentPage,
                              ),
                              const SizedBox(width: 10),
                              _ActionChip(
                                icon: Icons.picture_as_pdf,
                                label: 'PDF',
                                color: cs.secondary,
                                onPressed: _isEditing
                                    ? null
                                    : _createPdfForCurrentPage,
                              ),
                              const SizedBox(width: 10),
                              _ActionChip(
                                icon: Icons.share,
                                label: 'Share',
                                color: cs.primary,
                                onPressed: _isEditing ? null : _shareCurrentPage,
                              ),
                              if (_hasPdf) ...[
                                const SizedBox(width: 10),
                                _ActionChip(
                                  icon: Icons.visibility_outlined,
                                  label: 'View PDF',
                                  color: cs.primary,
                                  onPressed: _viewPdf,
                                ),
                              ],
                              const SizedBox(width: 10),
                              _ActionChip(
                                icon: Icons.text_snippet_outlined,
                                label: 'OCR',
                                color: cs.primary,
                                onPressed: _isEditing
                                    ? null
                                    : _extractTextForCurrentPage,
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: _isEditing ? null : _deleteCurrentPage,
                                icon: Icon(Icons.delete_outline, color: cs.error),
                                label: Text(
                                  'Delete',
                                  style: TextStyle(color: cs.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
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

  Future<void> _jumpToPage(int index) async {
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _editCurrentPage() async {
    final imagePath = _imagePaths[_currentIndex];
    final options = await showModalBottomSheet<ImageEditOptions>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ImageEditSheet(imagePath: imagePath),
    );
    if (options == null) return;

    setState(() => _isEditing = true);
    final edited = await _applyEditsToImage(imagePath, options);
    if (edited) {
      await _refreshDetailsForPath(imagePath);
    }

    if (!mounted) return;
    setState(() {
      _isEditing = false;
      _editedAny = _editedAny || edited;
    });

    showSnackBar(
      context,
      edited ? 'Page updated' : 'Failed to edit page',
      isError: !edited,
    );
  }

  Future<void> _createPdfForCurrentPage() async {
    final imagePath = _imagePaths[_currentIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Create PDF',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('Create a PDF from this page?'),
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
      final pageSize = PdfPageSizeOption.values.firstWhere(
        (option) => option.name == ref.read(pageSizePreferenceProvider),
        orElse: () => PdfPageSizeOption.a4,
      );
      final pdfService = ref.read(pdfServiceProvider);
      final tempPdf = await pdfService.buildPdf(
        title: widget.title,
        imagePaths: [imagePath],
        pageFormat: pageSize == PdfPageSizeOption.letter
            ? PdfPageFormat.letter
            : PdfPageFormat.a4,
      );

      await ref
          .read(documentServiceProvider)
          .savePdfToDocumentFolder(widget.docId, tempPdf);

      if (!mounted) return;
      setState(() {
        _editedAny = true;
        _hasPdf = true;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('PDF created successfully'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(label: 'View', onPressed: _viewPdf),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      showSnackBar(
        context,
        userFacingError(e, fallback: 'Could not create that PDF.'),
        isError: true,
      );
    }
  }

  Future<void> _shareCurrentPage() async {
    final imagePath = _imagePaths[_currentIndex];
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(imagePath)],
          subject: widget.title,
          text: 'Sharing this image',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showSnackBar(
        context,
        userFacingError(e, fallback: 'Could not share this page.'),
        isError: true,
      );
    }
  }

  Future<void> _extractTextForCurrentPage() async {
    final imagePath = _imagePaths[_currentIndex];
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AppProgressOverlay(message: 'Extracting text...'),
    );

    try {
      final text = await ref.read(ocrServiceProvider).extractTextFromPaths([
        imagePath,
      ]);
      if (!mounted) return;
      Navigator.pop(context);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => _OcrSheet(text: text),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showSnackBar(
        context,
        userFacingError(e, fallback: 'Could not extract text from this page.'),
        isError: true,
      );
    }
  }

  Future<void> _deleteCurrentPage() async {
    final imagePath = _imagePaths[_currentIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete this page?',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('This page will be deleted permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(documentServiceProvider).deleteImages(widget.docId, [
        imagePath,
      ]);
      _imageDetailsCache.remove(imagePath);
      if (!mounted) return;

      if (_imagePaths.length == 1) {
        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        _imagePaths.removeAt(_currentIndex);
        _imageDetailsByPath.remove(imagePath);
        if (_currentIndex >= _imagePaths.length) {
          _currentIndex = _imagePaths.length - 1;
        }
        _editedAny = true;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      });

      showSnackBar(context, 'Page deleted');
    } catch (e) {
      if (!mounted) return;
      showSnackBar(
        context,
        userFacingError(e, fallback: 'Could not delete this page.'),
        isError: true,
      );
    }
  }

  void _viewPdf() {
    context.push(AppRoutes.viewerPath(widget.docId));
  }

  Future<void> _refreshDetailsForPath(String imagePath) async {
    final rawDetails = await compute(_readImageDetails, [imagePath]);
    if (!mounted || rawDetails.isEmpty) return;

    final details = _ImageItemDetails.fromMap(rawDetails.first);
    _imageDetailsCache[imagePath] = details;

    setState(() {
      _imageDetailsByPath[imagePath] = details;
    });
  }

  Future<bool> _applyEditsToImage(
    String imagePath,
    ImageEditOptions options,
  ) async {
    if (!File(imagePath).existsSync()) return false;

    final tempPath = p.join(
      p.dirname(imagePath),
      '.edit_${DateTime.now().microsecondsSinceEpoch}_${p.basenameWithoutExtension(imagePath)}.jpg',
    );

    try {
      await ref.read(documentServiceProvider).backupOriginalImage(imagePath);
      final processedPath = await compute(
        applyImageEditsFromMap,
        ImageEditArgs(
          inputPath: imagePath,
          outputPath: tempPath,
          options: options,
        ).toMap(),
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

class _OcrSheet extends StatelessWidget {
  const _OcrSheet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final content = text.trim().isEmpty
        ? 'No text was detected on these pages.'
        : text.trim();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Extracted Text',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(child: SelectableText(content)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: content.startsWith('No text')
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: content));
                          showSnackBar(context, 'Text copied');
                        },
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: content.startsWith('No text')
                      ? null
                      : () async {
                          await SharePlus.instance.share(
                            ShareParams(text: content),
                          );
                        },
                  icon: const Icon(Icons.share),
                  label: const Text('Share text'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerPageSummary extends StatelessWidget {
  const _ViewerPageSummary({required this.pageNumber, required this.details});

  final int pageNumber;
  final _ImageItemDetails? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Page',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$pageNumber',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  details?.summaryLine ?? 'Loading page details...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  details?.updatedLine ?? 'Preparing image metadata',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerThumbnail extends StatelessWidget {
  const _ViewerThumbnail({
    required this.imagePath,
    required this.pageNumber,
    required this.isActive,
    required this.onTap,
  });

  final String imagePath;
  final int pageNumber;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 74,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isActive ? cs.primaryContainer : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive ? cs.primary : cs.outlineVariant,
            width: isActive ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$pageNumber',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: isActive ? cs.primary : cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageListTile extends StatelessWidget {
  const _ImageListTile({
    required this.imagePath,
    required this.pageNumber,
    required this.details,
    required this.isSelected,
    required this.selectMode,
    required this.onTap,
    required this.onLongPress,
  });

  final String imagePath;
  final int pageNumber;
  final _ImageItemDetails? details;
  final bool isSelected;
  final bool selectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primaryContainer.withValues(alpha: 0.42)
                : cs.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isSelected ? cs.primary : cs.outlineVariant,
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 86,
                      height: 112,
                      child: Image.file(
                        File(imagePath),
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, _) => Container(
                          color: cs.surfaceContainerHigh,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (selectMode)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary
                              : cs.scrim.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Page $pageNumber',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (!selectMode)
                          Icon(
                            Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      p.basename(imagePath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      details?.summaryLine ?? 'Loading image details...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      details?.updatedLine ?? 'Preparing image metadata',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageItemDetails {
  const _ImageItemDetails({
    required this.path,
    required this.extensionLabel,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.modifiedAt,
  });

  factory _ImageItemDetails.fromMap(Map<String, Object?> raw) {
    final modifiedAtMs = raw['modifiedAtMs'] as int?;
    return _ImageItemDetails(
      path: raw['path']! as String,
      extensionLabel: raw['extensionLabel']! as String,
      sizeBytes: raw['sizeBytes']! as int,
      width: raw['width']! as int,
      height: raw['height']! as int,
      modifiedAt: modifiedAtMs == null || modifiedAtMs <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(modifiedAtMs),
    );
  }

  final String path;
  final String extensionLabel;
  final int sizeBytes;
  final int width;
  final int height;
  final DateTime? modifiedAt;

  String get summaryLine {
    final parts = <String>[
      extensionLabel,
      if (width > 0 && height > 0) '${width}x$height',
      formatBytes(sizeBytes),
    ];
    return parts.join(' | ');
  }

  String get updatedLine {
    if (modifiedAt == null) return 'Date unavailable';
    return 'Updated ${formatDate(modifiedAt!)}';
  }
}

_ImageItemDetails? _getCachedImageDetails(String path) {
  final cached = _imageDetailsCache[path];
  if (cached == null) return null;

  try {
    final stat = File(path).statSync();
    final cachedModifiedAtMs = cached.modifiedAt?.millisecondsSinceEpoch ?? -1;
    final currentModifiedAtMs = stat.modified.millisecondsSinceEpoch;
    if (cached.sizeBytes == stat.size &&
        cachedModifiedAtMs == currentModifiedAtMs) {
      return cached;
    }
  } catch (_) {}

  _imageDetailsCache.remove(path);
  return null;
}

List<Map<String, Object?>> _readImageDetails(List<String> paths) {
  return paths.map((path) {
    final file = File(path);
    var sizeBytes = 0;
    int? modifiedAtMs;
    var width = 0;
    var height = 0;

    try {
      final stat = file.statSync();
      sizeBytes = stat.size;
      modifiedAtMs = stat.modified.millisecondsSinceEpoch;
    } catch (_) {}

    try {
      final decoded = img.decodeImage(file.readAsBytesSync());
      if (decoded != null) {
        width = decoded.width;
        height = decoded.height;
      }
    } catch (_) {}

    final extension = p.extension(path).replaceFirst('.', '').toUpperCase();

    return {
      'path': path,
      'extensionLabel': extension.isEmpty ? 'IMG' : extension,
      'sizeBytes': sizeBytes,
      'width': width,
      'height': height,
      'modifiedAtMs': modifiedAtMs,
    };
  }).toList();
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
                  color: isSelected
                      ? cs.primary
                      : cs.scrim.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
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
    final cs = Theme.of(context).colorScheme;
    final foreground = onPressed == null ? cs.outline : color;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: foreground,
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

enum _MenuAction {
  reorder,
  extractText,
  viewPdf,
  restoreOriginals,
  rename,
  delete,
}
