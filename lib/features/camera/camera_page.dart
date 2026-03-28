// lib/features/camera/camera_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../core/router.dart';
import '../../database/app_database.dart';
import '../../shared/services/document_service.dart';
import '../../shared/services/permission_service.dart';

class CameraPage extends ConsumerStatefulWidget {
  const CameraPage({super.key, this.existingDocId});
  final int? existingDocId;

  @override
  ConsumerState<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends ConsumerState<CameraPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _requestPermissionsAndScan(),
    );
  }

  void _safePop() {
    if (mounted && context.canPop()) context.pop();
  }

  Future<void> _requestPermissionsAndScan() async {
    final permissionService = ref.read(permissionServiceProvider);

    final hasCamera = await permissionService.requestCamera();
    if (!hasCamera) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Camera permission is required to scan documents'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: () => permissionService.openSettings(),
            ),
          ),
        );
      _safePop();
      return;
    }

    if (mounted) await _scan();
  }

  Future<void> _scan() async {
    try {
      final ImageScanResult? result = await FlutterDocScanner()
          .getScannedDocumentAsImages(page: AppConstants.maxPagesPerDocument);

      if (!mounted) return;
      if (result == null) {
        _safePop();
        return;
      }

      final imagePaths = result.images;
      final svc = ref.read(documentServiceProvider);

      if (widget.existingDocId != null) {
        await _appendToExistingDocument(svc, imagePaths);
        return;
      }

      final title = await _promptTitle();
      if (!mounted) return;
      final finalTitle = (title == null || title.isEmpty)
          ? 'Scan ${formatDate(DateTime.now())}'
          : title;

      final docId = await svc.createDocument(
        title: finalTitle,
        imagePaths: imagePaths,
      );

      if (mounted) {
        HapticFeedback.lightImpact();
        // Replace camera route so back from folder returns to previous page.
        context.pushReplacement(AppRoutes.folderPath(docId));
      }
    } on DocScanException {
      if (mounted) {
        showSnackBar(context, 'Scanning was cancelled or could not finish.', isError: true);
        _safePop();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
          context,
          userFacingError(e, fallback: 'Something went wrong while scanning.'),
          isError: true,
        );
        _safePop();
      }
    }
  }

  Future<void> _appendToExistingDocument(
    DocumentService svc,
    List<String> imagePaths,
  ) async {
    final doc = await ref
        .read(documentsDaoProvider)
        .getDocument(widget.existingDocId!);

    if (!mounted) return;
    if (doc == null) {
      showSnackBar(context, 'Document not found', isError: true);
      _safePop();
      return;
    }

    try {
      await svc.addImages(widget.existingDocId!, imagePaths);
      final pageCount = imagePaths.length;

      if (mounted) {
        showSnackBar(
          context,
          'Added $pageCount page${pageCount == 1 ? '' : 's'} to document',
        );
        _safePop();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to add pages: $e', isError: true);
        _safePop();
      }
    }
  }

  Future<String?> _promptTitle() async {
    List<Document> docs;
    try {
      docs = await ref
          .read(documentsDaoProvider)
          .watchAllDocuments()
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => []);
    } catch (_) {
      docs = [];
    }

    final baseTitle = 'Scan ${formatDate(DateTime.now())}';
    String title = baseTitle;
    int counter = 1;
    while (docs.any((d) => d.title == title)) {
      title = '$baseTitle ($counter)';
      counter++;
    }

    if (!mounted) return title;
    final ctrl = TextEditingController(text: title);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Name your document'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Document name',
            helperText: 'Leave empty to use default',
          ),
        ),
        actions: [
          TextButton(
            // Fix: "Use Default" always returns the generated title,
            // ignoring any edits the user may have made.
            onPressed: () => Navigator.pop(ctx, title),
            child: const Text('Use Default'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result ?? title;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _safePop,
        ),
      ),
      body: const Center(
        child: CircularProgressIndicator(color: Color(0xFF5C4BF5)),
      ),
    );
  }
}
