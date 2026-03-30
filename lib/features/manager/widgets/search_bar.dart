// lib/features/manager/widgets/search_bar.dart
import 'package:flutter/material.dart';

class DocSearchBar extends StatefulWidget {
  const DocSearchBar({
    super.key,
    required this.onChanged,
    this.initialValue = '',
  });

  final ValueChanged<String> onChanged;
  final String initialValue;

  @override
  State<DocSearchBar> createState() => _DocSearchBarState();
}

class _DocSearchBarState extends State<DocSearchBar> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: TextField(
          controller: _ctrl,
          onChanged: widget.onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search documents…',
            hintStyle: TextStyle(color: cs.onSurfaceVariant),
            prefixIcon: Icon(Icons.search, size: 20, color: cs.primary),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, size: 18, color: cs.onSurfaceVariant),
                    onPressed: () {
                      _ctrl.clear();
                      widget.onChanged('');
                    },
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
