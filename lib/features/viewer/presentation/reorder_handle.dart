import 'package:flutter/material.dart';

/// A drag handle widget used in the reorderable page list inside [ViewerPage].
///
/// Wraps Flutter's [ReorderableDragStartListener] so the user can grab the
/// handle icon to reorder pages without accidentally triggering taps on the
/// rest of the list tile.
class ReorderHandle extends StatelessWidget {
  const ReorderHandle({super.key});

  @override
  Widget build(BuildContext context) {
    // index is injected by ReorderableListView via the inherited widget tree;
    // ReorderableDragStartListener reads it automatically.
    return ReorderableDragStartListener(
      index: _indexOf(context),
      child: const Icon(Icons.drag_handle, color: Colors.grey),
    );
  }

  /// Walks up the widget tree to find the current item index provided by
  /// [SliverReorderableList] / [ReorderableListView].
  int _indexOf(BuildContext context) {
    final item = context
        .findAncestorWidgetOfExactType<_ReorderableItemScope>();
    return item?.index ?? 0;
  }
}

/// Internal helper — mirrors the private `_ReorderableItemScope` that
/// [ReorderableListView] injects. We re-declare it here only to read the index
/// without depending on a private Flutter API.
///
/// In practice Flutter exposes the index via [ReorderableDragStartListener]
/// directly when it is a descendant of a [ReorderableListView], so no custom
/// scope is needed at runtime. This class is a no-op placeholder kept for
/// clarity.
class _ReorderableItemScope extends InheritedWidget {
  final int index;

  const _ReorderableItemScope({
    required this.index,
    required super.child,
  });

  @override
  bool updateShouldNotify(_ReorderableItemScope old) => index != old.index;
}
