// lib/features/viewer/document_viewer_page.dart
// NOTE: This page is now only used for PDF-only documents.
// Image-based documents navigate directly to DocumentFolderPage.
import 'dart:io';
import 'package:docscanner/shared/services/pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../core/router.dart';
import '../../database/app_database.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_loading.dart';
import 'viewer_providers.dart';

class DocumentViewerPage extends ConsumerWidget {
  const DocumentViewerPage({super.key, required this.docId});
  final int docId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(documentProvider(docId));
    final imagesAsync = ref.watch(documentImagesProvider(docId));

    return docAsync.when(
      loading: () => const Scaffold(body: AppLoading()),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
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

        return imagesAsync.when(
          loading: () => const Scaffold(body: AppLoading()),
          error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
          data: (imagePaths) {
            // Non-PDF docs: redirect immediately to folder page
            final isPdf = imagePaths.length == 1 &&
                imagePaths.first.toLowerCase().endsWith('.pdf');

            if (!isPdf) {
              // Use addPostFrameCallback to avoid navigating during build
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  context.replace(AppRoutes.folderPath(docId));
                }
              });
              return const Scaffold(body: AppLoading());
            }

            // PDF viewer
            return Scaffold(
              appBar: AppBar(
                backgroundColor: Theme.of(context).colorScheme.surface,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
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
                      final pdfService = ref.read(pdfServiceProvider);
                      await pdfService.sharePdf(
                        File(imagePaths.first),
                        subject: doc.title,
                      );
                    },
                  ),
                ],
              ),
              body: PdfPreview(
                build: (format) async =>
                    File(imagePaths.first).readAsBytes(),
                useActions: false,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
              ),
            );
          },
        );
      },
    );
  }
}
