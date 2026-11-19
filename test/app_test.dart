import 'dart:io';

import 'package:conti/app/l10n.dart';
import 'package:conti/core/conti_state.dart';
import 'package:conti/core/model/account.dart';
import 'package:conti/core/model/category.dart';
import 'package:conti/core/model/entry.dart';
import 'package:conti/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Erster Start zeigt die Einrichtung', (tester) async {
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('conti-app-'));
    final s = ContiState(dir!.path);
    await tester.runAsync(s.load);
    L10n.language.value = AppLanguage.de;
    await tester.pumpWidget(ContiApp(state: s));
    await tester.pumpAndSettle();
    expect(find.text('Willkommen bei Conti'), findsOneWidget);
    expect(find.text('Neu einrichten'), findsOneWidget);
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('Übersicht und Buchungen mit Daten', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('conti-app-'));
    final s = ContiState(dir!.path);
    await tester.runAsync(() async {
      await s.load();
      await s.mergeIn(categories: DefaultCategories.build(english: false));
      await s.saveAccount(Account(id: 'bank', name: 'Testbank', openingDate: DateTime(DateTime.now().year, 1, 1)));
      await s.saveEntry(
        Entry(id: 'a', date: DateTime.now(), kind: EntryKind.income, amount: 50000, text: 'Konzert', accountId: 'bank', categoryId: 'cat-in-gigs'),
      );
      await s.saveEntry(
        Entry(id: 'b', date: DateTime.now(), kind: EntryKind.expense, amount: 3680, text: 'Saiten', accountId: 'bank', categoryId: 'cat-ex-equipment'),
      );
      await s.finishSetup();
    });
    L10n.language.value = AppLanguage.de;
    await tester.pumpWidget(ContiApp(state: s));
    await tester.pumpAndSettle();
    expect(find.text("463.20"), findsWidgets); // Gewinn 500.00 − 36.80
    expect(find.text('Testbank'), findsOneWidget);
    await tester.tap(find.text('Buchungen').first);
    await tester.pumpAndSettle();
    expect(find.text('Saiten'), findsWidgets);
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('Escape schliesst die Buchung, ein offenes Fenster zuerst', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('conti-esc-'));
    final s = ContiState(dir!.path);
    await tester.runAsync(() async {
      await s.load();
      await s.finishSetup();
    });
    L10n.language.value = AppLanguage.de;
    await tester.pumpWidget(ContiApp(state: s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buchung').last);
    await tester.pumpAndSettle();
    expect(find.text('Neue Buchung'), findsOneWidget);
    // Fenster über der Buchung: Escape schliesst nur das Fenster.
    showDialog<void>(context: tester.element(find.text('Neue Buchung')), builder: (_) => const AlertDialog(title: Text('Test')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Test'), findsNothing);
    expect(find.text('Neue Buchung'), findsOneWidget);
    // Cursor im Betragsfeld: Escape schliesst die Buchung.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Neue Buchung'), findsNothing);
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
