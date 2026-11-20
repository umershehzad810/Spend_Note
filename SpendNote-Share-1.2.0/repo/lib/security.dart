import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'store.dart';

class Security {
  final storage = const FlutterSecureStorage();
  final algorithm = AesGcm.with256bits();
  Future<SecretKey> key(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  List<int> random(int length) =>
      List.generate(length, (_) => Random.secure().nextInt(256));
  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw const FormatException('Use a 4 to 8 digit PIN.');
    }
    final salt = random(16);
    await storage.write(
      key: 'pin',
      value: jsonEncode({
        'salt': salt,
        'hash': await (await key(pin, salt)).extractBytes(),
      }),
    );
  }

  Future<bool> hasPin() async => await storage.read(key: 'pin') != null;
  Future<bool> verify(String pin) async {
    final raw = await storage.read(key: 'pin');
    if (raw == null) return true;
    final data = jsonDecode(raw);
    final actual = await (await key(
      pin,
      List<int>.from(data['salt']),
    )).extractBytes();
    final expected = List<int>.from(data['hash']);
    var diff = actual.length ^ expected.length;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }

  Future<List<int>> encrypt(String data, String password) async {
    if (password.length < 10) {
      throw const FormatException(
        'Use a backup passphrase of at least 10 characters.',
      );
    }
    final salt = random(16);
    final box = await algorithm.encrypt(
      utf8.encode(data),
      secretKey: await key(password, salt),
    );
    return utf8.encode(
      jsonEncode({
        'format': 'SpendNote-1',
        'salt': salt,
        'nonce': box.nonce,
        'mac': box.mac.bytes,
        'data': box.cipherText,
      }),
    );
  }

  Future<String> decrypt(List<int> bytes, String password) async {
    final data = jsonDecode(utf8.decode(bytes));
    if (data['format'] != 'SpendNote-1') {
      throw const FormatException('Unsupported backup format.');
    }
    return utf8.decode(
      await algorithm.decrypt(
        SecretBox(
          List<int>.from(data['data']),
          nonce: List<int>.from(data['nonce']),
          mac: Mac(List<int>.from(data['mac'])),
        ),
        secretKey: await key(password, List<int>.from(data['salt'])),
      ),
    );
  }
}

class AuthClient extends http.BaseClient {
  AuthClient(this.headers);
  final Map<String, String> headers;
  final http.Client inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(headers);
    return inner.send(request);
  }

  @override
  void close() {
    inner.close();
    super.close();
  }
}

