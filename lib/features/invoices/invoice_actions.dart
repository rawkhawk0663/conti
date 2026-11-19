import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/error_log.dart';
import '../../app/files.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/dates.dart';
import '../../core/invoice/invoicing.dart';
import '../../core/model/crm.dart';
import '../../core/money.dart';
import '../../core/sync/sync_controller.dart';
import '../../widgets/visuals.dart';
import '../settings/business_page.dart';

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) => showDatePicker(
  context: context,
  initialDate: initial,
  firstDate: DateTime(2000),
  lastDate: DateTime(Day.today().year + 5, 12, 31),
);

/// Rechnung stellen: prüfen, Nummer und Daten wählen, PDF erstellen.
/// Gibt den verrechneten Auftrag zurück (null = abgebrochen).
Future<Order?> issueInvoiceFlow(BuildContext context, Order order) async {
  final s = ContiScope.read(context);
  // Erst abgleichen, damit kein anderes Gerät dieselbe Nummer schon vergeben hat.
  try {
    await SyncScope.of(context).syncNow();
  } catch (_) {}
  if (!context.mounted) return null;
  final fresh = s.order(order.id) ?? order;
  var withQr = true;
  final problems = Invoicing.problems(s, fresh);
  if (problems.isNotEmpty) {
    final onlyQr = Invoicing.problems(s, fresh, withQr: false).isEmpty;
    final go = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Noch nicht bereit', 'Not ready yet')),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in problems) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('· $p')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
          if (onlyQr) TextButton(onPressed: () => Navigator.pop(context, 'noqr'), child: Text(tr('Ohne QR-Zahlteil', 'Without QR part'))),
          FilledButton(onPressed: () => Navigator.pop(context, 'business'), child: Text(tr('Mein Geschäft öffnen', 'Open My business'))),
        ],
      ),
    );
    if (!context.mounted) return null;
    if (go == 'business') {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BusinessPage()));
      return null;
    }
    if (go != 'noqr') return null;
    withQr = false;
  }

  final today = Day.today();
  var date = fresh.invoicedAt ?? today;
  var due = fresh.dueDate ?? date.add(Duration(days: s.business.invoice.paymentTermsDays));
  final number = TextEditingController(text: fresh.invoiceNumber.isNotEmpty ? fresh.invoiceNumber : Invoicing.nextNumber(s, date));
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(fresh.invoiceNumber.isEmpty ? tr('Rechnung stellen', 'Create invoice') : tr('Rechnung neu erstellen', 'Recreate invoice')),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: number, decoration: InputDecoration(labelText: tr('Rechnungs-Nr.', 'Invoice no.'))),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await _pickDate(context, date);
                        if (d != null) {
                          setState(() {
                            date = d;
                            due = d.add(Duration(days: s.business.invoice.paymentTermsDays));
                          });
                        }
                      },
                      child: InputDecorator(decoration: InputDecoration(labelText: tr('Datum', 'Date')), child: Text(Day.short(date))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await _pickDate(context, due);
                        if (d != null) setState(() => due = d);
                      },
                      child: InputDecorator(decoration: InputDecoration(labelText: tr('Zahlbar bis', 'Payable by')), child: Text(Day.short(due))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text(tr('Betrag', 'Amount'))),
                  Text('CHF ${Money.format(fresh.total)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              if (!withQr)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(tr('Ohne QR-Zahlteil.', 'Without QR payment part.'), style: TextStyle(color: context.conti.muted)),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(
            onPressed: () {
              final n = number.text.trim();
              if (n.isEmpty) {
                setState(() => error = tr('Bitte eine Nummer eingeben.', 'Please enter a number.'));
                return;
              }
              if (Invoicing.numberTaken(s, n, exceptOrder: fresh.id)) {
                setState(() => error = tr('Diese Nummer hat schon eine andere Rechnung.', 'Another invoice already has this number.'));
                return;
              }
              Navigator.pop(context, true);
            },
            child: Text(tr('Erstellen', 'Create')),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return null;
  try {
    final o = await Invoicing.issue(s, fresh, number: number.text.trim(), date: date, due: due, withQr: withQr);
    if (context.mounted) await openFile(context, s.dataPath(o.invoiceFile));
    return o;
  } catch (e, st) {
    ErrorLog.record(e, st, where: 'Rechnung erstellen');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Die Rechnung liess sich nicht erstellen: $e', 'The invoice could not be created: $e'))));
    }
    return null;
  }
}

