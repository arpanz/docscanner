// lib/features/camera/widgets/crop_enhance_sheet.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A bottom sheet for reviewing a captured page with basic enhance options.
/// Returns an updated image path when the user confirms, or null on cancel.
class CropEnhanceSheet extends ConsumerStatefulWidget {
  const CropEnhanceSheet({super.key, required this.imagePath});
  final String imagePath;

  @override
  ConsumerState<CropEnhanceSheet> createState() => _CropEnhanceSheetState();
}

class _CropEnhanceSheetState extends ConsumerState<CropEnhanceSheet> {
  _FilterMode _filter = _FilterMode.original;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // Handle
          const _SheetHandle(),

          // Header
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                Text('Enhance',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, widget.imagePath),
                  child: const Text('Use'),
                ),
              ],
            ),
          ),

          // Image preview
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _FilteredImage(
                  path: widget.imagePath,
                  filter: _filter,
                ),
              ),
            ),
          ),

          // Filter selector
          const SizedBox(height: 16),
          SizedBox(
            height: 72,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _FilterMode.values.map((mode) {
                final selected = _filter == mode;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = mode),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              width: selected ? 2 : 1,
                            ),
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          child: Icon(mode.icon,
                              color: selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mode.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filtered image (client-side color matrix approximation)
// ---------------------------------------------------------------------------
class _FilteredImage extends StatelessWidget {
  const _FilteredImage({required this.path, required this.filter});
  final String path;
  final _FilterMode filter;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(filter.matrix),
      child: Image.file(File(path), fit: BoxFit.contain),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter modes
// ---------------------------------------------------------------------------
enum _FilterMode {
  original,
  grayscale,
  enhance,
  blackwhite;

  String get label => switch (this) {
        original   => 'Original',
        grayscale  => 'Gray',
        enhance    => 'Enhance',
        blackwhite => 'B&W',
      };

  IconData get icon => switch (this) {
        original   => Icons.image_outlined,
        grayscale  => Icons.gradient,
        enhance    => Icons.auto_fix_high,
        blackwhite => Icons.contrast,
      };

  List<double> get matrix => switch (this) {
        original => [
            1, 0, 0, 0, 0,
            0, 1, 0, 0, 0,
            0, 0, 1, 0, 0,
            0, 0, 0, 1, 0,
          ],
        grayscale => [
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0,      0,      0,      1, 0,
          ],
        enhance => [
            1.2, 0,   0,   0, -20,
            0,   1.2, 0,   0, -20,
            0,   0,   1.2, 0, -20,
            0,   0,   0,   1,   0,
          ],
        blackwhite => [
            3,  -1.5, -1.5, 0, -20,
            -1.5, 3,  -1.5, 0, -20,
            -1.5,-1.5,  3,  0, -20,
            0,   0,   0,    1,   0,
          ],
      };
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 4),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
