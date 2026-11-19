import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/error_log.dart';
import '../app/l10n.dart';
import 'closing/depreciation.dart';
import 'closing/year_report.dart';
import 'dates.dart';
import 'device_settings.dart';
import 'model/account.dart';
import 'model/business.dart';
import 'model/category.dart';
import 'model/closing.dart';
import 'model/crm.dart';
import 'model/entry.dart';
import 'model/synced.dart';
import 'store/data_store.dart';
import 'store/json_file.dart';

/// Zustand der ganzen App. Hält alle Daten im Speicher und schreibt jede
/// Änderung sofort in den Datenordner.
class ContiState extends ChangeNotifier {
  ContiState(this.supportDir)
    : store = DataStore(p.join(supportDir, 'Daten')),
      device = DeviceSettings(JsonFile(p.join(supportDir, 'einstellungen.json')));

  /// Gerätespezifischer Ordner der App (Einstellungen, Fehlerprotokoll …).
  final String supportDir;
  final DataStore store;
  final DeviceSettings device;

  Business business = Business();
  List<Entry> _entries = [];
  List<Account> _accounts = [];
  List<Category> _categories = [];
  List<Client> _clients = [];
  List<Product> _products = [];
  List<Order> _orders = [];
  List<Task> _tasks = [];
  List<OrderKind> _orderKinds = [];
  List<Asset> _assets = [];
  List<YearClosing> _closings = [];
  bool dataInitialized = false;

  /// Wird nach jeder eigenen Änderung aufgerufen (der Abgleich startet dann bald).
  VoidCallback? onLocalChange;

  /// Anzeige neu aufbauen (z. B. nach geänderten Geräteeinstellungen).
  void refresh() => notifyListeners();

  void _changed() {
    notifyListeners();
    onLocalChange?.call();
  }

  Future<void> load() async {
    await device.load();
    L10n.language.value = device.language ?? AppLanguage.system;
    await reload();
  }

  /// Alles neu vom Datenordner lesen (z. B. nach einem Import).
  Future<void> reload() async {
    final s = await store.load();
    business = s.business;
    _entries = s.entries;
    _accounts = s.accounts;
    _categories = s.categories;
    _clients = s.clients;
    _products = s.products;
    _orders = s.orders;
    _tasks = s.tasks;
    _orderKinds = s.orderKinds;
    _assets = s.assets;
    _closings = s.closings;
    dataInitialized = s.initialized;
    if (dataInitialized) {
      await ensureOrderKinds(notify: false);
      await ensurePrivateCategories();
    }
    await _migrateOrderKinds();
    notifyListeners();
  }

  bool get needsSetup => !device.setupDone || !dataInitialized;

  // ---------- Lesen (nur nicht Gelöschtes) ----------

  List<Entry> get entries => _entries.where((e) => !e.deleted).toList();
  List<Account> get accounts => (_accounts.where((a) => !a.deleted).toList()..sort((a, b) => a.order.compareTo(b.order)));
  List<Account> get activeAccounts => accounts.where((a) => !a.archived).toList();
  List<Category> get categories =>
      (_categories.where((c) => !c.deleted).toList()..sort((a, b) => a.order.compareTo(b.order)));
  List<Client> get clients => _clients.where((c) => !c.deleted).toList()
    ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  List<Product> get products => _products.where((x) => !x.deleted).toList();
  List<Order> get orders => _orders.where((x) => !x.deleted).toList();
  List<Task> get tasks => _tasks.where((x) => !x.deleted).toList();
  List<Asset> get assets => _assets.where((x) => !x.deleted).toList();
  List<YearClosing> get closings => _closings.where((x) => !x.deleted).toList();
  List<OrderKind> get orderKinds =>
      (_orderKinds.where((k) => !k.deleted).toList()..sort((a, b) => a.order.compareTo(b.order)));

  Product? product(String? id) => _products.where((x) => x.id == id).firstOrNull;
  Order? order(String? id) => _orders.where((x) => x.id == id).firstOrNull;
  Task? task(String? id) => _tasks.where((x) => x.id == id).firstOrNull;
  OrderKind? orderKind(String? id) => _orderKinds.where((x) => x.id == id).firstOrNull;

