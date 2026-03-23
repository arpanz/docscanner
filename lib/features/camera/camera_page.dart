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
      final dynamic result = await FlutterDocScanner()
          .getScannedDocumentAsImages();

      if (!mounted) return;

      // Correct check — result is List<dynamic> directly, no .images property
      if (result == null || result is! List || result.isEmpty) {
        context.pop();
        return;
      }

      // Cast each element to String — these are file paths or content URIs
      final paths = result.map((e) => e.toString()).toList();

      // Prompt title AFTER we have confirmed we have pages
      final title = await _promptTitle();
      if (!mounted) return;
      if (title == null || title.isEmpty) {
        context.pop();
        return;
      }

      final svc = ref.read(documentServiceProvider);

      if (widget.existingDocId != null) {
        await svc.appendPages(widget.existingDocId!, paths);
        if (mounted) context.pop();
      } else {
        final docId = await svc.createDocument(title: title, imagePaths: paths);
        debugPrint('Navigating to: /viewer/$docId');
        if (mounted) context.go('/viewer/$docId');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Scan failed: $e', isError: true);
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
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator(color: Color(0xFF5C4BF5))),
    );
  }
}
