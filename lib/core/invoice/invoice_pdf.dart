import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/l10n.dart';
import '../dates.dart';
import '../model/business.dart';
import '../model/crm.dart';
import '../money.dart';
import '../swiss.dart';
import 'swiss_qr.dart';

/// Feste Schriftschnitte für Rechnungen (aus `assets/fonts/pdf`).
class PdfFonts {
  PdfFonts({required this.slabLight, required this.slab, required this.slabBold, required this.sans, required this.sansBold});

  final pw.Font slabLight, slab, slabBold, sans, sansBold;

  static PdfFonts? _cache;

  static Future<PdfFonts> load() async {
    if (_cache != null) return _cache!;
    Future<pw.Font> f(String n) async => pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/$n.ttf'));
    return _cache = PdfFonts(
      slabLight: await f('RobotoSlab-Light'),
      slab: await f('RobotoSlab-Regular'),
      slabBold: await f('RobotoSlab-Bold'),
      sans: await f('Arimo-Regular'),
      sansBold: await f('Arimo-Bold'),
    );
  }
}

/// Alles, was auf eine Rechnung kommt.
class InvoiceData {
  InvoiceData({
    required this.business,
    required this.order,
    required this.number,
    required this.date,
    required this.due,
    this.client,
    this.logo,
    this.signature,
    this.reminderOf,
    this.withQr = true,
  });

  final Business business;
  final Order order;
  final Client? client;
  final String number;
  final DateTime date;
  final DateTime due;

  /// Logo und Unterschrift als Dateien (SVG, PNG oder JPG).
  final File? logo;
  final File? signature;

  /// Zahlungserinnerung: Datum der ursprünglichen Rechnung.
  final DateTime? reminderOf;
  final bool withQr;

  bool get isReminder => reminderOf != null;

  /// Platzhalter in Texten ersetzen.
  String fill(String text) {
    final b = business;
    return text
        .replaceAll('{rechnungsnummer}', number)
        .replaceAll('{name}', b.ownerName.isNotEmpty ? b.ownerName : b.displayName)
        .replaceAll('{firma}', b.displayName)
        .replaceAll('{datum}', Day.long(date))
        .replaceAll('{faellig}', Day.long(due))
        .replaceAll('{fällig}', Day.long(due))
        .replaceAll('{kunde}', client?.displayName ?? '')
        .replaceAll('{auftrag}', order.number);
  }

  /// Wer im QR-Zahlteil als Empfänger steht.
  String get creditorName {
    final i = business.invoice;
    return switch (i.qrCreditorName) {
      'company' when business.companyName.isNotEmpty => business.companyName,
      'custom' when i.qrCreditorCustomName.trim().isNotEmpty => i.qrCreditorCustomName.trim(),
      _ => business.ownerName.isNotEmpty ? business.ownerName : business.displayName,
    };
  }

  QrBill get qrBill {
    final b = business;
    final c = client;
    final qrIban = Iban.isQrIban(b.iban);
    return QrBill(
      iban: b.iban,
      creditor: QrAddress(
        name: creditorName,
        street: b.street,
        houseNumber: b.houseNumber,
        zip: b.zip,
        city: b.city,
        country: b.country.isEmpty ? 'CH' : b.country,
      ),
      amount: order.total > 0 ? order.total : null,
      debtor: c == null
          ? null
          : QrAddress(
              name: c.company.isNotEmpty ? c.company : c.personName,
              street: c.street,
              houseNumber: c.houseNumber,
              zip: c.zip,
              city: c.city,
              country: c.country.isEmpty ? 'CH' : c.country,
            ),
      referenceType: qrIban ? QrReferenceType.qrr : QrReferenceType.non,
      reference: qrIban ? QrBill.qrReferenceFrom(number) : '',
      message: fill(b.invoice.qrMessage),
    );
  }
}

const _mm = PdfPageFormat.mm;
const _ink = PdfColor.fromInt(0xFF2A2A2E);
const _grey = PdfColor.fromInt(0xFF6E6E76);
const _rule = PdfColor.fromInt(0xFF8A8A90);

