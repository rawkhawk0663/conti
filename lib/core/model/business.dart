import 'synced.dart';

/// Angaben zum eigenen Geschäft („Mein Geschäft“): stehen auf Rechnungen und
/// im Jahresabschluss. Nichts davon steht im Programm, jede Person richtet
/// es selbst ein.
class Business implements Synced {
  Business({
    this.ownerName = '',
    this.companyName = '',
    this.street = '',
    this.houseNumber = '',
    this.zip = '',
    this.city = '',
    this.country = 'CH',
    this.email = '',
    this.phone = '',
    this.website = '',
    this.iban = '',
    this.bankName = '',
    this.bic = '',
    this.canton = '',
    this.vatLiable = false,
    this.vatNumber = '',
    this.logoFile = '',
    this.signatureFile = '',
    InvoiceSettings? invoice,
    List<DeadlineRule>? deadlineRules,
    DateTime? updatedAt,
  }) : invoice = invoice ?? InvoiceSettings(),
       deadlineRules = deadlineRules ?? DeadlineRule.defaults(),
       updatedAt = updatedAt ?? DateTime.utc(2000);

  @override
  String get id => 'business';
  @override
  bool get deleted => false;

  String ownerName;
  String companyName;
  String street;
  String houseNumber;
  String zip;
  String city;

  /// Ländercode (ISO), „CH“ oder „LI“.
  String country;
  String email;
  String phone;
  String website;
  String iban;
  String bankName;
  String bic;

  /// Kantonskürzel, z. B. „LU“ (für den Jahresabschluss).
  String canton;
  bool vatLiable;
  String vatNumber;

  /// Logo und Unterschrift als Dateien im Datenordner (z. B. „bilder/logo.png“).
  String logoFile;
  String signatureFile;
  InvoiceSettings invoice;
  List<DeadlineRule> deadlineRules;
  @override
  DateTime updatedAt;

  /// Name für die Anzeige: Firma, sonst Inhaber:in.
  String get displayName => companyName.isNotEmpty ? companyName : ownerName;

  bool get isEmpty => ownerName.isEmpty && companyName.isEmpty;

  void touch() => updatedAt = DateTime.now().toUtc();

  Business copy() => Business.fromJson(toJson());

  @override
  Map<String, dynamic> toJson() => {
    'format': 'conti-geschaeft',
    'version': 1,
    'ownerName': ownerName,
    'companyName': companyName,
    'street': street,
    'houseNumber': houseNumber,
    'zip': zip,
    'city': city,
    'country': country,
    'email': email,
    'phone': phone,
    'website': website,
    'iban': iban,
    'bankName': bankName,
    'bic': bic,
    'canton': canton,
    'vatLiable': vatLiable,
    'vatNumber': vatNumber,
    'logoFile': logoFile,
    'signatureFile': signatureFile,
    'invoice': invoice.toJson(),
    'deadlineRules': [for (final r in deadlineRules) r.toJson()],
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Business.fromJson(Map<String, dynamic> j) => Business(
    ownerName: j.str('ownerName'),
    companyName: j.str('companyName'),
    street: j.str('street'),
    houseNumber: j.str('houseNumber'),
    zip: j.str('zip'),
    city: j.str('city'),
    country: j.str('country', 'CH'),
    email: j.str('email'),
    phone: j.str('phone'),
    website: j.str('website'),
    iban: j.str('iban'),
    bankName: j.str('bankName'),
    bic: j.str('bic'),
    canton: j.str('canton'),
    vatLiable: j.flag('vatLiable'),
    vatNumber: j.str('vatNumber'),
    logoFile: j.str('logoFile'),
    signatureFile: j.str('signatureFile'),
    invoice: j['invoice'] is Map ? InvoiceSettings.fromJson(Map<String, dynamic>.from(j['invoice'] as Map)) : null,
    deadlineRules: j['deadlineRules'] is List ? [for (final r in j.maps('deadlineRules')) DeadlineRule.fromJson(r)] : null,
    updatedAt: j.stamp('updatedAt'),
  );
}

/// Wie Rechnungen aussehen (Paket 4). Texte können Platzhalter enthalten:
/// {rechnungsnummer}, {name}, {firma}, {datum}.
class InvoiceSettings {
  InvoiceSettings({
    this.invoicePrefix = 'RE-',
    this.orderPrefix = 'A-',
    this.paymentTermsDays = 30,
    this.font = 'roboto-slab',
    this.accentColor = '#7A3CF0',
    this.title = 'Rechnung',
    this.dueDateTitle = 'Zahlbar bis',
    this.totalTitle = 'Gesamtbetrag',
    this.footerNote = 'Vielen Dank für den Auftrag.\n{name}',
    this.qrMessage = 'Rechnung {rechnungsnummer}',
    this.qrCreditorName = 'owner',
    this.qrCreditorCustomName = '',
  });

  String invoicePrefix;
  String orderPrefix;
  int paymentTermsDays;
  String font;
  String accentColor;
  String title;
  String dueDateTitle;
  String totalTitle;
  String footerNote;
  String qrMessage;

  /// Wer im QR-Zahlteil als Empfänger steht: „owner“, „company“ oder „custom“.
  String qrCreditorName;
  String qrCreditorCustomName;

  Map<String, dynamic> toJson() => {
    'invoicePrefix': invoicePrefix,
    'orderPrefix': orderPrefix,
    'paymentTermsDays': paymentTermsDays,
    'font': font,
    'accentColor': accentColor,
    'title': title,
    'dueDateTitle': dueDateTitle,
    'totalTitle': totalTitle,
    'footerNote': footerNote,
    'qrMessage': qrMessage,
    'qrCreditorName': qrCreditorName,
    'qrCreditorCustomName': qrCreditorCustomName,
  };

  factory InvoiceSettings.fromJson(Map<String, dynamic> j) {
    final d = InvoiceSettings();
    return InvoiceSettings(
      invoicePrefix: j.str('invoicePrefix', d.invoicePrefix),
      orderPrefix: j.str('orderPrefix', d.orderPrefix),
      paymentTermsDays: j.integer('paymentTermsDays', d.paymentTermsDays),
      font: j.str('font', d.font),
      accentColor: j.str('accentColor', d.accentColor),
      title: j.str('title', d.title),
      dueDateTitle: j.str('dueDateTitle', d.dueDateTitle),
      totalTitle: j.str('totalTitle', d.totalTitle),
      footerNote: j.str('footerNote', d.footerNote),
      qrMessage: j.str('qrMessage', d.qrMessage),
      qrCreditorName: j.str('qrCreditorName', d.qrCreditorName),
      qrCreditorCustomName: j.str('qrCreditorCustomName'),
    );
  }
}

/// Ampel für Fristen bei Aufgaben: ab wie vielen Tagen vor der Frist welche Farbe.
class DeadlineRule {
  DeadlineRule({required this.id, required this.label, required this.days, required this.color});

  final String id;
  String label;
  int days;

  /// Farbe als „#rrggbb“.
  String color;

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'days': days, 'color': color};

  factory DeadlineRule.fromJson(Map<String, dynamic> j) =>
      DeadlineRule(id: j.str('id', newId()), label: j.str('label'), days: j.integer('days'), color: j.str('color', '#FFC83D'));

  static List<DeadlineRule> defaults() => [
    DeadlineRule(id: 'yellow', label: 'Gelb', days: 7, color: '#FFC83D'),
    DeadlineRule(id: 'orange', label: 'Orange', days: 4, color: '#FF8A4C'),
    DeadlineRule(id: 'red', label: 'Rot', days: 2, color: '#FF5A6E'),
  ];
}
