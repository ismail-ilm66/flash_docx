import 'package:drift/native.dart';
import 'package:flash_dox/features/documents/data/db/app_database.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

// The exact v2 schema (captured from schemaVersion 2 before the change).
const v2 = [
  'CREATE TABLE "documents" ("id" TEXT NOT NULL, "title" TEXT NOT NULL, "mode" INTEGER NOT NULL, "created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "pages" ("id" TEXT NOT NULL, "document_id" TEXT NOT NULL REFERENCES documents (id) ON DELETE CASCADE, "original_path" TEXT NOT NULL, "edits_json" TEXT NOT NULL, "page_order" INTEGER NOT NULL, "side" INTEGER NULL, "processed_path" TEXT NULL, "thumb_path" TEXT NULL, "ocr_text" TEXT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "activities" ("id" TEXT NOT NULL, "document_id" TEXT NOT NULL REFERENCES documents (id) ON DELETE CASCADE, "type" INTEGER NOT NULL, "at" TEXT NOT NULL, PRIMARY KEY ("id"))',
];

/// v1 stored ScanMode { single, batch, idCard, passport } by index. v2 has
/// { document, idCard, passport }; existing rows must keep their meaning.
void main() {
  test('v1 → v2 maps single/batch to document and shifts ID/passport', () async {
    final raw = sqlite3.openInMemory();
    // v1 had the same tables as v2; only the mode values differ.
    v2.forEach(raw.execute);
    final now = DateTime(2026).toIso8601String();
    for (final (id, v1Mode) in [('single', 0), ('batch', 1), ('id', 2), ('passport', 3)]) {
      raw.execute(
        'INSERT INTO documents (id, title, mode, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [id, id, v1Mode, now, now],
      );
    }
    raw.execute('PRAGMA user_version = 1;');

    final db = AppDatabase.test(NativeDatabase.opened(raw));
    final rows = await db.select(db.documents).get();
    final modes = {for (final r in rows) r.id: r.mode};
    expect(modes, {
      'single': ScanMode.document,
      'batch': ScanMode.document,
      'id': ScanMode.idCard,
      'passport': ScanMode.passport,
    });
    await db.close();
  });

  group('v2 → v3 (folders + smart names)', () {

    Map<String, List<String>> columns(Database raw) => {
          for (final t in ['documents', 'pages', 'activities'])
            t: [
              for (final r in raw.select('PRAGMA table_info("$t")'))
                '${r['name']} ${r['type']} notnull=${r['notnull']} default=${r['dflt_value']} pk=${r['pk']}',
            ],
        };

    test('adds folder and suggestion, files cards under IDs, keeps the data', () async {
      final raw = sqlite3.openInMemory();
      v2.forEach(raw.execute);
      final now = DateTime(2026, 11, 5).toIso8601String();
      for (final (id, mode) in [('doc', 0), ('id', 1), ('passport', 2)]) {
        raw.execute(
          'INSERT INTO documents (id, title, mode, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
          [id, 'Title $id', mode, now, now],
        );
      }
      raw.execute(
        'INSERT INTO pages (id, document_id, original_path, edits_json, page_order) VALUES (?, ?, ?, ?, ?)',
        ['p', 'doc', '/x.jpg', '{}', 0],
      );
      raw.execute('PRAGMA user_version = 2;');

      final db = AppDatabase.test(NativeDatabase.opened(raw, closeUnderlyingOnClose: false));
      final rows = await db.select(db.documents).get();
      expect({for (final r in rows) r.id: r.folder}, {
        'doc': DocFolder.other,
        'id': DocFolder.ids,
        'passport': DocFolder.ids,
      });
      expect(rows.every((r) => r.suggestion == null), isTrue);
      expect(rows.firstWhere((r) => r.id == 'doc').title, 'Title doc');
      expect(await db.select(db.pages).get(), hasLength(1));
      expect(raw.select('PRAGMA user_version').first.values.first, db.schemaVersion);

      // Same schema as a database created fresh at v3 (what drift's
      // SchemaVerifier checks).
      final fresh = sqlite3.openInMemory();
      final freshDb = AppDatabase.test(NativeDatabase.opened(fresh, closeUnderlyingOnClose: false));
      await freshDb.customSelect('SELECT 1').get();
      expect(columns(raw), columns(fresh));
      await db.close();
      await freshDb.close();
      raw.close();
      fresh.close();
    });

    test('suggestion JSON round-trips; bad JSON reads as no suggestion', () {
      const s = NameSuggestion(title: 'Electricity bill – Oct 2026', folder: DocFolder.bills, kind: 'electricity bill');
      expect(AppDatabase.suggestionFromJson(AppDatabase.suggestionToJson(s)), s);
      expect(AppDatabase.suggestionFromJson('{oops'), isNull);
      expect(AppDatabase.suggestionFromJson(null), isNull);
    });
  });

  test('v3 → v4 adds the draft table (round 7, P0-3), keeps the documents', () async {
    final raw = sqlite3.openInMemory();
    v2.forEach(raw.execute);
    raw
      ..execute('ALTER TABLE "documents" ADD COLUMN "folder" INTEGER NOT NULL DEFAULT 0')
      ..execute('ALTER TABLE "documents" ADD COLUMN "suggestion" TEXT NULL');
    final now = DateTime(2026, 11, 17).toIso8601String();
    raw
      ..execute(
        'INSERT INTO documents (id, title, mode, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        ['doc', 'Doc', 0, now, now],
      )
      ..execute('PRAGMA user_version = 3;');

    final db = AppDatabase.test(NativeDatabase.opened(raw, closeUnderlyingOnClose: false));
    expect(await db.select(db.documents).get(), hasLength(1));
    expect(await db.select(db.draftPages).get(), isEmpty);
    expect(raw.select('PRAGMA user_version').first.values.first, 4);

    final fresh = sqlite3.openInMemory();
    final freshDb = AppDatabase.test(NativeDatabase.opened(fresh, closeUnderlyingOnClose: false));
    await freshDb.customSelect('SELECT 1').get();
    List<String> cols(Database d) => [
          for (final r in d.select('PRAGMA table_info("draft_pages")'))
            '${r['name']} ${r['type']} notnull=${r['notnull']} default=${r['dflt_value']} pk=${r['pk']}',
        ];
    expect(cols(raw), cols(fresh));
    expect(cols(raw), isNotEmpty);
    await db.close();
    await freshDb.close();
    raw.close();
    fresh.close();
  });
}
