import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/error_log.dart';
import '../app/l10n.dart';
import 'dates.dart';
import 'device_settings.dart';
import 'model/account.dart';
import 'model/business.dart';
import 'model/category.dart';
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
  bool dataInitialized = false;

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
    dataInitialized = s.initialized;
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

  int incomeOf(int year, {int? month}) => _reportEntries(year)
      .where((e) => e.kind == EntryKind.income && (month == null || e.date.month == month))
      .fold(0, (s, e) => s + e.amount);

  int expensesOf(int year, {int? month}) => _reportEntries(year)
      .where((e) => e.kind == EntryKind.expense && (month == null || e.date.month == month))
      .fold(0, (s, e) => s + e.amount);

  /// Summen pro Oberkategorie (Unterkategorien zählen zur Oberkategorie).
  Map<String, int> totalsByTopCategory(int year, {required bool income}) {
    final out = <String, int>{};
    for (final e in _reportEntries(year).where((e) => e.kind == (income ? EntryKind.income : EntryKind.expense))) {
      e.amountsByCategory.forEach((catId, amount) {
        final c = category(catId);
        final top = c?.parentId != null && category(c!.parentId) != null ? c.parentId! : (c?.id ?? '');
        out[top] = (out[top] ?? 0) + amount;
      });
    }
    return out;
  }

  // ---------- Ändern ----------

  /// Buchung neu anlegen oder ändern.
  Future<void> saveEntry(Entry e, {int? previousYear}) async {
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
    x.deleted = true;
    x.touch();
    await _persistEntries({x.year});
  }

  Future<void> restoreEntry(Entry e) async {
    final x = entry(e.id);
    if (x == null) return;
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
      notifyListeners();
    }
  }

  Future<void> saveAccount(Account a) async {
    a.touch();
    _accounts.removeWhere((x) => x.id == a.id);
    _accounts.add(a);
    _accounts = await store.saveAccounts(_accounts);
    notifyListeners();
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
    notifyListeners();
  }

  bool categoryInUse(String id) =>
      entries.any((e) => e.categoryId == id || e.splits.any((s) => s.categoryId == id)) ||
      categories.any((c) => c.parentId == id);

  Future<void> deleteCategory(Category c) async {
    c.deleted = true;
    await saveCategory(c);
  }

  Future<void> saveBusiness(Business b) async {
    b.touch();
    business = await store.saveBusiness(b);
    notifyListeners();
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
    if (business != null) {
      if (business.updatedAt.isAfter(this.business.updatedAt)) this.business = await store.saveBusiness(business);
    }
    notifyListeners();
  }

  /// Einrichtung abschliessen.
  Future<void> finishSetup() async {
    await store.markInitialized();
    await device.setSetupDone();
    dataInitialized = true;
    notifyListeners();
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
