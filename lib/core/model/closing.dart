import '../../app/l10n.dart';
import '../dates.dart';
import 'synced.dart';

/// Wohin eine Kategorie im Jahresabschluss gehört. Die Gruppen folgen dem
/// Aufbau, den alle Kantone für Selbständige ohne kaufmännische Buchhaltung
/// verlangen (Einnahmen, Ausgaben, Privatbezüge und -einlagen).
enum ClosingGroup {
  revenue(true),
  otherIncome(true),
  privateIn(true),
  goods(false),
  personnel(false),
  rent(false),
  vehicle(false),
  other(false),
  privateOut(false);

  const ClosingGroup(this.income);

  /// Gehört zu den Einnahmen (sonst Ausgaben).
  final bool income;

  bool get isPrivate => this == privateIn || this == privateOut;

  static ClosingGroup? parse(String? s) => s == null ? null : values.where((v) => v.name == s).firstOrNull;

  static List<ClosingGroup> forIncome(bool income) => values.where((v) => v.income == income).toList();

  String get label => switch (this) {
    ClosingGroup.revenue => tr('Einnahmen aus Arbeit und Verkauf', 'Income from work and sales'),
    ClosingGroup.otherIncome => tr('Andere Geschäftserträge', 'Other business income'),
    ClosingGroup.privateIn => tr('Privateinlage (kein Ertrag)', 'Private deposit (not income)'),
    ClosingGroup.goods => tr('Waren und Material', 'Goods and materials'),
    ClosingGroup.personnel => tr('Löhne und Sozialleistungen', 'Wages and social costs'),
    ClosingGroup.rent => tr('Miete Geschäftsräume', 'Rent for business premises'),
    ClosingGroup.vehicle => tr('Fahrzeugkosten', 'Vehicle costs'),
    ClosingGroup.other => tr('Andere Geschäftskosten', 'Other business costs'),
    ClosingGroup.privateOut => tr('Privatbezug (keine Ausgabe)', 'Private withdrawal (not an expense)'),
  };
}

/// Art einer Anschaffung. Die Sätze sind die Normalsätze der
/// Eidgenössischen Steuerverwaltung (Merkblatt A 1995) in Prozent des
/// Buchwerts. Die Kantone übernehmen sie.
enum AssetType {
  furniture(25),
  machine(30),
  it(40),
  vehicle(40),
  tools(45),
  other(25);

  const AssetType(this.rate);

  /// Satz in Prozent vom Buchwert (degressiv). Linear: die Hälfte davon.
  final int rate;

  static AssetType parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => AssetType.other);

  String get label => switch (this) {
    AssetType.furniture => tr('Mobiliar und Einrichtungen', 'Furniture and fittings'),
    AssetType.machine => tr('Instrumente, Maschinen, Geräte', 'Instruments, machines, devices'),
    AssetType.it => tr('Computer und Software', 'Computers and software'),
    AssetType.vehicle => tr('Fahrzeuge', 'Vehicles'),
    AssetType.tools => tr('Werkzeuge', 'Tools'),
    AssetType.other => tr('Anderes', 'Other'),
  };
}

/// Wie abgeschrieben wird.
enum DepMethod {
  /// Jedes Jahr ein fester Prozentsatz vom Restwert (Normalfall).
  degressive,

  /// Jedes Jahr derselbe Betrag (Prozent vom Kaufpreis).
  linear,

  /// Alles im Jahr der Anschaffung (Sofortabschreibung).
  immediate;

  static DepMethod parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => DepMethod.degressive);

  String get label => switch (this) {
    DepMethod.degressive => tr('Vom Restwert (degressiv)', 'Of remaining value (declining)'),
    DepMethod.linear => tr('Gleichmässig (linear)', 'Even amounts (straight-line)'),
    DepMethod.immediate => tr('Alles im ersten Jahr', 'All in the first year'),
  };
}

/// Angaben zur Abschreibung. Hängt an einer Buchung (`Entry.asset`) oder an
/// einer Anlage ohne Buchung ([Asset]).
class AssetInfo {
  AssetInfo({this.name = '', this.type = AssetType.machine, this.method = DepMethod.degressive, int? rate, this.soldYear})
    : rate = rate ?? (method == DepMethod.linear ? type.rate ~/ 2 : type.rate);

  String name;
  AssetType type;
  DepMethod method;

  /// Prozent pro Jahr (degressiv: vom Restwert, linear: vom Kaufpreis).
  int rate;

  /// In diesem Jahr verkauft oder ausgeschieden: der Restwert wird dann ganz abgeschrieben.
  int? soldYear;

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    'method': method.name,
    'rate': rate,
    if (soldYear != null) 'soldYear': soldYear,
  };

  /// Liest auch das Format der früheren Buchhaltungs-App
  /// (`{enabled, method: linear, rate, startYear, acquisitionValue}`).
  /// Gibt null zurück, wenn keine Abschreibung gemeint ist.
  static AssetInfo? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    if (j.containsKey('enabled') && j['enabled'] != true) return null;
    final method = DepMethod.parse(j.strOrNull('method'));
    final type = AssetType.parse(j.strOrNull('type'));
    final rate = j.integer('rate', method == DepMethod.linear ? type.rate ~/ 2 : type.rate);
    return AssetInfo(
      name: j.str('name'),
      type: type,
      method: method,
      rate: rate.clamp(1, 100),
      soldYear: j['soldYear'] is int ? j['soldYear'] as int : null,
    );
  }

  AssetInfo copy() => AssetInfo.fromJson(toJson())!;
}

