// lib/features/viewer/widgets/page_item.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../database/app_database.dart' as db;

class PageItem extends StatelessWidget {
  const PageItem({
    super.key,
    required this.page,
    required this.index,
    required this.onDelete,
  });

  final db.Page page;
  final int index;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDelete,
      child: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Center(
                child: Image.file(
                  File(page.imagePath),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  errorBuilder: (ctx, err, _) => Center(
                    child: Text(
                      'Cannot load image\n${page.imagePath}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Page label — makes it clear this is a document viewer, not a photo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: Colors.black,
            child: Text(
              'Page ${index + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
