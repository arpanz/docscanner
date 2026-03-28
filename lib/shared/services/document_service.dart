// lib/shared/services/document_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
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
    final folderName =
        '${_sanitize(title)}_${_uuid.v4().substring(0, 8)}';
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

  /// Creates a document from a scanned PDF.
  /// Also rasters page 1 to a PNG cover so the card shows a thumbnail
  /// instead of initials.
  Future<int> createDocumentFromPdf({
    required String title,
    required String pdfPath,
    required int pageCount,
  }) async {
    final docsDir = await _documentsDir();
    final folderName =
        '${_sanitize(title)}_${_uuid.v4().substring(0, 8)}';
    final folderPath = p.join(docsDir.path, folderName);
    final folder = Directory(folderPath);
    await folder.create(recursive: true);

    final cleanPath = cleanFilePath(pdfPath);
    final pdfDest =
        p.join(folderPath, '${_sanitize(title)}.pdf');
    await File(cleanPath).copy(pdfDest);

    final docId = await _docsDao.insertDocument(
      DocumentsCompanion(
        title: Value(title),
        folderPath: Value(folderPath),
        pdfPath: Value(pdfDest),
      ),
    );

    try {
      await _rasterPdfCover(cleanPath, folderPath);
      await _docsDao.refreshDocumentMeta(docId, folderPath);
      return docId;
    } catch (e) {
      await folder.delete(recursive: true);
      await _docsDao.deleteDocument(docId);
      rethrow;
    }
  }

  /// Rasters the first page of a PDF and saves it as `cover.png`
  /// (prefixed with `~` so _addImages excludes it from user-page counting).
  Future<void> _rasterPdfCover(
      String pdfPath, String folderPath) async {
    try {
      final bytes = await File(pdfPath).readAsBytes();
      final rasters =
          await Printing.raster(bytes, pages: [0], dpi: 150).toList();
      if (rasters.isEmpty) return;
      final png = await rasters.first.toPng();
      // Prefix with '~' so it sorts last and is excluded from
      // user-page index counting in _addImages.
      final coverPath = p.join(folderPath, '~cover.png');
      await File(coverPath).writeAsBytes(png);
    } catch (e) {
      debugPrint('Cover raster failed: $e');
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
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
    } catch (_) {}
    await _docsDao.deleteDocument(docId);
  }

  Future<void> deleteImages(
      int docId, List<String> imagePaths) async {
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

      // Fix: refresh cover/imageCount so they point to the new folder path
      await _docsDao.refreshDocumentMeta(docId, newFolderPath);
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

  Future<void> refreshAllDocumentsMeta() async {
    final docs = await _docsDao.getAllDocuments();
    for (final doc in docs) {
      await _docsDao.refreshDocumentMeta(doc.id, doc.folderPath);
    }
  }

  /// Returns user-page images only — excludes the cover file (~cover.png)
  /// and any other internal files.
  Future<List<String>> getDocumentImages(
      String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) return [];
    final images = folder
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = p.basename(f.path);
          // Exclude the raster cover and any temp files
          if (name.startsWith('~')) return false;
          return f.path.toLowerCase().endsWith('.jpg') ||
              f.path.toLowerCase().endsWith('.jpeg') ||
              f.path.toLowerCase().endsWith('.png');
        })
        .map((f) => f.path)
        .toList()
      ..sort((a, b) => a.compareTo(b));
    return images;
  }

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

    await _docsDao.updateDocument(
      DocumentsCompanion(
        id: Value(docId),
        pdfPath: Value(saved.path),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // Fix: refresh so imageCount/coverImagePath stay accurate after PDF is added
    await _docsDao.refreshDocumentMeta(docId, doc.folderPath);

    return saved.path;
  }

  /// Reorders images in the document folder using a two-phase rename.
  /// Phase 1: rename each file to a temp name to avoid collisions.
  /// Phase 2: rename each temp file to its final zero-padded name.
  /// On any error in phase 2, attempts to restore original names.
  Future<void> reorderImages(
      int docId, List<String> orderedPaths) async {
    final doc = await _docsDao.getDocument(docId);
    if (doc == null) return;

    // Phase 1: rename to temp names, record originals for rollback
    final tempPaths = <String>[];
    final originalPaths = List<String>.from(orderedPaths);
    for (var i = 0; i < orderedPaths.length; i++) {
      final file = File(orderedPaths[i]);
      if (await file.exists()) {
        final ext = p.extension(orderedPaths[i]);
        final tempPath =
            p.join(doc.folderPath, 'tmp_$i$ext');
        await file.rename(tempPath);
        tempPaths.add(tempPath);
      } else {
        tempPaths.add(orderedPaths[i]); // keep original if missing
      }
    }

    // Phase 2: rename to final zero-padded names, with rollback on error
    final successfullyRenamed = <MapEntry<String, String>>[];
    try {
      for (var i = 0; i < tempPaths.length; i++) {
        final file = File(tempPaths[i]);
        if (await file.exists()) {
          final ext = p.extension(tempPaths[i]);
          final finalPath = p.join(
              doc.folderPath,
              '${i.toString().padLeft(4, '0')}$ext');
          await file.rename(finalPath);
          successfullyRenamed.add(MapEntry(finalPath, originalPaths[i]));
        }
      }
    } catch (e) {
      debugPrint('reorderImages phase-2 failed, attempting rollback: $e');
      for (final renamed in successfullyRenamed.reversed) {
        try {
          final finalFile = File(renamed.key);
          if (await finalFile.exists()) {
            await finalFile.rename(renamed.value);
          }
        } catch (_) {}
      }
      for (var i = 0; i < tempPaths.length; i++) {
        try {
          final tempFile = File(tempPaths[i]);
          if (await tempFile.exists()) {
            await tempFile.rename(originalPaths[i]);
          }
        } catch (_) {}
      }
      rethrow;
    }

    await _docsDao.refreshDocumentMeta(docId, doc.folderPath);
  }

  Future<void> _addImages(
      String folderPath, List<String> imagePaths) async {
    // Fix: exclude the raster cover (~cover.png) and any non-user files
    // from the existing count so new pages are indexed correctly.
    final existing = Directory(folderPath)
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = p.basename(f.path);
          if (name.startsWith('~')) return false;
          return f.path.toLowerCase().endsWith('.jpg') ||
              f.path.toLowerCase().endsWith('.jpeg') ||
              f.path.toLowerCase().endsWith('.png');
        })
        .length;

    final successfullyAdded = <String>[];
    for (var i = 0; i < imagePaths.length; i++) {
      final rawSrc = imagePaths[i];
      final src = cleanFilePath(rawSrc);
      final srcExt = p.extension(src).toLowerCase();
      final idx = existing + i;
      // Fix: preserve original extension — don't force .jpg for .png sources
      final destExt = (srcExt == '.pdf') ? '.jpg' : srcExt;
      final dest = p.join(
        folderPath,
        '${idx.toString().padLeft(4, '0')}$destExt',
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
    final srcExt = p.extension(src).toLowerCase();
    if (srcExt == '.pdf') {
      await File(src).copy(dest);
    } else {
      final result =
          await FlutterImageCompress.compressAndGetFile(
        src,
        dest,
        quality: AppConstants.defaultJpegQuality,
      );
      // Fallback: copy as-is if compression fails.
      // dest extension already matches src extension (fixed in _addImages)
      // so the copied file will be valid.
      if (result == null) await File(src).copy(dest);
    }
  }

  String _sanitize(String name) => name
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .trim()
      .replaceAll(' ', '_');

  Future<void> backupOriginalImage(String imagePath) async {
    final file = File(imagePath);
    final backup = File('$imagePath.bak');
    if (!await file.exists() || await backup.exists()) return;
    await file.copy(backup.path);
  }

  Future<bool> hasAnyBackups(String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) return false;
    await for (final entity in folder.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.bak')) {
        return true;
      }
    }
    return false;
  }

  Future<int> restoreBackups(int docId, String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) return 0;

    var restored = 0;
    await for (final entity in folder.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.bak')) {
        continue;
      }
      final originalPath = entity.path.substring(0, entity.path.length - 4);
      try {
        await entity.copy(originalPath);
        await entity.delete();
        restored++;
      } catch (_) {}
    }

    await _docsDao.refreshDocumentMeta(docId, folderPath);
    return restored;
  }
}

final documentServiceProvider =
    Provider<DocumentService>((ref) => DocumentService(ref));
