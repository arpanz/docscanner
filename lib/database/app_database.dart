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

  /// Migration history:
  ///   v1 → initial schema (id, title, createdAt, updatedAt, folderPath)
  ///   v2 → added pdfPath, imageCount, coverImagePath
  ///   v3 → added isFavourite
  ///
  /// NEVER drop tables on upgrade — that deletes user data.
  /// Always use additive migrations (addColumn / createTable).
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          await m.runMigrationSteps(
            from: from,
            to: to,
            steps: MigrationStepWithVersion(
              (stepFrom, stepTo, migrator) async {
                if (stepFrom == 1) {
                  // v1 → v2: add pdfPath, imageCount, coverImagePath
                  await migrator.addColumn(
                      documents, documents.pdfPath);
                  await migrator.addColumn(
                      documents, documents.imageCount);
                  await migrator.addColumn(
                      documents, documents.coverImagePath);
                }
                if (stepFrom == 2) {
                  // v2 → v3: add isFavourite
                  await migrator.addColumn(
                      documents, documents.isFavourite);
                }
              },
            ),
          );
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
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
// Riverpod providers
// ---------------------------------------------------------------------------
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = getDatabase();
  ref.onDispose(() {
    // Don't close the singleton
  });
  return db;
});

final documentsDaoProvider = Provider<DocumentsDao>((ref) {
  return ref.watch(appDatabaseProvider).documentsDao;
});
