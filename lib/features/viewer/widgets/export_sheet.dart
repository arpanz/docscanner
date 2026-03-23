// lib/features/viewer/widgets/export_sheet.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils.dart';
import '../../../database/app_database.dart';
import '../../../shared/services/document_service.dart';
import '../../../shared/services/pdf_service.dart';

class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({
    super.key,
    required this.docId,
    required this.docTitle,
  });

  final int docId;
  final String docTitle;

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  bool _loading = false;

  Future<void> _exportPdf() async {
    await _run(() async {
      final docService = ref.read(documentServiceProvider);
      final doc = await ref.read(documentsDaoProvider).getDocument(widget.docId);
      if (doc == null) throw Exception('Document not found');
      
      final imagePaths = await docService.getDocumentImages(doc.folderPath);

      // Check if it's a PDF-based document
      final isPdf = imagePaths.length == 1 && imagePaths.first.toLowerCase().endsWith('.pdf');

      if (isPdf) {
        // Share the existing PDF directly
        final cleanPath = cleanFilePath(imagePaths.first);
        await ref
            .read(pdfServiceProvider)
            .sharePdf(File(cleanPath), subject: widget.docTitle);
      } else {
        // Build PDF from images
        final pdfFile = await ref.read(pdfServiceProvider).buildPdf(
              title: widget.docTitle,
              imagePaths: imagePaths,
            );
        await ref
            .read(pdfServiceProvider)
            .sharePdf(pdfFile, subject: widget.docTitle);
      }
    });
  }

  Future<void> _printPdf() async {
    await _run(() async {
      final docService = ref.read(documentServiceProvider);
      final doc = await ref.read(documentsDaoProvider).getDocument(widget.docId);
      if (doc == null) throw Exception('Document not found');
      
      final imagePaths = await docService.getDocumentImages(doc.folderPath);

      // Check if it's a PDF-based document
      final isPdf = imagePaths.length == 1 && imagePaths.first.toLowerCase().endsWith('.pdf');

      if (isPdf) {
        final cleanPath = cleanFilePath(imagePaths.first);
        await ref.read(pdfServiceProvider).printPdf(File(cleanPath));
      } else {
        final pdfFile = await ref.read(pdfServiceProvider).buildPdf(
              title: widget.docTitle,
              imagePaths: imagePaths,
            );
        await ref.read(pdfServiceProvider).printPdf(pdfFile);
      }
    });
  }

  Future<void> _shareImages() async {
    await _run(() async {
      final docService = ref.read(documentServiceProvider);
      final doc = await ref.read(documentsDaoProvider).getDocument(widget.docId);
      if (doc == null) throw Exception('Document not found');
      
      final imagePaths = await docService.getDocumentImages(doc.folderPath);

      // Can't share PDF as images
      final isPdf = imagePaths.length == 1 && imagePaths.first.toLowerCase().endsWith('.pdf');

      if (isPdf) {
        throw Exception('Cannot share PDF documents as images. Use "Export as PDF" instead.');
      }

      await ref
          .read(pdfServiceProvider)
          .shareImages(imagePaths, subject: widget.docTitle);
    });
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _loading = true);
    try {
      await fn();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Export failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Export "${widget.docTitle}"',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator.adaptive(),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Export as PDF'),
                subtitle: const Text('Share a single PDF file'),
                onTap: _exportPdf,
              ),
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('Print'),
                subtitle: const Text('Print via system dialog'),
                onTap: _printPdf,
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Share images'),
                subtitle: const Text('Share individual page images'),
                onTap: _shareImages,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
