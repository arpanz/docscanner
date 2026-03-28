import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSortKey = 'sort_option';
const _kGridKey = 'is_grid_view';
const _kFolderListKey = 'folder_list_view';
const _kFavouritesKey = 'show_favourites_only';
const _kPageSizeKey = 'pdf_page_size';
const _kOnboardingSeenKey = 'has_seen_onboarding';

enum PdfPageSizeOption { a4, letter }

extension PdfPageSizeOptionLabel on PdfPageSizeOption {
  String get label => switch (this) {
    PdfPageSizeOption.a4 => 'A4',
    PdfPageSizeOption.letter => 'US Letter',
  };
}

class PersistentStringNotifier extends Notifier<String> {
  PersistentStringNotifier(this.key, this.fallback);

  final String key;
  final String fallback;

  @override
  String build() {
    _load();
    return fallback;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(key) ?? fallback;
  }

  Future<void> setValue(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }
}

class PersistentBoolNotifier extends Notifier<bool> {
  PersistentBoolNotifier(this.key, this.fallback);

  final String key;
  final bool fallback;

  @override
  bool build() {
    _load();
    return fallback;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(key) ?? fallback;
  }

  Future<void> setValue(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}

class SortPreferenceNotifier extends PersistentStringNotifier {
  SortPreferenceNotifier() : super(_kSortKey, 'dateDesc');
}

class GridPreferenceNotifier extends PersistentBoolNotifier {
  GridPreferenceNotifier() : super(_kGridKey, true);
}

class FolderListPreferenceNotifier extends PersistentBoolNotifier {
  FolderListPreferenceNotifier() : super(_kFolderListKey, true);
}

class FavouritesPreferenceNotifier extends PersistentBoolNotifier {
  FavouritesPreferenceNotifier() : super(_kFavouritesKey, false);
}

class PageSizePreferenceNotifier extends PersistentStringNotifier {
  PageSizePreferenceNotifier()
    : super(_kPageSizeKey, PdfPageSizeOption.a4.name);
}

class OnboardingPreferenceNotifier extends PersistentBoolNotifier {
  OnboardingPreferenceNotifier() : super(_kOnboardingSeenKey, false);
}

final sortPreferenceProvider = NotifierProvider<SortPreferenceNotifier, String>(
  SortPreferenceNotifier.new,
);

final gridPreferenceProvider = NotifierProvider<GridPreferenceNotifier, bool>(
  GridPreferenceNotifier.new,
);

final folderListPreferenceProvider =
    NotifierProvider<FolderListPreferenceNotifier, bool>(
      FolderListPreferenceNotifier.new,
    );

final favouritesPreferenceProvider =
    NotifierProvider<FavouritesPreferenceNotifier, bool>(
      FavouritesPreferenceNotifier.new,
    );

final pageSizePreferenceProvider =
    NotifierProvider<PageSizePreferenceNotifier, String>(
      PageSizePreferenceNotifier.new,
    );

final onboardingSeenProvider =
    NotifierProvider<OnboardingPreferenceNotifier, bool>(
      OnboardingPreferenceNotifier.new,
    );
