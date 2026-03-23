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
      child: InteractiveViewer(
        minScale: 1.0,
        maxScale: 4.0,
        child: SizedBox.expand(
          child: Image.file(File(page.imagePath), fit: BoxFit.contain),
        ),
      ),
    );
  }
}
