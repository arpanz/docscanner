// lib/features/viewer/document_viewer_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/utils.dart';
import '../../database/app_database.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_loading.dart';
import '../../shared/services/document_service.dart';
import 'viewer_providers.dart';
import 'widgets/page_item.dart';
import 'widgets/export_sheet.dart';

class DocumentViewerPage extends ConsumerWidget {
  const DocumentViewerPage({super.key, required this.docId});
  final int docId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(documentProvider(docId));
    final pagesAsync = ref.watch(documentPagesProvider(docId));

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
        return Scaffold(
          appBar: AppBar(
            title: Text(doc.title),
            actions: [
              // Add more pages
              IconButton(
                icon: const Icon(Icons.add_a_photo_outlined),
                tooltip: 'Add pages',
                onPressed: () =>
                    context.push('${AppRoutes.camera}?docId=$docId'),
              ),
              // Export
              IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Export',
                onPressed: () => _showExport(context, ref, doc),
              ),
              // More options
              PopupMenuButton<_MenuAction>(
                onSelected: (action) =>
                    _handleMenu(context, ref, doc, action),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _MenuAction.rename,
                    child: Text('Rename'),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.delete,
                    child: Text('Delete document'),
                  ),
                ],
              ),
            ],
          ),
          body: pagesAsync.when(
            loading: () => const AppLoading(),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (pages) {
              if (pages.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.image_not_supported_outlined,
                  title: 'No pages',
                  subtitle: 'Add pages using the camera button above.',
                );
              }
              return ReorderableListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: pages.length,
                onReorder: (oldIdx, newIdx) async {
                  if (newIdx > oldIdx) newIdx--;
                  final reordered = [...pages];
                  final item = reordered.removeAt(oldIdx);
                  reordered.insert(newIdx, item);
                  await ref
                      .read(documentServiceProvider)
                      .reorderPages(docId, reordered.map((p) => p.id).toList());
                },
                itemBuilder: (ctx, i) => PageItem(
                  key: ValueKey(pages[i].id),
                  page: pages[i],
                  index: i,
                  onDelete: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Delete page',
                      message: 'Remove page ${i + 1}?',
                    );
                    if (ok) {
                      await ref.read(documentServiceProvider).deletePage(
                            pages[i].id,
                            pages[i].imagePath,
                            docId,
                          );
                    }
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showExport(BuildContext context, WidgetRef ref, Document doc) {
    showModalBottomSheet(
      context: context,
      builder: (_) => ExportSheet(docId: docId, docTitle: doc.title),
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    Document doc,
    _MenuAction action,
  ) async {
    switch (action) {
      case _MenuAction.rename:
        final ctrl = TextEditingController(text: doc.title);
        final name = await showDialog<String>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Rename document'),
            content: TextField(controller: ctrl, autofocus: true),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(d, ctrl.text.trim()),
                  child: const Text('Rename')),
            ],
          ),
        );
        if (name != null && name.isNotEmpty) {
          await ref.read(documentServiceProvider).renameDocument(docId, name);
        }
        if (!context.mounted) return;
      case _MenuAction.delete:
        final ok = await confirmDialog(
          context,
          title: 'Delete document',
          message: 'Delete "${doc.title}"? This cannot be undone.',
        );
        if (!ok || !context.mounted) return;
        await ref.read(documentServiceProvider).deleteDocument(docId);
        if (!context.mounted) return;
        context.go(AppRoutes.manager);
    }
  }
}

enum _MenuAction { rename, delete }
