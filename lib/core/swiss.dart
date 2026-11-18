/// Schweizer Besonderheiten: IBAN, QR-IBAN, Kantone.
class Iban {
  Iban._();

  /// Ohne Leerzeichen, in Grossbuchstaben.
  static String compact(String s) => s.replaceAll(RegExp(r'\s'), '').toUpperCase();

  /// In Vierergruppen: „CH93 0076 2011 6238 5295 7“.
  static String pretty(String s) {
    final c = compact(s);
    final b = StringBuffer();
    for (var i = 0; i < c.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(c[i]);
    }
    return b.toString();
  }

  /// Prüfziffer nach ISO 13616 (Modulo 97). Für CH und LI auch die Länge (21).
  static bool isValid(String s) {
    final c = compact(s);
    if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$').hasMatch(c)) return false;
    if ((c.startsWith('CH') || c.startsWith('LI')) && c.length != 21) return false;
    final rearranged = c.substring(4) + c.substring(0, 4);
    var rest = 0;
    for (final ch in rearranged.codeUnits) {
      final v = ch >= 65 ? ch - 55 : ch - 48;
      for (final d in v.toString().codeUnits) {
        rest = (rest * 10 + d - 48) % 97;
      }
    }
    return rest == 1;
  }

  /// QR-IBAN: Die Bank-Nummer (Stellen 5–9) liegt zwischen 30000 und 31999.
  /// Mit einer QR-IBAN braucht der QR-Zahlteil eine QR-Referenz, mit einer
  /// normalen IBAN eine SCOR-Referenz oder gar keine.
  static bool isQrIban(String s) {
    final c = compact(s);
    if (c.length != 21 || !(c.startsWith('CH') || c.startsWith('LI'))) return false;
    final iid = int.tryParse(c.substring(4, 9));
    return iid != null && iid >= 30000 && iid <= 31999;
  }
}

/// Die 26 Kantone (Kürzel, Name).
const cantons = <(String, String)>[
  ('AG', 'Aargau'),
  ('AI', 'Appenzell Innerrhoden'),
  ('AR', 'Appenzell Ausserrhoden'),
  ('BE', 'Bern'),
  ('BL', 'Basel-Landschaft'),
  ('BS', 'Basel-Stadt'),
  ('FR', 'Freiburg'),
  ('GE', 'Genf'),
  ('GL', 'Glarus'),
  ('GR', 'Graubünden'),
  ('JU', 'Jura'),
  ('LU', 'Luzern'),
  ('NE', 'Neuenburg'),
  ('NW', 'Nidwalden'),
  ('OW', 'Obwalden'),
  ('SG', 'St. Gallen'),
  ('SH', 'Schaffhausen'),
  ('SO', 'Solothurn'),
  ('SZ', 'Schwyz'),
  ('TG', 'Thurgau'),
  ('TI', 'Tessin'),
  ('UR', 'Uri'),
  ('VD', 'Waadt'),
  ('VS', 'Wallis'),
  ('ZG', 'Zug'),
  ('ZH', 'Zürich'),
];

/// „Musterweg 12a“ → („Musterweg“, „12a“). Ohne Nummer am Ende: (ganz, '').
(String, String) splitStreet(String s) {
  final t = s.trim();
  final m = RegExp(r'^(.*?)[\s,]+(\d+[a-zA-Z]?(?:[-/]\d+[a-zA-Z]?)?)$').firstMatch(t);
  if (m == null || m.group(1)!.isEmpty) return (t, '');
  return (m.group(1)!.trim(), m.group(2)!);
}
