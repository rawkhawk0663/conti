import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/l10n.dart';
import '../dates.dart';
import '../invoice/invoice_pdf.dart' show PdfFonts;
import '../model/business.dart';
import '../model/closing.dart';
import '../money.dart';
import '../swiss.dart';
import 'canton_forms.dart';
import 'year_report.dart';

const _mm = PdfPageFormat.mm;
const _ink = PdfColor.fromInt(0xFF2A2A2E);
const _grey = PdfColor.fromInt(0xFF6E6E76);
const _rule = PdfColor.fromInt(0xFFB9B9C0);
const _band = PdfColor.fromInt(0xFFF1F1F4);

/// Jahresabschluss als PDF (A4), als Beilage zur Steuererklärung:
/// Erfolgsrechnung, Vermögen am Anfang und Ende des Jahres, Privatbezüge
/// und -einlagen mit Kontrolle, Abschreibungstabelle, offene Rechnungen und
/// (für unterstützte Kantone) die Felder der Formulare.
Future<Uint8List> buildClosingPdf({
  required YearReport r,
  required Business business,
  required YearClosing closing,
  PdfFonts? fonts,
  DateTime? now,
}) async {
  final f = fonts ?? await PdfFonts.load();
  final sansBody = business.invoice.font == 'sans';
  final light = sansBody ? f.sans : f.slabLight;
  final regular = sansBody ? f.sans : f.slab;
  final bold = sansBody ? f.sansBold : f.slabBold;
  final created = now ?? DateTime.now();
  final y = r.year;

  pw.TextStyle st(pw.Font font, double size, {PdfColor color = _ink}) =>
      pw.TextStyle(font: font, fontSize: size, color: color, lineSpacing: 1.3);
  String chf(int v) => Money.format(v);

  pw.Widget heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 7 * _mm, bottom: 2 * _mm),
    child: pw.Text(text, style: st(bold, 12.5)),
  );

  pw.Widget note(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 1.5 * _mm),
    child: pw.Text(text, style: st(light, 8, color: _grey)),
  );

  /// Tabelle: erste Spalte Text, weitere Spalten Beträge.
  pw.Widget table(List<String> head, List<_Row> rows, {List<int>? flex, int leftCols = 1}) {
    final fl = flex ?? [6, for (var i = 1; i < head.length; i++) 2];
    pw.Widget cell(String t, int i, pw.TextStyle s) => pw.Expanded(
      flex: fl[i],
      child: pw.Text(t, textAlign: i < leftCols ? pw.TextAlign.left : pw.TextAlign.right, style: s),
    );
    return pw.Column(
      children: [
        pw.Row(children: [for (var i = 0; i < head.length; i++) cell(head[i], i, st(regular, 8, color: _grey))]),
        pw.SizedBox(height: 1 * _mm),
        pw.Container(height: 0.6, color: _ink),
        for (final row in rows)
          pw.Container(
            color: row.total ? _band : null,
            padding: pw.EdgeInsets.fromLTRB(row.total ? 1.5 * _mm : 0, 1.1 * _mm, row.total ? 1.5 * _mm : 0, 1.1 * _mm),
            decoration: row.total || row.isHeader ? null : const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.3))),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: fl[0],
                  child: pw.Padding(
                    padding: pw.EdgeInsets.only(left: row.indent * 4 * _mm),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(row.label, style: st(row.total || row.isHeader ? bold : regular, 9)),
                        if (row.note.isNotEmpty) pw.Text(row.note, style: st(light, 7.5, color: _grey)),
                      ],
                    ),
                  ),
                ),
                for (var i = 0; i < row.values.length; i++)
                  cell(row.values[i], i + 1, st(row.total ? bold : regular, 9)),
              ],
            ),
          ),
      ],
    );
  }

  // ---------- Kopf ----------
  final b = business;
  final address = [
    if (b.companyName.isNotEmpty && b.ownerName.isNotEmpty) b.ownerName,
    [b.street, b.houseNumber].where((s) => s.isNotEmpty).join(' '),
    [b.zip, b.city].where((s) => s.isNotEmpty).join(' '),
  ].where((s) => s.isNotEmpty).toList();
  final canton = cantons.where((c) => c.$1 == b.canton).map((c) => c.$2).firstOrNull ?? '';
  final header = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(b.displayName.isEmpty ? tr('Mein Geschäft', 'My business') : b.displayName, style: st(bold, 11)),
                for (final l in address) pw.Text(l, style: st(light, 8.5, color: _grey)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(tr('Geschäftsjahr', 'Business year'), style: st(light, 8.5, color: _grey)),
              pw.Text('01.01.$y – 31.12.$y', style: st(bold, 10)),
              if (canton.isNotEmpty) pw.Text('${tr('Kanton', 'Canton')} $canton', style: st(light, 8.5, color: _grey)),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 8 * _mm),
      pw.Text('${tr('Jahresabschluss', 'Annual accounts')} $y', style: st(regular, 26)),
      pw.SizedBox(height: 1.5 * _mm),
      pw.Text(
        tr(
          'Aufstellung über Einnahmen und Ausgaben, Vermögen sowie Privatbezüge und Privateinlagen (selbständige Erwerbstätigkeit ohne kaufmännische Buchhaltung)',
          'Statement of income and expenses, assets, private withdrawals and deposits (self-employed, without double-entry bookkeeping)',
        ),
        style: st(light, 9, color: _grey),
      ),
      pw.SizedBox(height: 2 * _mm),
      pw.Text(
        closing.closed
            ? tr('Abgeschlossen am ${Day.short(closing.closedAt!.toLocal())}', 'Closed on ${Day.short(closing.closedAt!.toLocal())}')
            : tr('Entwurf: Das Jahr ist noch nicht abgeschlossen.', 'Draft: the year is not closed yet.'),
        style: st(bold, 8.5, color: closing.closed ? _ink : _grey),
      ),
    ],
  );

  // ---------- Erfolgsrechnung ----------
  final profitRows = <_Row>[
    _Row(tr('Einnahmen', 'Income'), const [], isHeader: true),
    for (final l in r.income) _Row(l.label, [chf(l.amount)], indent: 1),
    for (final x in r.unbookedIncome) _Row(x.label, [chf(x.amount)], indent: 1, note: tr('nicht gebucht', 'not booked')),
    _Row(tr('Total Einnahmen', 'Total income'), [chf(r.incomeTotal + r.unbookedIncomeTotal)], total: true),
    _Row(tr('Ausgaben', 'Expenses'), const [], isHeader: true),
    for (final l in r.expenses) _Row(l.label, [chf(-l.amount)], indent: 1),
    for (final x in r.unbookedExpenses)
      _Row(x.label, [chf(-x.amount)], indent: 1, note: tr('privat bezahlt, nicht gebucht', 'paid privately, not booked')),
    if (r.depreciationTotal != 0)
      _Row(tr('Abschreibungen (siehe Tabelle)', 'Depreciation (see schedule)'), [chf(-r.depreciationTotal)], indent: 1),
    for (final x in r.vehicleShares)
      _Row('${tr('Privatanteil', 'Private share')} ${x.label}', [chf(x.amount)], indent: 1,
          note: tr('0,9 % des Kaufpreises pro Monat, mindestens CHF 1\'800 im Jahr', '0.9% of the purchase price per month, at least CHF 1,800 a year')),
    for (final x in r.privateShares) _Row('${tr('Privatanteil', 'Private share')} ${x.label}', [chf(x.amount)], indent: 1),
    _Row(
      tr('Total Ausgaben', 'Total expenses'),
      [chf(-(r.expenseTotal + r.unbookedExpenseTotal + r.depreciationTotal - r.allPrivateShares))],
      total: true,
    ),
    _Row(tr('Ergebnis nach Zahlungen', 'Result on a cash basis'), [chf(r.cashProfit)], total: true),
    if (r.debtorsEndTotal != 0 || r.debtorsStartTotal != 0) ...[
      _Row(tr('+ Offene Kundenrechnungen am 31.12.$y', '+ Unpaid customer invoices on 31.12.$y'), [chf(r.debtorsEndTotal)], indent: 1),
      _Row(tr('− Offene Kundenrechnungen am 31.12.${y - 1}', '− Unpaid customer invoices on 31.12.${y - 1}'), [chf(-r.debtorsStartTotal)], indent: 1),
    ],
    if (r.creditorsEndTotal != 0 || r.creditorsStartTotal != 0) ...[
      _Row(tr('− Offene Lieferantenrechnungen am 31.12.$y', '− Unpaid supplier invoices on 31.12.$y'), [chf(-r.creditorsEndTotal)], indent: 1),
      _Row(tr('+ Offene Lieferantenrechnungen am 31.12.${y - 1}', '+ Unpaid supplier invoices on 31.12.${y - 1}'), [chf(r.creditorsStartTotal)], indent: 1),
    ],
    _Row(tr('Einkommen aus selbständiger Erwerbstätigkeit', 'Income from self-employment'), [chf(r.businessIncome)], total: true),
  ];

  // ---------- Vermögen ----------
  final assetRows = <_Row>[
    for (final a in r.accounts) _Row(a.account.name, [chf(a.start), chf(a.end)], indent: 1, note: a.account.iban.isEmpty ? '' : Iban.pretty(a.account.iban)),
    if (r.debtorsStartTotal != 0 || r.debtorsEndTotal != 0)
      _Row(tr('Offene Kundenrechnungen (Debitoren)', 'Unpaid customer invoices (receivables)'), [chf(r.debtorsStartTotal), chf(r.debtorsEndTotal)], indent: 1),
    if (r.assets.isNotEmpty)
      _Row(tr('Anlagen (Restwerte, siehe Tabelle)', 'Fixed assets (book values, see schedule)'), [chf(r.assetsStart), chf(r.assetsEnd)], indent: 1),
    if (r.creditorsStartTotal != 0 || r.creditorsEndTotal != 0)
      _Row(tr('Offene Lieferantenrechnungen (Kreditoren)', 'Unpaid supplier invoices (payables)'), [chf(-r.creditorsStartTotal), chf(-r.creditorsEndTotal)], indent: 1),
    _Row(tr('Geschäftsvermögen', 'Business assets'), [chf(r.netAssetsStart), chf(r.netAssetsEnd)], total: true),
  ];

  // ---------- Privat und Kontrolle ----------
  final privateRows = <_Row>[
    _Row(tr('Privatbezüge', 'Private withdrawals'), const [], isHeader: true),
    _Row(tr('Geld fürs Private (Bezüge, private Zahlungen)', 'Money taken for private use'), [chf(r.cashWithdrawals)], indent: 1),
    if (r.allPrivateShares != 0) _Row(tr('Privatanteile', 'Private shares'), [chf(r.allPrivateShares)], indent: 1),
    if (r.unbookedIncomeTotal != 0) _Row(tr('Nicht gebuchte Einnahmen', 'Income not booked'), [chf(r.unbookedIncomeTotal)], indent: 1),
    _Row(tr('Total Privatbezüge', 'Total withdrawals'), [chf(r.withdrawalsTotal)], total: true),
    _Row(tr('Privateinlagen', 'Private deposits'), const [], isHeader: true),
    _Row(tr('Geld aus dem Privaten', 'Money brought in privately'), [chf(r.cashDeposits)], indent: 1),
    if (r.newAccountDeposits != 0) _Row(tr('Anfangsbestand neuer Konten', 'Opening balance of new accounts'), [chf(r.newAccountDeposits)], indent: 1),
    if (r.unbookedExpenseTotal != 0) _Row(tr('Privat bezahlte Geschäftskosten', 'Business costs paid privately'), [chf(r.unbookedExpenseTotal)], indent: 1),
    _Row(tr('Total Privateinlagen', 'Total deposits'), [chf(r.depositsTotal)], total: true),
  ];
  final checkRows = <_Row>[
    _Row(tr('Geschäftsvermögen am 1. Januar', 'Business assets on 1 January'), [chf(r.netAssetsStart)]),
    _Row(tr('+ Einkommen aus selbständiger Erwerbstätigkeit', '+ Income from self-employment'), [chf(r.businessIncome)]),
    _Row(tr('− Privatbezüge', '− Private withdrawals'), [chf(-r.withdrawalsTotal)]),
    _Row(tr('+ Privateinlagen', '+ Private deposits'), [chf(r.depositsTotal)]),
    _Row(tr('= Geschäftsvermögen am 31. Dezember (gerechnet)', '= Business assets on 31 December (calculated)'), [chf(r.netAssetsEnd - r.difference)], total: true),
    _Row(tr('Geschäftsvermögen am 31. Dezember (laut Aufstellung)', 'Business assets on 31 December (as listed)'), [chf(r.netAssetsEnd)]),
    _Row(tr('Differenz', 'Difference'), [chf(r.difference)], total: true),
  ];

  // ---------- Abschreibungen ----------
  final depRows = <_Row>[
    for (final a in r.assets)
      _Row(
        a.asset.name.isEmpty ? a.asset.info.type.label : a.asset.name,
        [Day.short(a.asset.acquired), chf(a.asset.cost), chf(a.bought ? 0 : a.values.start), _rate(a.asset.info), chf(a.values.depreciation), chf(a.values.end)],
        note: [
          a.asset.info.type.label,
          if (a.bought) tr('angeschafft $y', 'acquired $y'),
          if (a.asset.info.soldYear == y) tr('verkauft/ausgeschieden', 'sold/disposed'),
        ].join(' · '),
      ),
    _Row(tr('Total', 'Total'), ['', '', chf(r.assetsStart), '', chf(r.depreciationTotal), chf(r.assetsEnd)], total: true),
  ];

  final sections = CantonForms.of(b.canton, r, mainOccupation: b.mainOccupation);

  final doc = pw.Document(title: '${tr('Jahresabschluss', 'Annual accounts')} $y', author: b.displayName, creator: 'Conti');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(20 * _mm, 16 * _mm, 20 * _mm, 14 * _mm),
      footer: (ctx) => pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              '${b.displayName} · ${tr('Jahresabschluss', 'Annual accounts')} $y · ${tr('erstellt am', 'created on')} ${Day.short(created)}',
              style: st(light, 7, color: _grey),
            ),
          ),
          pw.Text('${tr('Seite', 'Page')} ${ctx.pageNumber}/${ctx.pagesCount}', style: st(light, 7, color: _grey)),
        ],
      ),
      build: (ctx) => [
        header,
        heading(tr('Erfolgsrechnung', 'Income statement')),
        table([tr('Position', 'Item'), 'CHF'], profitRows),
        note(tr(
          'Einnahmen und Ausgaben zählen am Tag der Zahlung. Anschaffungen sind nicht in den Ausgaben, sondern über die Abschreibungen erfasst.',
          'Income and expenses count on the day of payment. Acquisitions are not in the expenses but included through depreciation.',
        )),
        heading(tr('Vermögen', 'Assets')),
        table([tr('Position', 'Item'), '01.01.$y', '31.12.$y'], assetRows),
        heading(tr('Privatbezüge und Privateinlagen', 'Private withdrawals and deposits')),
        table([tr('Position', 'Item'), 'CHF'], privateRows),
        heading(tr('Kontrolle', 'Check')),
        table([tr('Position', 'Item'), 'CHF'], checkRows),
        if (r.difference != 0)
          note(r.entriesWithoutAccount > 0
              ? tr(
                  '${r.entriesWithoutAccount} Buchungen gehören zu keinem Konto oder liegen vor dem Anfangsdatum ihres Kontos. Das erklärt die Differenz.',
                  '${r.entriesWithoutAccount} entries belong to no account or are dated before their account starts. This explains the difference.',
                )
              : tr('Die Differenz stammt aus Kontoständen, die nicht zu den Buchungen passen.', 'The difference comes from balances that do not match the entries.')),
        if (r.assets.isNotEmpty) ...[
          heading(tr('Abschreibungstabelle', 'Depreciation schedule')),
          table(
            [tr('Anlage', 'Asset'), tr('Gekauft', 'Bought'), tr('Kaufpreis', 'Cost'), '01.01.$y', tr('Satz', 'Rate'), tr('Abschreibung', 'Depreciation'), '31.12.$y'],
            depRows,
            flex: [5, 2, 2, 2, 2, 2, 2],
          ),
          note(tr(
            'Sätze nach den Normalsätzen der Eidgenössischen Steuerverwaltung (Merkblatt A 1995). Degressiv: vom Restwert; linear: vom Kaufpreis. Restwert mindestens CHF 1.',
            'Rates follow the standard rates of the Federal Tax Administration (leaflet A 1995). Declining: of the remaining value; straight-line: of the cost. Minimum book value CHF 1.',
          )),
        ],
        if (r.debtorsEnd.isNotEmpty) ...[
          heading(tr('Offene Kundenrechnungen am 31.12.$y', 'Unpaid customer invoices on 31.12.$y')),
          table(
            [tr('Kundschaft', 'Customer'), tr('Rechnung', 'Invoice'), tr('Datum', 'Date'), 'CHF'],
            [
              for (final d in r.debtorsEnd)
                _Row(d.clientName, [d.order.invoiceNumber, Day.short(d.order.invoicedAt!), chf(d.amount)]),
              _Row(tr('Total', 'Total'), ['', '', chf(r.debtorsEndTotal)], total: true),
            ],
            flex: [5, 2, 2, 2],
            leftCols: 3,
          ),
        ],
        if (r.creditorsEnd.isNotEmpty) ...[
          heading(tr('Offene Lieferantenrechnungen am 31.12.$y', 'Unpaid supplier invoices on 31.12.$y')),
          table([tr('Lieferant', 'Supplier'), 'CHF'], [
            for (final c in r.creditorsEnd) _Row(c.name, [chf(c.amount)], note: c.goods ? tr('Waren und Material', 'Goods and materials') : ''),
            _Row(tr('Total', 'Total'), [chf(r.creditorsEndTotal)], total: true),
          ]),
        ],
        for (final s in sections) ...[
          heading(s.title),
          table(
            [tr('Feld', 'Field'), tr('Bezeichnung', 'Description'), 'CHF'],
            [
              for (final fld in s.fields)
                _Row(fld.code, [fld.label, chf(fld.amount)], total: fld.total, note: fld.note),
            ],
            flex: [2, 7, 2],
            leftCols: 2,
          ),
          if (s.note.isNotEmpty) note(s.note),
        ],
      ],
    ),
  );
  return doc.save();
}

String _rate(AssetInfo i) => switch (i.method) {
  DepMethod.immediate => '100 %',
  DepMethod.linear => '${i.rate} % lin.',
  DepMethod.degressive => '${i.rate} %',
};

class _Row {
  _Row(this.label, this.values, {this.total = false, this.indent = 0, this.note = '', this.isHeader = false});

  final String label;
  final List<String> values;
  final bool total;
  final int indent;
  final String note;
  final bool isHeader;
}
