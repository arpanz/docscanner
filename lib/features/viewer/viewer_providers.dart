// lib/features/viewer/viewer_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';

final documentProvider =
    StreamProvider.family<Document?, int>((ref, docId) {
  return ref
      .watch(documentsDaoProvider)
      .getDocument(docId)
      .asStream();
});

final documentPagesProvider =
    StreamProvider.family<List<Page>, int>((ref, docId) {
  return ref.watch(pagesDaoProvider).watchPagesForDocument(docId);
});
