// lib/database/tables.dart
import 'package:drift/drift.dart';

// ---------------------------------------------------------------------------
// Documents table
// ---------------------------------------------------------------------------
class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  TextColumn get coverPagePath => text().nullable()();
  BoolColumn get isFavourite => boolean().withDefault(const Constant(false))();
  TextColumn get ocrText => text().nullable()();
}

// ---------------------------------------------------------------------------
// Pages table
// ---------------------------------------------------------------------------
class Pages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId => integer().references(Documents, #id)();
  TextColumn get imagePath => text()();
  IntColumn get pageIndex => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
