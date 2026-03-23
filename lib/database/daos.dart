// lib/database/daos.dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'app_database.dart';
import 'tables.dart';

part 'daos.g.dart';

// ---------------------------------------------------------------------------
// Documents DAO - lightweight metadata for folder-based storage
// ---------------------------------------------------------------------------
@DriftAccessor(tables: [Documents])
class DocumentsDao extends DatabaseAccessor<AppDatabase>
    with _$DocumentsDaoMixin {
  DocumentsDao(super.db);

  // Watch all documents ordered by updatedAt desc
  Stream<List<Document>> watchAllDocuments() => (select(
    documents,
  )..orderBy([(d) => OrderingTerm.desc(d.updatedAt)])).watch();

  // Watch favourites only
  Stream<List<Document>> watchFavourites() =>
      (select(documents)
            ..where((d) => d.isFavourite.equals(true))
            ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]))
          .watch();

  // Get single document by id
  Future<Document?> getDocument(int id) =>
      (select(documents)..where((d) => d.id.equals(id))).getSingleOrNull();

  // Insert a new document, returns its id
  Future<int> insertDocument(DocumentsCompanion entry) =>
      into(documents).insert(entry);

  // Update document fields
  Future<bool> updateDocument(DocumentsCompanion entry) =>
      update(documents).replace(entry);

  // Delete document row (caller must delete folder separately)
  Future<int> deleteDocument(int id) =>
      (delete(documents)..where((d) => d.id.equals(id))).go();

  // Toggle favourite
  Future<void> toggleFavourite(int id, bool value) async {
    await (update(documents)..where((d) => d.id.equals(id))).write(
      DocumentsCompanion(isFavourite: Value(value)),
    );
  }

  // Update image count + cover + updatedAt after any image mutation
  Future<void> refreshDocumentMeta(int docId, String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      await (update(documents)..where((d) => d.id.equals(docId))).write(
        DocumentsCompanion(
          imageCount: Value(0),
          coverImagePath: Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return;
    }

    final images = folder
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.toLowerCase().endsWith('.jpg') ||
            f.path.toLowerCase().endsWith('.jpeg') ||
            f.path.toLowerCase().endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    await (update(documents)..where((d) => d.id.equals(docId))).write(
      DocumentsCompanion(
        imageCount: Value(images.length),
        coverImagePath: Value(images.isEmpty ? null : images.first.path),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
