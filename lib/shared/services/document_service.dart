// lib/shared/services/document_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/constants.dart';
import '../../database/app_database.dart';
import '../../database/daos.dart';

class DocumentService {
  DocumentService(this._ref);

  final Ref _ref;

  DocumentsDao get _docsDao => _ref.read(documentsDaoProvider);
  PagesDao get _pagesDao => _ref.read(pagesDaoProvider);

  // ---------------------------------------------------------------------------
  // Create a new document from a list of raw image paths
  // ---------------------------------------------------------------------------
  Future<int> createDocument({
    required String title,
    required List<String> imagePaths,
  }) async {
    final docId = await _docsDao.insertDocument(
      DocumentsCompanion(title: Value(title)),
    );
    try {
      await _addPages(docId, imagePaths);
      await _docsDao.refreshDocumentMeta(docId);
      return docId;
    } catch (e) {
      // Roll back — delete the empty document row
      await _docsDao.deleteDocument(docId);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Create a new document from a scanned PDF
  // ---------------------------------------------------------------------------
  Future<int> createDocumentFromPdf({
    required String title,
    required String pdfPath,
    required int pageCount,
  }) async {
    final docId = await _docsDao.insertDocument(
      DocumentsCompanion(title: Value(title)),
    );
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'pages'));
      if (!await dir.exists()) await dir.create(recursive: true);

      final dest = p.join(
        dir.path,
        '${docId}_${DateTime.now().microsecondsSinceEpoch}.pdf',
      );

      // Clean the path in case `file://` is still prefixed
      final cleanPath = pdfPath.startsWith('file://')
          ? Uri.parse(pdfPath).toFilePath()
          : pdfPath;
      
      await File(cleanPath).copy(dest);

      await _pagesDao.insertPage(
        PagesCompanion(
          documentId: Value(docId),
          imagePath: Value(dest), // store PDF path
          pageIndex: const Value(0),
        ),
      );

      await _docsDao.refreshDocumentMeta(docId);
      return docId;
    } catch (e) {
      await _docsDao.deleteDocument(docId);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Append pages to an existing document
  // ---------------------------------------------------------------------------
  Future<void> appendPages(int docId, List<String> imagePaths) async {
    final existing = await _pagesDao.getPagesForDocument(docId);
    final startIndex = existing.length;
    await _addPages(docId, imagePaths, startIndex: startIndex);
    await _docsDao.refreshDocumentMeta(docId);
  }

  // ---------------------------------------------------------------------------
  // Delete a full document (files + DB rows)
  // ---------------------------------------------------------------------------
  Future<void> deleteDocument(int docId) async {
    final pages = await _pagesDao.getPagesForDocument(docId);
    for (final pg in pages) {
      await _deleteFile(pg.imagePath);
    }
    await _pagesDao.deletePagesForDocument(docId);
    await _docsDao.deleteDocument(docId);
  }

  // ---------------------------------------------------------------------------
  // Delete a single page
  // ---------------------------------------------------------------------------
  Future<void> deletePage(int pageId, String imagePath, int docId) async {
    await _deleteFile(imagePath);
    await _pagesDao.deletePage(pageId);
    await _docsDao.refreshDocumentMeta(docId);
  }

  // ---------------------------------------------------------------------------
  // Reorder pages
  // ---------------------------------------------------------------------------
  Future<void> reorderPages(int docId, List<int> orderedPageIds) async {
    await _pagesDao.reorderPages(docId, orderedPageIds);
    await _docsDao.refreshDocumentMeta(docId);
  }

  // ---------------------------------------------------------------------------
  // Rename document
  // ---------------------------------------------------------------------------
  Future<void> renameDocument(int docId, String newTitle) async {
    await _docsDao.updateDocument(
      DocumentsCompanion(
        id: Value(docId),
        title: Value(newTitle),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------
  Future<void> _addPages(
    int docId,
    List<String> imagePaths, {
    int startIndex = 0,
  }) async {
    final dir = await _pagesDir();
    var successCount = 0;
    Object? lastError;

    for (var i = 0; i < imagePaths.length; i++) {
      final rawSrc = imagePaths[i];
      // flutter_doc_scanner 0.0.17 returns paths like 'file:///storage/emulated/0/...'.
      // File() needs an absolute filesystem path.
      final src = rawSrc.startsWith('file://') ? Uri.parse(rawSrc).toFilePath() : rawSrc;
      final dest = p.join(
        dir.path,
        '${docId}_${startIndex + i}_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      try {
        await _compressAndSave(src, dest);
        await _pagesDao.insertPage(
          PagesCompanion(
            documentId: Value(docId),
            imagePath: Value(dest),
            pageIndex: Value(startIndex + successCount),
          ),
        );
        successCount++;
      } catch (e) {
        // Skip this page — don't crash the whole document
        debugPrint('Failed to save page $i: $e');
        lastError = e;
      }
    }

    if (successCount == 0) {
      if (lastError != null) {
        throw Exception('All images failed to process. Reason: $lastError');
      }
      throw Exception('No pages could be saved — all images failed to process');
    }
  }

  Future<void> _compressAndSave(String src, String dest) async {
    final result = await FlutterImageCompress.compressAndGetFile(
      src,
      dest,
      quality: AppConstants.defaultJpegQuality,
    );
    if (result == null) {
      // Fallback: plain copy (safe now — src is a real file path)
      await File(src).copy(dest);
    }
  }

  Future<Directory> _pagesDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'pages'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------
final documentServiceProvider = Provider<DocumentService>((ref) {
  return DocumentService(ref);
});
