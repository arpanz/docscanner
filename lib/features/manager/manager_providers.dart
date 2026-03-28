// lib/features/manager/manager_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/app_database.dart';

// ---------------------------------------------------------------------------
// Sort options
// ---------------------------------------------------------------------------
enum SortOption { dateDesc, dateAsc, nameAsc, nameDesc, pagesDesc }

extension SortOptionLabel on SortOption {
  String get label => switch (this) {
    SortOption.dateDesc => 'Newest first',
    SortOption.dateAsc => 'Oldest first',
    SortOption.nameAsc => 'Name A–Z',
    SortOption.nameDesc => 'Name Z–A',
    SortOption.pagesDesc => 'Most images',
  };
}

// ---------------------------------------------------------------------------
// Persisted preference notifiers
// ---------------------------------------------------------------------------
const _kSortOption = 'sort_option';
const _kIsGridView = 'is_grid_view';
const _kShowFavouritesOnly = 'show_favourites_only';

class SortOptionNotifier extends Notifier<SortOption> {
  @override
  SortOption build() {
    _loadSaved();
    return SortOption.dateDesc;
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_kSortOption);
    if (idx != null && idx < SortOption.values.length) {
      state = SortOption.values[idx];
    }
  }

  Future<void> set(SortOption option) async {
    state = option;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSortOption, option.index);
  }
}

class IsGridViewNotifier extends Notifier<bool> {
  @override
  bool build() {
    _loadSaved();
    return true;
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getBool(_kIsGridView);
    if (val != null) state = val;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsGridView, state);
  }
}

class ShowFavouritesOnlyNotifier extends Notifier<bool> {
  @override
  bool build() {
    _loadSaved();
    return false;
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getBool(_kShowFavouritesOnly);
    if (val != null) state = val;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowFavouritesOnly, state);
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final sortOptionProvider =
    NotifierProvider<SortOptionNotifier, SortOption>(SortOptionNotifier.new);

final searchQueryProvider = StateProvider<String>((_) => '');

final isGridViewProvider =
    NotifierProvider<IsGridViewNotifier, bool>(IsGridViewNotifier.new);

final showFavouritesOnlyProvider =
    NotifierProvider<ShowFavouritesOnlyNotifier, bool>(
        ShowFavouritesOnlyNotifier.new);

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
        ? List<Document>.from(docs)
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
