// lib/features/manager/widgets/doc_card.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../core/utils.dart';
import '../../../database/tables.dart';

class DocCard extends StatelessWidget {
  const DocCard({
    super.key,
    required this.document,
    required this.onTap,
    this.onLongPress,
  });

  final Document document;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cover image / placeholder
            Expanded(
              child: document.coverPagePath != null
                  ? Image.file(
                      File(document.coverPagePath!),
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Text(
                          initials(document.title),
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withOpacity(0.4),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${document.pageCount} page${document.pageCount == 1 ? '' : 's'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        relativeDate(document.updatedAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
