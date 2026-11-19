import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/error_log.dart';
import '../../app/files.dart';
import '../../app/l10n.dart';
import '../../core/closing/closing_csv.dart';
import '../../core/closing/closing_pdf.dart';
import '../../core/conti_state.dart';

/// Abschluss-PDF erstellen, im Datenordner ablegen und öffnen. Ein
/// vorhandenes PDF wird nie überschrieben (dann „-2“, „-3“ …).
Future<void> createClosingPdf(BuildContext context, int year, {bool open = true}) async {
  final s = ContiScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await buildClosingPdf(r: s.reportOf(year), business: s.business, closing: s.closingOf(year));
    var rel = 'abschluesse/$year/abschluss-$year.pdf';
    for (var n = 2; await File(s.dataPath(rel)).exists(); n++) {
      rel = 'abschluesse/$year/abschluss-$year-$n.pdf';
    }
    await s.store.putFile(rel, bytes);
    final c = s.closingOf(year).copy()..pdfFile = rel;
    await s.saveClosing(c);
    if (open && context.mounted) await openFile(context, s.dataPath(rel));
  } catch (e, st) {
    ErrorLog.record(e, st, where: 'Abschluss-PDF');
    messenger.showSnackBar(SnackBar(content: Text(tr('Das PDF ging nicht: $e', 'The PDF failed: $e'))));
  }
}

/// Alle Buchungen des Jahres als Tabelle (CSV): am Computer speichern, auf
/// dem Handy teilen.
Future<void> exportClosingCsv(BuildContext context, int year) async {
  final s = ContiScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final dir = await Directory.systemTemp.createTemp('conti-csv-');
    final file = File(p.join(dir.path, '${tr('Buchungen', 'Entries')}-$year.csv'));
    await file.writeAsBytes(ClosingCsv.bytes(ClosingCsv.entries(s, year)));
    if (!context.mounted) return;
    if (isDesktop) {
      await saveCopy(context, file.path);
    } else {
      await shareFile(context, file.path, subject: '${tr('Buchungen', 'Entries')} $year');
    }
  } catch (e, st) {
    ErrorLog.record(e, st, where: 'Tabelle exportieren');
    messenger.showSnackBar(SnackBar(content: Text(tr('Das ging nicht: $e', 'That didn’t work: $e'))));
  }
}
