// lib/features/manager/widgets/sort_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_prefs.dart';
import '../manager_providers.dart';

class SortBar extends ConsumerWidget {
  const SortBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(sortOptionProvider);
    final theme = Theme.of(context);

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: SortOption.values.map((opt) {
          final selected = opt == current;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(opt.label, style: const TextStyle(fontSize: 12)),
              selected: selected,
              showCheckmark: true,
              backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
              selectedColor: theme.colorScheme.primaryContainer,
              side: BorderSide(
                color: selected ? theme.colorScheme.primary.withOpacity(0.5) : theme.colorScheme.outlineVariant.withOpacity(0.5),
                width: 1,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              onSelected: (_) => ref
                  .read(sortPreferenceProvider.notifier)
                  .setValue(opt.name),
              labelStyle: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
