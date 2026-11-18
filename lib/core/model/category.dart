import '../dates.dart';
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
    'updatedAt': Day.stamp(updatedAt),
    if (deleted) 'deleted': true,
  };

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j.str('id', newId()),
    name: j.str('name'),
    income: j.flag('income'),
    parentId: j.strOrNull('parentId'),
    order: j.integer('order'),
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
}
