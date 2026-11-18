import '../app/l10n.dart';

/// Datum ohne Uhrzeit, gespeichert als „2026-11-18“.
class Day {
  Day._();

  static DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String toKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// „2026-11-18“ (auch mit Uhrzeit dahinter) → Datum. Ungültig → null.
  static DateTime? parse(String? s) {
    if (s == null || s.length < 10) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (m == null) return null;
    return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  /// „18.11.2026“
  static String short(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// „18.11.“
  static String dayMonth(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

  /// „18. November 2026“
  static String long(DateTime d) => '${d.day}. ${monthName(d.month)} ${d.year}';

  static String monthName(int m) => (L10n.isEnglish ? _monthsEn : _monthsDe)[m - 1];

  static String monthShort(int m) => monthName(m).substring(0, 3);

  static const _monthsDe = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
  ];
  static const _monthsEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// Zeitstempel für „zuletzt geändert“ (UTC, damit Geräte in anderen
  /// Zeitzonen richtig vergleichen).
  static String stamp([DateTime? t]) => (t ?? DateTime.now()).toUtc().toIso8601String();

  static DateTime parseStamp(String? s) => DateTime.tryParse(s ?? '')?.toUtc() ?? DateTime.utc(2000);
}
