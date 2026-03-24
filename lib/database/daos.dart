// lib/database/daos.dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'app_database.dart';
import 'tables.dart';

part 'daos.g.dart';

@DriftAccessor(tables: [Documents])
class DocumentsDao extends DatabaseAccessor<AppDatabase>
    with _$DocumentsDaoMixin {
  DocumentsDao(super.db);

  /// Returns an unsorted stream — sorting is handled entirely by
  /// filteredDocumentsProvider on the client side to avoid
  /// double-ordering and flash-of-wrong-order issues.
  Stream<List<Document>> watchAllDocuments() =>
      select(documents).watch();

  Stream<List<Document>> watchFavourites() =>
      (select(documents)
            ..where((d) => d.isFavourite.equals(true)))
          .watch();

  Future<Document?> getDocument(int id) =>
      (select(documents)..where((d) => d.id.equals(id)))
          .getSingleOrNull();

  Future<int> insertDocument(DocumentsCompanion entry) =>
      into(documents).insert(entry);

  Future<bool> updateDocument(DocumentsCompanion entry) =>
      update(documents).replace(entry);

  Future<int> deleteDocument(int id) =>
      (delete(documents)..where((d) => d.id.equals(id))).go();

  Future<void> toggleFavourite(int id, bool value) async {
    await (update(documents)..where((d) => d.id.equals(id))).write(
      DocumentsCompanion(isFavourite: Value(value)),
    );
  }

  /// Refreshes imageCount, coverImagePath, updatedAt from the folder.
  /// Async listing — never blocks the main thread.
  /// PDF-only documents get imageCount = 1 so sort-by-images works.
  Future<void> refreshDocumentMeta(
      int docId, String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      await (update(documents)
            ..where((d) => d.id.equals(docId)))
          .write(
        DocumentsCompanion(
          imageCount: const Value(0),
          coverImagePath: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return;
    }

    final allFiles = await folder
        .list()
        .where((e) => e is File)
        .cast<File>()
        .toList();

    final images = allFiles
        .where((f) =>
            f.path.toLowerCase().endsWith('.jpg') ||
            f.path.toLowerCase().endsWith('.jpeg') ||
            f.path.toLowerCase().endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    if (images.isEmpty) {
      final pdfs = allFiles.where(
          (f) => f.path.toLowerCase().endsWith('.pdf'));
      final hasPdf =
          pdfs.isNotEmpty && await pdfs.first.exists();
      await (update(documents)
            ..where((d) => d.id.equals(docId)))
          .write(
        DocumentsCompanion(
          imageCount: Value(hasPdf ? 1 : 0),
          coverImagePath: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return;
    }

    await (update(documents)
          ..where((d) => d.id.equals(docId)))
        .write(
      DocumentsCompanion(
        imageCount: Value(images.length),
        coverImagePath: Value(images.first.path),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
