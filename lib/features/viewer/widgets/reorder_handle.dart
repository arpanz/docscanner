// lib/features/viewer/widgets/reorder_handle.dart
import 'package:flutter/material.dart';

/// A drag handle widget used inside ReorderableListView items.
/// Must be wrapped with ReorderableDragStartListener.
class ReorderHandle extends StatelessWidget {
  const ReorderHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: 0, // index is set by the parent ReorderableListView
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          Icons.drag_handle,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
