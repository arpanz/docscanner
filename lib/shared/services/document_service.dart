// lib/shared/services/document_service.dart
import 'dart:io';
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
    await _addPages(docId, imagePaths);
    await _docsDao.refreshDocumentMeta(docId);
    return docId;
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
    for (var i = 0; i < imagePaths.length; i++) {
      final src = imagePaths[i];
      final dest = p.join(dir.path, '${docId}_${startIndex + i}.jpg');
      await _compressAndSave(src, dest);
      await _pagesDao.insertPage(
        PagesCompanion(
          documentId: Value(docId),
          imagePath: Value(dest),
          pageIndex: Value(startIndex + i),
        ),
      );
    }
  }

  Future<void> _compressAndSave(String src, String dest) async {
    final result = await FlutterImageCompress.compressAndGetFile(
      src,
      dest,
      quality: AppConstants.defaultJpegQuality,
    );
    if (result == null) {
      // Fallback: plain copy
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
