import 'dart:convert';

import '../../app/l10n.dart';
import '../conti_state.dart';
import '../dates.dart';
import '../model/closing.dart';
import '../model/entry.dart';

/// Alle Buchungen eines Jahres als Tabelle (CSV) für Excel oder eine
/// Treuhänderin. Strichpunkt als Trennzeichen und BOM, damit Excel in der
/// Schweiz Umlaute und Spalten richtig erkennt. Beträge mit Punkt, ohne
/// Tausender-Zeichen.
class ClosingCsv {
  ClosingCsv._();

  static String _amount(int rappen) {
    final neg = rappen < 0;
    final abs = rappen.abs();
    return '${neg ? '-' : ''}${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  static String _cell(String v) {
    if (v.contains(';') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  static String _line(List<String> cells) => cells.map(_cell).join(';');

  /// Eine Zeile pro Buchung bzw. pro Teil einer aufgeteilten Buchung.
  static String entries(ContiState s, int year) {
    final rows = <String>[
      _line([
        tr('Datum', 'Date'),
        tr('Beleg-Nr.', 'Ref. no.'),
        tr('Text', 'Text'),
        tr('Art', 'Type'),
        tr('Kategorie', 'Category'),
        tr('Im Abschluss', 'In the accounts'),
        tr('Konto', 'Account'),
        tr('Auf Konto', 'To account'),
        tr('Betrag CHF', 'Amount CHF'),
        tr('Kundschaft', 'Customer'),
        tr('Belege', 'Receipts'),
        tr('Bemerkung', 'Note'),
      ]),
    ];
    final list = s.entries.where((e) => e.year == year).toList()..sort((a, b) => a.date.compareTo(b.date));
    for (final e in list) {
      final kind = switch (e.kind) {
        EntryKind.income => tr('Einnahme', 'Income'),
        EntryKind.expense => tr('Ausgabe', 'Expense'),
        EntryKind.transfer => tr('Umbuchung', 'Transfer'),
      };
      final sign = e.kind == EntryKind.expense ? -1 : 1;
      final parts = e.kind == EntryKind.transfer ? {'': e.amount} : e.amountsByCategory;
      final isAsset = e.kind == EntryKind.expense && AssetInfo.fromJson(e.asset) != null;
      parts.forEach((catId, amount) {
        final String group;
        if (e.kind == EntryKind.transfer) {
          group = tr('Umbuchung', 'Transfer');
        } else if (e.excludeFromReports) {
          group = tr('Zählt nicht (privat)', 'Not counted (private)');
        } else if (isAsset) {
          group = tr('Anschaffung (Abschreibung)', 'Acquisition (depreciation)');
        } else {
          group = s.groupOf(catId, income: e.kind == EntryKind.income).label;
        }
        rows.add(
          _line([
            Day.short(e.date),
            e.number,
            e.text,
            kind,
            catId.isEmpty ? '' : s.categoryLabel(catId),
            group,
            s.account(e.accountId)?.name ?? '',
            s.account(e.toAccountId)?.name ?? '',
            _amount(sign * amount),
            s.client(e.clientId)?.displayName ?? '',
            '${e.attachments.length}',
            e.notes,
          ]),
        );
      });
    }
    return rows.join('\r\n');
  }

  /// Als Bytes mit BOM (für eine Datei).
  static List<int> bytes(String csv) => [0xEF, 0xBB, 0xBF, ...utf8.encode(csv)];
}