  /// Name der Auftragsart (ältere Daten tragen noch den Namen selbst).
  String kindLabel(Order o) => orderKind(o.kind)?.name ?? o.kind;

  List<Order> ordersOf(String clientId) => orders.where((o) => o.clientId == clientId).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  List<Entry> entriesOf(String clientId) => entries.where((e) => e.clientId == clientId).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  List<Task> tasksOf(String clientId) => tasks.where((t) => t.clientId == clientId).toList();

  /// Verrechnet, aber noch nicht bezahlt (in Rappen).
  int openAmountOf(String clientId) =>
      ordersOf(clientId).where((o) => o.status == OrderStatus.invoiced).fold(0, (a, o) => a + o.total);

  /// Offene Aufgaben, nach Frist (ohne Frist zuletzt).
  List<Task> get openTasks => tasks.where((t) => !t.done).toList()
    ..sort((a, b) {
      if (a.due == null && b.due == null) return a.createdAt.compareTo(b.createdAt);
      if (a.due == null) return 1;
      if (b.due == null) return -1;
      return a.due!.compareTo(b.due!);
    });

  /// Aufgebrauchte Abos, die noch nicht erledigt oder verrechnet sind.
  List<Order> get usedUpSubscriptions =>
      orders.where((o) => o.subscriptionUsedUp && o.status != OrderStatus.cancelled && !o.followedUp).toList();

  /// Nächste freie Auftragsnummer, z. B. „A-2026-0009“.
  String nextOrderNumber([DateTime? at]) {
    final year = (at ?? Day.today()).year;
    final prefix = '${business.invoice.orderPrefix}$year-';
    var max = 0;
    for (final o in _orders) {
      if (!o.number.startsWith(prefix)) continue;
      final n = int.tryParse(o.number.substring(prefix.length));
      if (n != null && n > max) max = n;
    }
    return '$prefix${(max + 1).toString().padLeft(4, '0')}';
  }

  /// Ältere Aufträge tragen den Namen der Art statt der ID: einmal umstellen.
  /// Die neue Art bekommt eine ID aus dem Namen, damit zwei Geräte dieselbe anlegen.
  Future<void> _migrateOrderKinds() async {
    final ids = {for (final k in _orderKinds) k.id};
    final todo = _orders.where((o) => !o.deleted && o.kind.isNotEmpty && !ids.contains(o.kind)).toList();
    if (todo.isEmpty) return;
    final newKinds = <OrderKind>[];
    for (final o in todo) {
      final name = o.kind.trim();
      var k = [..._orderKinds, ...newKinds].where((x) => !x.deleted && x.name.toLowerCase() == name.toLowerCase()).firstOrNull;
      if (k == null) {
        k = OrderKind(
          id: 'imp-kind-${name.toLowerCase().codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0x7fffffff)}',
          name: name,
          order: 100 + newKinds.length,
          updatedAt: DateTime.utc(2026, 1, 1),
        );
        newKinds.add(k);
      }
      o.kind = k.id;
    }
    try {
      if (newKinds.isNotEmpty) _orderKinds = await store.saveOrderKinds(mergeById(_orderKinds, newKinds));
      _orders = await store.saveOrders(_orders);
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Auftragsarten umstellen');
    }
  }

  Account? account(String? id) => _accounts.where((a) => a.id == id).firstOrNull;
  Category? category(String? id) => _categories.where((c) => c.id == id).firstOrNull;
  Client? client(String? id) => _clients.where((c) => c.id == id).firstOrNull;
  Entry? entry(String id) => _entries.where((e) => e.id == id).firstOrNull;

  /// „Spesen › Fahrspesen“
  String categoryLabel(String? id) {
    final c = category(id);
    if (c == null) return tr('Ohne Kategorie', 'No category');
    final parent = category(c.parentId);
    return parent == null ? c.name : '${parent.name} › ${c.name}';
  }

