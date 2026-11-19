import '../dates.dart';
import 'closing.dart';
import 'synced.dart';

/// Kategorie für Einnahmen oder Ausgaben, optional mit Oberkategorie
/// (z. B. „Fahrspesen“ unter „Spesen“).
class Category implements Synced {
  Category({
    required this.id,
    required this.name,
    required this.income,
    this.parentId,
    this.order = 0,
    this.group,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  @override
  final String id;
  String name;

  /// true = Einnahmen, false = Ausgaben.
  bool income;
  String? parentId;
  int order;

  /// Wohin die Kategorie im Jahresabschluss gehört. Null = von der
  /// Oberkategorie übernehmen bzw. Vorschlag ([ClosingGroups.suggest]).
  ClosingGroup? group;
  @override
  DateTime updatedAt;
  @override
  bool deleted;

  void touch() => updatedAt = DateTime.now().toUtc();

  Category copy() => Category.fromJson(toJson());

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'income': income,
    if (parentId != null) 'parentId': parentId,
    'order': order,
    if (group != null) 'group': group!.name,
    'updatedAt': Day.stamp(updatedAt),
    if (deleted) 'deleted': true,
  };

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j.str('id', newId()),
    name: j.str('name'),
    income: j.flag('income'),
    parentId: j.strOrNull('parentId'),
    order: j.integer('order'),
    group: ClosingGroup.parse(j.strOrNull('group')),
    updatedAt: j.stamp('updatedAt'),
    deleted: j.flag('deleted'),
  );
}

/// Vorgeschlagene Kategorien für Selbständige. Die IDs sind fest, damit zwei
/// Geräte, die beide neu eingerichtet werden, dieselben Kategorien haben
/// (sonst gäbe es nach dem Abgleich alles doppelt).
class DefaultCategories {
  DefaultCategories._();

  /// (id, Deutsch, Englisch, Einnahme?, Oberkategorie)
  static const List<(String, String, String, bool, String?)> all = [
    ('cat-in-services', 'Dienstleistungen', 'Services', true, null),
    ('cat-in-teaching', 'Unterricht', 'Teaching', true, null),
    ('cat-in-gigs', 'Gagen', 'Fees & gigs', true, null),
    ('cat-in-sales', 'Verkauf', 'Sales', true, null),
    ('cat-in-other', 'Sonstiger Ertrag', 'Other income', true, null),
    ('cat-ex-material', 'Material', 'Materials', false, null),
    ('cat-ex-equipment', 'Geräte & Instrumente', 'Equipment & instruments', false, null),
    ('cat-ex-it', 'Informatik & Software', 'IT & software', false, null),
    ('cat-ex-rent', 'Raummiete', 'Rent', false, null),
    ('cat-ex-expenses', 'Spesen', 'Expenses', false, null),
    ('cat-ex-travel', 'Fahrspesen', 'Travel', false, 'cat-ex-expenses'),
    ('cat-ex-meals', 'Verpflegung', 'Meals', false, 'cat-ex-expenses'),
    ('cat-ex-phone', 'Telefon & Internet', 'Phone & internet', false, null),
    ('cat-ex-insurance', 'Versicherungen & Gebühren', 'Insurance & fees', false, null),
    ('cat-ex-training', 'Weiterbildung', 'Training', false, null),
    ('cat-ex-marketing', 'Werbung', 'Marketing', false, null),
    ('cat-ex-other', 'Sonstiger Aufwand', 'Other expenses', false, null),
  ];

  static List<Category> build({required bool english}) {
    final t = DateTime.utc(2026, 1, 1);
    var i = 0;
    return [
      for (final (id, de, en, income, parent) in all)
        Category(id: id, name: english ? en : de, income: income, parentId: parent, order: i++, updatedAt: t),
    ];
  }

  /// Zwei Kategorien für Geld zwischen Geschäft und Privat. Sie zählen nicht
  /// als Einnahme oder Ausgabe, sondern als Privatbezug bzw. Privateinlage.
  static const privateOutId = 'cat-private-out';
  static const privateInId = 'cat-private-in';

  static List<Category> buildPrivate({required bool english}) {
    final t = DateTime.utc(2026, 1, 1);
    return [
      Category(id: privateOutId, name: english ? 'Private withdrawal' : 'Privatbezug', income: false, order: 900, group: ClosingGroup.privateOut, updatedAt: t),
      Category(id: privateInId, name: english ? 'Private deposit' : 'Privateinlage', income: true, order: 900, group: ClosingGroup.privateIn, updatedAt: t),
    ];
  }
}

/// Vorschläge, wohin eine Kategorie im Abschluss gehört.
class ClosingGroups {
  ClosingGroups._();

  static const _byId = {
    'cat-in-other': ClosingGroup.otherIncome,
    'cat-ex-material': ClosingGroup.goods,
    'cat-ex-rent': ClosingGroup.rent,
    DefaultCategories.privateOutId: ClosingGroup.privateOut,
    DefaultCategories.privateInId: ClosingGroup.privateIn,
  };

  /// Gruppe einer Kategorie: eigene Angabe, sonst die der Oberkategorie,
  /// sonst ein Vorschlag. [cats]: alle Kategorien nach ID.
  static ClosingGroup resolve(Map<String, Category> cats, String? id, {required bool income}) {
    final c = cats[id];
    if (c == null) return income ? ClosingGroup.revenue : ClosingGroup.other;
    if (c.group != null && c.group!.income == income) return c.group!;
    final parent = cats[c.parentId];
    if (parent?.group != null && parent!.group!.income == income) return parent.group!;
    final g = suggest(parent ?? c);
    // Eine Ausgaben-Gruppe an einer Einnahme (oder umgekehrt) gilt nicht.
    if (g.income != income) return income ? ClosingGroup.revenue : ClosingGroup.other;
    return g;
  }

  /// Vorschlag aus ID oder Name (für Kategorien ohne eigene Angabe).
  static ClosingGroup suggest(Category c) {
    final fixed = _byId[c.id];
    if (fixed != null) return fixed;
    final n = c.name.toLowerCase();
    if (n.contains('privat') || n.contains('private')) return c.income ? ClosingGroup.privateIn : ClosingGroup.privateOut;
    if (c.income) {
      return n.contains('sonstig') || n.contains('other') || n.contains('übrig') ? ClosingGroup.otherIncome : ClosingGroup.revenue;
    }
    if (n.contains('material') || n.contains('waren') || n.contains('goods')) return ClosingGroup.goods;
    if (n.contains('miete') || n.contains('raum') || n.contains('rent')) return ClosingGroup.rent;
    if (n.contains('fahrzeug') || n.contains('auto') || n.contains('benzin') || n.contains('vehicle')) return ClosingGroup.vehicle;
    if (n.contains('lohn') || n.contains('löhne') || n.contains('wage')) return ClosingGroup.personnel;
    return ClosingGroup.other;
  }
}
