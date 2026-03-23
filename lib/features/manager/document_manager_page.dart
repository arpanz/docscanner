// lib/features/manager/document_manager_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/utils.dart';
import '../../database/app_database.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_loading.dart';
import '../../shared/services/document_service.dart';
import 'manager_providers.dart';
import 'widgets/doc_card.dart';
import 'widgets/sort_bar.dart';
import 'widgets/search_bar.dart';

class DocumentManagerPage extends ConsumerWidget {
  const DocumentManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(filteredDocumentsProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('DocScanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(
            children: [
              DocSearchBar(
                initialValue: query,
                onChanged: (v) =>
                    ref.read(searchQueryProvider.notifier).state = v,
              ),
              const SortBar(),
            ],
          ),
        ),
      ),
      body: docsAsync.when(
        loading: () => const AppLoading(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (docs) {
          if (docs.isEmpty) {
            return AppEmptyState(
              icon: Icons.document_scanner_outlined,
              title: query.isEmpty
                  ? 'No documents yet'
                  : 'No results for "$query"',
              subtitle: query.isEmpty
                  ? 'Tap the camera button to scan your first document.'
                  : null,
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: docs.length,
            itemBuilder: (ctx, i) => DocCard(
              document: docs[i],
              onTap: () => context.push(AppRoutes.viewerPath(docs[i].id)),
              onLongPress: () => _showDocOptions(context, ref, docs[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.camera),
        child: const Icon(Icons.camera_alt),
      ),
    );
  }

  void _showDocOptions(
      BuildContext context, WidgetRef ref, Document doc) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(ctx);
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
                          onPressed: () =>
                              Navigator.pop(d, ctrl.text.trim()),
                          child: const Text('Rename')),
                    ],
                  ),
                );
                if (name != null && name.isNotEmpty) {
                  await ref
                      .read(documentServiceProvider)
                      .renameDocument(doc.id, name);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await confirmDialog(
                  context,
                  title: 'Delete document',
                  message:
                      'Delete "${doc.title}"? This cannot be undone.',
                );
                if (ok) {
                  await ref
                      .read(documentServiceProvider)
                      .deleteDocument(doc.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