  /// Kategorien in Baum-Reihenfolge (Oberkategorie, dann ihre Unterkategorien).
  List<(Category, int)> categoryTree({bool? income}) {
    final all = categories.where((c) => income == null || c.income == income).toList();
    final ids = all.map((c) => c.id).toSet();
    final out = <(Category, int)>[];
    for (final top in all.where((c) => c.parentId == null || !ids.contains(c.parentId))) {
      out.add((top, 0));
      for (final sub in all.where((c) => c.parentId == top.id)) {
        out.add((sub, 1));
      }
    }
    return out;
  }

  /// Jahre, in denen es Buchungen gibt (neueste zuerst), plus das laufende.
  List<int> get years {
    final s = {for (final e in entries) e.year, Day.today().year};
    return s.toList()..sort((a, b) => b.compareTo(a));
  }

  // ---------- Auswertungen ----------

  /// Saldo eines Kontos bis und mit [until] (null = heute und alles davor).
  int balance(String accountId, {DateTime? until}) {
    final a = account(accountId);
    if (a == null) return 0;
    var sum = a.opening;
    for (final e in entries) {
      if (e.date.isBefore(a.openingDate)) continue;
      if (until != null && e.date.isAfter(until)) continue;
      if (e.accountId == accountId) {
        sum += switch (e.kind) {
          EntryKind.income => e.amount,
          EntryKind.expense => -e.amount,
          EntryKind.transfer => -e.amount,
        };
      }
      if (e.kind == EntryKind.transfer && e.toAccountId == accountId) sum += e.amount;
    }
    return sum;
  }

  int get totalBalance => accounts.where((a) => !a.archived).fold(0, (s, a) => s + balance(a.id));

  Iterable<Entry> _reportEntries(int year) => entries.where((e) => e.year == year && !e.excludeFromReports);

  /// Gruppe einer Kategorie im Abschluss.
  ClosingGroup groupOf(String? categoryId, {required bool income}) =>
      ClosingGroups.resolve({for (final c in _categories) c.id: c}, categoryId, income: income);

  /// Geschäftlicher Teil einer Buchung (ohne Privatbezüge und -einlagen,
  /// ohne Buchungen, die nicht in Auswertungen zählen).
  int businessAmount(Entry e) {
    if (e.excludeFromReports || e.kind == EntryKind.transfer) return 0;
    final income = e.kind == EntryKind.income;
    var sum = 0;
    e.amountsByCategory.forEach((id, amount) {
      if (!groupOf(id, income: income).isPrivate) sum += amount;
    });
    return sum;
  }

  /// Ist die Buchung ganz privat (Privatbezug oder Privateinlage)?
  bool isPrivateEntry(Entry e) => e.kind != EntryKind.transfer && businessAmount(e) == 0 && !e.excludeFromReports;

  int incomeOf(int year, {int? month}) => _reportEntries(year)
      .where((e) => e.kind == EntryKind.income && (month == null || e.date.month == month))
      .fold(0, (s, e) => s + businessAmount(e));

  int expensesOf(int year, {int? month}) => _reportEntries(year)
      .where((e) => e.kind == EntryKind.expense && (month == null || e.date.month == month))
      .fold(0, (s, e) => s + businessAmount(e));

  /// Summen pro Oberkategorie (Unterkategorien zählen zur Oberkategorie).
  /// Privatbezüge und -einlagen zählen nicht.
  Map<String, int> totalsByTopCategory(int year, {required bool income}) {
    final out = <String, int>{};
    for (final e in _reportEntries(year).where((e) => e.kind == (income ? EntryKind.income : EntryKind.expense))) {
      e.amountsByCategory.forEach((catId, amount) {
        if (groupOf(catId, income: income).isPrivate) return;
        final c = category(catId);
        final top = c?.parentId != null && category(c!.parentId) != null ? c.parentId! : (c?.id ?? '');
        out[top] = (out[top] ?? 0) + amount;
      });
    }
    return out;
  }

  // ---------- Jahresabschluss ----------

  /// Angaben zum Abschluss eines Jahres (leer, falls es noch keine gibt).
  YearClosing closingOf(int year) =>
      _closings.where((c) => c.year == year && !c.deleted).firstOrNull ?? YearClosing(year: year);

  bool isYearClosed(int year) => closingOf(year).closed;

