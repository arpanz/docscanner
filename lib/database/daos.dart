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

  Stream<List<Document>> watchAllDocuments() => (select(
        documents,
      )..orderBy([(d) => OrderingTerm.desc(d.updatedAt)])).watch();

  Stream<List<Document>> watchFavourites() =>
      (select(documents)
            ..where((d) => d.isFavourite.equals(true))
            ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]))
          .watch();

  Future<Document?> getDocument(int id) =>
      (select(documents)..where((d) => d.id.equals(id))).getSingleOrNull();

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

  /// Refreshes imageCount, coverImagePath, and updatedAt from the folder.
  /// Uses async list() to avoid blocking the main thread.
  /// For PDF-only documents, sets imageCount = 1 so sorting works.
  Future<void> refreshDocumentMeta(int docId, String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      await (update(documents)..where((d) => d.id.equals(docId))).write(
        DocumentsCompanion(
          imageCount: const Value(0),
          coverImagePath: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return;
    }

    // Use async listing — never block the main thread
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
      final pdf = allFiles.where(
          (f) => f.path.toLowerCase().endsWith('.pdf'));
      final hasPdf = pdf.isNotEmpty && await pdf.first.exists();
      await (update(documents)..where((d) => d.id.equals(docId))).write(
        DocumentsCompanion(
          imageCount: Value(hasPdf ? 1 : 0),
          coverImagePath: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return;
    }

    await (update(documents)..where((d) => d.id.equals(docId))).write(
      DocumentsCompanion(
        imageCount: Value(images.length),
        coverImagePath: Value(images.first.path),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
