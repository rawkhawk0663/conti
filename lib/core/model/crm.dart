import '../dates.dart';
import 'synced.dart';

/// Kundin oder Kunde. Die Adresse ist in Feldern erfasst, so wie sie der
/// QR-Zahlteil verlangt (Strasse, Hausnummer, PLZ, Ort getrennt).
class Client implements Synced {
  Client({
    required this.id,
    this.firstName = '',
    this.lastName = '',
    this.company = '',
    this.email = '',
    this.phone = '',
    this.street = '',
    this.houseNumber = '',
    this.zip = '',
    this.city = '',
    this.country = 'CH',
    this.notes = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deleted = false,
  }) : createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  @override
  final String id;
  String firstName;
  String lastName;
  String company;
  String email;
  String phone;
  String street;
  String houseNumber;
  String zip;
  String city;
  String country;
  String notes;
  final DateTime createdAt;
  @override
  DateTime updatedAt;
  @override
  bool deleted;

  String get personName => [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

  Client copy() => Client.fromJson(toJson());

  /// „Musterweg 3, 6000 Luzern“
  String get addressLine => [
    [street, houseNumber].where((s) => s.isNotEmpty).join(' '),
    [zip, city].where((s) => s.isNotEmpty).join(' '),
  ].where((s) => s.isNotEmpty).join(', ');

  String get displayName {
    if (company.isNotEmpty) return company;
    final n = personName;
    return n.isNotEmpty ? n : '–';
  }

  void touch() => updatedAt = DateTime.now().toUtc();

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'firstName': firstName,
    'lastName': lastName,
    'company': company,
    'email': email,
    'phone': phone,
    'street': street,
    'houseNumber': houseNumber,
    'zip': zip,
    'city': city,
    'country': country,
    if (notes.isNotEmpty) 'notes': notes,
    'createdAt': Day.stamp(createdAt),
    'updatedAt': Day.stamp(updatedAt),
    if (deleted) 'deleted': true,
  };

  factory Client.fromJson(Map<String, dynamic> j) => Client(
    id: j.str('id', newId()),
    firstName: j.str('firstName'),
    lastName: j.str('lastName'),
    company: j.str('company'),
    email: j.str('email'),
    phone: j.str('phone'),
    street: j.str('street'),
    houseNumber: j.str('houseNumber'),
    zip: j.str('zip'),
    city: j.str('city'),
    country: j.str('country', 'CH'),
    notes: j.str('notes'),
    createdAt: j.stamp('createdAt'),
    updatedAt: j.stamp('updatedAt'),
    deleted: j.flag('deleted'),
  );
}

/// Wie ein Produkt verrechnet wird.
enum PriceUnit {
  flat,
  hour,
  lesson,
  piece;

  static PriceUnit parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => PriceUnit.flat);
}

/// Produkt oder Leistung mit Preis (z. B. „Gig“, „Lektion 45 Minuten“).
class Product implements Synced {
  Product({
    required this.id,
    required this.name,
    this.description = '',
    this.group = '',
    this.price = 0,
    this.unit = PriceUnit.flat,
    this.vat = 'none',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deleted = false,
  }) : createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  @override
  final String id;
  String name;
  String description;

  /// Gruppe zum Ordnen (z. B. „Musik“, „Grafik“).
  String group;

  /// Preis in Rappen pro Einheit.
  int price;
  PriceUnit unit;
  String vat;
  final DateTime createdAt;
  @override
  DateTime updatedAt;
  @override
  bool deleted;

  void touch() => updatedAt = DateTime.now().toUtc();

  Product copy() => Product.fromJson(toJson());

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'group': group,
    'price': price,
    'unit': unit.name,
    'vat': vat,
    'createdAt': Day.stamp(createdAt),
    'updatedAt': Day.stamp(updatedAt),
    if (deleted) 'deleted': true,
  };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
    id: j.str('id', newId()),
    name: j.str('name'),
    description: j.str('description'),
    group: j.str('group'),
    price: j.integer('price'),
    unit: PriceUnit.parse(j.strOrNull('unit')),
    vat: j.str('vat', 'none'),
    createdAt: j.stamp('createdAt'),
    updatedAt: j.stamp('updatedAt'),
    deleted: j.flag('deleted'),
  );
}

/// Stand eines Auftrags.
enum OrderStatus {
  open,
  inProgress,
  done,
  invoiced,
  paid,
  cancelled;

  static OrderStatus parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => OrderStatus.open);
}

/// Eine Position in einem Auftrag oder auf einer Rechnung.
class OrderItem {
  OrderItem({
    required this.id,
    required this.name,
    this.productId,
    this.description = '',
    this.unit = PriceUnit.flat,
    this.quantity = 1,
    this.unitPrice = 0,
    this.vat = 'none',
  });