  /// Verkaufte oder ausgeschiedene Anlagen: ID → Jahr (das früheste gilt).
  Map<String, int> get disposals {
    final out = <String, int>{};
    for (final c in closings) {
      for (final id in c.disposed) {
        final cur = out[id];
        if (cur == null || c.year < cur) out[id] = c.year;
      }
    }
    return out;
  }

  /// Anlagen mit Abschreibungen: aus Buchungen und ohne Buchung.
  List<FixedAsset> get fixedAssets {
    final sold = disposals;
    final list = [
      for (final e in entries)
        if (e.kind == EntryKind.expense && !e.excludeFromReports)
          if (AssetInfo.fromJson(e.asset) case final info?) FixedAsset.fromEntry(e, info),
      for (final a in assets) FixedAsset.fromAsset(a),
    ];
    for (final f in list) {
      if (sold[f.id] case final y?) f.info.soldYear = y;
    }
    return list;
  }

  /// Der Abschluss eines Jahres, aus allen Daten berechnet.
  YearReport reportOf(int year) => YearReport.compute(
    year: year,
    entries: entries,
    accounts: accounts,
    categories: categories,
    orders: orders,
    clients: clients,
    assets: assets,
    closing: closingOf(year),
    previous: closingOf(year - 1),
    disposals: disposals,
  );

  Future<void> saveClosing(YearClosing c) async {
    c.touch();
    _closings.removeWhere((x) => x.id == c.id);
    _closings.add(c);
    _closings = await store.saveClosings(_closings);
    _changed();
  }

  /// Jahr abschliessen: danach lassen sich die Buchungen dieses Jahres nicht
  /// mehr ändern.
  Future<void> closeYear(int year) async {
    final c = closingOf(year).copy();
    final now = DateTime.now().toUtc();
    c.closedAt = now;
    c.history.add(ClosingEvent(action: 'closed', at: now));
    await saveClosing(c);
  }

  /// Abschluss aufheben (bleibt im Verlauf sichtbar).
  Future<void> reopenYear(int year) async {
    final c = closingOf(year).copy();
    c.closedAt = null;
    c.history.add(ClosingEvent(action: 'reopened', at: DateTime.now().toUtc()));
    await saveClosing(c);
  }

  Future<void> saveAsset(Asset a) async {
    a.touch();
    _assets.removeWhere((x) => x.id == a.id);
    _assets.add(a);
    _assets = await store.saveAssets(_assets);
    _changed();
  }

  Future<void> deleteAsset(Asset a) => saveAsset(a.copy()..deleted = true);

  /// Kategorien „Privatbezug“ und „Privateinlage“ anlegen, falls es sie noch
  /// nie gab (gelöschte kommen nicht zurück).
  Future<void> ensurePrivateCategories() async {
    if (_categories.any((c) => c.id == DefaultCategories.privateOutId || c.id == DefaultCategories.privateInId)) return;
    try {
      _categories = await store.saveCategories(mergeById(_categories, DefaultCategories.buildPrivate(english: L10n.isEnglish)));
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Privat-Kategorien anlegen');
    }
  }

  // ---------- Ändern ----------

  /// Buchung neu anlegen oder ändern.
  Future<void> saveEntry(Entry e, {int? previousYear}) async {
    if (isYearClosed(e.year) || (previousYear != null && isYearClosed(previousYear))) {
      throw YearClosedException(isYearClosed(e.year) ? e.year : previousYear!);
    }
    e.touch();
    _entries.removeWhere((x) => x.id == e.id);
    _entries.add(e);
    await _persistEntries({e.year, ?previousYear});
    await device.setLastAccountId(e.accountId);
  }

  /// Löschen = als gelöscht markieren (Grabstein). Rückgängig macht [restoreEntry].
  Future<void> deleteEntry(Entry e) async {
    final x = entry(e.id);
    if (x == null) return;
    if (isYearClosed(x.year)) throw YearClosedException(x.year);
    x.deleted = true;
    x.touch();
    await _persistEntries({x.year});
  }

