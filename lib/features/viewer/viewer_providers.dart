// lib/features/viewer/viewer_providers.dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../shared/services/document_service.dart';

final documentProvider =
    StreamProvider.family<Document?, int>((ref, docId) {
  return ref
      .watch(documentsDaoProvider)
      .getDocument(docId)
      .asStream();
});

final documentImagesProvider =
    FutureProvider.family<List<String>, int>((ref, docId) async {
  final doc = await ref.read(documentsDaoProvider).getDocument(docId);
  if (doc == null) return [];
  
  final docService = ref.read(documentServiceProvider);
  return await docService.getDocumentImages(doc.folderPath);
});
