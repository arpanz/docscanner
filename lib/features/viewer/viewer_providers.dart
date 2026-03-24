// lib/features/viewer/viewer_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../shared/services/document_service.dart';

// Reactive stream — watches single document, updates on rename/delete
final documentProvider =
    StreamProvider.family<Document?, int>((ref, docId) {
  final dao = ref.watch(documentsDaoProvider);
  return (dao.select(dao.documents)
        ..where((d) => d.id.equals(docId)))
      .watchSingleOrNull();
});

// FutureProvider for images — invalidated when service mutates folder
final documentImagesProvider =
    FutureProvider.family<List<String>, int>((ref, docId) async {
  final doc = await ref.read(documentsDaoProvider).getDocument(docId);
  if (doc == null) return [];
  final docService = ref.read(documentServiceProvider);
  return docService.getDocumentImages(doc.folderPath);
});
