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

  /// v3: Home folder, and the smart-name suggestion as JSON.
  IntColumn get folder => intEnum<DocFolder>().withDefault(const Constant(0))();
  TextColumn get suggestion => text().nullable()();

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
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 ScanMode: single=0, batch=1, idCard=2, passport=3.
            // v2 ScanMode: document=0, idCard=1, passport=2.
            await customStatement(
              'UPDATE documents SET mode = CASE mode '
              'WHEN 0 THEN 0 WHEN 1 THEN 0 WHEN 2 THEN 1 WHEN 3 THEN 2 ELSE 0 END',
            );
          }
          if (from < 3) {
            await m.addColumn(documents, documents.folder);
            await m.addColumn(documents, documents.suggestion);
            // ID cards and passports go to the IDs folder.
            await customStatement(
              'UPDATE documents SET folder = ${DocFolder.ids.index} '
              'WHERE mode IN (${ScanMode.idCard.index}, ${ScanMode.passport.index})',
            );
          }
        },
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

  static NameSuggestion? suggestionFromJson(String? json) {
    if (json == null) return null;
    try {
      return NameSuggestion.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  static String? suggestionToJson(NameSuggestion? s) => s == null ? null : jsonEncode(s.toJson());

  static Activity activityFromRow(ActivityRow r) => Activity(
        id: r.id,
        documentId: r.documentId,
        type: r.type,
        at: r.at,
      );
}
