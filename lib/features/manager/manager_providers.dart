import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_prefs.dart';
import '../../database/app_database.dart';

enum SortOption { dateDesc, dateAsc, nameAsc, nameDesc, pagesDesc }

extension SortOptionLabel on SortOption {
  String get label => switch (this) {
        SortOption.dateDesc => 'Newest first',
        SortOption.dateAsc => 'Oldest first',
        SortOption.nameAsc => 'Name A-Z',
        SortOption.nameDesc => 'Name Z-A',
        SortOption.pagesDesc => 'Most images',
      };
}

extension SortOptionStorage on SortOption {
  static SortOption fromStoredValue(String value) {
    return SortOption.values.firstWhere(
      (option) => option.name == value,
      orElse: () => SortOption.dateDesc,
    );
  }
}

final searchQueryProvider = StateProvider<String>((_) => '');

final sortOptionProvider = Provider<SortOption>((ref) {
  final stored = ref.watch(sortPreferenceProvider);
  return SortOptionStorage.fromStoredValue(stored);
});

final isGridViewProvider = Provider<bool>((ref) {
  return ref.watch(gridPreferenceProvider);
});

final showFavouritesOnlyProvider = Provider<bool>((ref) {
  return ref.watch(favouritesPreferenceProvider);
});

final allDocumentsProvider = StreamProvider<List<Document>>((ref) {
  final dao = ref.watch(documentsDaoProvider);
  final showFavourites = ref.watch(showFavouritesOnlyProvider);
  if (showFavourites) return dao.watchFavourites();
  return dao.watchAllDocuments();
});

final filteredDocumentsProvider = Provider<AsyncValue<List<Document>>>((ref) {
  final allAsync = ref.watch(allDocumentsProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final sort = ref.watch(sortOptionProvider);

  return allAsync.whenData((docs) {
    var filtered = query.isEmpty
        ? docs.toList()
        : docs.where((d) => d.title.toLowerCase().contains(query)).toList();

    filtered.sort(
      (a, b) => switch (sort) {
        SortOption.dateDesc => b.updatedAt.compareTo(a.updatedAt),
        SortOption.dateAsc => a.updatedAt.compareTo(b.updatedAt),
        SortOption.nameAsc => a.title.compareTo(b.title),
        SortOption.nameDesc => b.title.compareTo(a.title),
        SortOption.pagesDesc => b.imageCount.compareTo(a.imageCount),
      },
    );

    return filtered;
  });
});
