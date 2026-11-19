import 'dart:io';
import 'dart:typed_data';

import '../../app/l10n.dart';
import '../conti_state.dart';
import '../dates.dart';
import '../model/crm.dart';
import '../model/entry.dart';
import '../model/synced.dart';
import 'invoice_pdf.dart';

/// Rechnungen stellen, Zahlungen verbuchen, Zahlungserinnerungen.
///
/// Gestellte Rechnungen werden als PDF im Datenordner aufbewahrt
/// (`rechnungen/<jahr>/<nummer>.pdf`) und nie verändert. Wird eine Rechnung
/// neu erstellt, bekommt die neue Datei einen eigenen Namen.
class Invoicing {
  Invoicing._();

  /// Nächste freie Rechnungsnummer, z. B. „RE-2026-0007“.
  static String nextNumber(ContiState s, DateTime date) {
    final prefix = '${s.business.invoice.invoicePrefix}${date.year}-';
    var max = 0;
    for (final o in s.orders) {
      if (!o.invoiceNumber.startsWith(prefix)) continue;
      final n = int.tryParse(o.invoiceNumber.substring(prefix.length));
      if (n != null && n > max) max = n;
    }
    return '$prefix${(max + 1).toString().padLeft(4, '0')}';
  }

  /// Ist die Nummer schon bei einem anderen Auftrag vergeben?
  static bool numberTaken(ContiState s, String number, {String? exceptOrder}) =>
      s.orders.any((o) => o.id != exceptOrder && o.invoiceNumber == number);

  static File? _file(ContiState s, String rel) => rel.isEmpty ? null : File(s.dataPath(rel));

  static InvoiceData data(ContiState s, Order o, {required String number, required DateTime date, required DateTime due, DateTime? reminderOf, bool withQr = true}) =>
      InvoiceData(
        business: s.business,
        order: o,
        client: s.client(o.clientId),
        number: number,
        date: date,
        due: due,
        logo: _file(s, s.business.logoFile),
        signature: _file(s, s.business.signatureFile),
        reminderOf: reminderOf,
        withQr: withQr,
      );

  /// Was einer Rechnung fehlt (leer = alles bereit).
  static List<String> problems(ContiState s, Order o, {bool withQr = true}) {
    final out = <String>[];
    if (o.items.isEmpty) out.add(tr('Der Auftrag hat noch keine Positionen.', 'The order has no items yet.'));
    if (o.total <= 0) out.add(tr('Der Gesamtbetrag ist null.', 'The total is zero.'));
    final b = s.business;
    if (b.displayName.isEmpty) out.add(tr('Unter „Mein Geschäft“ fehlt dein Name.', 'Your name is missing under “My business”.'));
    if (withQr) {
      final d = data(s, o, number: '0', date: Day.today(), due: Day.today());
      out.addAll(d.qrBill.problems(tr: tr));
    }
    return out;
  }

  /// Rechnung stellen: PDF erstellen und aufbewahren, Auftrag auf
  /// „verrechnet“ setzen. Gibt den geänderten Auftrag zurück.
  static Future<Order> issue(ContiState s, Order order, {required String number, required DateTime date, required DateTime due, bool withQr = true}) async {
    final o = order.copy();
    final bytes = await buildInvoicePdf(data(s, o, number: number, date: date, due: due, withQr: withQr));
    var rel = 'rechnungen/${date.year}/${_safe(number)}.pdf';
    var n = 2;
    while (await File(s.dataPath(rel)).exists()) {
      rel = 'rechnungen/${date.year}/${_safe(number)}-$n.pdf';
      n++;
    }
    await s.store.putFile(rel, bytes);
    o
      ..invoiceNumber = number
      ..invoicedAt = date
      ..dueDate = due
      ..invoiceFile = rel
      ..status = o.status == OrderStatus.paid ? OrderStatus.paid : OrderStatus.invoiced;
    await s.saveOrder(o);
    return o;
  }

  /// Zahlungserinnerung als PDF (wird ebenfalls aufbewahrt). Gibt den Pfad zurück.
  static Future<String> reminder(ContiState s, Order order, {required DateTime date, required DateTime due}) async {
    final o = order.copy();
    final bytes = await buildInvoicePdf(
      data(s, o, number: o.invoiceNumber, date: date, due: due, reminderOf: o.invoicedAt ?? date),
    );
    final rel = 'rechnungen/${(o.invoicedAt ?? date).year}/${_safe(o.invoiceNumber)}-erinnerung-${o.reminders.length + 1}.pdf';
    await s.store.putFile(rel, bytes);
    o
      ..reminders = [...o.reminders, date]
      ..dueDate = due;
    await s.saveOrder(o);
    return s.dataPath(rel);
  }

  /// Zahlung erfassen: Einnahme buchen (mit der Rechnung als Beleg) und den
  /// Auftrag auf „bezahlt“ setzen.
  static Future<Entry> recordPayment(
    ContiState s,
    Order order, {
    required DateTime date,
    required String accountId,
    required int amount,
    String? categoryId,
  }) async {
    final o = order.copy();
    final client = s.client(o.clientId);
    final attachments = <Attachment>[];
    if (o.invoiceFile.isNotEmpty && await File(s.dataPath(o.invoiceFile)).exists()) {
      attachments.add(
        Attachment(
          id: newId(),
          file: o.invoiceFile,
          name: '${o.invoiceNumber}.pdf',
          kind: 'invoice',
          size: await File(s.dataPath(o.invoiceFile)).length(),
        ),
      );
    }
    final e = Entry(
      id: newId(),
      date: date,
      kind: EntryKind.income,
      amount: amount,
      text: [o.title.isEmpty ? tr('Rechnung', 'Invoice') : o.title, ?client?.displayName].join(' · '),
      accountId: accountId,
      categoryId: categoryId,
      number: o.invoiceNumber,
      clientId: o.clientId,
      orderId: o.id,
      attachments: attachments,
    );
    await s.saveEntry(e);
    o
      ..status = OrderStatus.paid
      ..paidAt = date
      ..paidEntryId = e.id;
    await s.saveOrder(o);
    return e;
  }

  /// Beispielrechnung für die Vorschau in den Einstellungen.
  static Future<Uint8List> preview(ContiState s) {
    final today = Day.today();
    final o = Order(
      id: 'vorschau',
      number: '${s.business.invoice.orderPrefix}${today.year}-0001',
      title: tr('Beispiel', 'Example'),
      items: [
        OrderItem(id: '1', name: 'Gig', description: tr('Pauschalgage für Konzert', 'Flat fee for a concert'), unitPrice: 30000),
        OrderItem(id: '2', name: tr('Fahrkosten', 'Travel'), quantity: 1, unitPrice: 4000),
      ],
    );
    final d = InvoiceData(
      business: s.business,
      order: o,
      client: Client(id: 'x', firstName: 'Erika', lastName: 'Muster', street: 'Beispielweg', houseNumber: '12', zip: '3000', city: 'Bern'),
      number: nextNumber(s, today),
      date: today,
      due: today.add(Duration(days: s.business.invoice.paymentTermsDays)),
      logo: _file(s, s.business.logoFile),
      signature: _file(s, s.business.signatureFile),
    );
    return buildInvoicePdf(d);
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
}
