import 'dart:convert';
import 'dart:io';

import 'package:conti/core/backup.dart';
import 'package:conti/core/conti_state.dart';
import 'package:conti/core/import/legacy_import.dart';
import 'package:conti/core/model/account.dart';
import 'package:conti/core/model/category.dart';
import 'package:conti/core/model/entry.dart';
import 'package:conti/core/model/synced.dart';
import 'package:conti/core/money.dart';
import 'package:conti/core/store/data_store.dart';
import 'package:conti/core/swiss.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Money', () {
    test('liest Schweizer Schreibweisen', () {
      expect(Money.parse("1'234.50"), 123450);
      expect(Money.parse('1’234,5'), 123450);
      expect(Money.parse('12'), 1200);
      expect(Money.parse('CHF 40.-'), 4000);
      expect(Money.parse('-3.05'), -305);
      expect(Money.parse('.5'), 50);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('1.234'), isNull);
    });
    test('schreibt mit Apostroph', () {
      expect(Money.format(123450), "1'234.50");
      expect(Money.format(100000000), "1'000'000.00");
      expect(Money.format(-505), '−5.05');
      expect(Money.format(4000, sign: true, currency: true), 'CHF +40.00');
      expect(Money.fromFrancs(38.2), 3820);
      expect(Money.fromFrancs(0.1 + 0.2), 30);
      expect(Money.roundTo5(1232), 1230);
      expect(Money.roundTo5(1233), 1235);
    });
  });

  group('IBAN', () {
    test('prüft die Prüfziffer', () {
      expect(Iban.isValid('CH93 0076 2011 6238 5295 7'), isTrue);
      expect(Iban.isValid('CH94 0076 2011 6238 5295 7'), isFalse);
      expect(Iban.isValid('CH93 0076 2011 6238 5295'), isFalse);
      expect(Iban.pretty('ch9300762011623852957'), 'CH93 0076 2011 6238 5295 7');
    });
    test('erkennt QR-IBAN', () {
      expect(Iban.isQrIban('CH44 3199 9123 0008 8901 2'), isTrue);
      expect(Iban.isQrIban('CH93 0076 2011 6238 5295 7'), isFalse);
    });
    test('trennt Strasse und Hausnummer', () {
      expect(splitStreet('Beispielweg 12a'), ('Beispielweg', '12a'));
      expect(splitStreet('Dorf'), ('Dorf', ''));
      expect(splitStreet('Rue du Lac 3-5'), ('Rue du Lac', '3-5'));
    });
  });

  group('Zusammenführen', () {
    test('jüngere Fassung gewinnt, Grabsteine bleiben', () {
      final old = Entry(id: 'x', date: DateTime(2026), kind: EntryKind.income, amount: 100, updatedAt: DateTime.utc(2026, 1, 1));
      final newer = Entry(
        id: 'x',
        date: DateTime(2026),
        kind: EntryKind.income,
        amount: 100,
        deleted: true,
        updatedAt: DateTime.utc(2026, 2, 1),
      );
      final other = Entry(id: 'y', date: DateTime(2026), kind: EntryKind.expense, amount: 5);
      final m = mergeById([old], [newer, other]);
      expect(m.length, 2);
      expect(m.firstWhere((e) => e.id == 'x').deleted, isTrue);
    });
  });

  group('Datenordner', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('conti-test-'));
    tearDown(() async => dir.delete(recursive: true));

    test('speichert pro Jahr und führt mit der Festplatte zusammen', () async {
      final s = ContiState(dir.path);
      await s.load();
      final a = Account(id: 'bank', name: 'Bank', opening: 10000, openingDate: DateTime(2025, 1, 1));
      await s.saveAccount(a);
      await s.saveEntry(Entry(id: 'e1', date: DateTime(2025, 5, 1), kind: EntryKind.income, amount: 5000, accountId: 'bank'));
      await s.saveEntry(Entry(id: 'e2', date: DateTime(2026, 5, 1), kind: EntryKind.expense, amount: 1250, accountId: 'bank'));
      expect(File(p.join(dir.path, 'Daten', 'buchungen', '2025.json')).existsSync(), isTrue);
      expect(File(p.join(dir.path, 'Daten', 'buchungen', '2026.json')).existsSync(), isTrue);
      expect(s.balance('bank'), 10000 + 5000 - 1250);

      // Ein anderes Gerät schreibt eine Buchung dazu, während diese App läuft.
      final other = ContiState(dir.path);
      await other.load();
      await other.saveEntry(Entry(id: 'e3', date: DateTime(2026, 6, 1), kind: EntryKind.income, amount: 700, accountId: 'bank'));
      // Diese App speichert danach etwas im selben Jahr: e3 darf nicht verschwinden.
      await s.saveEntry(Entry(id: 'e4', date: DateTime(2026, 7, 1), kind: EntryKind.expense, amount: 100, accountId: 'bank'));
      final again = ContiState(dir.path);
      await again.load();
      expect(again.entries.map((e) => e.id).toSet(), {'e1', 'e2', 'e3', 'e4'});

      // Buchung ins andere Jahr verschieben.
      final e2 = again.entry('e2')!.copy();
      e2.date = DateTime(2025, 12, 31);
      await again.saveEntry(e2, previousYear: 2026);
      final third = ContiState(dir.path);
      await third.load();
      expect(third.entries.where((e) => e.id == 'e2').single.year, 2025);
      expect(third.incomeOf(2026), 700);
      expect(third.expensesOf(2025), 1250);
    });

    test('Umbuchung verschiebt nur zwischen Konten', () async {
      final s = ContiState(dir.path);
      await s.load();
      await s.saveAccount(Account(id: 'cash', name: 'Kasse', type: AccountType.cash, openingDate: DateTime(2026, 1, 1)));
      await s.saveAccount(Account(id: 'bank', name: 'Bank', openingDate: DateTime(2026, 1, 1)));
      await s.saveEntry(Entry(id: 'i', date: DateTime(2026, 2, 1), kind: EntryKind.income, amount: 300, accountId: 'cash'));
      await s.saveEntry(
        Entry(id: 't', date: DateTime(2026, 2, 2), kind: EntryKind.transfer, amount: 200, accountId: 'cash', toAccountId: 'bank'),
      );
      expect(s.balance('cash'), 100);
      expect(s.balance('bank'), 200);
      expect(s.incomeOf(2026), 300);
      expect(s.expensesOf(2026), 0);
    });

    test('Sicherung einspielen führt zusammen', () async {
      final s = ContiState(dir.path);
      await s.load();
      await s.finishSetup();
      await s.saveEntry(Entry(id: 'k', date: DateTime(2026, 3, 1), kind: EntryKind.income, amount: 100));
      final zip = p.join(dir.path, 'sicherung.zip');
      await Backup.writeZip(s, zip);
      await s.deleteEntry(s.entry('k')!);
      expect(s.entries, isEmpty);
      // Gelöscht ist jünger als die Sicherung: bleibt gelöscht.
      await Backup.restore(s, zip);
      expect(s.entries, isEmpty);
      // In einem leeren Ordner kommt alles zurück.
      final dir2 = await Directory.systemTemp.createTemp('conti-test2-');
      final s2 = ContiState(dir2.path);
      await s2.load();
      expect(await Backup.restore(s2, zip), 1);
      expect(s2.entries.single.amount, 100);
      await dir2.delete(recursive: true);
    });
  });

  group('Import aus der alten App', () {
    late Map<String, dynamic> json;
    setUp(() {
      json = jsonDecode(File('test/fixtures/legacy_sample.json').readAsStringSync()) as Map<String, dynamic>;
    });

    test('liest alles', () {
      expect(LegacyImport.looksLike(json), isTrue);
      final d = LegacyImport.parse(json, existing: DefaultCategories.build(english: false));
      expect(d.entries.length, 3);
      final income = d.entries.firstWhere((e) => e.id == 'e-1');
      expect(income.kind, EntryKind.income);
      expect(income.amount, 45000);
      expect(income.orderId, 'o-1');
      expect(income.clientId, 'c-1');
      // Spesen gibt es schon als Standard-Kategorie, Fahrspesen auch (darunter).
      final travel = d.entries.firstWhere((e) => e.id == 'e-2');
      expect(travel.amount, 3820);
      expect(travel.categoryId, 'cat-ex-travel');
      // Aufgeteilte Buchung
      final split = d.entries.firstWhere((e) => e.id == 'e-3');
      expect(split.categoryId, isNull);
      expect(split.splits.map((s) => s.amount).toList(), [6005, 4005]);
      expect(d.newCategories.map((c) => c.name).toSet(), containsAll(['Musik', 'Materialaufwand', 'Papier']));
      // Gleiche Namen ergeben dieselbe ID (zweiter Import ohne Doppelte).
      final d2 = LegacyImport.parse(json, existing: DefaultCategories.build(english: false));
      expect(d2.newCategories.map((c) => c.id).toSet(), d.newCategories.map((c) => c.id).toSet());

      expect(d.clients.single.street, 'Beispielweg');
      expect(d.clients.single.houseNumber, '12a');
      expect(d.clients.single.country, 'CH');
      expect(d.products.map((x) => x.price).toList(), [30000, 7500]);
      expect(d.orders.single.items.single.unitPrice, 45000);
      expect(d.tasks.single.done, isTrue);
      expect(d.business.ownerName, 'Max Beispiel');
      expect(d.business.street, 'Musterstrasse');
      expect(d.business.houseNumber, '5');
      expect(d.business.iban, 'CH93 0076 2011 6238 5295 7');
      expect(d.business.invoice.invoicePrefix, 'XYZ-');
      expect(d.business.invoice.footerNote, 'Vielen Dank für den Auftrag.\n{name}');
      expect(d.business.invoice.qrMessage, 'Rechnung {rechnungsnummer}');
      expect(d.logo?.extension, '.svg');
      expect(d.attachments.length, 2);
      expect(d.yearSummary[2025], (45000, 3820, 2));
    });

    test('übernimmt Buchungen und Belege', () async {
      final dir = await Directory.systemTemp.createTemp('conti-imp-');
      final receipts = Directory(p.join(dir.path, 'alt', 'Belege', '2025'))..createSync(recursive: true);
      File(p.join(receipts.path, '2025-04-02 Billett.pdf')).writeAsStringSync('%PDF-Beispiel');
      final s = ContiState(p.join(dir.path, 'app'));
      await s.load();
      await s.mergeIn(categories: DefaultCategories.build(english: false));
      await s.saveAccount(Account(id: 'bank', name: 'Bank', openingDate: DateTime(2025, 1, 1)));
      final d = LegacyImport.parse(json, existing: s.categories);
      final r = await LegacyImport.apply(s, d, accountId: 'bank', receiptsFolder: p.join(dir.path, 'alt', 'Belege'));
      expect(r.entries, 3);
      expect(r.attachmentsFound, 1);
      expect(r.attachmentsMissing, ['Rechnung Kulturhaus.pdf']);
      final e2 = s.entry('e-2')!;
      expect(e2.attachments.single.name, 'Billett.pdf');
      expect(File(s.dataPath(e2.attachments.single.file)).readAsStringSync(), '%PDF-Beispiel');
      expect(s.balance('bank'), 45000 - 3820 - 10010);
      expect(s.business.logoFile, 'bilder/logo.svg');
      expect(s.categoryLabel('cat-ex-travel'), 'Spesen › Fahrspesen');

      // Zweiter Import: nichts doppelt.
      await LegacyImport.apply(s, LegacyImport.parse(json, existing: s.categories), accountId: 'bank');
      expect(s.entries.length, 3);
      expect(s.categories.where((c) => c.name == 'Musik').length, 1);
      // Beleg bleibt dran, auch wenn beim zweiten Mal kein Ordner gewählt wurde.
      expect(s.entry('e-2')!.attachments.length, 1, reason: 'jüngere Fassung mit Beleg gewinnt');
      await dir.delete(recursive: true);
    });
  });

  test('Datenordner-Format bleibt lesbar', () async {
    final dir = await Directory.systemTemp.createTemp('conti-fmt-');
    final store = DataStore(dir.path);
    await store.markInitialized();
    final snap = await store.load();
    expect(snap.initialized, isTrue);
    expect(snap.entries, isEmpty);
    await dir.delete(recursive: true);
  });
}