/// Zahlung erfassen: Einnahme mit der Rechnung als Beleg.
Future<void> recordPaymentFlow(BuildContext context, Order order) async {
  final s = ContiScope.read(context);
  final accounts = s.activeAccounts;
  if (accounts.isEmpty) return;
  final cats = s.categoryTree(income: true);
  var date = Day.today();
  var accountId = (accounts.where((a) => a.id == s.device.lastAccountId).firstOrNull ?? accounts.first).id;
  String? categoryId = cats.isEmpty ? null : cats.first.$1.id;
  // Bisherige Zahlungen dieses Kunden: gleiche Kategorie vorschlagen.
  final earlier = s.entriesOf(order.clientId ?? '').where((e) => e.orderId != null && e.categoryId != null).firstOrNull;
  if (earlier != null) categoryId = earlier.categoryId;
  final amount = TextEditingController(text: Money.forInput(order.total));
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr('Zahlung erfassen', 'Record payment')),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'CHF'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await _pickDate(context, date);
                        if (d != null) setState(() => date = d);
                      },
                      child: InputDecorator(decoration: InputDecoration(labelText: tr('Eingang am', 'Received on')), child: Text(Day.short(date))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: accountId,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Konto', 'Account')),
                items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                onChanged: (v) => setState(() => accountId = v ?? accountId),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                initialValue: cats.any((c) => c.$1.id == categoryId) ? categoryId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Kategorie', 'Category')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('Ohne Kategorie', 'No category'))),
                  for (final (c, depth) in cats)
                    DropdownMenuItem(value: c.id, child: Padding(padding: EdgeInsets.only(left: depth * 16.0), child: Text(c.name))),
                ],
                onChanged: (v) => setState(() => categoryId = v),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(
            onPressed: () {
              final a = Money.parse(amount.text);
              if (a == null || a <= 0) {
                setState(() => error = tr('Bitte einen Betrag eingeben.', 'Please enter an amount.'));
                return;
              }
              Navigator.pop(context, true);
            },
            child: Text(tr('Verbuchen', 'Record')),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await Invoicing.recordPayment(s, s.order(order.id) ?? order, date: date, accountId: accountId, amount: Money.parse(amount.text)!, categoryId: categoryId);
  } on YearClosedException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Zahlung verbucht, Rechnung bezahlt.', 'Payment recorded, invoice paid.')), persist: false),
    );
  }
}

/// Zahlungserinnerung erstellen und öffnen.
Future<void> reminderFlow(BuildContext context, Order order) async {
  final s = ContiScope.read(context);
  final today = Day.today();
  try {
    final path = await Invoicing.reminder(s, s.order(order.id) ?? order, date: today, due: today.add(const Duration(days: 10)));
    if (context.mounted) await openFile(context, path);
  } catch (e, st) {
    ErrorLog.record(e, st, where: 'Zahlungserinnerung');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Das ging nicht: $e', 'That didn’t work: $e'))));
    }
  }
}

/// Karte „Rechnung“ im Auftrag: Stand und alle Knöpfe dazu.
class InvoiceCard extends StatelessWidget {
  const InvoiceCard({super.key, required this.orderId, required this.beforeIssue});
  final String orderId;

