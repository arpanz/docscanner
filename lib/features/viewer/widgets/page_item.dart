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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
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
                          'Cannot load page ${index + 1}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Page ${index + 1}',
                style: const TextStyle(color: Colors.black45, fontSize: 12),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
