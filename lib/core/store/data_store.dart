import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/account.dart';
import '../model/business.dart';
import '../model/category.dart';
import '../model/closing.dart';
import '../model/crm.dart';
import '../model/entry.dart';
import '../model/synced.dart';
import 'json_file.dart';

/// Alles, was im Datenordner liegt.
class DataSnapshot {
  DataSnapshot({
    required this.business,
    required this.entries,
    required this.accounts,
    required this.categories,
    required this.clients,
    required this.products,
    required this.orders,
    required this.tasks,
    required this.orderKinds,
    required this.assets,
    required this.closings,
    required this.initialized,
  });

  Business business;
  List<Entry> entries;
  List<Account> accounts;
  List<Category> categories;
  List<Client> clients;
  List<Product> products;
  List<Order> orders;
  List<Task> tasks;
  List<OrderKind> orderKinds;
  List<Asset> assets;
  List<YearClosing> closings;

  /// Gibt es die Markierungsdatei (der Ordner wurde schon einmal eingerichtet)?
  bool initialized;
}

/// Der Datenordner von Conti. Dieser Ordner wird später (Paket 2) mit
/// Dropbox abgeglichen. Darum gilt:
/// - jede Sammlung ist eine eigene Datei, Buchungen eine Datei pro Jahr,
/// - jeder Eintrag hat eine ID und eine Änderungszeit,
/// - beim Speichern wird mit dem Stand auf der Festplatte zusammengeführt
///   (pro Eintrag gewinnt die jüngere Änderung), damit nie etwas verloren geht,
///   das inzwischen ein anderes Gerät geschrieben hat.
///
/// Aufbau (Datei- und Ordnernamen werden nie übersetzt):
/// ```
/// conti.json              Markierung (Format, Version)
/// geschaeft.json          Mein Geschäft
/// konten.json, kategorien.json, kunden.json, produkte.json,
/// auftraege.json, aufgaben.json, auftragsarten.json
/// anlagen.json            Anlagen ohne Buchung (Abschreibungen)
/// abschluesse.json        Jahresabschlüsse (ein Eintrag pro Jahr)
/// buchungen/<jahr>.json   Buchungen eines Jahres
/// belege/<jahr>/<id>.<endung>   Belege (werden nie verändert)
/// bilder/                 Logo, Unterschrift
/// ```
class DataStore {
  DataStore(this.root);

  final String root;

  /// Immer nur ein Schreibvorgang auf einmal (Speichern und Abgleich lesen,
  /// führen zusammen und schreiben, ohne dass etwas dazwischenkommt).
  Future<void>? _last;

  Future<T> withLock<T>(Future<T> Function() job) async {
    final previous = _last;
    final done = Completer<void>();
    _last = done.future;
    try {
      if (previous != null) await previous;
      return await job();
    } finally {
      done.complete();
    }
  }

  static const marker = 'conti.json';

  String pathOf(String relative) => p.join(root, relative);

  JsonFile _file(String name) => JsonFile(p.join(root, name));

  Future<DataSnapshot> load() async {
    final initialized = await File(p.join(root, marker)).exists();
    final b = await _file('geschaeft.json').read();
    return DataSnapshot(
      business: b.isEmpty ? Business() : Business.fromJson(b),
      entries: await _loadEntries(),
      accounts: await _loadList('konten.json', Account.fromJson),
      categories: await _loadList('kategorien.json', Category.fromJson),
      clients: await _loadList('kunden.json', Client.fromJson),
      products: await _loadList('produkte.json', Product.fromJson),
      orders: await _loadList('auftraege.json', Order.fromJson),
      tasks: await _loadList('aufgaben.json', Task.fromJson),
      orderKinds: await _loadList('auftragsarten.json', OrderKind.fromJson),
      assets: await _loadList('anlagen.json', Asset.fromJson),
      closings: await _loadList('abschluesse.json', YearClosing.fromJson),
      initialized: initialized,
    );
  }

  /// Markierungsdatei schreiben (beim Einrichten).
  Future<void> markInitialized() => withLock(() async {
    if (await File(p.join(root, marker)).exists()) return;
    await _file(marker).write({'format': 'conti-daten', 'version': 1, 'created': DateTime.now().toUtc().toIso8601String()});
  });

  Future<List<T>> _loadList<T>(String name, T Function(Map<String, dynamic>) fromJson) async {
    final j = await _file(name).read();
    return [for (final m in j.maps('items')) fromJson(m)];
  }

