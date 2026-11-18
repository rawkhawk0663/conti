import '../dates.dart';
import 'synced.dart';

/// Art einer Buchung.
enum EntryKind {
  income,
  expense,

  /// Geld von einem eigenen Konto auf ein anderes (z. B. Bargeld auf die
  /// Bank). Zählt weder als Einnahme noch als Ausgabe.
  transfer;

  static EntryKind parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => EntryKind.expense);
}

/// Ein Beleg (Foto oder PDF), der an einer Buchung hängt. Die Datei liegt im
/// Datenordner unter [file] (relativ, z. B. `belege/2026/<id>.jpg`).
class Attachment {
  Attachment({
    required this.id,
    required this.file,
    required this.name,
    this.kind = 'receipt',
    this.size = 0,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now().toUtc();

  final String id;
  final String file;

  /// Ursprünglicher Dateiname (für die Anzeige).
  final String name;

  /// „receipt“ (Quittung), „invoice“ (Rechnung) oder „other“.
  final String kind;
  final int size;
  final DateTime addedAt;

  bool get isImage => RegExp(r'\.(jpe?g|png|gif|webp|heic|bmp)$', caseSensitive: false).hasMatch(file);
  bool get isPdf => file.toLowerCase().endsWith('.pdf');

  Map<String, dynamic> toJson() => {
    'id': id,
    'file': file,
    'name': name,
    'kind': kind,
    'size': size,
    'addedAt': Day.stamp(addedAt),
  };

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
    id: j.str('id', newId()),
    file: j.str('file'),
    name: j.str('name'),
    kind: j.str('kind', 'receipt'),
    size: j.integer('size'),
    addedAt: j.stamp('addedAt'),
  );
}

/// Teil einer aufgeteilten Buchung (eine Quittung, mehrere Kategorien).
class EntrySplit {
  EntrySplit({required this.categoryId, required this.amount, this.text = ''});

  String categoryId;
  int amount;
  String text;

  Map<String, dynamic> toJson() => {'categoryId': categoryId, 'amount': amount, if (text.isNotEmpty) 'text': text};

  factory EntrySplit.fromJson(Map<String, dynamic> j) =>
      EntrySplit(categoryId: j.str('categoryId'), amount: j.integer('amount'), text: j.str('text'));
}

/// Eine Buchung im Kassenbuch.
class Entry implements Synced {
  Entry({
    required this.id,
    required this.date,
    required this.kind,
    required this.amount,
    this.text = '',
    this.accountId = '',
    this.toAccountId,
    this.categoryId,
    List<EntrySplit>? splits,
    this.number = '',
    this.clientId,
    this.orderId,
    this.vat = 'none',
    List<Attachment>? attachments,
    this.notes = '',
    this.excludeFromReports = false,
    this.asset,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deleted = false,
  }) : splits = splits ?? [],
       attachments = attachments ?? [],
       createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  @override
  final String id;
  DateTime date;
  EntryKind kind;

  /// Betrag in Rappen, immer positiv. Ob Einnahme oder Ausgabe, sagt [kind].
  int amount;
  String text;
  String accountId;

  /// Nur bei Umbuchungen: Zielkonto.
  String? toAccountId;

  /// Kategorie (bei aufgeteilten Buchungen leer, dann gelten [splits]).
  String? categoryId;
  List<EntrySplit> splits;

  /// Belegnummer (frei, z. B. aus der alten App).
  String number;
  String? clientId;
  String? orderId;

  /// MWST-Satz (ab Paket 6). „none“ = keine MWST.
  String vat;
  List<Attachment> attachments;
  String notes;

  /// Zählt nicht in Auswertungen (z. B. Privates, nur zur Übersicht).
  bool excludeFromReports;

  /// Angaben zur Abschreibung, falls es eine Anschaffung ist (Paket 5).
  Map<String, dynamic>? asset;
  final DateTime createdAt;
  @override
  DateTime updatedAt;
  @override
  bool deleted;

  int get year => date.year;

  /// Betrag mit Vorzeichen aus Sicht des Gewinns (Einnahme +, Ausgabe −,
  /// Umbuchung 0).
  int get signedAmount => switch (kind) {
    EntryKind.income => amount,
    EntryKind.expense => -amount,
    EntryKind.transfer => 0,
  };

  /// Beträge pro Kategorie (für Auswertungen; aufgeteilte Buchungen zählen
  /// pro Teil).
  Map<String, int> get amountsByCategory {
    if (splits.isNotEmpty) {
      final m = <String, int>{};
      for (final s in splits) {
        m[s.categoryId] = (m[s.categoryId] ?? 0) + s.amount;
      }
      return m;
    }
    return {categoryId ?? '': amount};
  }

  void touch() => updatedAt = DateTime.now().toUtc();

  Entry copy() => Entry.fromJson(toJson());

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'date': Day.toKey(date),
    'kind': kind.name,
    'amount': amount,
    'text': text,
    'accountId': accountId,
    if (toAccountId != null) 'toAccountId': toAccountId,
    if (categoryId != null) 'categoryId': categoryId,
    if (splits.isNotEmpty) 'splits': [for (final s in splits) s.toJson()],
    if (number.isNotEmpty) 'number': number,
    if (clientId != null) 'clientId': clientId,
    if (orderId != null) 'orderId': orderId,
    'vat': vat,
    if (attachments.isNotEmpty) 'attachments': [for (final a in attachments) a.toJson()],
    if (notes.isNotEmpty) 'notes': notes,
    if (excludeFromReports) 'excludeFromReports': true,
    if (asset != null) 'asset': asset,
    'createdAt': Day.stamp(createdAt),
    'updatedAt': Day.stamp(updatedAt),
    if (deleted) 'deleted': true,
  };

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
    id: j.str('id', newId()),
    date: Day.parse(j.strOrNull('date')) ?? Day.today(),
    kind: EntryKind.parse(j.strOrNull('kind')),
    amount: j.integer('amount').abs(),
    text: j.str('text'),
    accountId: j.str('accountId'),
    toAccountId: j.strOrNull('toAccountId'),
    categoryId: j.strOrNull('categoryId'),
    splits: [for (final s in j.maps('splits')) EntrySplit.fromJson(s)],
    number: j.str('number'),
    clientId: j.strOrNull('clientId'),
    orderId: j.strOrNull('orderId'),
    vat: j.str('vat', 'none'),
    attachments: [for (final a in j.maps('attachments')) Attachment.fromJson(a)],
    notes: j.str('notes'),
    excludeFromReports: j.flag('excludeFromReports'),
    asset: j['asset'] is Map ? Map<String, dynamic>.from(j['asset'] as Map) : null,
    createdAt: j.stamp('createdAt'),
    updatedAt: j.stamp('updatedAt'),
    deleted: j.flag('deleted'),
  );
}
