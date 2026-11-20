import 'database_test_support.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendnote/main.dart';
import 'package:spendnote/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initializeTestDatabase();
  testWidgets(
    'Google connection is required before onboarding or financial screens',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await tester.runAsync(() async {
        final store = Store();
        await store.open(path: inMemoryDatabasePath);
        await tester.pumpWidget(SpendNote(store));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.text('Continue with Google'), findsOneWidget);
        expect(find.text('Add transaction'), findsNothing);
        expect(find.text('What should we call you?'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await store.db.close();
      });
    },
  );
}