  final String id;
  String? productId;
  String name;
  String description;
  PriceUnit unit;
  double quantity;

  /// Preis pro Einheit in Rappen.
  int unitPrice;
  String vat;

  int get total => (unitPrice * quantity).round();

  Map<String, dynamic> toJson() => {
    'id': id,
    if (productId != null) 'productId': productId,
    'name': name,
    'description': description,
    'unit': unit.name,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'vat': vat,
  };

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
    id: j.str('id', newId()),
    productId: j.strOrNull('productId'),
    name: j.str('name'),
    description: j.str('description'),
    unit: PriceUnit.parse(j.strOrNull('unit')),
    quantity: j.dbl('quantity', 1),
    unitPrice: j.integer('unitPrice'),
    vat: j.str('vat', 'none'),
  );
}

/// Eine bezogene Lektion in einem Abo.
class Session {
  Session({required this.id, required this.date, this.note = ''});
  final String id;
  DateTime date;
  String note;

  Map<String, dynamic> toJson() => {'id': id, 'date': Day.toKey(date), if (note.isNotEmpty) 'note': note};

  factory Session.fromJson(Map<String, dynamic> j) =>
      Session(id: j.str('id', newId()), date: Day.parse(j.strOrNull('date')) ?? Day.today(), note: j.str('note'));
}

/// Eine Auftragsart (Gig, Lektionen-Abo, Grafik …). Legt man selbst an.
/// Bei einem Abo ([subscription]) zählt Conti die bezogenen Lektionen,
/// [lessons] ist die vorgeschlagene Grösse eines neuen Abos.
class OrderKind implements Synced {
  OrderKind({
    required this.id,
    required this.name,
    this.subscription = false,
    this.lessons = 5,
    this.order = 0,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  @override
  final String id;
  String name;
  bool subscription;
  int lessons;
  int order;
  @override
  DateTime updatedAt;
  @override
  bool deleted;

  void touch() => updatedAt = DateTime.now().toUtc();

  OrderKind copy() => OrderKind.fromJson(toJson());

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (subscription) 'subscription': true,
    'lessons': lessons,
    'order': order,
    'updatedAt': Day.stamp(updatedAt),
    if (deleted) 'deleted': true,
  };

  factory OrderKind.fromJson(Map<String, dynamic> j) => OrderKind(
    id: j.str('id', newId()),
    name: j.str('name'),
    subscription: j.flag('subscription'),
    lessons: j.integer('lessons', 5),
    order: j.integer('order'),
    updatedAt: j.stamp('updatedAt'),
    deleted: j.flag('deleted'),
  );

  /// Vorschläge mit festen IDs (zwei neu eingerichtete Geräte haben dieselben).
  static List<OrderKind> defaults({required bool english}) {
    final t = DateTime.utc(2026, 1, 1);
    return [
      OrderKind(id: 'kind-gig', name: 'Gig', order: 0, updatedAt: t),
      OrderKind(id: 'kind-abo', name: english ? 'Lesson pack' : 'Lektionen-Abo', subscription: true, lessons: 5, order: 1, updatedAt: t),
      OrderKind(id: 'kind-lessons', name: english ? 'Single lessons' : 'Einzellektionen', order: 2, updatedAt: t),
      OrderKind(id: 'kind-design', name: english ? 'Design' : 'Grafik', order: 3, updatedAt: t),
      OrderKind(id: 'kind-other', name: english ? 'Other' : 'Sonstiges', order: 4, updatedAt: t),
    ];
  }
}

/// Ein Auftrag: Gig, Lektionen-Abo, Grafik-Auftrag … ([kind] ist die ID
/// einer [OrderKind]; ältere Daten können dort noch einen Namen haben).
class Order implements Synced {
  Order({
    required this.id,
    required this.number,
    required this.title,
    this.kind = '',
    this.date,
    this.lessonsTotal,
    List<Session>? sessions,
    this.followUpId,
    this.clientId,
    this.status = OrderStatus.open,
    List<OrderItem>? items,
    this.invoiceNumber = '',
    this.invoicedAt,
    this.dueDate,
    this.paidAt,
    this.paidEntryId,
    this.invoiceFile = '',
    this.notes = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deleted = false,
  }) : items = items ?? [],
       sessions = sessions ?? [],
       createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  @override
  final String id;
  String number;
  String title;

  /// Auftragsart (ID einer [OrderKind]).
  String kind;

  /// Datum des Auftrags (z. B. des Gigs). Null = ohne Datum.
  DateTime? date;

  /// Nur bei Abos: wie viele Lektionen das Abo hat.
  int? lessonsTotal;

  /// Nur bei Abos: bezogene Lektionen.
  List<Session> sessions;

  /// Nur bei Abos: das danach angelegte nächste Abo (dann keine Erinnerung mehr).
  String? followUpId;