class Backups extends ChangeNotifier {
  Backups(this.store, this.security) {
    store.addListener(schedule);
  }
  final Store store;
  final Security security;
  static const serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '451353665067-tjsjkn84a9tmtjac8tq4b15vfle7volj.apps.googleusercontent.com',
  );
  final google = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
    serverClientId: serverClientId.isEmpty ? null : serverClientId,
  );
  GoogleSignInAccount? user;
  String? email;
  String status = 'Connect Google to protect your records';
  Timer? debounce, retry;
  bool busy = false, configured = false;
  String? passphrase;
  bool get connected => email != null;
  String storageKey(String name) => 'drive_${email}_$name';
  Future<void> initialize() async {
    retry?.cancel();
    email = await security.storage.read(key: 'drive_session');
    if (email != null) {
      passphrase = await security.storage.read(key: storageKey('passphrase'));
      configured = passphrase != null;
    }
    retry = Timer.periodic(const Duration(minutes: 1), (_) => schedule());
    status = connected ? 'Waiting to back up changes' : status;
    schedule();
    notifyListeners();
  }

  Future<void> configure(String password) async {
    if (password.length < 10) {
      throw const FormatException('Use at least 10 characters.');
    }
    passphrase = password;
    await security.storage.write(
      key: storageKey('passphrase'),
      value: password,
    );
    await security.storage.delete(key: storageKey('revision'));
    configured = true;
    schedule();
    notifyListeners();
  }

  void schedule() {
    if (!connected ||
        !configured ||
        busy ||
        store.settings['onboarded'] != 'true') {
      return;
    }
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 3), () => unawaited(sync()));
  }

  Future<void> sync({bool force = false}) async {
    if (busy || !connected || !configured) return;
    busy = true;
    final revision = store.revision;
    var succeeded = false;
    try {
      final last = await security.storage.read(key: storageKey('revision'));
      if (!force && last == '$revision') {
        status = 'All changes backed up';
        return;
      }
      status = 'Backing up to Google Drive…';
      notifyListeners();
      await backup(passphrase!, automatic: true);
      await security.storage.write(
        key: storageKey('revision'),
        value: '$revision',
      );
      status = store.revision == revision
          ? 'All changes backed up'
          : 'New changes waiting to back up';
      succeeded = true;
    } catch (_) {
      status = 'Backup pending · Check internet or reconnect Google';
    } finally {
      busy = false;
      notifyListeners();
      if (succeeded && store.revision != revision) schedule();
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    retry?.cancel();
    store.removeListener(schedule);
    super.dispose();
  }

  Future<void> connect() async {
    if (busy) {
      throw const FormatException('Wait for the current backup to finish.');
    }
    final selected = await google.signIn();
    if (selected == null) throw const FormatException('Connection cancelled.');
    final bound = await security.storage.read(key: 'drive_owner');
    if (bound != null && bound != selected.email) {
      await google.signOut();
      throw const FormatException(
        'Reconnect the Google account previously linked to this data.',
      );
    }
    if (!await google.requestScopes([drive.DriveApi.driveAppdataScope])) {
      throw const FormatException('Google Drive permission is required.');
    }
    user = selected;
    email = selected.email;
    await security.storage.write(key: 'drive_owner', value: email);
    await security.storage.write(key: 'drive_session', value: email);
    passphrase = await security.storage.read(key: storageKey('passphrase'));
    configured = passphrase != null;
    status = 'Google connected';
    schedule();
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (busy) {
      throw const FormatException('Wait for the current backup to finish.');
    }
    await google.disconnect();
    await security.storage.delete(key: 'drive_session');
    user = null;
    email = null;
    configured = false;
    passphrase = null;
    debounce?.cancel();
    status = 'Connect Google to continue';
    notifyListeners();
  }

  Future<T> withDrive<T>(Future<T> Function(drive.DriveApi) action) async {
    user ??= await google.signInSilently().timeout(const Duration(seconds: 20));
    if (user == null) {
      throw const FormatException('Connect your Google account first.');
    }
    if (user!.email != email) {
      throw const FormatException(
        'Google account does not match the linked account.',
      );
    }
    final client = AuthClient(await user!.authHeaders);
    try {
      return await action(
        drive.DriveApi(client),
      ).timeout(const Duration(seconds: 60));
    } finally {
      client.close();
    }
  }

  Future<void> backup(String password, {bool automatic = false}) async {
    try {
      final bytes = await security.encrypt(await store.snapshot(), password);
      final file = await withDrive(
        (api) => api.files.create(
          drive.File()
            ..name =
                '${automatic ? 'SpendNote-auto' : 'SpendNote'}-${DateTime.now().toUtc().toIso8601String()}.snb'
            ..parents = ['appDataFolder'],
          uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
        ),
      );
      await store.save('backup_history', {
        'date': DateTime.now().toIso8601String(),
        'status': 'Successful',
        'file_id': file.id,
      });
    } catch (_) {
      await store.save('backup_history', {
        'date': DateTime.now().toIso8601String(),
        'status': 'Failed',
      });
      rethrow;
    }
  }

  Future<List<drive.File>> list() => withDrive(
    (api) async =>
        (await api.files.list(
          spaces: 'appDataFolder',
          q: "trashed = false and name contains 'SpendNote-'",
          orderBy: 'createdTime desc',
          $fields: 'files(id,name,createdTime)',
          pageSize: 100,
        )).files ??
        [],
  );
  Future<String> read(String id, String password) => withDrive((api) async {
    final media =
        await api.files.get(
              id,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
      if (bytes.length > 50000000) {
        throw const FormatException('Backup is too large.');
      }
    }
    return security.decrypt(bytes, password);
  });
}
