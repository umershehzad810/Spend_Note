import 'database_test_support.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendnote/security.dart';
import 'package:spendnote/store.dart';

class FakeBackups extends Backups {
  FakeBackups(super.store, super.security);
  int uploads = 0;
  bool fail = false;
  Completer<void>? hold;
  @override
  Future<void> backup(String password, {bool automatic = false}) async {
    uploads++;
    if (hold != null) await hold!.future;
    if (fail) throw Exception('Offline');
    await store.save('backup_history', {
      'date': '2026-11-20',
      'status': 'Successful',
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initializeTestDatabase();
  late Store store;
  late FakeBackups cloud;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    store = Store();
    await store.open(path: inMemoryDatabasePath);
    await store.setup('Test', 'PKR', 'Cash', 10000);
    cloud = FakeBackups(store, Security())..email = 'owner@example.com';
    await cloud.configure('long recovery passphrase');
  });
  tearDown(() async {
    cloud.dispose();
    await store.db.close();
  });
  test(
    'unchanged data and backup history do not trigger repeat uploads',
    () async {
      final before = store.revision;
      await cloud.sync();
      expect(cloud.uploads, 1);
      expect(store.revision, before);
      await cloud.sync();
      expect(cloud.uploads, 1);
      await store.preference('name', 'Changed');
      await cloud.sync();
      expect(cloud.uploads, 2);
    },
  );
  test('failed upload retains pending revision for retry', () async {
    cloud.fail = true;
    await cloud.sync();
    expect(cloud.status, contains('pending'));
    expect(
      await cloud.security.storage.read(key: cloud.storageKey('revision')),
      isNull,
    );
    cloud.fail = false;
    await cloud.sync();
    expect(cloud.uploads, 2);
    expect(
      await cloud.security.storage.read(key: cloud.storageKey('revision')),
      '${store.revision}',
    );
  });
  test(
    'concurrent attempts are serialized and edits during upload remain pending',
    () async {
      cloud.hold = Completer<void>();
      final upload = cloud.sync();
      while (cloud.uploads == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await cloud.sync(force: true);
      expect(cloud.uploads, 1);
      await store.preference('name', 'Edited during upload');
      cloud.hold!.complete();
      await upload;
      expect(
        await cloud.security.storage.read(key: cloud.storageKey('revision')),
        isNot('${store.revision}'),
      );
      cloud.hold = null;
      await cloud.sync();
      expect(cloud.uploads, 2);
    },
  );
  test('stored account and passphrase support retry after restart', () async {
    await cloud.security.storage.write(
      key: 'drive_session',
      value: cloud.email,
    );
    await cloud.initialize();
    expect(cloud.connected, true);
    expect(cloud.configured, true);
    expect(cloud.passphrase, 'long recovery passphrase');
    await cloud.sync();
    expect(cloud.uploads, 1);
  });
}
