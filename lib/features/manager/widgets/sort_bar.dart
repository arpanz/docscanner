// lib/features/manager/widgets/sort_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../manager_providers.dart';

class SortBar extends ConsumerWidget {
  const SortBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(sortOptionProvider);
    final theme = Theme.of(context);

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: SortOption.values.map((opt) {
          final selected = opt == current;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(opt.label),
              selected: selected,
              onSelected: (_) =>
                  ref.read(sortOptionProvider.notifier).state = opt,
              labelStyle: theme.textTheme.labelMedium?.copyWith(
                color: selected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