  Future<void> restoreEntry(Entry e) async {
    final x = entry(e.id);
    if (x == null) return;
    if (isYearClosed(x.year)) throw YearClosedException(x.year);
    x.deleted = false;
    x.touch();
    await _persistEntries({x.year});
  }

  Future<void> _persistEntries(Set<int> years) async {
    try {
      _entries = await store.saveEntries(_entries, years);
    } catch (err, st) {
      ErrorLog.record(err, st, where: 'Buchungen speichern');
      rethrow;
    } finally {
      _changed();
    }
  }

  Future<void> saveAccount(Account a) async {
    a.touch();
    _accounts.removeWhere((x) => x.id == a.id);
    _accounts.add(a);
    _accounts = await store.saveAccounts(_accounts);
    _changed();
  }

  /// Konto löschen geht nur ohne Buchungen, sonst wird es archiviert.
  bool accountInUse(String id) => entries.any((e) => e.accountId == id || e.toAccountId == id);

  Future<void> deleteAccount(Account a) async {
    a.deleted = true;
    await saveAccount(a);
  }

  Future<void> saveCategory(Category c) async {
    c.touch();
    _categories.removeWhere((x) => x.id == c.id);
    _categories.add(c);
    _categories = await store.saveCategories(_categories);
    _changed();
  }

  bool categoryInUse(String id) =>
      entries.any((e) => e.categoryId == id || e.splits.any((s) => s.categoryId == id)) ||
      categories.any((c) => c.parentId == id);

  Future<void> deleteCategory(Category c) async {
    c.deleted = true;
    await saveCategory(c);
  }

  Future<void> saveClient(Client c) async {
    c.touch();
    _clients.removeWhere((x) => x.id == c.id);
    _clients.add(c);
    _clients = await store.saveClients(_clients);
    _changed();
  }

  Future<void> deleteClient(Client c) async {
    final x = c.copy()..deleted = true;
    await saveClient(x);
  }

  Future<void> saveProduct(Product x) async {
    x.touch();
    _products.removeWhere((y) => y.id == x.id);
    _products.add(x);
    _products = await store.saveProducts(_products);
    _changed();
  }

  Future<void> deleteProduct(Product x) => saveProduct(x.copy()..deleted = true);

  Future<void> saveOrder(Order x) async {
    x.touch();
    _orders.removeWhere((y) => y.id == x.id);
    _orders.add(x);
    _orders = await store.saveOrders(_orders);
    _changed();
  }

  Future<void> deleteOrder(Order x) => saveOrder(x.copy()..deleted = true);

  Future<void> saveTask(Task x) async {
    x.touch();
    _tasks.removeWhere((y) => y.id == x.id);
    _tasks.add(x);
    _tasks = await store.saveTasks(_tasks);
    _changed();
  }

  Future<void> deleteTask(Task x) => saveTask(x.copy()..deleted = true);

  Future<void> saveOrderKind(OrderKind k) async {
    k.touch();
    _orderKinds.removeWhere((y) => y.id == k.id);
    _orderKinds.add(k);
    _orderKinds = await store.saveOrderKinds(_orderKinds);
    _changed();
  }

  bool orderKindInUse(String id) => orders.any((o) => o.kind == id);

  /// Vorgeschlagene Auftragsarten anlegen, falls es sie noch nie gab
  /// (gelöschte bleiben als Grabstein und kommen nicht zurück).
  Future<void> ensureOrderKinds({bool notify = true}) async {
    if (_orderKinds.any((k) => k.id.startsWith('kind-'))) return;
    try {
      _orderKinds = await store.saveOrderKinds(mergeById(_orderKinds, OrderKind.defaults(english: L10n.isEnglish)));
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Auftragsarten anlegen');
    }
    if (notify) _changed();
  }

  Future<void> saveBusiness(Business b) async {
    b.touch();
    business = await store.saveBusiness(b);
    _changed();
  }

