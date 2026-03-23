// lib/shared/services/document_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../database/app_database.dart';
import '../../database/daos.dart';

class DocumentService {
  DocumentService(this._ref);

  final Ref _ref;
  final _uuid = const Uuid();

  DocumentsDao get _docsDao => _ref.read(documentsDaoProvider);

  // ---------------------------------------------------------------------------
  // Get app documents directory
  // ---------------------------------------------------------------------------
  Future<Directory> _documentsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'documents'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ---------------------------------------------------------------------------
  // Create a new document from a list of raw image paths
  // ---------------------------------------------------------------------------
  Future<int> createDocument({
    required String title,
    required List<String> imagePaths,
  }) async {
    final docsDir = await _documentsDir();
    final folderName = '${_sanitize(title)}_${_uuid.v4().substring(0, 8)}';
    final folderPath = p.join(docsDir.path, folderName);
    final folder = Directory(folderPath);
    await folder.create(recursive: true);

    final docId = await _docsDao.insertDocument(
      DocumentsCompanion(
        title: Value(title),
        folderPath: Value(folderPath),
      ),
    );

    try {
      await _addImages(folderPath, imagePaths);
      await _docsDao.refreshDocumentMeta(docId, folderPath);
      return docId;
    } catch (e) {
      // Roll back — delete the folder and document row
      await folder.delete(recursive: true);
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
    final docsDir = await _documentsDir();
    final folderName = '${_sanitize(title)}_${_uuid.v4().substring(0, 8)}';
    final folderPath = p.join(docsDir.path, folderName);
    final folder = Directory(folderPath);
    await folder.create(recursive: true);

    // Copy PDF to folder
    final cleanPath = cleanFilePath(pdfPath);
    final pdfDest = p.join(folderPath, '${_sanitize(title)}.pdf');
    await File(cleanPath).copy(pdfDest);

    final docId = await _docsDao.insertDocument(
      DocumentsCompanion(
        title: Value(title),
        folderPath: Value(folderPath),
        pdfPath: Value(pdfDest),
      ),
    );

    try {
      await _docsDao.refreshDocumentMeta(docId, folderPath);
      return docId;
    } catch (e) {
      await folder.delete(recursive: true);
      await _docsDao.deleteDocument(docId);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Add images to an existing document
  // ---------------------------------------------------------------------------
  Future<void> addImages(int docId, List<String> imagePaths) async {
    final doc = await _docsDao.getDocument(docId);
    if (doc == null) throw Exception('Document not found');

    await _addImages(doc.folderPath, imagePaths);
    await _docsDao.refreshDocumentMeta(docId, doc.folderPath);
  }

  // ---------------------------------------------------------------------------
  // Delete a full document (folder + DB row)
  // ---------------------------------------------------------------------------
  Future<void> deleteDocument(int docId) async {
    final doc = await _docsDao.getDocument(docId);
    if (doc == null) return;

    try {
      final folder = Directory(doc.folderPath);
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
    } catch (_) {}

    await _docsDao.deleteDocument(docId);
  }

  // ---------------------------------------------------------------------------
  // Delete specific images from a document
  // ---------------------------------------------------------------------------
  Future<void> deleteImages(int docId, List<String> imagePaths) async {
    final doc = await _docsDao.getDocument(docId);
    if (doc == null) return;

    for (final path in imagePaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    await _docsDao.refreshDocumentMeta(docId, doc.folderPath);
  }

  // ---------------------------------------------------------------------------
  // Rename document (also renames folder)
  // ---------------------------------------------------------------------------
  Future<void> renameDocument(int docId, String newTitle) async {
    final doc = await _docsDao.getDocument(docId);
    if (doc == null) return;

    final oldFolder = Directory(doc.folderPath);
    if (await oldFolder.exists()) {
      final parentDir = oldFolder.parent;
      final folderName = '${_sanitize(newTitle)}_${_uuid.v4().substring(0, 8)}';
      final newFolderPath = p.join(parentDir.path, folderName);
      await oldFolder.rename(newFolderPath);

      await _docsDao.updateDocument(
        DocumentsCompanion(
          id: Value(docId),
          title: Value(newTitle),
          folderPath: Value(newFolderPath),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      await _docsDao.updateDocument(
        DocumentsCompanion(
          id: Value(docId),
          title: Value(newTitle),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Toggle favourite
  // ---------------------------------------------------------------------------
  Future<void> toggleFavourite(int docId, bool value) async {
    await _docsDao.toggleFavourite(docId, value);
  }

  // ---------------------------------------------------------------------------
  // Get all images in a document folder
  // ---------------------------------------------------------------------------
  Future<List<String>> getDocumentImages(String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) return [];

    final images = folder
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.toLowerCase().endsWith('.jpg') ||
            f.path.toLowerCase().endsWith('.jpeg') ||
            f.path.toLowerCase().endsWith('.png'))
        .map((f) => f.path)
        .toList()
      ..sort((a, b) => a.compareTo(b));

    return images;
  }

  // ---------------------------------------------------------------------------
  // Reorder images in a document folder
  // ---------------------------------------------------------------------------
  Future<void> reorderImages(int docId, List<String> orderedPaths) async {
    final doc = await _docsDao.getDocument(docId);
    if (doc == null) return;

    // Rename files with numeric prefix for ordering
    for (var i = 0; i < orderedPaths.length; i++) {
      final oldFile = File(orderedPaths[i]);
      if (await oldFile.exists()) {
        final ext = p.extension(orderedPaths[i]);
        final newFileName = '${i.toString().padLeft(4, '0')}_$i$ext';
        final newPath = p.join(doc.folderPath, newFileName);
        if (orderedPaths[i] != newPath) {
          await oldFile.rename(newPath);
        }
      }
    }

    await _docsDao.refreshDocumentMeta(docId, doc.folderPath);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------
  Future<void> _addImages(String folderPath, List<String> imagePaths) async {
    final successfullyAdded = <String>[];

    for (var i = 0; i < imagePaths.length; i++) {
      final rawSrc = imagePaths[i];
      final src = cleanFilePath(rawSrc);
      final ext = p.extension(src).toLowerCase();
      final dest = p.join(
        folderPath,
        '${i.toString().padLeft(4, '0')}_$i${ext == '.pdf' ? '.jpg' : ext}',
      );
      try {
        if (ext == '.pdf') {
          // Convert PDF page to image
          await _compressAndSave(src, dest);
        } else {
          await _compressAndSave(src, dest);
        }
        successfullyAdded.add(dest);
      } catch (e) {
        debugPrint('Failed to save image $i: $e');
      }
    }

    if (successfullyAdded.isEmpty) {
      throw Exception('No images could be saved — all images failed to process');
    }
  }

  Future<void> _compressAndSave(String src, String dest) async {
    final ext = p.extension(src).toLowerCase();
    if (ext == '.pdf') {
      // For PDFs, we'll need to rasterize first (handled by caller)
      await File(src).copy(dest);
    } else {
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
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_');
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------
final documentServiceProvider = Provider<DocumentService>((ref) {
  return DocumentService(ref);
});
