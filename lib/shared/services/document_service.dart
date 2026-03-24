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

  Future<Directory> _documentsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'documents'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

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
      await folder.delete(recursive: true);
      await _docsDao.deleteDocument(docId);
      rethrow;
    }
  }

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

  Future<void> addImages(int docId, List<String> imagePaths) async {
    final doc = await _docsDao.getDocument(docId);
    if (doc == null) throw Exception('Document not found');
    await _addImages(doc.folderPath, imagePaths);
    await _docsDao.refreshDocumentMeta(docId, doc.folderPath);
  }

  Future<void> deleteDocument(int docId) async {
    final doc = await _docsDao.getDocument(docId);
    if (doc == null) return;
    try {
      final folder = Directory(doc.folderPath);
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (_) {}
    await _docsDao.deleteDocument(docId);
  }

  Future<void> deleteImages(int docId, List<String> imagePaths) async {
    final doc = await _docsDao.getDocument(docId);
    if (doc == null) return;
    for (final path in imagePaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _docsDao.refreshDocumentMeta(docId, doc.folderPath);
  }

  /// Renames the document title and folder. Also updates pdfPath if it
  /// lives inside the old folder, so no stale paths remain in the DB.
  Future<void> renameDocument(int docId, String newTitle) async {
    final doc = await _docsDao.getDocument(docId);
    if (doc == null) return;

    final oldFolder = Directory(doc.folderPath);
    if (await oldFolder.exists()) {
      final parentDir = oldFolder.parent;
      final folderName =
          '${_sanitize(newTitle)}_${_uuid.v4().substring(0, 8)}';
      final newFolderPath = p.join(parentDir.path, folderName);
      await oldFolder.rename(newFolderPath);

      // Recalculate pdfPath if it was inside the old folder
      String? newPdfPath;
      if (doc.pdfPath != null &&
          doc.pdfPath!.startsWith(doc.folderPath)) {
        final relativePdf =
            doc.pdfPath!.substring(doc.folderPath.length);
        newPdfPath = newFolderPath + relativePdf;
      }

      await _docsDao.updateDocument(
        DocumentsCompanion(
          id: Value(docId),
          title: Value(newTitle),
          folderPath: Value(newFolderPath),
          pdfPath: newPdfPath != null
              ? Value(newPdfPath)
              : const Value.absent(),
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

  Future<void> toggleFavourite(int docId, bool value) async {
    await _docsDao.toggleFavourite(docId, value);
  }

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

  /// Saves a built PDF into the document's own folder (not the app root).
  /// Returns the path of the saved PDF.
  /// Naming includes a timestamp to avoid silent overwrites.
  Future<String> savePdfToDocumentFolder(
      int docId, File tempPdf) async {
    final doc = await _docsDao.getDocument(docId);
    if (doc == null) throw Exception('Document not found');

    final timestamp =
        DateTime.now().millisecondsSinceEpoch.toString();
    final dest = p.join(
      doc.folderPath,
      '${_sanitize(doc.title)}_$timestamp.pdf',
    );
    final saved = await tempPdf.copy(dest);

    // Update pdfPath in DB
    await _docsDao.updateDocument(
      DocumentsCompanion(
        id: Value(docId),
        pdfPath: Value(saved.path),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return saved.path;
  }

  /// Reorder images using a temp-rename strategy to avoid name conflicts.
  Future<void> reorderImages(int docId, List<String> orderedPaths) async {
    final doc = await _docsDao.getDocument(docId);
    if (doc == null) return;

    // Step 1 — rename all to temp names
    final tempPaths = <String>[];
    for (var i = 0; i < orderedPaths.length; i++) {
      final file = File(orderedPaths[i]);
      if (await file.exists()) {
        final ext = p.extension(orderedPaths[i]);
        final tempPath = p.join(doc.folderPath, 'tmp_$i$ext');
        await file.rename(tempPath);
        tempPaths.add(tempPath);
      } else {
        tempPaths.add(orderedPaths[i]);
      }
    }

    // Step 2 — rename from temp to final sorted names
    for (var i = 0; i < tempPaths.length; i++) {
      final file = File(tempPaths[i]);
      if (await file.exists()) {
        final ext = p.extension(tempPaths[i]);
        final finalPath = p.join(
            doc.folderPath, '${i.toString().padLeft(4, '0')}$ext');
        await file.rename(finalPath);
      }
    }

    await _docsDao.refreshDocumentMeta(docId, doc.folderPath);
  }

  Future<void> _addImages(
      String folderPath, List<String> imagePaths) async {
    final existing = Directory(folderPath)
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.toLowerCase().endsWith('.jpg') ||
            f.path.toLowerCase().endsWith('.jpeg') ||
            f.path.toLowerCase().endsWith('.png'))
        .length;

    final successfullyAdded = <String>[];
    for (var i = 0; i < imagePaths.length; i++) {
      final rawSrc = imagePaths[i];
      final src = cleanFilePath(rawSrc);
      final ext = p.extension(src).toLowerCase();
      final idx = existing + i;
      final dest = p.join(
        folderPath,
        '${idx.toString().padLeft(4, '0')}${ext == '.pdf' ? '.jpg' : ext}',
      );
      try {
        await _compressAndSave(src, dest);
        successfullyAdded.add(dest);
      } catch (e) {
        debugPrint('Failed to save image $i: $e');
      }
    }

    if (successfullyAdded.isEmpty) {
      throw Exception(
          'No images could be saved — all images failed to process');
    }
  }

  Future<void> _compressAndSave(String src, String dest) async {
    final ext = p.extension(src).toLowerCase();
    if (ext == '.pdf') {
      await File(src).copy(dest);
    } else {
      final result = await FlutterImageCompress.compressAndGetFile(
        src,
        dest,
        quality: AppConstants.defaultJpegQuality,
      );
      if (result == null) await File(src).copy(dest);
    }
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_');
}

final documentServiceProvider = Provider<DocumentService>((ref) {
  return DocumentService(ref);
});
