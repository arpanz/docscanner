// lib/features/viewer/document_viewer_page.dart
import 'dart:io';
import 'package:docscanner/shared/services/pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../core/router.dart';
import '../../core/utils.dart';
import '../../database/app_database.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_loading.dart';
import '../../shared/services/document_service.dart';
import 'viewer_providers.dart';

class DocumentViewerPage extends ConsumerStatefulWidget {
  const DocumentViewerPage({super.key, required this.docId});
  final int docId;

  @override
  ConsumerState<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends ConsumerState<DocumentViewerPage> {
  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(documentProvider(widget.docId));
    final imagesAsync = ref.watch(documentImagesProvider(widget.docId));

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
            if (imagePaths.isEmpty) {
              return Scaffold(
                appBar: AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
                  title: Text(doc.title),
                ),
                body: const AppEmptyState(
                  icon: Icons.image_not_supported_outlined,
                  title: 'No images',
                  subtitle: 'Add images using the camera button.',
                ),
                floatingActionButton: FloatingActionButton.extended(
                  onPressed: () =>
                      context.push('${AppRoutes.camera}?docId=${widget.docId}'),
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Add Images'),
                ),
              );
            }

            final isPdf =
                imagePaths.length == 1 &&
                imagePaths.first.toLowerCase().endsWith('.pdf');
            if (isPdf) {
              // Show PDF preview
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
                  build: (format) async => File(imagePaths.first).readAsBytes(),
                  useActions: false,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                ),
              );
            }

            // Show image grid - redirect to folder page for better UX
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
              ),
              body: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: imagePaths.length,
                itemBuilder: (ctx, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(imagePaths[i]), fit: BoxFit.cover),
                ),
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () =>
                    context.push(AppRoutes.folderPath(widget.docId)),
                icon: const Icon(Icons.folder_open),
                label: const Text('Open Folder'),
              ),
            );
          },
        );
      },
    );
  }
}
