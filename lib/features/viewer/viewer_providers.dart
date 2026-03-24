// lib/features/viewer/viewer_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';

/// Reactive stream for a single document.
/// Used by DocumentViewerPage to watch renames/deletes in real time.
final documentProvider =
    StreamProvider.family<Document?, int>((ref, docId) {
  final dao = ref.watch(documentsDaoProvider);
  return (dao.select(dao.documents)
        ..where((d) => d.id.equals(docId)))
      .watchSingleOrNull();
});