/// Eine Anlage ohne Buchung in Conti, z. B. ein Instrument, das vor der
/// ersten Buchung in Conti gekauft wurde. Für sie gilt ein Restwert am
/// 1. Januar von [openingYear].
class Asset implements Synced {
  Asset({
    required this.id,
    required this.info,
    required this.acquired,
    this.cost = 0,
    required this.openingYear,
    this.openingValue = 0,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  @override
  final String id;
  AssetInfo info;
  DateTime acquired;

  /// Kaufpreis in Rappen.
  int cost;

  /// Ab diesem Jahr rechnet Conti die Abschreibungen.
  int openingYear;

  /// Restwert am 1. Januar von [openingYear] (Rappen).
  int openingValue;
  @override
  DateTime updatedAt;
  @override
  bool deleted;

  void touch() => updatedAt = DateTime.now().toUtc();

  Asset copy() => Asset.fromJson(toJson());

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    ...info.toJson(),
    'acquired': Day.toKey(acquired),
    'cost': cost,
    'openingYear': openingYear,
    'openingValue': openingValue,
    'updatedAt': Day.stamp(updatedAt),
    if (deleted) 'deleted': true,
  };

  factory Asset.fromJson(Map<String, dynamic> j) => Asset(
    id: j.str('id', newId()),
    info: AssetInfo.fromJson(j) ?? AssetInfo(),
    acquired: Day.parse(j.strOrNull('acquired')) ?? DateTime(Day.today().year, 1, 1),
    cost: j.integer('cost'),
    openingYear: j.integer('openingYear', Day.today().year),
    openingValue: j.integer('openingValue'),
    updatedAt: j.stamp('updatedAt'),
    deleted: j.flag('deleted'),
  );
}

/// Ein Fahrzeug, das geschäftlich und privat gebraucht wird.
class Vehicle {
  Vehicle({required this.id, this.name = '', this.price = 0, this.months = 12});

  final String id;
  String name;

  /// Kaufpreis ohne MWST (Rappen).
  int price;

  /// So viele Monate im Jahr im Geschäft.
  int months;

  /// Privatanteil nach der Praxis der Steuerverwaltung: 0,9 % des
  /// Kaufpreises pro Monat, mindestens CHF 150 pro Monat (CHF 1'800 im Jahr).
  int get privateShare {
    final m = months.clamp(0, 12);
    final byPrice = (price * 0.009 * m).round();
    final minimum = 15000 * m;
    return byPrice > minimum ? byPrice : minimum;
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'price': price, 'months': months};

  factory Vehicle.fromJson(Map<String, dynamic> j) =>
      Vehicle(id: j.str('id', newId()), name: j.str('name'), price: j.integer('price'), months: j.integer('months', 12));
}

/// Art einer Korrektur im Abschluss.
enum AdjustmentKind {
  /// Privatanteil an einer Kategorie (z. B. Handy 30 % privat).
  privateShare,

  /// Geschäftskosten, die privat bezahlt und nicht gebucht sind (z. B. Arbeitszimmer zuhause).
  unbookedExpense,

  /// Geschäftliche Einnahme, die nicht gebucht ist.
  unbookedIncome;

  static AdjustmentKind parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => AdjustmentKind.privateShare);
}

/// Eine Korrektur im Abschluss eines Jahres.
class Adjustment {
  Adjustment({
    required this.id,
    this.kind = AdjustmentKind.privateShare,
    this.label = '',
    this.categoryId,
    this.percent,
    this.amount = 0,
    this.group = ClosingGroup.other,
  });

  final String id;
  AdjustmentKind kind;
  String label;

  /// Nur bei Privatanteilen: auf diese Kategorie (mit Unterkategorien).
  String? categoryId;

  /// Prozent der Kategorie. Null = fester Betrag [amount].
  double? percent;
  int amount;

  /// Bei nicht gebuchten Kosten: wohin sie gehören (z. B. Miete fürs Arbeitszimmer).
  ClosingGroup group;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    if (categoryId != null) 'categoryId': categoryId,
    if (percent != null) 'percent': percent,
    'amount': amount,
    'group': group.name,
  };

  factory Adjustment.fromJson(Map<String, dynamic> j) => Adjustment(
    id: j.str('id', newId()),
    kind: AdjustmentKind.parse(j.strOrNull('kind')),
    label: j.str('label'),
    categoryId: j.strOrNull('categoryId'),
    percent: j['percent'] is num ? (j['percent'] as num).toDouble() : null,
    amount: j.integer('amount'),
    group: ClosingGroup.parse(j.strOrNull('group')) ?? ClosingGroup.other,
  );
}

