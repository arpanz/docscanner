// lib/features/viewer/document_viewer_page.dart
import 'dart:io';
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

class DocumentViewerPage extends ConsumerStatefulWidget {
  const DocumentViewerPage({super.key, required this.docId});
  final int docId;

  @override
  ConsumerState<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends ConsumerState<DocumentViewerPage> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _reorderMode = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(documentProvider(widget.docId));
    final pagesAsync = ref.watch(documentPagesProvider(widget.docId));

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
              // Toggle reorder mode
              IconButton(
                icon: Icon(_reorderMode ? Icons.check : Icons.reorder),
                tooltip: _reorderMode ? 'Done reordering' : 'Reorder pages',
                onPressed: () => setState(() => _reorderMode = !_reorderMode),
              ),
              // Add more pages
              IconButton(
                icon: const Icon(Icons.add_a_photo_outlined),
                tooltip: 'Add pages',
                onPressed: () =>
                    context.push('${AppRoutes.camera}?docId=${widget.docId}'),
              ),
              // Export
              IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Export',
                onPressed: () => _showExport(context, ref, doc),
              ),
              // More options
              PopupMenuButton<_MenuAction>(
                onSelected: (action) => _handleMenu(context, ref, doc, action),
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

              // Reorder mode — full list with drag handles
              if (_reorderMode) {
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
                        .reorderPages(
                          widget.docId,
                          reordered.map((p) => p.id).toList(),
                        );
                  },
                  itemBuilder: (ctx, i) => ListTile(
                    key: ValueKey(pages[i].id),
                    leading: SizedBox(
                      width: 48,
                      height: 64,
                      child: Image.file(
                        File(pages[i].imagePath),
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text('Page ${i + 1}'),
                    trailing: const Icon(Icons.drag_handle),
                  ),
                );
              }

              // Normal mode — swipeable full-screen pages
              return Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: pages.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (ctx, i) => PageItem(
                      page: pages[i],
                      index: i,
                      onDelete: () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'Delete page',
                          message: 'Remove page ${i + 1}?',
                        );
                        if (ok) {
                          await ref
                              .read(documentServiceProvider)
                              .deletePage(
                                pages[i].id,
                                pages[i].imagePath,
                                widget.docId,
                              );
                        }
                      },
                    ),
                  ),
                  // Page counter overlay
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_currentPage + 1} / ${pages.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
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
      builder: (_) => ExportSheet(docId: widget.docId, docTitle: doc.title),
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
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, ctrl.text.trim()),
                child: const Text('Rename'),
              ),
            ],
          ),
        );
        if (name != null && name.isNotEmpty) {
          await ref
              .read(documentServiceProvider)
              .renameDocument(widget.docId, name);
        }
        if (!context.mounted) return;
      case _MenuAction.delete:
        final ok = await confirmDialog(
          context,
          title: 'Delete document',
          message: 'Delete "${doc.title}"? This cannot be undone.',
        );
        if (!ok || !context.mounted) return;
        await ref.read(documentServiceProvider).deleteDocument(widget.docId);
        if (!context.mounted) return;
        context.go(AppRoutes.manager);
    }
  }
}

enum _MenuAction { rename, delete }
