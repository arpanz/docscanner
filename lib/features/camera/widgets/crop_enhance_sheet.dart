import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

const _lumaRed = 0.2126;
const _lumaGreen = 0.7152;
const _lumaBlue = 0.0722;

enum FilterMode {
  original,
  grayscale,
  enhance,
  blackwhite;

  String get label => switch (this) {
    original => 'Original',
    grayscale => 'Gray',
    enhance => 'Enhance',
    blackwhite => 'B&W',
  };

  IconData get icon => switch (this) {
    original => Icons.image_outlined,
    grayscale => Icons.gradient,
    enhance => Icons.auto_fix_high,
    blackwhite => Icons.contrast,
  };
}

class ImageEditOptions {
  const ImageEditOptions({
    this.filter = FilterMode.original,
    this.brightness = 0,
    this.contrast = 1,
    this.rotationTurns = 0,
  });

  final FilterMode filter;
  final double brightness;
  final double contrast;
  final int rotationTurns;

  ImageEditOptions copyWith({
    FilterMode? filter,
    double? brightness,
    double? contrast,
    int? rotationTurns,
  }) {
    return ImageEditOptions(
      filter: filter ?? this.filter,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      rotationTurns: rotationTurns ?? this.rotationTurns,
    );
  }
}

class ImageEditArgs {
  const ImageEditArgs({
    required this.inputPath,
    required this.outputPath,
    required this.options,
  });

  final String inputPath;
  final String outputPath;
  final ImageEditOptions options;
}

String applyImageEdits(ImageEditArgs args) {
  final bytes = File(args.inputPath).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) {
    throw Exception('Failed to decode image');
  }

  switch (args.options.filter) {
    case FilterMode.original:
      break;
    case FilterMode.grayscale:
      image = img.grayscale(image);
      break;
    case FilterMode.enhance:
      image = img.adjustColor(
        image,
        contrast: 1.22,
        saturation: 0.9,
        brightness: 0.04,
      );
      break;
    case FilterMode.blackwhite:
      image = img.grayscale(image);
      image = img.adjustColor(image, contrast: 1.4, brightness: 0.06);
      image = _threshold(image, 165);
      break;
  }

  if (args.options.brightness.abs() > 0.001 ||
      (args.options.contrast - 1).abs() > 0.001) {
    image = img.adjustColor(
      image,
      brightness: args.options.brightness,
      contrast: args.options.contrast,
    );
  }

  final turns = args.options.rotationTurns % 4;
  if (turns == 1) {
    image = img.copyRotate(image, angle: 90);
  } else if (turns == 2) {
    image = img.copyRotate(image, angle: 180);
  } else if (turns == 3) {
    image = img.copyRotate(image, angle: 270);
  }

  File(args.outputPath).writeAsBytesSync(img.encodeJpg(image, quality: 95));
  return args.outputPath;
}

img.Image _threshold(img.Image image, int threshold) {
  for (final pixel in image) {
    final value = pixel.r >= threshold ? 255 : 0;
    pixel
      ..r = value
      ..g = value
      ..b = value;
  }
  return image;
}

class ImageEditSheet extends StatefulWidget {
  const ImageEditSheet({
    super.key,
    required this.imagePath,
    this.initial = const ImageEditOptions(),
  });

  final String imagePath;
  final ImageEditOptions initial;

  @override
  State<ImageEditSheet> createState() => _ImageEditSheetState();
}

class _ImageEditSheetState extends State<ImageEditSheet> {
  late ImageEditOptions _options;

  @override
  void initState() {
    super.initState();
    _options = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.96,
      minChildSize: 0.7,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          const _SheetHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                Expanded(
                  child: Text(
                    'Edit page',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _options),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    height: 340,
                    color: cs.surfaceContainerHighest,
                    child: _PreviewImage(
                      path: widget.imagePath,
                      options: _options,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Filter',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 80,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: FilterMode.values.map((mode) {
                      final selected = _options.filter == mode;
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: InkWell(
                          onTap: () => setState(() {
                            _options = _options.copyWith(filter: mode);
                          }),
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 88,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? cs.primary
                                    : cs.outlineVariant,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  mode.icon,
                                  color: selected
                                      ? cs.onPrimaryContainer
                                      : cs.onSurfaceVariant,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  mode.label,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: selected
                                        ? cs.onPrimaryContainer
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),
                _SliderTile(
                  title: 'Brightness',
                  value: _options.brightness,
                  min: -0.4,
                  max: 0.4,
                  divisions: 16,
                  label: '${(_options.brightness * 100).round()}%',
                  onChanged: (value) => setState(() {
                    _options = _options.copyWith(brightness: value);
                  }),
                ),
                _SliderTile(
                  title: 'Contrast',
                  value: _options.contrast,
                  min: 0.6,
                  max: 1.6,
                  divisions: 10,
                  label: _options.contrast.toStringAsFixed(2),
                  onChanged: (value) => setState(() {
                    _options = _options.copyWith(contrast: value);
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  'Rotate',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _options = _options.copyWith(
                          rotationTurns: (_options.rotationTurns + 3) % 4,
                        );
                      }),
                      icon: const Icon(Icons.rotate_left),
                      label: const Text('Rotate Left'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _options = _options.copyWith(
                          rotationTurns: (_options.rotationTurns + 1) % 4,
                        );
                      }),
                      icon: const Icon(Icons.rotate_right),
                      label: const Text('Rotate Right'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.path, required this.options});

  final String path;
  final ImageEditOptions options;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: options.rotationTurns,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(_previewMatrix(options)),
        child: Image.file(File(path), fit: BoxFit.contain),
      ),
    );
  }
}

List<double> _previewMatrix(ImageEditOptions options) {
  var contrast = options.contrast;
  var brightness = options.brightness;
  var saturation = 1.0;

  switch (options.filter) {
    case FilterMode.original:
      break;
    case FilterMode.grayscale:
      saturation = 0;
      break;
    case FilterMode.enhance:
      contrast *= 1.22;
      brightness += 0.04;
      saturation = 0.9;
      break;
    case FilterMode.blackwhite:
      contrast *= 1.55;
      brightness += 0.06;
      saturation = 0;
      break;
  }

  final offset = brightness * 255;
  final inverseSaturation = 1 - saturation;
  final red = inverseSaturation * _lumaRed;
  final green = inverseSaturation * _lumaGreen;
  final blue = inverseSaturation * _lumaBlue;

  return [
    contrast * (red + saturation),
    contrast * green,
    contrast * blue,
    0,
    offset,
    contrast * red,
    contrast * (green + saturation),
    contrast * blue,
    0,
    offset,
    contrast * red,
    contrast * green,
    contrast * (blue + saturation),
    0,
    offset,
    0,
    0,
    0,
    1,
    0,
  ];
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
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
