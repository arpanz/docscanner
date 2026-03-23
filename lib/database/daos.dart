// lib/database/daos.dart
import 'package:drift/drift.dart';
import 'app_database.dart';
import 'tables.dart';

part 'daos.g.dart';

// ---------------------------------------------------------------------------
// Documents DAO
// ---------------------------------------------------------------------------
@DriftAccessor(tables: [Documents, Pages])
class DocumentsDao extends DatabaseAccessor<AppDatabase>
    with _$DocumentsDaoMixin {
  DocumentsDao(super.db);

  // Watch all documents ordered by updatedAt desc
  Stream<List<Document>> watchAllDocuments() =>
      (select(documents)..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]))
          .watch();

  // Watch favourites only
  Stream<List<Document>> watchFavourites() => (select(documents)
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

  // Delete document row (caller must delete page files + rows separately)
  Future<int> deleteDocument(int id) =>
      (delete(documents)..where((d) => d.id.equals(id))).go();

  // Toggle favourite
  Future<void> toggleFavourite(int id, bool value) async {
    await (update(documents)..where((d) => d.id.equals(id))).write(
      DocumentsCompanion(isFavourite: Value(value)),
    );
  }

  // Update page count + cover + updatedAt after any page mutation
  Future<void> refreshDocumentMeta(int docId) async {
    final pageRows = await (select(pages)
          ..where((p) => p.documentId.equals(docId))
          ..orderBy([(p) => OrderingTerm.asc(p.pageIndex)]))
        .get();
    await (update(documents)..where((d) => d.id.equals(docId))).write(
      DocumentsCompanion(
        pageCount: Value(pageRows.length),
        coverPagePath: Value(pageRows.isEmpty ? null : pageRows.first.imagePath),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pages DAO
// ---------------------------------------------------------------------------
@DriftAccessor(tables: [Pages])
class PagesDao extends DatabaseAccessor<AppDatabase> with _$PagesDaoMixin {
  PagesDao(super.db);

  // Watch pages for a document ordered by pageIndex
  Stream<List<Page>> watchPagesForDocument(int docId) =>
      (select(pages)
            ..where((p) => p.documentId.equals(docId))
            ..orderBy([(p) => OrderingTerm.asc(p.pageIndex)]))
          .watch();

  Future<List<Page>> getPagesForDocument(int docId) =>
      (select(pages)
            ..where((p) => p.documentId.equals(docId))
            ..orderBy([(p) => OrderingTerm.asc(p.pageIndex)]))
          .get();

  Future<int> insertPage(PagesCompanion entry) => into(pages).insert(entry);

  Future<void> reorderPages(int docId, List<int> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await (update(pages)..where((p) => p.id.equals(orderedIds[i]))).write(
        PagesCompanion(pageIndex: Value(i)),
      );
    }
  }

  Future<int> deletePage(int pageId) =>
      (delete(pages)..where((p) => p.id.equals(pageId))).go();

  Future<int> deletePagesForDocument(int docId) =>
      (delete(pages)..where((p) => p.documentId.equals(docId))).go();
}
