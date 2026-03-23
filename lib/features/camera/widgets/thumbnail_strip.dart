// lib/features/camera/widgets/thumbnail_strip.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants.dart';

class ThumbnailStrip extends StatelessWidget {
  const ThumbnailStrip({
    super.key,
    required this.imagePaths,
    required this.onTap,
  });

  final List<String> imagePaths;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    if (imagePaths.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: AppConstants.thumbHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: imagePaths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          return GestureDetector(
            onTap: () => onTap(i),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(imagePaths[i]),
                    width: AppConstants.thumbWidth,
                    height: AppConstants.thumbHeight,
                    fit: BoxFit.cover,
                  ),
                ),
                // Page number badge
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
