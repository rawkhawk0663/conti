import 'package:flutter/material.dart';

import '../../app/error_log.dart';
import '../../app/files.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/invoice/invoicing.dart';
import '../../core/model/business.dart';
import '../../widgets/visuals.dart';

/// Wie Rechnungen aussehen: Nummern, Texte, Schrift, Name im QR-Zahlteil.
class InvoiceSettingsPage extends StatefulWidget {
  const InvoiceSettingsPage({super.key});

  @override
  State<InvoiceSettingsPage> createState() => _InvoiceSettingsPageState();
}

class _InvoiceSettingsPageState extends State<InvoiceSettingsPage> {
  late Business _b;
  final _c = <String, TextEditingController>{};
  bool _busy = false;

  TextEditingController _ctl(String k, String v) => _c.putIfAbsent(k, () => TextEditingController(text: v));

  @override
  void initState() {
    super.initState();
    _b = ContiScope.read(context).business.copy();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _take() {
    final i = _b.invoice;
    String v(String k, String fallback) => _c[k]?.text ?? fallback;
    i
      ..invoicePrefix = v('prefix', i.invoicePrefix).trim()
      ..orderPrefix = v('orderPrefix', i.orderPrefix).trim()
      ..paymentTermsDays = int.tryParse(v('terms', '${i.paymentTermsDays}').trim()) ?? i.paymentTermsDays
      ..title = v('title', i.title).trim()
      ..dueDateTitle = v('due', i.dueDateTitle).trim()
      ..totalTitle = v('total', i.totalTitle).trim()
      ..footerNote = v('footer', i.footerNote)
      ..qrMessage = v('qr', i.qrMessage).trim()
      ..qrCreditorCustomName = v('custom', i.qrCreditorCustomName).trim();
  }

  Future<void> _save() async {
    _take();
    await ContiScope.read(context).saveBusiness(_b);
    if (!mounted) return;
    _b = ContiScope.read(context).business.copy();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Gesichert', 'Saved')), persist: false));
  }

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      await _save();
      if (!mounted) return;
      final bytes = await Invoicing.preview(ContiScope.read(context));
      if (mounted) await openPdfBytes(context, bytes, 'Conti-Vorschau.pdf');
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Rechnungsvorschau');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Vorschau ging nicht: $e', 'Preview failed: $e'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _b.invoice;
    final c = context.conti;
    Widget field(String key, String label, String value, {String? hint, int lines = 1, TextInputType? type}) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: _ctl(key, value),
        minLines: lines,
        maxLines: lines == 1 ? 1 : 6,
        keyboardType: type,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Rechnungen', 'Invoices'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              if (_busy) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
              SectionCard(
                title: tr('Nummern und Frist', 'Numbers and terms'),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: field('prefix', tr('Kürzel Rechnungen', 'Invoice prefix'), i.invoicePrefix, hint: 'RE-')),
                        const SizedBox(width: 12),
                        Expanded(child: field('orderPrefix', tr('Kürzel Aufträge', 'Order prefix'), i.orderPrefix, hint: 'A-')),
                      ],
                    ),
                    field('terms', tr('Zahlungsfrist in Tagen', 'Payment terms in days'), '${i.paymentTermsDays}', type: TextInputType.number),
                    Text(
                      tr('Die Nummern sehen so aus: ${i.invoicePrefix}2026-0007 und ${i.orderPrefix}2026-0012.', 'Numbers look like this: ${i.invoicePrefix}2026-0007 and ${i.orderPrefix}2026-0012.'),
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: tr('Texte', 'Texts'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field('title', tr('Titel', 'Title'), i.title, hint: tr('Rechnung', 'Invoice')),
                    Row(
                      children: [
                        Expanded(child: field('due', tr('„Zahlbar bis“', '“Payable by”'), i.dueDateTitle)),
                        const SizedBox(width: 12),
                        Expanded(child: field('total', tr('„Gesamtbetrag“', '“Total”'), i.totalTitle)),
                      ],
                    ),
                    field('footer', tr('Dankeszeile', 'Closing note'), i.footerNote, lines: 3),
                    field('qr', tr('Mitteilung im QR-Zahlteil', 'Message in the QR payment part'), i.qrMessage),
                    Text(
                      tr(
                        'Platzhalter: {rechnungsnummer}, {name}, {firma}, {kunde}, {datum}, {fällig}, {auftrag}',
                        'Placeholders: {rechnungsnummer} (number), {name}, {firma} (company), {kunde} (client), {datum} (date), {fällig} (due), {auftrag} (order)',
                      ),
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: tr('Darstellung', 'Look'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CapsLabel(tr('Schrift', 'Font')),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'roboto-slab', label: Text(tr('Mit Serifen', 'Serif'))),
                        ButtonSegment(value: 'sans', label: Text(tr('Ohne Serifen', 'Sans serif'))),
                      ],
                      selected: {i.font == 'sans' ? 'sans' : 'roboto-slab'},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => setState(() => i.font = v.first),
                    ),
                    const SizedBox(height: 18),
                    CapsLabel(tr('Name im QR-Zahlteil', 'Name in the QR payment part')),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'owner', label: Text(tr('Mein Name', 'My name'))),
                        ButtonSegment(value: 'company', label: Text(tr('Firma', 'Company'))),
                        ButtonSegment(value: 'custom', label: Text(tr('Eigener', 'Custom'))),
                      ],
                      selected: {i.qrCreditorName},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => setState(() => i.qrCreditorName = v.first),
                    ),
                    if (i.qrCreditorName == 'custom') ...[const SizedBox(height: 14), field('custom', tr('Name', 'Name'), i.qrCreditorCustomName)],
                    const SizedBox(height: 8),
                    Text(
                      tr('Logo, Unterschrift, Adresse und IBAN stellst du unter „Mein Geschäft“ ein.', 'Logo, signature, address and IBAN are set under “My business”.'),
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(onPressed: _busy ? null : _preview, icon: const Icon(Icons.visibility_outlined), label: Text(tr('Vorschau', 'Preview'))),
                  GradientButton(label: tr('Sichern', 'Save'), icon: Icons.check, onPressed: _busy ? null : _save),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
