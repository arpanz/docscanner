// lib/features/viewer/document_viewer_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/router.dart';
import '../../database/app_database.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_loading.dart';
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
          Scaffold(body: Center(child: Text('Error: $e'))),
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

        // Guard ensures redirect fires at most once even if the
        // stream emits multiple times.
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

class _PdfViewerScaffold extends StatelessWidget {
  const _PdfViewerScaffold(
      {required this.doc, required this.pdfPath});
  final Document doc;
  final String pdfPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            Theme.of(context).colorScheme.surface,
        foregroundColor:
            Theme.of(context).colorScheme.onSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
          },
        ),
        title: Text(doc.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: () async {
              await SharePlus.instance.share(
                ShareParams(
                  files: [
                    XFile(pdfPath,
                        mimeType: 'application/pdf'),
                  ],
                  subject: doc.title,
                ),
              );
            },
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) async =>
            File(pdfPath).readAsBytes(),
        useActions: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      ),
    );
  }
}
