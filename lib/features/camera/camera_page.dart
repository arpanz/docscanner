// lib/features/camera/camera_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart' show Value;
import '../../core/utils.dart';
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
    // Request permissions and launch scanner
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissionsAndScan());
  }

  void _safePop() {
    if (mounted && context.canPop()) {
      context.pop();
    }
  }

  Future<void> _requestPermissionsAndScan() async {
    final permissionService = ref.read(permissionServiceProvider);
    
    // Request camera permission
    final hasCamera = await permissionService.requestCamera();
    if (!hasCamera) {
      if (!mounted) return;
      showSnackBar(
        context,
        'Camera permission is required to scan documents',
        isError: true,
      );
      _safePop();
      return;
    }

    // Request storage permission
    final hasStorage = await permissionService.requestStorage();
    if (!hasStorage) {
      if (!mounted) return;
      showSnackBar(
        context,
        'Storage permission is required to save scanned documents',
        isError: true,
      );
      _safePop();
      return;
    }

    // Permissions granted, proceed with scan
    if (mounted) await _scan();
  }

  Future<void> _scan() async {
    try {
      final PdfScanResult? result = await FlutterDocScanner()
          .getScannedDocumentAsPdf(page: 10);

      if (!mounted) return;
      if (result == null) {
        _safePop();
        return;
      }

      final pdfPath = result.pdfUri;
      debugPrint('PDF path: $pdfPath');

      final svc = ref.read(documentServiceProvider);

      // Handle adding pages to existing document
      if (widget.existingDocId != null) {
        await _appendToExistingDocument(svc, pdfPath, result.pageCount);
        return;
      }

      // Create new document from PDF
      final title = await _promptTitle();
      if (!mounted) return;
      // Use the returned title (or default if cancelled)
      final finalTitle = title == null || title.isEmpty ? 'Document ${formatDate(DateTime.now())}' : title;

      final docId = await svc.createDocumentFromPdf(
        title: finalTitle,
        pdfPath: pdfPath,
        pageCount: result.pageCount,
      );
      if (mounted) context.go('/viewer/$docId');

    } on DocScanException catch (e) {
      if (mounted) {
        showSnackBar(context, 'Scan failed: ${e.message}', isError: true);
        _safePop();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Error: $e', isError: true);
        _safePop();
      }
    }
  }

  Future<void> _appendToExistingDocument(
    DocumentService svc,
    String pdfPath,
    int pageCount,
  ) async {
    // Clean the path in case `file://` is still prefixed
    final cleanPath = cleanFilePath(pdfPath);

    // Get existing document to check if it's PDF-based
    final doc = await ref
        .read(documentsDaoProvider)
        .getDocument(widget.existingDocId!);

    if (!mounted) return;

    if (doc == null) {
      showSnackBar(context, 'Document not found', isError: true);
      _safePop();
      return;
    }

    // Append images to existing document folder
    try {
      final svc = ref.read(documentServiceProvider);
      await svc.addImages(widget.existingDocId!, [cleanPath]);

      if (mounted) {
        showSnackBar(context, 'Added $pageCount page(s) to document');
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
    // Get existing documents to check for duplicates
    final docs = await ref
        .read(documentsDaoProvider)
        .watchAllDocuments()
        .first;
    
    final baseTitle = 'Document ${formatDate(DateTime.now())}';
    String title = baseTitle;
    int counter = 1;
    
    while (docs.any((d) => d.title == title)) {
      title = '$baseTitle ($counter)';
      counter++;
    }
    
    final ctrl = TextEditingController(text: title);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true, // Allow dismissal
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
    // Return title even if dialog was dismissed (user can edit later)
    return result ?? title;
  }

  @override
  Widget build(BuildContext context) {
    // Briefly shown while the native scanner is launching
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
      body: const Center(child: CircularProgressIndicator(color: Color(0xFF5C4BF5))),
    );
  }
}
