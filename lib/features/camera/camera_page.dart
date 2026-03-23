// lib/features/camera/camera_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils.dart';
import '../../shared/services/document_service.dart';

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
    // Launch scanner immediately after the first frame is drawn
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    try {
      final PdfScanResult? result = await FlutterDocScanner()
          .getScannedDocumentAsPdf(page: 10);

      if (!mounted) return;
      if (result == null) {
        context.pop();
        return;
      }

      final pdfPath = result.pdfUri;
      debugPrint('PDF path: $pdfPath');

      final title = await _promptTitle();
      if (!mounted) return;
      if (title == null || title.isEmpty) {
        context.pop();
        return;
      }

      final svc = ref.read(documentServiceProvider);

      // If existingDocId is provided but it's a PDF architecture, we cannot 
      // straightforwardly append pages. Ideally 'add pages' is hidden for PDFs.
      if (widget.existingDocId != null) {
        context.pop(); // Not supported for PDFs in this quick fix
        return;
      }

      final docId = await svc.createDocumentFromPdf(
        title: title,
        pdfPath: pdfPath,
        pageCount: result.pageCount,
      );
      if (mounted) context.go('/viewer/$docId');

    } on DocScanException catch (e) {
      if (mounted) {
        showSnackBar(context, 'Scan failed: ${e.message}', isError: true);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Error: $e', isError: true);
        context.pop();
      }
    }
  }

  Future<String?> _promptTitle() async {
    final ctrl = TextEditingController(
      text: 'Document ${formatDate(DateTime.now())}',
    );
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Name your document'),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
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
          onPressed: () => context.pop(),
        ),
      ),
      body: const Center(child: CircularProgressIndicator(color: Color(0xFF5C4BF5))),
    );
  }
}
