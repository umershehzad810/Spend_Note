import 'database_test_support.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendnote/store.dart';
import 'package:spendnote/security.dart';

void main() {
  initializeTestDatabase();
  late Store s;
  setUp(() async {
    s = Store();
    await s.open(path: inMemoryDatabasePath);
    await s.setup('Test', 'PKR', 'Cash', 100000);
    await s.save('accounts', {
      'name': 'Bank',
      'type': 'Bank',
      'opening': 200000,
    });
  });
  tearDown(() async => s.db.close());
  Future<void> entry(String type, int amount, {int? id, int? dest}) =>
      s.transaction({
        'id': id,
        'type': type,
        'amount': amount,
        'account_id': 1,
        'destination_id': dest,
        'category_id': type == 'transfer'
            ? null
            : s.categories.firstWhere((c) => c['type'] == type)['id'],
        'date': '2026-11-19',
        'note': 'test',
      });
  test('money is parsed in exact minor units', () {
    expect(money('123.45'), 12345);
    expect(money('0.1'), 10);
    expect(() => money('1.001'), throwsFormatException);
    expect(() => money('-1'), throwsFormatException);
  });
  test(
    'edits, deletes and transfers recalculate balances without double counting',
    () async {
      await entry('income', 50000);
      await entry('expense', 20000);
      await entry('transfer', 30000, dest: 2);
      expect(s.balance(1), 100000);
      expect(s.balance(2), 230000);
      expect(s.total('expense', '2026-11'), 20000);
      expect(s.total('income', '2026-11'), 50000);
      final expense = s.entries.firstWhere((e) => e['type'] == 'expense');
      await entry('expense', 10000, id: expense['id'] as int);
      expect(s.balance(1), 110000);
      await s.remove('transactions', expense['id'] as int);
      expect(s.balance(1), 120000);
      final transfer = s.entries.firstWhere((e) => e['type'] == 'transfer');
      await s.remove('transactions', transfer['id'] as int);
      expect(s.balance(1), 150000);
      expect(s.balance(2), 200000);
    },
  );
  test('invalid transfer is rejected atomically', () async {
    await expectLater(entry('transfer', 100, dest: 1), throwsFormatException);
    expect(s.entries, isEmpty);
    expect(s.balance(1), 100000);
  });
  test('budgets exclude income, transfers and savings allocations', () async {
    final category = s.categories.firstWhere(
      (c) => c['type'] == 'expense',
    )['id'];
    await s.save('budgets', {
      'category_id': category,
      'month': '2026-11',
      'amount': 50000,
    });
    await entry('expense', 15000);
    await entry('income', 50000);
    await entry('transfer', 10000, dest: 2);
    await s.save('savings_goals', {'name': 'Rainy day', 'target': 100000});
    final before = s.balance(1);
    await s.save('goal_contributions', {
      'goal_id': s.goals.first['id'],
      'amount': 20000,
      'date': '2026-11-19',
    });
    expect(s.total('expense', '2026-11', category: category as int), 15000);
    expect(s.saved(s.goals.first['id'] as int), 20000);
    expect(s.balance(1), before);
  });
  test('snapshot restores records and malformed restore rolls back', () async {
    await entry('expense', 12345);
    final snapshot = await s.snapshot();
    await s.remove('transactions', s.entries.first['id'] as int);
    await s.restore(snapshot);
    expect(s.balance(1), 87655);
    final bad = jsonDecode(snapshot);
    bad['tables']['transactions'][0]['account_id'] = 999;
    await expectLater(s.restore(jsonEncode(bad)), throwsA(anything));
    expect(s.balance(1), 87655);
    await expectLater(s.restore('{"schema":99}'), throwsFormatException);
  });
  test(
    'authenticated encryption rejects wrong passwords and tampering',
    () async {
      final security = Security();
      final bytes = await security.encrypt(
        'private records',
        'a strong passphrase',
      );
      expect(
        await security.decrypt(bytes, 'a strong passphrase'),
        'private records',
      );
      await expectLater(
        security.decrypt(bytes, 'wrong passphrase'),
        throwsA(anything),
      );
      final data = jsonDecode(utf8.decode(bytes));
      data['data'][0] ^= 1;
      await expectLater(
        security.decrypt(utf8.encode(jsonEncode(data)), 'a strong passphrase'),
        throwsA(anything),
      );
    },
  );
  test('local PIN verifier validates and rejects incorrect PINs', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final security = Security();
    expect(await security.hasPin(), false);
    await security.setPin('123456');
    expect(await security.hasPin(), true);
    expect(await security.verify('123456'), true);
    expect(await security.verify('000000'), false);
    await expectLater(security.setPin('12'), throwsFormatException);
  });
  test('SQLite data survives close and reopen', () async {
    final dir = await Directory.systemTemp.createTemp('spendnote-test-');
    final path = '${dir.path}/persistent.db';
    final first = Store();
    await first.open(path: path);
    await first.setup('Offline user', 'PKR', 'Cash', 12345);
    await first.db.close();
    final second = Store();
    await second.open(path: path);
    expect(second.settings['name'], 'Offline user');
    expect(second.balance(second.accounts.first['id'] as int), 12345);
    await second.db.close();
    await dir.delete(recursive: true);
  });
}
