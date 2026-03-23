// lib/features/viewer/widgets/page_item.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../database/tables.dart';
import 'reorder_handle.dart';

class PageItem extends StatelessWidget {
  const PageItem({
    super.key,
    required this.page,
    required this.index,
    required this.onDelete,
  });

  final Page page;
  final int index;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // Page image
          ClipRRect(
            child: Image.file(
              File(page.imagePath),
              width: 90,
              height: 120,
              fit: BoxFit.cover,
            ),
          ),

          // Page info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Page ${index + 1}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    page.imagePath.split('/').last,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // Delete button
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.error,
            ),
            onPressed: onDelete,
            tooltip: 'Delete page',
          ),

          // Drag handle
          const ReorderHandle(),
        ],
      ),
    );
  }
}
