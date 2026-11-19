import 'dart:io';

import 'package:conti/app/l10n.dart';
import 'package:conti/core/closing/canton_forms.dart';
import 'package:conti/core/closing/closing_csv.dart';
import 'package:conti/core/closing/closing_pdf.dart';
import 'package:conti/core/closing/depreciation.dart';
import 'package:conti/core/invoice/invoice_pdf.dart';
import 'package:conti/core/model/business.dart';
import 'package:conti/core/closing/year_report.dart';
import 'package:conti/core/conti_state.dart';
import 'package:conti/core/model/account.dart';
import 'package:conti/core/model/category.dart';
import 'package:conti/core/model/closing.dart';
import 'package:conti/core/model/crm.dart';
import 'package:conti/core/model/entry.dart';
import 'package:flutter_test/flutter_test.dart';

Entry _e(String id, DateTime d, EntryKind k, int amount, {String cat = '', String acc = 'bank', Map<String, dynamic>? asset, bool exclude = false}) =>
    Entry(id: id, date: d, kind: k, amount: amount, accountId: acc, categoryId: cat.isEmpty ? null : cat, asset: asset, excludeFromReports: exclude);

void main() {
  group('Abschreibungen', () {
    FixedAsset asset(AssetInfo info, int cost) => FixedAsset(
      id: 'a',
      info: info,
      acquired: DateTime(2026, 3, 1),
      cost: cost,
      startYear: 2026,
      startValue: cost,
      entryId: 'x',
    );

    test('degressiv 40 % vom Restwert, am Schluss bleibt CHF 1', () {
      final a = asset(AssetInfo(type: AssetType.it), 200000);
      expect(a.yearOf(2026).depreciation, 80000);
      expect(a.yearOf(2027).start, 120000);
      expect(a.yearOf(2027).depreciation, 48000);
      expect(a.yearOf(2028).depreciation, 28800);
      expect(a.yearOf(2025).start, 0);
      // Nach genügend Jahren steht die Anlage mit CHF 1.
      expect(a.yearOf(2040).end, Depreciation.memo);
      expect(a.boughtIn(2026), isTrue);
      expect(a.boughtIn(2027), isFalse);
    });

    test('linear: jedes Jahr gleich viel', () {
      final a = asset(AssetInfo(type: AssetType.machine, method: DepMethod.linear, rate: 20), 100000);
      for (var y = 2026; y <= 2029; y++) {
        expect(a.yearOf(y).depreciation, 20000, reason: '$y');
      }
      expect(a.yearOf(2030).depreciation, 19900);
      expect(a.yearOf(2030).end, 100);
      expect(a.yearOf(2031).depreciation, 0);
    });

    test('Sofortabschreibung und Verkauf', () {
      final a = asset(AssetInfo(method: DepMethod.immediate), 150000);
      expect(a.yearOf(2026).depreciation, 149900);
      final b = asset(AssetInfo(type: AssetType.vehicle, soldYear: 2027), 1000000);
      expect(b.yearOf(2027).end, 0);
      expect(b.yearOf(2027).depreciation, b.yearOf(2027).start);
      expect(b.yearOf(2028).start, 0);
    });

    test('Format der früheren App wird gelesen', () {
      expect(AssetInfo.fromJson({'enabled': false, 'method': 'linear', 'rate': 20}), isNull);
      final i = AssetInfo.fromJson({'enabled': true, 'method': 'linear', 'rate': 20, 'startYear': 2025, 'acquisitionValue': 450})!;
      expect(i.method, DepMethod.linear);
      expect(i.rate, 20);
    });

    test('Fahrzeug: 0,9 % pro Monat, mindestens CHF 1800', () {
      expect(Vehicle(id: 'v', price: 3000000).privateShare, 324000);
      expect(Vehicle(id: 'v', price: 500000).privateShare, 180000);
      expect(Vehicle(id: 'v', price: 3000000, months: 6).privateShare, 162000);
    });
  });

  group('Jahresabschluss', () {
    final cats = [
      ...DefaultCategories.build(english: false),
      ...DefaultCategories.buildPrivate(english: false),
    ];

    test('Kontrolle geht auf: Vermögen Anfang + Einkommen − Bezüge + Einlagen = Vermögen Ende', () {
      final accounts = [
        Account(id: 'bank', name: 'Bank', opening: 500000, openingDate: DateTime(2025, 1, 1)),
        Account(id: 'cash', name: 'Kasse', type: AccountType.cash, opening: 20000, openingDate: DateTime(2026, 6, 1)),
      ];
      final entries = [
        _e('2025a', DateTime(2025, 5, 1), EntryKind.income, 100000, cat: 'cat-in-gigs'),
        _e('i1', DateTime(2026, 2, 1), EntryKind.income, 300000, cat: 'cat-in-teaching'),
        _e('i2', DateTime(2026, 7, 3), EntryKind.income, 40000, cat: 'cat-in-gigs', acc: 'cash'),
        _e('x1', DateTime(2026, 2, 5), EntryKind.expense, 12000, cat: 'cat-ex-phone'),
        _e('x2', DateTime(2026, 4, 5), EntryKind.expense, 8000, cat: 'cat-ex-travel'),
        _e('x3', DateTime(2026, 4, 9), EntryKind.expense, 30000, cat: 'cat-ex-material'),
        _e('p1', DateTime(2026, 5, 1), EntryKind.expense, 100000, cat: DefaultCategories.privateOutId),
        _e('p2', DateTime(2026, 5, 2), EntryKind.income, 5000, cat: DefaultCategories.privateInId),
        _e('ex', DateTime(2026, 5, 3), EntryKind.expense, 2500, cat: 'cat-ex-other', exclude: true),
        _e('lap', DateTime(2026, 7, 1), EntryKind.expense, 200000, cat: 'cat-ex-it', asset: AssetInfo(name: 'Laptop', type: AssetType.it).toJson()),
        Entry(id: 't', date: DateTime(2026, 8, 1), kind: EntryKind.transfer, amount: 10000, accountId: 'bank', toAccountId: 'cash'),
      ];
      final orders = [
        Order(id: 'o1', number: 'A-1', title: 'Gig', kind: 'kind-gig', clientId: 'c', status: OrderStatus.invoiced, invoicedAt: DateTime(2026, 12, 20), items: [OrderItem(id: 'i', name: 'Gage', unitPrice: 60000, quantity: 1)]),
        Order(id: 'o2', number: 'A-2', title: 'Alt', kind: 'kind-gig', clientId: 'c', status: OrderStatus.paid, invoicedAt: DateTime(2025, 12, 10), paidAt: DateTime(2026, 1, 15), items: [OrderItem(id: 'i', name: 'Gage', unitPrice: 25000, quantity: 1)]),
      ];
      final closing = YearClosing(
        year: 2026,
        vehicles: [Vehicle(id: 'v', name: 'Auto', price: 2000000)],
        adjustments: [
          Adjustment(id: 'a1', label: 'Handy privat', categoryId: 'cat-ex-phone', percent: 25),
          Adjustment(id: 'a2', kind: AdjustmentKind.unbookedExpense, label: 'Arbeitszimmer', amount: 120000, group: ClosingGroup.rent),
        ],
        creditors: [Creditor(id: 'k', name: 'Musikhaus', amount: 7000, goods: true)],
      );
      final r = YearReport.compute(
        year: 2026,
        entries: entries,
        accounts: accounts,
        categories: cats,
        orders: orders,
        clients: [Client(id: 'c', company: 'Kulturverein')],
        assets: const [],
        closing: closing,
        previous: YearClosing(year: 2025),
      );
      expect(r.incomeTotal, 340000);
      expect(r.expenseTotal, 50000);
      expect(r.depreciationTotal, 80000);
      expect(r.vehicleShareTotal, 216000);
      expect(r.privateShareTotal, 3000);
      expect(r.unbookedExpenseTotal, 120000);
      expect(r.cashWithdrawals, 102500);
      expect(r.cashDeposits, 5000);
      expect(r.debtorsStartTotal, 25000);
      expect(r.debtorsEndTotal, 60000);
      expect(r.creditorsEndTotal, 7000);
      expect(r.cashProfit, 340000 - 50000 - 120000 - 80000 + 216000 + 3000);
      expect(r.businessIncome, r.cashProfit + 60000 - 25000 - 7000);
      expect(r.accounts.firstWhere((a) => a.account.id == 'cash').openedDuringYear, 20000);
      expect(r.assetsEnd, 120000);
      expect(r.boughtThisYear, 200000);
      expect(r.groupTotal(ClosingGroup.goods), 30000);
      expect(r.groupTotal(ClosingGroup.rent), 120000);
      expect(r.entriesWithoutAccount, 0);
      expect(r.difference, 0);

      // Luzern: Bruttogewinn minus Kosten ergibt das Einkommen.
      final lu = CantonForms.of('LU', r, mainOccupation: true);
      int code(String c) => lu.first.fields.where((f) => f.code == c).fold(0, (a, f) => a + f.amount);
      // Kosten stehen positiv, Privatanteile und Abschreibungen mit Vorzeichen.
      var afterCosts = code('S220');
      for (final f in lu.first.fields) {
        if (const ['S222', 'S230', 'S239'].contains(f.code)) afterCosts -= f.amount;
        if (f.code == 'S236–S238') afterCosts += f.amount < 0 ? f.amount.abs() : -f.amount;
        if (f.code == 'S240') afterCosts -= f.amount;
        if (f.code.isEmpty) afterCosts += f.amount;
      }
      expect(afterCosts, r.businessIncome);
      expect(code('S200'), 340000);
      expect(code('S230'), 120000);
      expect(code('Ziffer 110'), r.businessIncome);
      final priv = {for (final f in lu[2].fields) f.code: f.amount};
      expect(priv['S320'], 102500);
      expect(priv['S322'], 216000);
      // Die Ausgaben stehen in Baum-Reihenfolge, Unterkategorien mit Oberkategorie.
      expect(r.expenses.map((l) => l.label), contains('Spesen › Fahrspesen'));
    });

    test('Buchungen ohne Konto erklären eine Differenz', () {
      final r = YearReport.compute(
        year: 2026,
        entries: [_e('a', DateTime(2026, 2, 1), EntryKind.income, 1000, cat: 'cat-in-gigs', acc: 'weg')],
        accounts: [Account(id: 'bank', name: 'Bank', openingDate: DateTime(2026, 1, 1))],
        categories: cats,
        orders: const [],
        clients: const [],
        assets: const [],
      );
      expect(r.entriesWithoutAccount, 1);
      expect(r.difference, -1000);
    });
  });

  testWidgets('PDF und Tabelle lassen sich erstellen', (tester) async {
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('conti-pdf-'));
    final s = ContiState(dir!.path);
    await tester.runAsync(() async {
      await s.load();
      await s.mergeIn(categories: DefaultCategories.build(english: false));
      await s.finishSetup();
      await s.saveAccount(Account(id: 'bank', name: 'Bank', openingDate: DateTime(2026, 1, 1), opening: 100000));
      await s.saveEntry(_e('a', DateTime(2026, 3, 1), EntryKind.income, 50000, cat: 'cat-in-gigs'));
      await s.saveEntry(_e('b', DateTime(2026, 3, 2), EntryKind.expense, 1234, cat: 'cat-ex-phone'));
      await s.saveEntry(Entry(id: 'c', date: DateTime(2026, 4, 1), kind: EntryKind.expense, amount: 9000, accountId: 'bank', text: 'Saiten; "Rot"', splits: [
        EntrySplit(categoryId: 'cat-ex-material', amount: 6000),
        EntrySplit(categoryId: 'cat-ex-travel', amount: 3000),
      ]));
      await s.saveEntry(_e('d', DateTime(2026, 5, 1), EntryKind.expense, 240000, cat: 'cat-ex-equipment', asset: AssetInfo(name: 'Verstärker').toJson()));
    });
    L10n.language.value = AppLanguage.de;
    final csv = ClosingCsv.entries(s, 2026);
    final lines = csv.split('\r\n');
    expect(lines.length, 1 + 5);
    expect(csv, contains('"Saiten; ""Rot"""'));
    expect(csv, contains('-12.34'));
    expect(csv, contains('Anschaffung (Abschreibung)'));
    expect(ClosingCsv.bytes(csv).take(3), [0xEF, 0xBB, 0xBF]);

    final fonts = await tester.runAsync(PdfFonts.load);
    final b = Business(ownerName: 'Erika Muster', canton: 'LU');
    final pdf = await tester.runAsync(() => buildClosingPdf(r: s.reportOf(2026), business: b, closing: s.closingOf(2026), fonts: fonts));
    expect(pdf!.length, greaterThan(5000));
    await tester.runAsync(() => File('${Directory.systemTemp.path}/conti-abschluss-test.pdf').writeAsBytes(pdf));
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  group('Abgeschlossenes Jahr', () {
    late Directory dir;
    late ContiState s;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('conti-closing-');
      s = ContiState(dir.path);
      await s.load();
      L10n.language.value = AppLanguage.de;
      await s.mergeIn(categories: DefaultCategories.build(english: false));
      await s.finishSetup();
      await s.saveAccount(Account(id: 'bank', name: 'Bank', openingDate: DateTime(2025, 1, 1)));
    });

    tearDown(() => dir.delete(recursive: true));

    test('sperrt Buchungen, Wiedereröffnen bleibt im Verlauf', () async {
      final e = _e('a', DateTime(2025, 3, 1), EntryKind.income, 1000, cat: 'cat-in-gigs');
      await s.saveEntry(e);
      expect(s.categories.any((c) => c.id == DefaultCategories.privateOutId), isTrue);
      await s.closeYear(2025);
      expect(s.isYearClosed(2025), isTrue);
      expect(() => s.saveEntry(e.copy()..amount = 5), throwsA(isA<YearClosedException>()));
      expect(() => s.deleteEntry(e), throwsA(isA<YearClosedException>()));
      // In ein abgeschlossenes Jahr verschieben geht auch nicht.
      final f = _e('b', DateTime(2026, 3, 1), EntryKind.income, 1000, cat: 'cat-in-gigs');
      await s.saveEntry(f);
      expect(() => s.saveEntry(f.copy()..date = DateTime(2025, 12, 1), previousYear: 2026), throwsA(isA<YearClosedException>()));
      await s.reopenYear(2025);
      expect(s.isYearClosed(2025), isFalse);
      expect(s.closingOf(2025).history.map((h) => h.action), ['closed', 'reopened']);
      // Neu geladen: alles noch da.
      final t = ContiState(dir.path);
      await t.load();
      expect(t.closingOf(2025).history.length, 2);
      expect(t.reportOf(2025).incomeTotal, 1000);
    });

    test('Privatbezüge zählen nicht als Ausgabe', () async {
      await s.saveEntry(_e('a', DateTime(2026, 3, 1), EntryKind.expense, 50000, cat: DefaultCategories.privateOutId));
      await s.saveEntry(_e('b', DateTime(2026, 3, 2), EntryKind.expense, 1000, cat: 'cat-ex-phone'));
      expect(s.expensesOf(2026), 1000);
      expect(s.totalsByTopCategory(2026, income: false).keys, ['cat-ex-phone']);
    });
  });
}
