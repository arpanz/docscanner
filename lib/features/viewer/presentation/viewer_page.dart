import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../database/app_database.dart';
import '../../../shared/services/pdf_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../manager/providers/document_providers.dart';
import 'export_sheet.dart';
import 'page_item.dart';

class ViewerPage extends ConsumerStatefulWidget {
  final int documentId;

  const ViewerPage({super.key, required this.documentId});

  @override
  ConsumerState<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends ConsumerState<ViewerPage> {
  bool _reorderMode = false;

  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(documentByIdProvider(widget.documentId));
    final pagesAsync = ref.watch(documentPagesProvider(widget.documentId));

    return docAsync.when(
      loading: () => const AppScaffold(
        title: 'Document',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => AppScaffold(
        title: 'Error',
        body: Center(child: Text('$e')),
      ),
      data: (doc) {
        if (doc == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => context.pop());
          return const SizedBox.shrink();
        }
        return AppScaffold(
          title: doc.name,
          actions: [
            IconButton(
              icon: Icon(_reorderMode ? Icons.check : Icons.reorder),
              tooltip: _reorderMode ? 'Done' : 'Reorder pages',
              onPressed: () => setState(() => _reorderMode = !_reorderMode),
            ),
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export',
              onPressed: () => _showExportSheet(context, doc),
            ),
          ],
          body: pagesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (pages) => _reorderMode
                ? _ReorderablePageList(
                    documentId: widget.documentId,
                    pages: pages,
                  )
                : _PageGrid(pages: pages),
          ),
        );
      },
    );
  }

  void _showExportSheet(BuildContext context, Document doc) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ExportSheet(document: doc),
    );
  }
}

// ---------------------------------------------------------------------------
// Grid view (normal mode)
// ---------------------------------------------------------------------------

class _PageGrid extends StatelessWidget {
  final List<DocumentPage> pages;

  const _PageGrid({required this.pages});

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return const Center(child: Text('No pages yet.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: pages.length,
      itemBuilder: (_, i) => PageItem(page: pages[i]),
    );
  }
}

// ---------------------------------------------------------------------------
// Reorderable list (reorder mode)
// ---------------------------------------------------------------------------

class _ReorderablePageList extends ConsumerWidget {
  final int documentId;
  final List<DocumentPage> pages;

  const _ReorderablePageList({
    required this.documentId,
    required this.pages,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pages.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        ref
            .read(documentPagesProvider(documentId).notifier)
            .reorderPage(oldIndex, newIndex);
      },
      itemBuilder: (_, i) {
        final page = pages[i];
        return ListTile(
          key: ValueKey(page.id),
          leading: SizedBox(
            width: 48,
            height: 64,
            child: Image.file(
              File(page.imagePath),
              fit: BoxFit.cover,
            ),
          ),
          title: Text('Page ${i + 1}'),
          trailing: const ReorderHandle(),
        );
      },
    );
  }
}