  bool get followedUp => followUpId != null;
  bool get isSubscription => lessonsTotal != null;
  int get lessonsUsed => sessions.length;
  int get lessonsLeft => (lessonsTotal ?? 0) - sessions.length;
  bool get subscriptionUsedUp => isSubscription && lessonsLeft <= 0;
  String? clientId;
  OrderStatus status;
  List<OrderItem> items;
  String invoiceNumber;
  DateTime? invoicedAt;
  DateTime? dueDate;
  DateTime? paidAt;
  String? paidEntryId;

  /// Gestellte Rechnung als PDF im Datenordner (wird nie verändert).
  String invoiceFile;
  String notes;
  final DateTime createdAt;
  @override
  DateTime updatedAt;
  @override
  bool deleted;

  int get total => items.fold(0, (s, i) => s + i.total);

  void touch() => updatedAt = DateTime.now().toUtc();

  Order copy() => Order.fromJson(toJson());

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'title': title,
    'kind': kind,
    if (date != null) 'date': Day.toKey(date!),
    if (lessonsTotal != null) 'lessonsTotal': lessonsTotal,
    if (sessions.isNotEmpty) 'sessions': [for (final x in sessions) x.toJson()],
    if (followUpId != null) 'followUpId': followUpId,
    if (clientId != null) 'clientId': clientId,
    'status': status.name,
    'items': [for (final i in items) i.toJson()],
    'invoiceNumber': invoiceNumber,
    if (invoicedAt != null) 'invoicedAt': Day.toKey(invoicedAt!),
    if (dueDate != null) 'dueDate': Day.toKey(dueDate!),
    if (paidAt != null) 'paidAt': Day.toKey(paidAt!),
    if (paidEntryId != null) 'paidEntryId': paidEntryId,
    if (invoiceFile.isNotEmpty) 'invoiceFile': invoiceFile,
    if (notes.isNotEmpty) 'notes': notes,
    'createdAt': Day.stamp(createdAt),
    'updatedAt': Day.stamp(updatedAt),
    if (deleted) 'deleted': true,
  };

  factory Order.fromJson(Map<String, dynamic> j) => Order(
    id: j.str('id', newId()),
    number: j.str('number'),
    title: j.str('title'),
    kind: j.str('kind'),
    date: Day.parse(j.strOrNull('date')),
    lessonsTotal: j['lessonsTotal'] is num ? j.integer('lessonsTotal') : null,
    sessions: [for (final x in j.maps('sessions')) Session.fromJson(x)],
    followUpId: j.strOrNull('followUpId'),
    clientId: j.strOrNull('clientId'),
    status: OrderStatus.parse(j.strOrNull('status')),
    items: [for (final i in j.maps('items')) OrderItem.fromJson(i)],
    invoiceNumber: j.str('invoiceNumber'),
    invoicedAt: Day.parse(j.strOrNull('invoicedAt')),
    dueDate: Day.parse(j.strOrNull('dueDate')),
    paidAt: Day.parse(j.strOrNull('paidAt')),
    paidEntryId: j.strOrNull('paidEntryId'),
    invoiceFile: j.str('invoiceFile'),
    notes: j.str('notes'),
    createdAt: j.stamp('createdAt'),
    updatedAt: j.stamp('updatedAt'),
    deleted: j.flag('deleted'),
  );
}

/// Eine Aufgabe mit Frist, allgemein oder zu einem Kunden.
class Task implements Synced {
  Task({
    required this.id,
    required this.title,
    this.clientId,
    this.due,
    this.notes = '',
    this.done = false,
    this.doneAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deleted = false,
  }) : createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  @override
  final String id;
  String title;
  String? clientId;
  DateTime? due;
  String notes;
  bool done;
  DateTime? doneAt;
  final DateTime createdAt;
  @override
  DateTime updatedAt;
  @override
  bool deleted;

  void touch() => updatedAt = DateTime.now().toUtc();

  Task copy() => Task.fromJson(toJson());

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (clientId != null) 'clientId': clientId,
    if (due != null) 'due': Day.toKey(due!),
    if (notes.isNotEmpty) 'notes': notes,
    'done': done,
    if (doneAt != null) 'doneAt': Day.stamp(doneAt),
    'createdAt': Day.stamp(createdAt),
    'updatedAt': Day.stamp(updatedAt),
    if (deleted) 'deleted': true,
  };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j.str('id', newId()),
    title: j.str('title'),
    clientId: j.strOrNull('clientId'),
    due: Day.parse(j.strOrNull('due')),
    notes: j.str('notes'),
    done: j.flag('done'),
    doneAt: j['doneAt'] is String ? j.stamp('doneAt') : null,
    createdAt: j.stamp('createdAt'),
    updatedAt: j.stamp('updatedAt'),
    deleted: j.flag('deleted'),
  );
}