  /// Mehrere Sammlungen auf einmal übernehmen (Import, Sicherung einspielen).
  /// Pro Eintrag gewinnt die jüngere Fassung, es geht also nichts verloren.
  Future<void> mergeIn({
    List<Entry> entries = const [],
    List<Account> accounts = const [],
    List<Category> categories = const [],
    List<Client> clients = const [],
    List<Product> products = const [],
    List<Order> orders = const [],
    List<Task> tasks = const [],
    List<OrderKind> orderKinds = const [],
    List<Asset> assets = const [],
    List<YearClosing> closings = const [],
    Business? business,
  }) async {
    if (entries.isNotEmpty) {
      _entries = mergeById(_entries, entries);
      _entries = await store.saveEntries(_entries, {for (final e in entries) e.year});
    }
    if (accounts.isNotEmpty) _accounts = await store.saveAccounts(mergeById(_accounts, accounts));
    if (categories.isNotEmpty) _categories = await store.saveCategories(mergeById(_categories, categories));
    if (clients.isNotEmpty) _clients = await store.saveClients(mergeById(_clients, clients));
    if (products.isNotEmpty) _products = await store.saveProducts(mergeById(_products, products));
    if (orders.isNotEmpty) _orders = await store.saveOrders(mergeById(_orders, orders));
    if (tasks.isNotEmpty) _tasks = await store.saveTasks(mergeById(_tasks, tasks));
    if (orderKinds.isNotEmpty) _orderKinds = await store.saveOrderKinds(mergeById(_orderKinds, orderKinds));
    if (assets.isNotEmpty) _assets = await store.saveAssets(mergeById(_assets, assets));
    if (closings.isNotEmpty) _closings = await store.saveClosings(mergeById(_closings, closings));
    if (orders.isNotEmpty) {
      await ensureOrderKinds(notify: false);
      await _migrateOrderKinds();
    }
    if (business != null) {
      if (business.updatedAt.isAfter(this.business.updatedAt)) this.business = await store.saveBusiness(business);
    }
    _changed();
  }

  /// Einrichtung abschliessen.
  Future<void> finishSetup() async {
    await store.markInitialized();
    await ensureOrderKinds(notify: false);
    await ensurePrivateCategories();
    await device.setSetupDone();
    dataInitialized = true;
    _changed();
  }

  /// Datei als Beleg in den Datenordner kopieren. Gibt den Beleg zurück.
  Future<Attachment> addAttachmentFile({
    required String sourcePath,
    required String name,
    required int year,
    String kind = 'receipt',
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    return addAttachmentBytes(bytes: bytes, name: name, year: year, kind: kind);
  }

  Future<Attachment> addAttachmentBytes({
    required List<int> bytes,
    required String name,
    required int year,
    String kind = 'receipt',
    String? id,
  }) async {
    final aid = id ?? newId();
    var ext = p.extension(name).toLowerCase();
    if (ext.isEmpty || ext.length > 6) ext = '.bin';
    final rel = 'belege/$year/$aid$ext';
    await store.putFile(rel, bytes);
    return Attachment(id: aid, file: rel, name: name, kind: kind, size: bytes.length);
  }

  /// Vollständiger Pfad einer Datei im Datenordner.
  String dataPath(String relative) => store.pathOf(relative);

  Future<void> setThemeMode(ThemeMode m) async {
    await device.setThemeMode(m);
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage? l) async {
    await device.setLanguage(l);
    L10n.set(l ?? AppLanguage.system);
    notifyListeners();
  }
}

/// Macht den [ContiState] überall verfügbar: `ContiScope.of(context)`.
class ContiScope extends InheritedNotifier<ContiState> {
  const ContiScope({super.key, required ContiState state, required super.child}) : super(notifier: state);

  static ContiState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ContiScope>()!.notifier!;

  /// Ohne Abhängigkeit (für Knöpfe, die nur etwas auslösen).
  static ContiState read(BuildContext context) => context.getInheritedWidgetOfExactType<ContiScope>()!.notifier!;
}

/// Buchung in einem abgeschlossenen Jahr: lässt sich nicht mehr ändern.
class YearClosedException implements Exception {
  YearClosedException(this.year);

  final int year;

  String get message => tr(
    'Das Jahr $year ist abgeschlossen. Erfasse eine Korrektur im laufenden Jahr.',
    'The year $year is closed. Record a correction in the current year.',
  );

  @override
  String toString() => message;
}
