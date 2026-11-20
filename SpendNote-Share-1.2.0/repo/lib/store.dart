import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

int money(String value) {
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value.trim())) {
    throw const FormatException(
      'Enter an amount with at most two decimal places.',
    );
  }
  final parts = value.trim().split('.');
  final result =
      int.parse(parts[0]) * 100 +
      int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  if (result > 900000000000000) {
    throw const FormatException('Amount is too large.');
  }
  return result;
}

class Store extends ChangeNotifier {
  late Database db;
  List<Map<String, Object?>> accounts = [],
      categories = [],
      entries = [],
      budgets = [],
      goals = [],
      contributions = [],
      backups = [];
  Map<String, String> settings = {};
  Future<void> open({String? path}) async {
    db = await openDatabase(
      path ?? p.join(await getDatabasesPath(), 'spendnote.db'),
      version: 1,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, v) async {
        for (final sql in schema) {
          await d.execute(sql);
        }
        for (final type in ['expense', 'income']) {
          final names = type == 'expense'
              ? ['Food', 'Transport', 'Bills', 'Shopping', 'Health', 'Other']
              : ['Salary', 'Pocket Money', 'Freelancing', 'Gifts'];
          for (var i = 0; i < names.length; i++) {
            await d.insert('categories', {
              'name': names[i],
              'type': type,
              'color': i % 6,
              'icon': i % 6,
            });
          }
        }
      },
    );
    await refresh();
  }

  static const schema = [
    'CREATE TABLE accounts(id INTEGER PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, opening INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE categories(id INTEGER PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL CHECK(type IN ("income","expense")), color INTEGER NOT NULL DEFAULT 0, icon INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE transactions(id INTEGER PRIMARY KEY, type TEXT NOT NULL CHECK(type IN ("income","expense","transfer")), amount INTEGER NOT NULL CHECK(amount > 0), account_id INTEGER NOT NULL REFERENCES accounts(id), destination_id INTEGER REFERENCES accounts(id), category_id INTEGER REFERENCES categories(id), date TEXT NOT NULL, note TEXT NOT NULL DEFAULT "", CHECK((type = "transfer" AND destination_id IS NOT NULL AND destination_id != account_id AND category_id IS NULL) OR (type != "transfer" AND destination_id IS NULL AND category_id IS NOT NULL)))',
    'CREATE INDEX transaction_date ON transactions(date)',
    'CREATE TABLE budgets(id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL REFERENCES categories(id), month TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0), UNIQUE(category_id,month))',
    'CREATE TABLE savings_goals(id INTEGER PRIMARY KEY, name TEXT NOT NULL, target INTEGER NOT NULL CHECK(target > 0), date TEXT)',
    'CREATE TABLE goal_contributions(id INTEGER PRIMARY KEY, goal_id INTEGER NOT NULL REFERENCES savings_goals(id) ON DELETE CASCADE, amount INTEGER NOT NULL CHECK(amount > 0), date TEXT NOT NULL)',
    'CREATE TABLE backup_history(id INTEGER PRIMARY KEY, date TEXT NOT NULL, status TEXT NOT NULL, file_id TEXT)',
    'CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  ];
  Future<void> refresh() async {
    accounts = await db.query('accounts');
    categories = await db.query('categories');
    entries = await db.query('transactions', orderBy: 'date DESC, id DESC');
    budgets = await db.query('budgets');
    goals = await db.query('savings_goals');
    contributions = await db.query('goal_contributions');
    backups = await db.query('backup_history', orderBy: 'date DESC');
    settings = {
      for (final r in await db.query('app_settings'))
        r['key'] as String: r['value'] as String,
    };
    notifyListeners();
  }

  int get revision => int.tryParse(settings['data_revision'] ?? '0') ?? 0;
  Future<void> markChanged(DatabaseExecutor t) async {
    // Android uses its system SQLite. Older supported devices do not implement
    // UPSERT, so initialize and increment inside the caller's transaction.
    await t.insert('app_settings', {
      'key': 'data_revision',
      'value': '0',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await t.rawUpdate(
      'UPDATE app_settings SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT) WHERE key = ?',
      ['data_revision'],
    );
  }

  Future<void> save(String table, Map<String, Object?> row) async {
    await db.transaction((t) async {
      if (row['id'] == null) {
        await t.insert(table, row);
      } else {
        await t.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
      }
      if (table != 'backup_history') await markChanged(t);
    });
    await refresh();
  }

  Future<void> remove(String table, int id) async {
    await db.transaction((t) async {
      await t.delete(table, where: 'id = ?', whereArgs: [id]);
      await markChanged(t);
    });
    await refresh();
  }

  Future<void> preference(String key, String value) async {
    await db.transaction((t) async {
      await t.insert('app_settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await markChanged(t);
    });
    await refresh();
  }

  Future<void> setup(
    String name,
    String currency,
    String account,
    int opening,
  ) async {
    await db.transaction((t) async {
      final existing = await t.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['onboarded'],
      );
      if (existing.any((r) => r['value'] == 'true')) return;
      await t.insert('accounts', {
        'name': account,
        'type': 'Cash',
        'opening': opening,
      });
      for (final e in {
        'name': name,
        'currency': currency,
        'onboarded': 'true',
      }.entries) {
        await t.insert('app_settings', {
          'key': e.key,
          'value': e.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await markChanged(t);
    });
    await refresh();
  }

  Future<void> transaction(Map<String, Object?> row) async {
    final amount = row['amount'] as int;
    if (amount <= 0) {
      throw const FormatException('Amount must be greater than zero.');
    }
    final account = accounts.firstWhere((a) => a['id'] == row['account_id']);
    if (account['archived'] == 1) {
      throw const FormatException('Choose an active account.');
    }
    if (row['type'] == 'transfer') {
      if (row['destination_id'] == row['account_id']) {
        throw const FormatException('Choose two different accounts.');
      }
      accounts.firstWhere(
        (a) => a['id'] == row['destination_id'] && a['archived'] == 0,
      );
    } else {
      categories.firstWhere(
        (c) => c['id'] == row['category_id'] && c['type'] == row['type'],
      );
    }
    await save('transactions', row);
  }

  int balance(int id) =>
      (accounts.firstWhere((a) => a['id'] == id)['opening'] as int) +
      entries.fold<int>(0, (sum, e) {
        final amount = e['amount'] as int;
        return sum +
            (e['account_id'] == id
                ? (e['type'] == 'income' ? amount : -amount)
                : 0) +
            (e['destination_id'] == id ? amount : 0);
      });
  int total(String type, String month, {int? category}) => entries
      .where(
        (e) =>
            e['type'] == type &&
            (e['date'] as String).startsWith(month) &&
            (category == null || e['category_id'] == category),
      )
      .fold(0, (s, e) => s + (e['amount'] as int));
  int saved(int id) => contributions
      .where((c) => c['goal_id'] == id)
      .fold(0, (s, e) => s + (e['amount'] as int));
  String accountName(Object? id) =>
      accounts.where((a) => a['id'] == id).firstOrNull?['name'] as String? ??
      'Account';
  String categoryName(Object? id) =>
      categories.where((a) => a['id'] == id).firstOrNull?['name'] as String? ??
      'Transfer';
  static const tables = [
    'accounts',
    'categories',
    'transactions',
    'budgets',
    'savings_goals',
    'goal_contributions',
    'app_settings',
  ];
  Future<String> snapshot() => db.transaction(
    (t) async => jsonEncode({
      'schema': 1,
      'app': 'SpendNote',
      'tables': {for (final table in tables) table: await t.query(table)},
    }),
  );
  Future<void> restore(String data) async {
    final payload = jsonDecode(data) as Map<String, dynamic>;
    if (payload['schema'] != 1 || payload['app'] != 'SpendNote') {
      throw const FormatException('Incompatible backup.');
    }
    final rows = payload['tables'] as Map<String, dynamic>;
    for (final table in tables) {
      if (rows[table] is! List) {
        throw const FormatException('Incomplete backup.');
      }
    }
    await db.transaction((t) async {
      for (final table in tables.reversed) {
        await t.delete(table);
      }
      for (final table in tables) {
        for (final row in rows[table] as List) {
          await t.insert(table, Map<String, Object?>.from(row as Map));
        }
      }
      final invalid = await t.rawQuery('PRAGMA foreign_key_check');
      if (invalid.isNotEmpty) {
        throw const FormatException('Backup failed integrity checks.');
      }
      await markChanged(t);
    });
    await refresh();
  }
}
