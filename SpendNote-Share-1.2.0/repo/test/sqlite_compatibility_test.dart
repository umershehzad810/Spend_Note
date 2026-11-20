import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendnote/store.dart';
import 'database_test_support.dart';

void main() {
  initializeTestDatabase();
  late Store store;
  setUp(() async {
    store = Store();
    await store.open(path: inMemoryDatabasePath);
  });
  tearDown(() async => store.db.close());
  test('legacy test run really loads SQLite 3.22', () async {
    final version =
        (await store.db.rawQuery(
              'SELECT sqlite_version() AS version',
            )).single['version']
            as String;
    if (Platform.environment['SPENDNOTE_SQLITE_DLL'] != null) {
      expect(version, '3.22.0');
      // Demonstrate that this engine rejects the previous implementation.
      await expectLater(
        store.db.execute(
          "INSERT INTO app_settings(key,value) VALUES('probe','0') ON CONFLICT(key) DO UPDATE SET value='1'",
        ),
        throwsA(isA<DatabaseException>()),
      );
    }
    expect(version, isNotEmpty);
  });
  test(
    'reported onboarding input persists and repeat submission is harmless',
    () async {
      await Future.wait([
        store.setup('Husnain', 'PKR', 'Cash', money('1200')),
        store.setup('Husnain', 'PKR', 'Cash', money('1200')),
      ]);
      expect(store.accounts, hasLength(1));
      expect(store.balance(store.accounts.single['id'] as int), 120000);
      expect(store.settings['onboarded'], 'true');
      expect(store.settings['name'], 'Husnain');
      expect(store.revision, 1);
    },
  );
  test('concurrent changes increment revisions without lost updates', () async {
    await store.setup('Test', 'PKR', 'Cash', 0);
    final before = store.revision;
    await Future.wait(
      List.generate(20, (i) => store.preference('test_$i', '$i')),
    );
    expect(store.revision, before + 20);
    final rows = await store.db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['data_revision'],
    );
    expect(rows, hasLength(1));
  });
  test(
    'failed financial write rolls back without advancing pending revision',
    () async {
      await store.setup('Test', 'PKR', 'Cash', 0);
      final before = store.revision;
      await expectLater(
        store.save('budgets', {
          'category_id': 999999,
          'month': '2026-11',
          'amount': 100,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await store.refresh();
      expect(store.revision, before);
      expect(store.budgets, isEmpty);
    },
  );
}