Future<pw.Widget?> _image(File? f, {required double height, double? maxWidth}) async {
  if (f == null || !await f.exists()) return null;
  try {
    if (f.path.toLowerCase().endsWith('.svg')) {
      return pw.SizedBox(
        height: height,
        width: maxWidth,
        child: pw.SvgImage(svg: await f.readAsString(), fit: pw.BoxFit.contain, alignment: pw.Alignment.centerLeft),
      );
    }
    return pw.SizedBox(
      height: height,
      width: maxWidth,
      child: pw.Image(pw.MemoryImage(await f.readAsBytes()), fit: pw.BoxFit.contain, alignment: pw.Alignment.centerLeft),
    );
  } catch (_) {
    return null;
  }
}

/// Rechnung (oder Zahlungserinnerung) als PDF, A4, im Aufbau: Logo oben
/// links, Absender und Kontakt rechts, grosser Titel, Empfänger, Angaben
/// rechts, Tabelle Beschreibung/Tarif/Anzahl/Preis, Dankeszeile mit
/// Unterschrift, Gesamtbetrag, unten der QR-Zahlteil mit Empfangsschein.
Future<Uint8List> buildInvoicePdf(InvoiceData d, {PdfFonts? fonts}) async {
  final f = fonts ?? await PdfFonts.load();
  final b = d.business;
  final inv = b.invoice;
  final sansBody = inv.font == 'sans';
  final light = sansBody ? f.sans : f.slabLight;
  final regular = sansBody ? f.sans : f.slab;
  final bold = sansBody ? f.sansBold : f.slabBold;

  pw.TextStyle st(pw.Font font, double size, {PdfColor color = _ink}) =>
      pw.TextStyle(font: font, fontSize: size, color: color, lineSpacing: 1.5);

  final logo = await _image(d.logo, height: 13 * _mm, maxWidth: 75 * _mm);
  final signature = await _image(d.signature, height: 12 * _mm, maxWidth: 45 * _mm);

  // ---------- Kopf ----------
  final sender = [
    b.companyName.isNotEmpty && b.ownerName.isNotEmpty ? b.ownerName : b.displayName,
    [b.street, b.houseNumber].where((s) => s.isNotEmpty).join(' '),
    [b.zip, b.city].where((s) => s.isNotEmpty).join(' '),
  ].where((s) => s.isNotEmpty).toList();
  final contact = [b.website, b.email, b.phone].where((s) => s.isNotEmpty).toList();
  pw.Widget column(List<String> lines) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [for (final l in lines) pw.Text(l, style: st(light, 8.5, color: _grey))],
  );
  final header = pw.Column(
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: logo ??
                pw.Text(b.displayName, style: st(bold, 16)),
          ),
          column(sender),
          if (contact.isNotEmpty) ...[pw.SizedBox(width: 12 * _mm), column(contact)],
        ],
      ),
      pw.SizedBox(height: 8 * _mm),
      pw.Container(height: 0.6, color: _rule),
    ],
  );

  // ---------- Titel, Empfänger, Angaben ----------
  final c = d.client;
  final recipient = c == null
      ? <String>[]
      : [
          if (c.company.isNotEmpty && c.personName.isNotEmpty) c.personName,
          [c.street, c.houseNumber].where((s) => s.isNotEmpty).join(' '),
          [c.zip, c.city].where((s) => s.isNotEmpty).join(' '),
          if (c.country.isNotEmpty && c.country != 'CH') c.country,
          if (c.country == 'CH' && (c.city.isNotEmpty)) tr('Schweiz', 'Switzerland'),
        ].where((s) => s.isNotEmpty).toList();
  pw.Widget meta(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3 * _mm),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [pw.Text(label, style: st(light, 8.5, color: _grey)), pw.Text(value, style: st(bold, 10.5))],
    ),
  );
  final title = d.isReminder ? tr('Zahlungserinnerung', 'Payment reminder') : (inv.title.isEmpty ? tr('Rechnung', 'Invoice') : inv.title);
  final titleBlock = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: st(regular, 30)),
            pw.SizedBox(height: 14 * _mm),
            if (c != null) pw.Text(c.company.isNotEmpty ? c.company : c.personName, style: st(bold, 11.5)),
            for (final l in recipient) pw.Text(l, style: st(light, 9.5, color: _grey)),
          ],
        ),
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          meta(tr('Rechnungs-Nr.', 'Invoice no.'), d.number),
          if (d.order.number.isNotEmpty) meta(tr('Auftrags-Nr.', 'Order no.'), d.order.number),
          if (d.isReminder) meta(tr('Rechnung vom', 'Invoice dated'), Day.long(d.reminderOf!)),
          meta(tr('Datum', 'Date'), Day.long(d.date)),
          meta(inv.dueDateTitle.isEmpty ? tr('Zahlbar bis', 'Payable by') : inv.dueDateTitle, Day.long(d.due)),
        ],
      ),
    ],
  );

  // ---------- Positionen ----------
  String qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');
  final rows = <pw.Widget>[
    pw.Row(
      children: [
        pw.Expanded(flex: 5, child: pw.Text(tr('Beschreibung', 'Description'), style: st(regular, 11))),
        pw.Expanded(flex: 2, child: pw.Text(tr('Tarif', 'Rate'), textAlign: pw.TextAlign.right, style: st(regular, 11))),
        pw.Expanded(flex: 2, child: pw.Text(tr('Anzahl', 'Qty'), textAlign: pw.TextAlign.right, style: st(regular, 11))),
        pw.Expanded(flex: 2, child: pw.Text(tr('Preis', 'Price'), textAlign: pw.TextAlign.right, style: st(regular, 11))),
      ],
    ),
    pw.SizedBox(height: 2.5 * _mm),
    pw.Container(height: 0.9, color: _ink),
    pw.SizedBox(height: 3 * _mm),
    for (final i in d.order.items)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3 * _mm),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(i.name, style: st(bold, 10.5)),
                  if (i.description.isNotEmpty) pw.Text(i.description, style: st(light, 8.5, color: _grey)),
                ],
              ),
            ),
            pw.Expanded(flex: 2, child: pw.Text('CHF ${Money.format(i.unitPrice)}', textAlign: pw.TextAlign.right, style: st(bold, 10.5))),
            pw.Expanded(flex: 2, child: pw.Text(qty(i.quantity), textAlign: pw.TextAlign.right, style: st(regular, 10.5))),
            pw.Expanded(flex: 2, child: pw.Text('CHF ${Money.format(i.total)}', textAlign: pw.TextAlign.right, style: st(bold, 10.5))),
          ],
        ),
      ),
    pw.Container(height: 0.9, color: _ink),
  ];

  final note = d.fill(inv.footerNote);
  final reminderText = d.isReminder
      ? tr(
          'Die Rechnung vom ${Day.long(d.reminderOf!)} ist noch nicht bezahlt. Vielen Dank für die Zahlung bis ${Day.long(d.due)}.',
          'The invoice dated ${Day.long(d.reminderOf!)} has not been paid yet. Thank you for paying by ${Day.long(d.due)}.',
        )
      : null;
  final footer = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (note.trim().isNotEmpty) pw.Text(note, style: st(light, 10.5, color: _grey)),
            if (signature != null) ...[pw.SizedBox(height: 3 * _mm), signature],
          ],
        ),
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(inv.totalTitle.isEmpty ? tr('Gesamtbetrag', 'Total') : inv.totalTitle, style: st(light, 8.5, color: _grey)),
          pw.Text('CHF ${Money.format(d.order.total)}', style: st(bold, 13.5)),
        ],
      ),
    ],
  );

  final content = <pw.Widget>[
    header,
    pw.SizedBox(height: 14 * _mm),
    titleBlock,
    pw.SizedBox(height: 12 * _mm),
    if (reminderText != null) ...[pw.Text(reminderText, style: st(regular, 10.5)), pw.SizedBox(height: 8 * _mm)],
    ...rows,
    pw.SizedBox(height: 6 * _mm),
    footer,
  ];

  final doc = pw.Document(title: '$title ${d.number}', author: b.displayName, creator: 'Conti');
  const side = 24 * _mm;
  final slip = d.withQr ? _paymentSlip(d.qrBill, f) : null;
  // Passt alles auf eine Seite über den Zahlteil? Sonst Zahlteil auf eine eigene Seite.
  final fitsOnePage = d.order.items.length + (reminderText == null ? 0 : 1) + d.order.items.where((i) => i.description.isNotEmpty).length ~/ 2 <= 4;

  if (slip == null || fitsOnePage) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned(
              left: side,
              right: side,
              top: 20 * _mm,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: content),
            ),
            if (slip != null) ...[
              pw.Positioned(left: 0, right: 0, bottom: 105 * _mm + 1.5 * _mm, child: _separateHint(f)),
              pw.Positioned(left: 0, bottom: 0, child: slip),
            ],
          ],
        ),
      ),
    );
  } else {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(side, 20 * _mm, side, 20 * _mm),
        build: (_) => content,
      ),
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned(
              left: side,
              top: 20 * _mm,
              child: pw.Text('$title ${d.number}', style: st(regular, 14)),
            ),
            pw.Positioned(left: 0, right: 0, bottom: 105 * _mm + 1.5 * _mm, child: _separateHint(f)),
            pw.Positioned(left: 0, bottom: 0, child: slip),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