  /// Vor dem Stellen: Eingaben im Auftrag sichern. Gibt false zurück, wenn es nicht ging.
  final Future<bool> Function() beforeIssue;

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final o = s.order(orderId);
    final invoiced = o != null && o.invoiceNumber.isNotEmpty;
    final path = invoiced && o.invoiceFile.isNotEmpty ? s.dataPath(o.invoiceFile) : '';
    final hasFile = path.isNotEmpty && File(path).existsSync();
    final overdue = o != null && o.overdue(Day.today());
    final paid = o?.status == OrderStatus.paid;
    return SectionCard(
      title: tr('Rechnung', 'Invoice'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!invoiced) ...[
            Text(
              tr(
                'Aus diesem Auftrag wird eine PDF-Rechnung mit QR-Zahlteil. Sie wird aufbewahrt und nie verändert.',
                'This order becomes a PDF invoice with a QR payment part. It is kept and never changed.',
              ),
              style: TextStyle(color: c.muted),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: GradientButton(
                label: tr('Rechnung stellen', 'Create invoice'),
                icon: Icons.request_quote_outlined,
                onPressed: () async {
                  if (!await beforeIssue()) return;
                  if (!context.mounted) return;
                  final x = s.order(orderId);
                  if (x != null) await issueInvoiceFlow(context, x);
                },
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.invoiceNumber, style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        [
                          if (o.invoicedAt != null) tr('vom ${Day.short(o.invoicedAt!)}', 'dated ${Day.short(o.invoicedAt!)}'),
                          if (o.dueDate != null && !paid) tr('zahlbar bis ${Day.short(o.dueDate!)}', 'payable by ${Day.short(o.dueDate!)}'),
                          if (paid && o.paidAt != null) tr('bezahlt am ${Day.short(o.paidAt!)}', 'paid on ${Day.short(o.paidAt!)}'),
                          if (o.reminders.isNotEmpty) tr('${o.reminders.length} × erinnert', '${o.reminders.length} reminder(s)'),
                        ].join(' · '),
                        style: TextStyle(color: overdue ? c.minus : c.muted),
                      ),
                    ],
                  ),
                ),
                if (!hasFile)
                  Tooltip(message: tr('Kein PDF in Conti (z. B. aus der früheren App)', 'No PDF in Conti (e.g. from the previous app)'), child: Icon(Icons.description_outlined, color: c.muted)),
                if (paid)
                  Icon(Icons.check_circle, color: c.plus)
                else if (overdue)
                  Text(tr('Überfällig', 'Overdue'), style: TextStyle(color: c.minus, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (hasFile) OutlinedButton.icon(onPressed: () => openFile(context, path), icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(tr('Öffnen', 'Open'))),
                if (hasFile)
                  Builder(
                    builder: (bctx) => OutlinedButton.icon(
                      onPressed: () => shareFile(
                        bctx,
                        path,
                        subject: tr('Rechnung ${o.invoiceNumber}', 'Invoice ${o.invoiceNumber}'),
                        text: tr('Rechnung ${o.invoiceNumber} über CHF ${Money.format(o.total)}', 'Invoice ${o.invoiceNumber} for CHF ${Money.format(o.total)}'),
                      ),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(tr('Senden', 'Send')),
                    ),
                  ),
                if (hasFile && isDesktop) OutlinedButton.icon(onPressed: () => saveCopy(context, path), icon: const Icon(Icons.save_alt), label: Text(tr('Speichern unter …', 'Save as …'))),
                if (!paid) OutlinedButton.icon(onPressed: () => reminderFlow(context, o), icon: const Icon(Icons.notification_important_outlined), label: Text(tr('Zahlungserinnerung', 'Reminder'))),
                if (!paid)
                  TextButton(
                    onPressed: () async {
                      if (!await beforeIssue()) return;
                      if (context.mounted) await issueInvoiceFlow(context, s.order(orderId)!);
                    },
                    child: Text(tr('Neu erstellen', 'Recreate')),
                  ),
                if (!paid) GradientButton(label: tr('Zahlung erfassen', 'Record payment'), icon: Icons.payments_outlined, colors: c.mint, onPressed: () => recordPaymentFlow(context, o)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
