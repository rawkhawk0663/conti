/// Geldbeträge rechnet Conti immer in ganzen Rappen (`int`). So gibt es keine
/// Rundungsfehler, wie sie bei Kommazahlen entstehen (0.1 + 0.2 ≠ 0.3).
class Money {
  Money._();

  /// Franken (z. B. aus einer alten Datei: 38.2) → Rappen (3820).
  static int fromFrancs(num chf) => (chf * 100).round();

  /// Eingabe lesen: „1'234.50“, „1’234,5“, „12“, „-3.05“, „CHF 40.-“.
  /// Gibt null zurück, wenn es keine Zahl ist.
  static int? parse(String input) {
    var s = input.trim().replaceAll(RegExp(r'^(CHF|Fr\.?)\s*', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r"[\s'’`]"), '');
    if (s.endsWith('.-') || s.endsWith(',-') || s.endsWith('.–')) s = s.substring(0, s.length - 2);
    if (s.isEmpty) return null;
    var negative = false;
    if (s.startsWith('-') || s.startsWith('−')) {
      negative = true;
      s = s.substring(1);
    }
    s = s.replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{0,2})?$|^\.\d{1,2}$').hasMatch(s)) return null;
    final parts = s.split('.');
    final francs = parts[0].isEmpty ? 0 : int.parse(parts[0]);
    var cents = 0;
    if (parts.length > 1 && parts[1].isNotEmpty) {
      cents = int.parse(parts[1].padRight(2, '0'));
    }
    final v = francs * 100 + cents;
    return negative ? -v : v;
  }

  /// Rappen → „1'234.50“ (Schweizer Schreibweise). [sign]: „+“ vor positiven
  /// Beträgen. Negative Beträge bekommen immer ein echtes Minuszeichen.
  static String format(int rappen, {bool sign = false, bool currency = false}) {
    final neg = rappen < 0;
    final abs = rappen.abs();
    final francs = abs ~/ 100;
    final cents = (abs % 100).toString().padLeft(2, '0');
    final digits = francs.toString();
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write("'");
      b.write(digits[i]);
    }
    final prefix = neg ? '−' : (sign && rappen > 0 ? '+' : '');
    return '${currency ? 'CHF ' : ''}$prefix$b.$cents';
  }

  /// Für ein Eingabefeld: „1234.50“ (ohne Tausender-Zeichen, ohne Vorzeichen).
  static String forInput(int rappen) {
    final abs = rappen.abs();
    return '${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  /// Auf 5 Rappen runden (für Bargeld).
  static int roundTo5(int rappen) => (rappen / 5).round() * 5;
}
