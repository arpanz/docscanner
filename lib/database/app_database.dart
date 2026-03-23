// lib/database/app_database.dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import 'tables.dart';
import 'daos.dart';

part 'app_database.g.dart';

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------
@DriftDatabase(tables: [Documents], daos: [DocumentsDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal([QueryExecutor? executor])
    : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Drop old tables and recreate for fresh start
      for (final table in allTables) {
        await m.drop(table);
      }
      await m.createAll();
    },
  );
}

// Singleton instance
AppDatabase? _instance;

AppDatabase getDatabase() {
  _instance ??= AppDatabase._internal();
  return _instance!;
}

// ---------------------------------------------------------------------------
// Connection helper
// ---------------------------------------------------------------------------
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, AppConstants.dbName));
    return NativeDatabase.createInBackground(file);
  });
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = getDatabase();
  ref.onDispose(() {
    // Don't close the singleton database
  });
  return db;
});

final documentsDaoProvider = Provider<DocumentsDao>((ref) {
  return ref.watch(appDatabaseProvider).documentsDao;
});
