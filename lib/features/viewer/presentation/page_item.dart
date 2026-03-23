import 'dart:io';

import 'package:flutter/material.dart';

import '../../../database/app_database.dart';

class PageItem extends StatelessWidget {
  final DocumentPage page;

  const PageItem({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(page.imagePath),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFFEEEEEE),
              child: Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              color: Colors.black45,
              child: Text(
                'Page ${page.pageOrder + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
