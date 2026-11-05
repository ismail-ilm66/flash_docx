import 'package:drift/native.dart';
import 'package:flash_dox/features/documents/data/db/app_database.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// v1 stored ScanMode { single, batch, idCard, passport } by index. v2 has
/// { document, idCard, passport }; existing rows must keep their meaning.
void main() {
  test('v1 → v2 maps single/batch to document and shifts ID/passport', () async {
    final raw = sqlite3.openInMemory();
    // Build the real v2 tables, then rewind to v1 with v1 mode values.
    final setup = AppDatabase.test(NativeDatabase.opened(raw, closeUnderlyingOnClose: false));
    await setup.customSelect('SELECT 1').get();
    final now = DateTime(2026).toIso8601String();
    for (final (id, v1Mode) in [('single', 0), ('batch', 1), ('id', 2), ('passport', 3)]) {
      await setup.customStatement(
        'INSERT INTO documents (id, title, mode, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [id, id, v1Mode, now, now],
      );
    }
    await setup.close();
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
}