/// Eine am 31. Dezember noch offene Rechnung eines Lieferanten.
class Creditor {
  Creditor({required this.id, this.name = '', this.amount = 0, this.goods = false});

  final String id;
  String name;
  int amount;

  /// Für Waren und Material (sonst andere Kosten).
  bool goods;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'amount': amount, if (goods) 'goods': true};

  factory Creditor.fromJson(Map<String, dynamic> j) =>
      Creditor(id: j.str('id', newId()), name: j.str('name'), amount: j.integer('amount'), goods: j.flag('goods'));
}

/// Ein Eintrag im Verlauf eines Abschlusses (abgeschlossen, wieder geöffnet).
class ClosingEvent {
  ClosingEvent({required this.action, required this.at});

  /// „closed“ oder „reopened“.
  final String action;
  final DateTime at;

  Map<String, dynamic> toJson() => {'action': action, 'at': Day.stamp(at)};

  factory ClosingEvent.fromJson(Map<String, dynamic> j) => ClosingEvent(action: j.str('action'), at: j.stamp('at'));
}

/// Alles, was zum Abschluss eines Jahres gehört und nicht schon in den
/// Buchungen steht (`abschluesse.json`, ein Eintrag pro Jahr).
class YearClosing implements Synced {
  YearClosing({
    required this.year,
    List<Vehicle>? vehicles,
    List<Adjustment>? adjustments,
    List<Creditor>? creditors,
    Set<String>? checkedAccounts,
    Set<String>? disposed,
    this.closedAt,
    List<ClosingEvent>? history,
    this.pdfFile = '',
    DateTime? updatedAt,
    this.deleted = false,
  }) : vehicles = vehicles ?? [],
       adjustments = adjustments ?? [],
       creditors = creditors ?? [],
       checkedAccounts = checkedAccounts ?? {},
       disposed = disposed ?? {},
       history = history ?? [],
       updatedAt = updatedAt ?? DateTime.utc(2000);

  static String idOf(int year) => 'year-$year';

  @override
  String get id => idOf(year);
  final int year;
  List<Vehicle> vehicles;
  List<Adjustment> adjustments;
  List<Creditor> creditors;

  /// Konten, deren Stand am 31.12. mit dem Auszug verglichen wurde.
  Set<String> checkedAccounts;

  /// Anlagen (ID einer `FixedAsset`), die in diesem Jahr verkauft wurden oder
  /// ausgeschieden sind. Ihr Restwert wird in diesem Jahr ganz abgeschrieben.
  Set<String> disposed;

  /// Abgeschlossen am … (null = offen).
  DateTime? closedAt;
  List<ClosingEvent> history;

  /// Zuletzt erstelltes Abschluss-PDF (relativ zum Datenordner).
  String pdfFile;
  @override
  DateTime updatedAt;
  @override
  bool deleted;

  bool get closed => closedAt != null;

  void touch() => updatedAt = DateTime.now().toUtc();

  YearClosing copy() => YearClosing.fromJson(toJson());

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'year': year,
    if (vehicles.isNotEmpty) 'vehicles': [for (final v in vehicles) v.toJson()],
    if (adjustments.isNotEmpty) 'adjustments': [for (final a in adjustments) a.toJson()],
    if (creditors.isNotEmpty) 'creditors': [for (final c in creditors) c.toJson()],
    if (checkedAccounts.isNotEmpty) 'checkedAccounts': checkedAccounts.toList()..sort(),
    if (disposed.isNotEmpty) 'disposed': disposed.toList()..sort(),
    if (closedAt != null) 'closedAt': Day.stamp(closedAt),
    if (history.isNotEmpty) 'history': [for (final h in history) h.toJson()],
    if (pdfFile.isNotEmpty) 'pdfFile': pdfFile,
    'updatedAt': Day.stamp(updatedAt),
    if (deleted) 'deleted': true,
  };

  factory YearClosing.fromJson(Map<String, dynamic> j) => YearClosing(
    year: j.integer('year', int.tryParse(j.str('id').replaceFirst('year-', '')) ?? Day.today().year),
    vehicles: [for (final m in j.maps('vehicles')) Vehicle.fromJson(m)],
    adjustments: [for (final m in j.maps('adjustments')) Adjustment.fromJson(m)],
    creditors: [for (final m in j.maps('creditors')) Creditor.fromJson(m)],
    checkedAccounts: {for (final x in (j['checkedAccounts'] is List ? j['checkedAccounts'] as List : const [])) '$x'},
    disposed: {for (final x in (j['disposed'] is List ? j['disposed'] as List : const [])) '$x'},
    closedAt: j['closedAt'] is String ? j.stamp('closedAt') : null,
    history: [for (final m in j.maps('history')) ClosingEvent.fromJson(m)],
    pdfFile: j.str('pdfFile'),
    updatedAt: j.stamp('updatedAt'),
    deleted: j.flag('deleted'),
  );
}
