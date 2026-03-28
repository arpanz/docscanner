// lib/features/viewer/document_viewer_page.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/router.dart';
import '../../database/app_database.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_loading.dart';
import '../../shared/services/pdf_service.dart';
import 'viewer_providers.dart';

class DocumentViewerPage extends ConsumerStatefulWidget {
  const DocumentViewerPage({super.key, required this.docId});
  final int docId;

  @override
  ConsumerState<DocumentViewerPage> createState() =>
      _DocumentViewerPageState();
}

class _DocumentViewerPageState
    extends ConsumerState<DocumentViewerPage> {
  bool _redirected = false;

  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(documentProvider(widget.docId));

    return docAsync.when(
      loading: () => const Scaffold(body: AppLoading()),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Something went wrong', style: TextStyle(color: Theme.of(context).colorScheme.error)))),
      data: (doc) {
        if (doc == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const AppEmptyState(
              icon: Icons.find_in_page_outlined,
              title: 'Document not found',
            ),
          );
        }

        final pdfPath = doc.pdfPath;
        if (pdfPath != null && File(pdfPath).existsSync()) {
          return _PdfViewerScaffold(doc: doc, pdfPath: pdfPath);
        }

        // Guard: fire redirect at most once even if stream emits multiple times
        if (!_redirected) {
          _redirected = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.replace(
                  AppRoutes.folderPath(widget.docId));
            }
          });
        }
        return const Scaffold(body: AppLoading());
      },
    );
  }
}

// ---------------------------------------------------------------------------
// PDF viewer scaffold — caches bytes in initState so PdfPreview
// does not re-read the file on every build callback.
// ---------------------------------------------------------------------------
class _PdfViewerScaffold extends ConsumerStatefulWidget {
  const _PdfViewerScaffold(
      {required this.doc, required this.pdfPath});
  final Document doc;
  final String pdfPath;

  @override
  ConsumerState<_PdfViewerScaffold> createState() =>
      _PdfViewerScaffoldState();
}

class _PdfViewerScaffoldState extends ConsumerState<_PdfViewerScaffold> {
  Uint8List? _pdfBytes;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadBytes();
  }

  Future<void> _loadBytes() async {
    try {
      final bytes = await File(widget.pdfPath).readAsBytes();
      if (mounted) setState(() => _pdfBytes = bytes);
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
          },
        ),
        title: Text(widget.doc.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: 'Print',
            onPressed: () async {
              final pdfService = ref.read(pdfServiceProvider);
              await pdfService.printPdf(File(widget.pdfPath));
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () async {
              await SharePlus.instance.share(
                ShareParams(
                  files: [
                    XFile(widget.pdfPath,
                        mimeType: 'application/pdf'),
                  ],
                  subject: widget.doc.title,
                ),
              );
            },
          ),
        ],
      ),
      body: _loadError != null
          ? Center(
              child: Text('Failed to load PDF',
                  style: TextStyle(color: cs.error)))
          : _pdfBytes == null
              ? const AppLoading()
              : PdfPreview(
                  build: (format) async => _pdfBytes!,
                  useActions: false,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                ),
    );
  }
}
