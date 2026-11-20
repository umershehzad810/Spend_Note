import 'database_test_support.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendnote/main.dart';
import 'package:spendnote/mobile_ui.dart';
import 'package:spendnote/store.dart';
import 'package:spendnote/security.dart';

void main() {
  initializeTestDatabase();
  testWidgets(
    'mobile screens render and transaction can be created, edited and deleted',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final sdk =
            Platform.environment['FLUTTER_ROOT'] ??
            r'C:\Users\pc\Tools\flutter';
        final regular = File(
          '$sdk/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
        );
        if (await regular.exists()) {
          final loader = FontLoader('Roboto')
            ..addFont(
              Future.value(ByteData.sublistView(await regular.readAsBytes())),
            );
          await loader.load();
        }
        final iconFile = File(
          '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        );
        if (await iconFile.exists()) {
          final loader = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(ByteData.sublistView(await iconFile.readAsBytes())),
            );
          await loader.load();
        }
        final s = Store();
        await s.open(path: inMemoryDatabasePath);
        await s.setup('Ayesha', 'PKR', 'Cash', 12500000);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: spendNoteTheme(),
            home: RepaintBoundary(
              key: boundary,
              child: Home(s, Security(), () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Expense').first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Amount'),
          '120.50',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Note (optional)'),
          'Lunch',
        );
        await tester.tap(find.text('Save'));
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(s.entries.length, 1);
        expect(s.balance(1), 12487950);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MaterialApp(
            theme: spendNoteTheme(),
            home: RepaintBoundary(
              key: boundary,
              child: Home(s, Security(), () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('docs').create();
        await File(
          'docs/mobile-preview.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        for (final name in [
          'Activity',
          'Plan',
          'More',
          'Accounts',
          'More',
          'Reports',
          'More',
          'Settings',
          'Home',
        ]) {
          await tester.tap(find.text(name).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: name);
        }
        await tester.ensureVisible(find.text('Lunch'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lunch'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Amount'), '100');
        await tester.tap(find.text('Save'));
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(s.balance(1), 12490000);
        await tester.pumpWidget(const SizedBox());
        await s.db.close();
      });
    },
  );
}
