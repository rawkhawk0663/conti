import '../money.dart';
import '../swiss.dart';

/// Eine Adresse im QR-Zahlteil. Seit November 2025 nur noch strukturiert
/// (Strasse, Hausnummer, PLZ und Ort in eigenen Feldern).
class QrAddress {
  const QrAddress({
    required this.name,
    this.street = '',
    this.houseNumber = '',
    required this.zip,
    required this.city,
    this.country = 'CH',
  });

  final String name;
  final String street;
  final String houseNumber;
  final String zip;
  final String city;
  final String country;

  bool get isComplete => name.trim().isNotEmpty && zip.trim().isNotEmpty && city.trim().isNotEmpty && country.trim().length == 2;

  /// Zeilen für die Anzeige im Zahlteil.
  List<String> get lines => [
    name,
    if ('$street $houseNumber'.trim().isNotEmpty) '$street $houseNumber'.trim(),
    '$zip $city'.trim(),
  ];

  List<String> get _fields => [
    'S',
    _clip(name, 70),
    _clip(street, 70),
    _clip(houseNumber, 16),
    _clip(zip, 16),
    _clip(city, 35),
    country.trim().toUpperCase(),
  ];
}

/// Art der Referenz im QR-Zahlteil.
enum QrReferenceType {
  /// QR-Referenz (27 Ziffern), nur mit QR-IBAN.
  qrr,

  /// Creditor Reference (ISO 11648, „RF…“), mit normaler IBAN.
  scor,

  /// Ohne Referenz, dafür eine Mitteilung (normale IBAN).
  non;

  String get code => switch (this) {
    QrReferenceType.qrr => 'QRR',
    QrReferenceType.scor => 'SCOR',
    QrReferenceType.non => 'NON',
  };
}

/// Ein Schweizer QR-Zahlteil (Swiss Payment Standards, Version 2.0 des
/// Datenformats, „SPC 0200“).
class QrBill {
  QrBill({
    required this.iban,
    required this.creditor,
    this.amount,
    this.currency = 'CHF',
    this.debtor,
    this.referenceType = QrReferenceType.non,
    this.reference = '',
    this.message = '',
    this.billInformation = '',
  });

  final String iban;
  final QrAddress creditor;

  /// Betrag in Rappen (null = ohne Betrag, der Zahlende füllt ihn aus).
  final int? amount;
  final String currency;
  final QrAddress? debtor;
  final QrReferenceType referenceType;
  final String reference;

  /// „Zusätzliche Informationen“ (unstrukturierte Mitteilung).
  final String message;
  final String billInformation;

  String get ibanCompact => Iban.compact(iban);

  /// Was fehlt oder nicht stimmt (leer = alles in Ordnung). Die Texte sind
  /// für die Anzeige gedacht.
  List<String> problems({required String Function(String de, String en) tr}) {
    final out = <String>[];
    if (!Iban.isValid(iban) || !(ibanCompact.startsWith('CH') || ibanCompact.startsWith('LI'))) {
      out.add(tr('Die IBAN fehlt oder stimmt nicht (Schweiz oder Liechtenstein).', 'The IBAN is missing or not valid (Switzerland or Liechtenstein).'));
    }
    if (!creditor.isComplete) {
      out.add(tr('Name, PLZ und Ort des Geschäfts fehlen (Mein Geschäft).', 'Business name, postcode and town are missing (My business).'));
    }
    final qr = Iban.isQrIban(iban);
    if (qr && referenceType != QrReferenceType.qrr) {
      out.add(tr('Mit einer QR-IBAN braucht es eine QR-Referenz.', 'A QR-IBAN needs a QR reference.'));
    }
    if (!qr && referenceType == QrReferenceType.qrr) {
      out.add(tr('Eine QR-Referenz geht nur mit einer QR-IBAN.', 'A QR reference needs a QR-IBAN.'));
    }
    if (referenceType == QrReferenceType.qrr && !isValidQrReference(reference)) {
      out.add(tr('Die QR-Referenz stimmt nicht.', 'The QR reference is not valid.'));
    }
    if (amount != null && (amount! < 1 || amount! > 99999999999)) {
      out.add(tr('Der Betrag muss zwischen 0.01 und 999\'999\'999.99 liegen.', 'The amount must be between 0.01 and 999,999,999.99.'));
    }
    if (message.length + billInformation.length > 140) {
      out.add(tr('Die Mitteilung ist zu lang (höchstens 140 Zeichen).', 'The message is too long (140 characters at most).'));
    }
    return out;
  }

  /// Betrag für den QR-Code: „300.00“ (ohne Tausender-Zeichen).
  String get amountText => amount == null ? '' : Money.forInput(amount!);

  /// Inhalt des QR-Codes, Zeilen mit Zeilenumbruch getrennt.
  String payload() {
    final empty7 = List.filled(7, '');
    final lines = <String>[
      'SPC',
      '0200',
      '1',
      ibanCompact,
      ...creditor._fields,
      ...empty7, // endgültiger Zahlungsempfänger (nicht verwendet)
      amountText,
      currency,
      ...(debtor != null && debtor!.isComplete ? debtor!._fields : empty7),
      referenceType.code,
      referenceType == QrReferenceType.non ? '' : reference.replaceAll(' ', ''),
      _clip(message, 140),
      'EPD',
      if (billInformation.isNotEmpty) billInformation,
    ];
    return lines.join('\n');
  }

  /// QR-Referenz zur Anzeige in Fünfergruppen von rechts: „21 00000 00003 …“.
  static String prettyQrReference(String r) {
    final s = r.replaceAll(' ', '');
    final b = StringBuffer();
    final first = s.length % 5;
    if (first > 0) b.write(s.substring(0, first));
    for (var i = first; i < s.length; i += 5) {
      if (b.isNotEmpty) b.write(' ');
      b.write(s.substring(i, i + 5));
    }
    return b.toString();
  }

  /// QR-Referenz aus Ziffern bilden: vorne mit Nullen auf 26 Stellen, dazu
  /// die Prüfziffer (Modulo 10, rekursiv).
  static String qrReferenceFrom(String digits) {
    final d = digits.replaceAll(RegExp(r'\D'), '');
    final body = d.length > 26 ? d.substring(d.length - 26) : d.padLeft(26, '0');
    return '$body${mod10Check(body)}';
  }

  static bool isValidQrReference(String r) {
    final s = r.replaceAll(' ', '');
    if (!RegExp(r'^\d{27}$').hasMatch(s)) return false;
    return mod10Check(s.substring(0, 26)) == int.parse(s[26]);
  }

  /// Prüfziffer Modulo 10, rekursiv (wie bei Einzahlungsscheinen).
  static int mod10Check(String digits) {
    const table = [0, 9, 4, 6, 8, 2, 7, 1, 3, 5];
    var carry = 0;
    for (final c in digits.codeUnits) {
      carry = table[(carry + c - 48) % 10];
    }
    return (10 - carry) % 10;
  }
}

String _clip(String s, int max) {
  final t = s.trim().replaceAll(RegExp(r'[\r\n]+'), ' ');
  return t.length <= max ? t : t.substring(0, max);
}
