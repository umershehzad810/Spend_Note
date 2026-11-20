import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendnote/main.dart';
import 'package:spendnote/store.dart';
import 'database_test_support.dart';

void main() {
  initializeTestDatabase();
  testWidgets('onboarding form saves the reported inputs and leaves setup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final store = Store();
      await store.open(path: inMemoryDatabasePath);
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: store,
            builder: (_, _) => store.settings['onboarded'] == 'true'
                ? const Scaffold(body: Text('Setup complete'))
                : Setup(store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'What should we call you?'),
        'Husnain',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Opening balance'),
        '1200',
      );
      final button = find.byType(FilledButton);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      for (var i = 0; i < 50 && store.settings['onboarded'] != 'true'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Setup complete'), findsOneWidget);
      expect(store.balance(store.accounts.single['id'] as int), 120000);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await store.db.close();
    });
  });
}