pw.Widget _separateHint(PdfFonts f) => pw.Center(
  child: pw.Text(
    tr('Vor der Einzahlung abzutrennen', 'Separate before paying in'),
    style: pw.TextStyle(font: f.sans, fontSize: 7, color: _grey),
  ),
);

/// Gestrichelte Linie (Trennlinie des Zahlteils).
pw.Widget _dashed({required bool vertical, required double length}) => pw.SizedBox(
  width: vertical ? 1 : length,
  height: vertical ? length : 1,
  child: pw.CustomPaint(
    painter: (canvas, size) {
      canvas
        ..setStrokeColor(PdfColors.black)
        ..setLineWidth(0.5)
        ..setLineDashPattern([3, 2]);
      if (vertical) {
        canvas
          ..moveTo(0.5, 0)
          ..lineTo(0.5, size.y);
      } else {
        canvas
          ..moveTo(0, 0.5)
          ..lineTo(size.x, 0.5);
      }
      canvas
        ..strokePath()
        ..setLineDashPattern();
    },
  ),
);

/// Eckmarken für ein leeres Feld (Betrag oder „Zahlbar durch“ zum Ausfüllen).
pw.Widget _cornerBox(double w, double h) => pw.SizedBox(
  width: w,
  height: h,
  child: pw.CustomPaint(
    painter: (canvas, size) {
      const l = 3 * _mm;
      canvas
        ..setStrokeColor(PdfColors.black)
        ..setLineWidth(0.75);
      final x = size.x, y = size.y;
      canvas
        ..moveTo(0, l)
        ..lineTo(0, 0)
        ..lineTo(l, 0)
        ..moveTo(x - l, 0)
        ..lineTo(x, 0)
        ..lineTo(x, l)
        ..moveTo(x, y - l)
        ..lineTo(x, y)
        ..lineTo(x - l, y)
        ..moveTo(l, y)
        ..lineTo(0, y)
        ..lineTo(0, y - l)
        ..strokePath();
    },
  ),
);

