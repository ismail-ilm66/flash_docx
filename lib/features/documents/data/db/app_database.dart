import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:injectable/injectable.dart';

part 'app_database.g.dart';

@DataClassName('DocumentRow')
class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get mode => intEnum<ScanMode>()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PageRow')
class Pages extends Table {
  TextColumn get id => text()();
  TextColumn get documentId =>
      text().references(Documents, #id, onDelete: KeyAction.cascade)();
  TextColumn get originalPath => text()();
  TextColumn get editsJson => text()();
  IntColumn get pageOrder => integer()();
  IntColumn get side => intEnum<CardSide>().nullable()();
  TextColumn get processedPath => text().nullable()();
  TextColumn get thumbPath => text().nullable()();
  TextColumn get ocrText => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ActivityRow')
class Activities extends Table {
  TextColumn get id => text()();
  TextColumn get documentId =>
      text().references(Documents, #id, onDelete: KeyAction.cascade)();
  IntColumn get type => intEnum<ActivityType>()();
  DateTimeColumn get at => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@lazySingleton
@DriftDatabase(tables: [Documents, Pages, Activities])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'flashdox'));

  /// For tests.
  AppDatabase.test(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  @disposeMethod
  Future<void> dispose() => close();

  // ---------- mapping ----------

  static ScanPage pageFromRow(PageRow r) => ScanPage(
        id: r.id,
        documentId: r.documentId,
        originalPath: r.originalPath,
        edits: PageEdits.fromJson(jsonDecode(r.editsJson) as Map<String, dynamic>),
        order: r.pageOrder,
        side: r.side,
        processedPath: r.processedPath,
        thumbPath: r.thumbPath,
        ocrText: r.ocrText,
      );

  static PagesCompanion pageToCompanion(ScanPage p) => PagesCompanion.insert(
        id: p.id,
        documentId: p.documentId,
        originalPath: p.originalPath,
        editsJson: jsonEncode(p.edits.toJson()),
        pageOrder: p.order,
        side: Value(p.side),
        processedPath: Value(p.processedPath),
        thumbPath: Value(p.thumbPath),
        ocrText: Value(p.ocrText),
      );

  static Activity activityFromRow(ActivityRow r) => Activity(
        id: r.id,
        documentId: r.documentId,
        type: r.type,
        at: r.at,
      );
}