  Future<List<Entry>> _loadEntries() async {
    final dir = Directory(p.join(root, 'buchungen'));
    if (!await dir.exists()) return [];
    var out = <Entry>[];
    await for (final f in dir.list()) {
      if (f is! File || !RegExp(r'\d{4}\.json$').hasMatch(f.path)) continue;
      final j = await JsonFile(f.path).read();
      // Wurde eine Buchung in ein anderes Jahr verschoben, kann sie kurz in
      // zwei Dateien stehen. Dann gilt die jüngere Fassung.
      out = mergeById(out, [for (final m in j.maps('entries')) Entry.fromJson(m)]);
    }
    return out;
  }

  /// Eine Sammlung speichern, vorher mit der Festplatte zusammenführen.
  /// Gibt die zusammengeführte Liste zurück.
  Future<List<T>> saveList<T extends Synced>(
    String name,
    String format,
    List<T> items,
    T Function(Map<String, dynamic>) fromJson,
  ) => withLock(() async {
    final f = _file(name);
    final disk = [for (final m in (await f.read()).maps('items')) fromJson(m)];
    final merged = mergeById(items, disk);
    await f.write({
      'format': format,
      'version': 1,
      'items': [for (final x in merged) x.toJson()],
    });
    return merged;
  });

  Future<List<Account>> saveAccounts(List<Account> a) => saveList('konten.json', 'conti-konten', a, Account.fromJson);
  Future<List<Category>> saveCategories(List<Category> c) =>
      saveList('kategorien.json', 'conti-kategorien', c, Category.fromJson);
  Future<List<Client>> saveClients(List<Client> c) => saveList('kunden.json', 'conti-kunden', c, Client.fromJson);
  Future<List<Product>> saveProducts(List<Product> x) =>
      saveList('produkte.json', 'conti-produkte', x, Product.fromJson);
  Future<List<Order>> saveOrders(List<Order> x) => saveList('auftraege.json', 'conti-auftraege', x, Order.fromJson);
  Future<List<Task>> saveTasks(List<Task> x) => saveList('aufgaben.json', 'conti-aufgaben', x, Task.fromJson);
  Future<List<OrderKind>> saveOrderKinds(List<OrderKind> x) =>
      saveList('auftragsarten.json', 'conti-auftragsarten', x, OrderKind.fromJson);
  Future<List<Asset>> saveAssets(List<Asset> x) => saveList('anlagen.json', 'conti-anlagen', x, Asset.fromJson);
  Future<List<YearClosing>> saveClosings(List<YearClosing> x) =>
      saveList('abschluesse.json', 'conti-abschluesse', x, YearClosing.fromJson);

  /// Buchungen der Jahre [years] speichern (jedes Jahr eine Datei).
  /// Verschiebt man eine Buchung in ein anderes Jahr, müssen beide Jahre
  /// gespeichert werden: Im alten bleibt ein Grabstein unter derselben ID
  /// liegen, der aber älter ist und deshalb beim Laden nicht gewinnt.
  Future<List<Entry>> saveEntries(List<Entry> all, Set<int> years) => withLock(() async {
    final byId = {for (final e in all) e.id: e};
    for (final year in years) {
      final f = JsonFile(p.join(root, 'buchungen', '$year.json'));
      final disk = [for (final m in (await f.read()).maps('entries')) Entry.fromJson(m)];
      final mine = all.where((e) => e.year == year).toList();
      // Was auf der Festplatte in diesem Jahr liegt, inzwischen aber in einem
      // anderen Jahr steht: dort als verschoben vermerken (nicht mehr hier).
      final movedAway = disk.where((d) => byId[d.id] != null && byId[d.id]!.year != year).map((d) => d.id).toSet();
      final merged = mergeById(mine, disk.where((d) => !movedAway.contains(d.id))).where((e) => e.year == year).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      await f.write({
        'format': 'conti-buchungen',
        'version': 1,
        'year': year,
        'entries': [for (final e in merged) e.toJson()],
      });
      for (final e in merged) {
        final cur = byId[e.id];
        if (cur == null || e.updatedAt.isAfter(cur.updatedAt)) byId[e.id] = e;
      }
    }
    return byId.values.toList();
  });

  Future<Business> saveBusiness(Business b) => withLock(() async {
    final f = _file('geschaeft.json');
    final diskJson = await f.read();
    if (diskJson.isNotEmpty) {
      final disk = Business.fromJson(diskJson);
      if (disk.updatedAt.isAfter(b.updatedAt)) return disk;
    }
    await f.write(b.toJson());
    return b;
  });

  /// Datei in den Datenordner legen (z. B. einen Beleg). [relative]: Ziel
  /// relativ zum Datenordner.
  Future<File> putFile(String relative, List<int> bytes) => withLock(() => writeBytesUnlocked(relative, bytes));

  /// Datei schreiben, ohne die Sperre zu nehmen (nur innerhalb von [withLock]).
  Future<File> writeBytesUnlocked(String relative, List<int> bytes) async {
    final f = File(pathOf(relative));
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
    return f;
  }
}
