// lib/database/tables.dart
import 'package:drift/drift.dart';

// ---------------------------------------------------------------------------
// Documents table - lightweight metadata for folder-based storage
// ---------------------------------------------------------------------------
class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get folderPath => text()(); // Path to the document folder
  TextColumn get pdfPath => text().nullable()(); // Path to generated PDF (if any)
  IntColumn get imageCount => integer().withDefault(const Constant(0))();
  TextColumn get coverImagePath => text().nullable()(); // First image as cover
  BoolColumn get isFavourite => boolean().withDefault(const Constant(false))();
}
