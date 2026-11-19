import 'dart:convert';
import 'dart:io';

import 'package:conti/app/l10n.dart';
import 'package:conti/core/conti_state.dart';
import 'package:conti/core/dates.dart';
import 'package:conti/core/invoice/invoice_pdf.dart';
import 'package:conti/core/invoice/invoicing.dart';
import 'package:conti/core/invoice/swiss_qr.dart';
import 'package:conti/core/import/legacy_import.dart';
import 'package:conti/core/model/category.dart';
import 'package:conti/core/model/account.dart';
import 'package:conti/core/model/business.dart';
import 'package:conti/core/model/crm.dart';
import 'package:conti/core/model/entry.dart';
import 'package:flutter_test/flutter_test.dart';

String trDe(String de, String en) => de;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QR-Referenz', () {
    test('Prüfziffer Modulo 10 rekursiv (Beispiel der Banken)', () {
      expect(QrBill.mod10Check('21000000000313947143000901'), 7);
      expect(QrBill.isValidQrReference('21 00000 00003 13947 14300 09017'), isTrue);
      expect(QrBill.isValidQrReference('21 00000 00003 13947 14300 09018'), isFalse);
      final r = QrBill.qrReferenceFrom('RE-2026-0007');
      expect(r.length, 27);
      expect(r.startsWith('0000000000000000002026000'), isTrue);
      expect(QrBill.isValidQrReference(r), isTrue);
      expect(QrBill.prettyQrReference('210000000003139471430009017'), '21 00000 00003 13947 14300 09017');
    });
  });

  group('Zahlteil', () {
    const creditor = QrAddress(name: 'Max Beispiel', street: 'Musterweg', houseNumber: '3', zip: '6000', city: 'Luzern');
    test('Inhalt mit normaler IBAN und Mitteilung', () {
      final q = QrBill(
        iban: 'CH93 0076 2011 6238 5295 7',
        creditor: creditor,
        amount: 30000,
        debtor: const QrAddress(name: 'Erika Muster', street: 'Beispielweg', houseNumber: '12', zip: '3000', city: 'Bern'),
        message: 'Rechnung RE-2026-0007',
      );
      expect(q.problems(tr: trDe), isEmpty);
      final lines = q.payload().split('\n');
      expect(lines.length, 31);
      expect(lines.sublist(0, 4), ['SPC', '0200', '1', 'CH9300762011623852957']);
      expect(lines.sublist(4, 11), ['S', 'Max Beispiel', 'Musterweg', '3', '6000', 'Luzern', 'CH']);
      expect(lines.sublist(11, 18), List.filled(7, ''));
      expect(lines[18], '300.00');
      expect(lines[19], 'CHF');
      expect(lines.sublist(20, 27), ['S', 'Erika Muster', 'Beispielweg', '12', '3000', 'Bern', 'CH']);
      expect(lines[27], 'NON');
      expect(lines[28], '');
      expect(lines[29], 'Rechnung RE-2026-0007');
      expect(lines[30], 'EPD');
    });

    test('QR-IBAN braucht eine QR-Referenz, ohne Zahlenden bleibt das Feld leer', () {
      final bad = QrBill(iban: 'CH44 3199 9123 0008 8901 2', creditor: creditor, amount: 100);
      expect(bad.problems(tr: trDe), contains('Mit einer QR-IBAN braucht es eine QR-Referenz.'));
      final ok = QrBill(
        iban: 'CH44 3199 9123 0008 8901 2',
        creditor: creditor,
        amount: 100,
        referenceType: QrReferenceType.qrr,
        reference: '210000000003139471430009017',
      );
      expect(ok.problems(tr: trDe), isEmpty);
      final lines = ok.payload().split('\n');
      expect(lines.sublist(20, 27), List.filled(7, ''));
      expect(lines[27], 'QRR');
      expect(lines[28], '210000000003139471430009017');
    });

    test('fehlende Angaben werden gemeldet', () {
      final q = QrBill(iban: 'CH00 1234', creditor: const QrAddress(name: '', zip: '', city: ''), amount: 0);
      final p = q.problems(tr: trDe);
      expect(p.length, greaterThanOrEqualTo(3));
    });
  });

  group('Rechnungen', () {
    late Directory dir;
    late ContiState s;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('conti-inv-');
      s = ContiState(dir.path);
      await s.load();
      L10n.language.value = AppLanguage.de;
      await s.finishSetup();
      await s.saveBusiness(
        Business(
          ownerName: 'Max Beispiel',
          street: 'Musterweg',
          houseNumber: '3',
          zip: '6000',
          city: 'Luzern',
          email: 'max@example.com',
          iban: 'CH93 0076 2011 6238 5295 7',
          invoice: InvoiceSettings(invoicePrefix: 'XY-'),
        ),
      );
      await s.saveAccount(Account(id: 'bank', name: 'Bank', openingDate: DateTime(2026, 1, 1)));
      await s.saveClient(Client(id: 'c', firstName: 'Erika', lastName: 'Muster', street: 'Beispielweg', houseNumber: '12', zip: '3000', city: 'Bern'));
    });
    tearDown(() => dir.delete(recursive: true));

    Order order({int items = 1}) => Order(
      id: 'o',
      number: 'A-2026-0001',
      title: 'Konzert',
      clientId: 'c',
      items: [
        for (var i = 0; i < items; i++)
          OrderItem(id: '$i', name: 'Gig $i', description: 'Pauschalgage für Konzert', unitPrice: 30000),
      ],
    );

    test('Nummern zählen pro Jahr', () async {
      expect(Invoicing.nextNumber(s, DateTime(2026, 5, 1)), 'XY-2026-0001');
      await s.saveOrder(Order(id: 'old', number: 'A', title: 'x', invoiceNumber: 'XY-2026-0006'));
      expect(Invoicing.nextNumber(s, DateTime(2026, 5, 1)), 'XY-2026-0007');
      expect(Invoicing.numberTaken(s, 'XY-2026-0006'), isTrue);
    });

    test('Rechnung stellen, PDF aufbewahren, Zahlung verbuchen', () async {
      await s.saveOrder(order());
      expect(Invoicing.problems(s, s.order('o')!), isEmpty);
      final date = DateTime(2026, 11, 18);
      final o = await Invoicing.issue(s, s.order('o')!, number: 'XY-2026-0001', date: date, due: date.add(const Duration(days: 30)));
      expect(o.status, OrderStatus.invoiced);
      expect(o.invoiceFile, 'rechnungen/2026/XY-2026-0001.pdf');
      final pdf = File(s.dataPath(o.invoiceFile));
      expect(pdf.readAsBytesSync().take(4), '%PDF'.codeUnits);
      expect(o.overdue(DateTime(2026, 12, 19)), isTrue);
      expect(o.overdue(DateTime(2026, 12, 17)), isFalse);

      // Neu erstellen: die alte Datei bleibt, die neue bekommt einen eigenen Namen.
      final o2 = await Invoicing.issue(s, o, number: 'XY-2026-0001', date: date, due: date.add(const Duration(days: 30)));
      expect(o2.invoiceFile, 'rechnungen/2026/XY-2026-0001-2.pdf');
      expect(pdf.existsSync(), isTrue);

      final path = await Invoicing.reminder(s, o2, date: DateTime(2026, 12, 20), due: DateTime(2026, 12, 30));
      expect(File(path).existsSync(), isTrue);
      expect(s.order('o')!.reminders.single, DateTime(2026, 12, 20));

      final e = await Invoicing.recordPayment(s, s.order('o')!, date: DateTime(2026, 12, 22), accountId: 'bank', amount: 30000, categoryId: 'cat-in-gigs');
      expect(e.kind, EntryKind.income);
      expect(e.orderId, 'o');
      expect(e.number, 'XY-2026-0001');
      expect(e.attachments.single.kind, 'invoice');
      expect(s.order('o')!.status, OrderStatus.paid);
      expect(s.balance('bank'), 30000);
      expect(s.openAmountOf('c'), 0);
    });

    test('lange Rechnung: Zahlteil auf eigener Seite, mit QR-IBAN und Referenz', () async {
      final b = s.business.copy()..iban = 'CH44 3199 9123 0008 8901 2';
      await s.saveBusiness(b);
      await s.saveOrder(order(items: 12));
      final d = Invoicing.data(s, s.order('o')!, number: 'XY-2026-0002', date: Day.today(), due: Day.today());
      expect(d.qrBill.referenceType, QrReferenceType.qrr);
      expect(d.qrBill.problems(tr: trDe), isEmpty);
      final bytes = await buildInvoicePdf(d);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(d.fill('Vielen Dank.\n{name}, Rechnung {rechnungsnummer}'), 'Vielen Dank.\nMax Beispiel, Rechnung XY-2026-0002');
    });

    test('Import übernimmt Rechnungs-PDFs der früheren App', () async {
      final json = jsonDecode(File('test/fixtures/legacy_sample.json').readAsStringSync()) as Map<String, dynamic>;
      final old = Directory('${dir.path}/alt/Rechnungen/2025')..createSync(recursive: true);
      Directory('${dir.path}/alt/Belege').createSync(recursive: true);
      File('${old.path}/XYZ-2025-0001.pdf').writeAsStringSync('%PDF-alt');
      await s.mergeIn(categories: DefaultCategories.build(english: false));
      await LegacyImport.apply(s, LegacyImport.parse(json, existing: s.categories), accountId: 'bank', receiptsFolder: '${dir.path}/alt/Belege');
      final o = s.order('o-1')!;
      expect(o.invoiceFile, 'rechnungen/2025/XYZ-2025-0001.pdf');
      expect(File(s.dataPath(o.invoiceFile)).readAsStringSync(), '%PDF-alt');
    });

    test('Vorschau geht auch ohne Kunden', () async {
      final bytes = await Invoicing.preview(s);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}
