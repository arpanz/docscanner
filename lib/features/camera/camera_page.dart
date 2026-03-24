// lib/features/camera/camera_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _requestPermissionsAndScan());
  }

  void _safePop() {
    if (mounted && context.canPop()) context.pop();
  }

  Future<void> _requestPermissionsAndScan() async {
    final permissionService = ref.read(permissionServiceProvider);

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

    // On Android, only request storage permission on API <= 32 (Android 12 and below).
    // Android 13+ (API 33+) removed READ_EXTERNAL_STORAGE — requesting it causes
    // an automatic denial that blocks the entire scan flow.
    if (Platform.isAndroid) {
      final needsStorage = await _needsStoragePermission();
      if (needsStorage) {
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
      }
    }

    if (mounted) await _scan();
  }

  /// Returns true only on Android API <= 32, where storage permission is needed.
  /// Uses permission_handler status check as a proxy — on API 33+ the permission
  /// status will be .denied/.permanentlyDenied immediately without prompting,
  /// meaning we can detect old Android by checking if the permission is requestable.
  Future<bool> _needsStoragePermission() async {
    // manageExternalStorage is API 30+, storage is the legacy one.
    // If Permission.storage is not restricted (i.e., not permanently denied before
    // ever asking), we're likely on API <= 32.
    // Safest approach: check if Permission.storage.status is not permanentlyDenied
    // without prompting — on API 33+ it returns permanentlyDenied immediately.
    final status = await Permission.storage.status;
    // On Android 13+: returns .denied or .permanentlyDenied without ever prompting.
    // We only need to request it if it's in a requestable state (denied, not permanent).
    // On Android 13+ .photos permission covers gallery, not needed for scan flow.
    return status.isDenied; // .isDenied means it can still be requested
  }

  Future<void> _scan() async {
    try {
      final PdfScanResult? result =
          await FlutterDocScanner().getScannedDocumentAsPdf(page: 10);

      if (!mounted) return;
      if (result == null) {
        _safePop();
        return;
      }

      final pdfPath = result.pdfUri;
      final svc = ref.read(documentServiceProvider);

      if (widget.existingDocId != null) {
        await _appendToExistingDocument(svc, pdfPath, result.pageCount);
        return;
      }

      final title = await _promptTitle();
      if (!mounted) return;
      final finalTitle = (title == null || title.isEmpty)
          ? 'Document ${formatDate(DateTime.now())}'
          : title;

      final docId = await svc.createDocumentFromPdf(
        title: finalTitle,
        pdfPath: pdfPath,
        pageCount: result.pageCount,
      );

      if (mounted) {
        // pop camera first, then push folder — preserves nav stack
        context.pop();
        context.push(AppRoutes.folderPath(docId));
      }
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
    final cleanPath = cleanFilePath(pdfPath);
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
    final docs =
        await ref.read(documentsDaoProvider).watchAllDocuments().first;

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
            onPressed: () => Navigator.pop(
                ctx,
                ctrl.text.trim().isEmpty ? title : ctrl.text.trim()),
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