/// Der QR-Zahlteil mit Empfangsschein (210 × 105 mm), nach den Vorgaben
/// der Schweizer Banken: Empfangsschein 62 mm breit, Zahlteil 148 mm, QR-Code
/// 46 × 46 mm mit Schweizer Kreuz, Schrift ohne Serifen.
pw.Widget _paymentSlip(QrBill q, PdfFonts f) {
  pw.TextStyle h(double s) => pw.TextStyle(font: f.sansBold, fontSize: s, color: PdfColors.black);
  pw.TextStyle v(double s) => pw.TextStyle(font: f.sans, fontSize: s, color: PdfColors.black, lineSpacing: 1);

  List<pw.Widget> block(String heading, List<String> lines, double hs, double vs) => [
    pw.Text(heading, style: h(hs)),
    for (final l in lines) pw.Text(l, style: v(vs)),
    pw.SizedBox(height: vs * 0.9),
  ];

  final account = [Iban.pretty(q.iban), ...q.creditor.lines];
  final ref = q.referenceType == QrReferenceType.qrr
      ? QrBill.prettyQrReference(q.reference)
      : (q.referenceType == QrReferenceType.scor ? q.reference : '');
  final hasDebtor = q.debtor != null && q.debtor!.isComplete;

  // Empfangsschein
  final receipt = pw.SizedBox(
    width: 52 * _mm,
    height: 95 * _mm,
    child: pw.Stack(
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(tr('Empfangsschein', 'Receipt'), style: h(11)),
            pw.SizedBox(height: 4 * _mm),
            ...block(tr('Konto / Zahlbar an', 'Account / Payable to'), account, 6, 8),
            if (ref.isNotEmpty) ...block(tr('Referenz', 'Reference'), [ref], 6, 8),
            if (hasDebtor)
              ...block(tr('Zahlbar durch', 'Payable by'), q.debtor!.lines, 6, 8)
            else ...[
              pw.Text(tr('Zahlbar durch (Name/Adresse)', 'Payable by (name/address)'), style: h(6)),
              pw.SizedBox(height: 1 * _mm),
              _cornerBox(52 * _mm, 20 * _mm),
            ],
          ],
        ),
        pw.Positioned(
          left: 0,
          top: 63 * _mm,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 12 * _mm,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [pw.Text(tr('Währung', 'Currency'), style: h(6)), pw.Text(q.currency, style: v(8))],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(tr('Betrag', 'Amount'), style: h(6)),
                  if (q.amount != null) pw.Text(Money.format(q.amount!).replaceAll("'", ' '), style: v(8)) else _cornerBox(30 * _mm, 10 * _mm),
                ],
              ),
            ],
          ),
        ),
        pw.Positioned(right: 0, top: 77 * _mm, child: pw.Text(tr('Annahmestelle', 'Acceptance point'), style: h(6))),
      ],
    ),
  );

  // Zahlteil
  final qr = pw.SizedBox(
    width: 46 * _mm,
    height: 46 * _mm,
    child: pw.Stack(
      alignment: pw.Alignment.center,
      children: [
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
          data: q.payload(),
          width: 46 * _mm,
          height: 46 * _mm,
          drawText: false,
        ),
        // Schweizer Kreuz, 7 × 7 mm mit weissem Rand
        pw.Container(
          width: 7 * _mm,
          height: 7 * _mm,
          color: PdfColors.white,
          alignment: pw.Alignment.center,
          child: pw.Container(
            width: 6 * _mm,
            height: 6 * _mm,
            color: PdfColors.black,
            child: pw.Stack(
              alignment: pw.Alignment.center,
              children: [
                pw.Container(width: 1.2 * _mm, height: 3.9 * _mm, color: PdfColors.white),
                pw.Container(width: 3.9 * _mm, height: 1.2 * _mm, color: PdfColors.white),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  final payment = pw.SizedBox(
    width: 138 * _mm,
    height: 95 * _mm,
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 51 * _mm,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(tr('Zahlteil', 'Payment part'), style: h(11)),
              pw.SizedBox(height: 5 * _mm),
              qr,
              pw.SizedBox(height: 5 * _mm),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 14 * _mm,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [pw.Text(tr('Währung', 'Currency'), style: h(8)), pw.Text(q.currency, style: v(10))],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(tr('Betrag', 'Amount'), style: h(8)),
                      if (q.amount != null) pw.Text(Money.format(q.amount!).replaceAll("'", ' '), style: v(10)) else _cornerBox(40 * _mm, 15 * _mm),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 5 * _mm),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              ...block(tr('Konto / Zahlbar an', 'Account / Payable to'), account, 8, 10),
              if (ref.isNotEmpty) ...block(tr('Referenz', 'Reference'), [ref], 8, 10),
              if (q.message.isNotEmpty) ...block(tr('Zusätzliche Informationen', 'Additional information'), [q.message], 8, 10),
              if (hasDebtor)
                ...block(tr('Zahlbar durch', 'Payable by'), q.debtor!.lines, 8, 10)
              else ...[
                pw.Text(tr('Zahlbar durch (Name/Adresse)', 'Payable by (name/address)'), style: h(8)),
                pw.SizedBox(height: 1 * _mm),
                _cornerBox(65 * _mm, 25 * _mm),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  return pw.SizedBox(
    width: 210 * _mm,
    height: 105 * _mm,
    child: pw.Stack(
      children: [
        pw.Positioned(left: 0, top: 0, child: _dashed(vertical: false, length: 210 * _mm)),
        pw.Positioned(left: 62 * _mm, top: 0, child: _dashed(vertical: true, length: 105 * _mm)),
        pw.Positioned(left: 5 * _mm, top: 5 * _mm, child: receipt),
        pw.Positioned(left: 67 * _mm, top: 5 * _mm, child: payment),
      ],
    ),
  );
}
