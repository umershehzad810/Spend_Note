import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void initializeSqliteLibrary() {
  final legacy = Platform.environment['SPENDNOTE_SQLITE_DLL'];
  if (legacy != null && legacy.isNotEmpty) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open(legacy),
    );
  } else {
    sqfliteFfiInit();
  }
}

void initializeTestDatabase() {
  databaseFactory = createDatabaseFactoryFfi(ffiInit: initializeSqliteLibrary);
}
