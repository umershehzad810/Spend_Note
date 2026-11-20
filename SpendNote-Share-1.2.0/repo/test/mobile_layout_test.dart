import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendnote/main.dart';
import 'package:spendnote/mobile_ui.dart';
import 'package:spendnote/security.dart';
import 'package:spendnote/store.dart';
import 'database_test_support.dart';

void main() {
  initializeTestDatabase();
  for (final size in [
    const Size(320, 720),
    const Size(360, 800),
    const Size(412, 915),
    const Size(1080, 1920),
  ]) {
    testWidgets('phone navigation and sheets at ${size.width} wide', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final sdk =
            Platform.environment['FLUTTER_ROOT'] ??
            r'C:\Users\pc\Tools\flutter';
        for (final entry in {
          'Roboto': 'roboto-regular.ttf',
          'MaterialIcons': 'materialicons-regular.otf',
        }.entries) {
          final file = File(
            '$sdk/bin/cache/artifacts/material_fonts/${entry.value}',
          );
          if (await file.exists()) {
            final loader = FontLoader(entry.key)
              ..addFont(
                Future.value(ByteData.sublistView(await file.readAsBytes())),
              );
            await loader.load();
          }
        }
        final store = Store();
        await store.open(path: inMemoryDatabasePath);
        await store.setup('Husnain', 'PKR', 'Cash', 120000);
        final boundary = GlobalKey();
        final overlay = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: spendNoteTheme(dark: size.width == 360),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(size.width == 360 ? 1.3 : 1),
              ),
              child: PhoneViewport(
                child: RepaintBoundary(key: overlay, child: child!),
              ),
            ),
            home: RepaintBoundary(
              key: boundary,
              child: Home(store, Security(), () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationDestination), findsNWidgets(4));
        if (size.width > 600) {
          expect(
            MediaQuery.sizeOf(tester.element(find.byType(Home))).width,
            440,
          );
        }
        expect(tester.takeException(), isNull);
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
        await tester.tap(find.text('Activity').last);
        await tester.pumpAndSettle();
        if (size.width == 412) {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'docs/mobile-activity.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        }
        await tester.tap(find.byTooltip('Add transaction'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Re-layout with an Android keyboard visible; Save stays on the sheet.
        tester.view.viewInsets = FakeViewPadding(bottom: size.height * .32);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        if (size.width == 412) {
          final image =
              await (overlay.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'docs/mobile-transaction-sheet.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        }
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await store.db.close();
      });
    });
  }
}
