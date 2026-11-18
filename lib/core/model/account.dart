import '../../app/l10n.dart';
import '../dates.dart';
import 'synced.dart';

/// Wo das Geld liegt.
enum AccountType {
  bank,
  post,
  cash,
  twint,
  card,
  other;

  static AccountType parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => AccountType.other);

  String get label => switch (this) {
    AccountType.bank => tr('Bankkonto', 'Bank account'),
    AccountType.post => 'PostFinance',
    AccountType.cash => tr('Bargeld', 'Cash'),
    AccountType.twint => 'TWINT',
    AccountType.card => tr('Kreditkarte', 'Credit card'),
    AccountType.other => tr('Anderes', 'Other'),
  };
}

/// Ein Konto: Bank, PostFinance, Kasse, TWINT …
class Account implements Synced {
  Account({
    required this.id,
    required this.name,
    this.type = AccountType.bank,
    this.iban = '',
    this.opening = 0,
    DateTime? openingDate,
    this.order = 0,
    this.archived = false,
    DateTime? updatedAt,
    this.deleted = false,
  }) : openingDate = openingDate ?? DateTime(Day.today().year, 1, 1),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  @override
  final String id;
  String name;
  AccountType type;
  String iban;

  /// Anfangsbestand in Rappen, am Tag [openingDate].
  int opening;
  DateTime openingDate;
  int order;

  /// Nicht mehr benutzt: erscheint nicht mehr in der Auswahl.
  bool archived;
  @override
  DateTime updatedAt;
  @override
  bool deleted;

  void touch() => updatedAt = DateTime.now().toUtc();

  Account copy() => Account.fromJson(toJson());

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    if (iban.isNotEmpty) 'iban': iban,
    'opening': opening,
    'openingDate': Day.toKey(openingDate),
    'order': order,
    if (archived) 'archived': true,
    'updatedAt': Day.stamp(updatedAt),
    if (deleted) 'deleted': true,
  };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    id: j.str('id', newId()),
    name: j.str('name'),
    type: AccountType.parse(j.strOrNull('type')),
    iban: j.str('iban'),
    opening: j.integer('opening'),
    openingDate: Day.parse(j.strOrNull('openingDate')),
    order: j.integer('order'),
    archived: j.flag('archived'),
    updatedAt: j.stamp('updatedAt'),
    deleted: j.flag('deleted'),
  );
}
