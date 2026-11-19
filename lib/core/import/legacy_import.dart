import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../conti_state.dart';
import '../dates.dart';
import '../model/business.dart';
import '../model/category.dart';
import '../model/crm.dart';
import '../model/entry.dart';
import '../model/synced.dart';
import '../money.dart';
import '../swiss.dart';

/// Ein Bild aus der alten Datei (Logo, Unterschrift).
class ImportedImage {
  ImportedImage(this.bytes, this.extension);
  final List<int> bytes;
  final String extension;
}

/// Ein Beleg, dessen Datei noch gesucht werden muss.
class PendingAttachment {
  PendingAttachment({
    required this.entryId,
    required this.id,
    required this.storedFileName,
    required this.originalName,
    required this.kind,
    required this.year,
  });
  final String entryId;
  final String id;

  /// Pfad in der alten App, relativ zu ihrem Belegordner (z. B. „2026/x.pdf“).
  final String storedFileName;
  final String originalName;
  final String kind;
  final int year;
}

/// Was aus der Datei der früheren Buchhaltungs-App gelesen wurde.
class LegacyData {
  LegacyData({
    required this.entries,
    required this.newCategories,
    required this.clients,
    required this.products,
    required this.orders,
    required this.tasks,
    required this.business,
    required this.attachments,
    required this.bankName,
    this.invoicePaths = const {},
    this.logo,
    this.signature,
  });

  final List<Entry> entries;

  /// Kategorien, die es in Conti noch nicht gibt und neu angelegt werden.
  final List<Category> newCategories;
  final List<Client> clients;
  final List<Product> products;
  final List<Order> orders;
  final List<Task> tasks;
  final Business business;
  final List<PendingAttachment> attachments;

  /// Pfade der Rechnungs-PDFs der früheren App (Auftrags-ID → Pfad).
  final Map<String, String> invoicePaths;
  final String bankName;
  final ImportedImage? logo;
  final ImportedImage? signature;

  Map<int, (int income, int expense, int count)> get yearSummary {
    final m = <int, (int, int, int)>{};
    for (final e in entries) {
      final (i, x, n) = m[e.year] ?? (0, 0, 0);
      m[e.year] = (
        i + (e.kind == EntryKind.income ? e.amount : 0),
        x + (e.kind == EntryKind.expense ? e.amount : 0),
        n + 1,
      );
    }
    return m;
  }
}

/// Ergebnis nach dem Übernehmen.
class LegacyImportResult {
  LegacyImportResult({required this.entries, required this.attachmentsFound, required this.attachmentsMissing});
  final int entries;
  final int attachmentsFound;
  final List<String> attachmentsMissing;
}

/// Liest die Datendatei (JSON) der früheren Buchhaltungs-App und übernimmt
/// sie in Conti. Die IDs bleiben erhalten: Wer zweimal importiert, bekommt
/// nichts doppelt, und in Conti Geändertes (jünger) bleibt bestehen.
class LegacyImport {
  LegacyImport._();

  /// Sieht die Datei aus wie eine Datei der früheren App?
  static bool looksLike(Map<String, dynamic> j) =>
      j['entries'] is List && (j['company'] is Map || j['clients'] is List || j['invoiceSettings'] is Map);

  static LegacyData parse(Map<String, dynamic> j, {required List<Category> existing}) {
    final cats = [...existing];
    final created = <Category>[];
    final now = DateTime.now().toUtc();

    // Kategorie nach Name suchen oder neu anlegen. Die ID ergibt sich aus dem
    // Namen, damit ein zweiter Import dieselbe Kategorie trifft.
    Category categoryFor(String name, bool income, {String? parentId}) {
      final n = name.trim().isEmpty ? (income ? 'Sonstiger Ertrag' : 'Sonstiger Aufwand') : name.trim();
      final hit = cats
          .where((c) => !c.deleted && c.income == income && c.parentId == parentId && c.name.toLowerCase() == n.toLowerCase())
          .firstOrNull;
      if (hit != null) return hit;
      final key = '${income ? 'in' : 'ex'}|${parentId ?? ''}|${n.toLowerCase()}';
      final id = 'imp-${sha1.convert(utf8.encode(key)).toString().substring(0, 12)}';
      final c = Category(id: id, name: n, income: income, parentId: parentId, order: 1000 + created.length, updatedAt: now);
      cats.add(c);
      created.add(c);
      return c;
    }

    final entries = <Entry>[];
    final pending = <PendingAttachment>[];
    for (final e in j.maps('entries')) {
      final income = e.str('type') == 'income';
      final main = categoryFor(e.str('category'), income);
      final items = e.maps('expenseItems');
      String? categoryId = main.id;
      final splits = <EntrySplit>[];
      if (items.length == 1) {
        final sub = items.first.str('category').trim();
        if (sub.isNotEmpty && sub.toLowerCase() != main.name.toLowerCase()) {
          categoryId = categoryFor(sub, income, parentId: main.id).id;
        }
      } else if (items.length > 1) {
        categoryId = null;
        for (final it in items) {
          final sub = it.str('category').trim();
          final c = sub.isEmpty || sub.toLowerCase() == main.name.toLowerCase()
              ? main
              : categoryFor(sub, income, parentId: main.id);
          splits.add(EntrySplit(categoryId: c.id, amount: Money.fromFrancs(it.dbl('amount')), text: it.str('description')));
        }
      }
      final date = Day.parse(e.strOrNull('date')) ?? Day.today();
      final id = e.str('id', newId());
      final dep = e['depreciation'];
      for (final a in e.maps('attachments')) {
        final stored = a.str('storedFileName');
        if (stored.isEmpty) continue;
        pending.add(
          PendingAttachment(
            entryId: id,
            id: a.str('id', newId()),
            storedFileName: stored,
            originalName: a.str('originalFileName', p.basename(stored)),
            kind: a.str('kind', 'receipt') == 'invoice' ? 'invoice' : 'receipt',
            year: int.tryParse(a.str('year')) ?? date.year,
          ),
        );
      }
      entries.add(
        Entry(
          id: id,
          date: date,
          kind: income ? EntryKind.income : EntryKind.expense,
          amount: Money.fromFrancs(e.dbl('amount')).abs(),
          text: e.str('description'),
          categoryId: categoryId,
          splits: splits,
          number: e.str('transactionNumber'),
          clientId: e.strOrNull('clientId'),
          orderId: e.strOrNull('sourceOrderId'),
          notes: e.str('attachmentDescription'),
          excludeFromReports: e.flag('excludeFromReports'),
          asset: dep is Map && dep['enabled'] == true ? Map<String, dynamic>.from(dep) : null,
          createdAt: e.stamp('createdAt'),
          updatedAt: e.stamp('updatedAt'),
        ),
      );
    }

    final clients = [
      for (final c in j.maps('clients'))
        () {
          final (street, number) = splitStreet(c.str('street'));
          return Client(
            id: c.str('id', newId()),
            firstName: c.str('firstName'),
            lastName: c.str('lastName'),
            company: c.str('company'),
            email: c.str('email'),
            phone: c.str('phone'),
            street: street,
            houseNumber: number,
            zip: c.str('zip'),
            city: c.str('city'),
            country: _countryCode(c.str('country')),
            notes: c.str('notes'),
            createdAt: c.stamp('createdAt'),
            updatedAt: c.stamp('updatedAt'),
          );
        }(),
    ];

    PriceUnit unitOf(String s) => s == 'hourly' ? PriceUnit.hour : PriceUnit.flat;

    final products = [
      for (final x in j.maps('products'))
        Product(
          id: x.str('id', newId()),
          name: x.str('name'),
          description: x.str('description'),
          group: x.str('category'),
          price: Money.fromFrancs(x.dbl('price')),
          unit: unitOf(x.str('pricingType')),
          createdAt: x.stamp('createdAt'),
          updatedAt: x.stamp('updatedAt'),
        ),
    ];

    final orders = [
      for (final o in j.maps('orders'))
        Order(
          id: o.str('id', newId()),
          number: o.str('orderNumber'),
          title: o.str('title'),
          kind: o.maps('items').firstOrNull?.str('category') ?? '',
          clientId: o.strOrNull('clientId'),
          status: _status(o.str('status')),
          items: [
            for (final i in o.maps('items'))
              OrderItem(
                id: i.str('id', newId()),
                productId: i.strOrNull('productId'),
                name: i.str('name'),
                description: i.str('description'),
                unit: unitOf(i.str('pricingType')),
                quantity: i.dbl('quantity', 1),
                unitPrice: Money.fromFrancs(i.dbl('unitPrice')),
              ),
          ],
          invoiceNumber: o.str('invoiceNumber'),
          invoicedAt: Day.parse(o.strOrNull('invoicedAt')),
          paidAt: Day.parse(o.strOrNull('paidAt')),
          paidEntryId: o.strOrNull('paidEntryId'),
          notes: o.str('notes'),
          createdAt: o.stamp('createdAt'),
          updatedAt: o.stamp('updatedAt'),
        ),
    ];

    final tasks = [
      for (final t in j.maps('tasks'))
        Task(
          id: t.str('id', newId()),
          title: t.str('title'),
          clientId: t.strOrNull('clientId'),
          due: Day.parse(t.strOrNull('dueDate')),
          notes: t.str('notes'),
          done: t.flag('completed'),
          doneAt: t.strOrNull('completedAt') == null ? null : t.stamp('completedAt'),
          createdAt: t.stamp('createdAt'),
          updatedAt: t.stamp('updatedAt'),
        ),
    ];

    final company = j['company'] is Map ? Map<String, dynamic>.from(j['company'] as Map) : <String, dynamic>{};
    final inv = j['invoiceSettings'] is Map
        ? Map<String, dynamic>.from(j['invoiceSettings'] as Map)
        : <String, dynamic>{};
    String placeholders(String s) => s
        .replaceAll('{deinName}', '{name}')
        .replaceAll('{invoiceNumber}', '{rechnungsnummer}')
        .replaceAll('{companyName}', '{firma}');
    final (street, number) = splitStreet(company.str('street'));
    final d = InvoiceSettings();
    final rules = j['taskSettings'] is Map ? (j['taskSettings'] as Map<String, dynamic>).maps('deadlineRules') : const [];
    final business = Business(
      ownerName: company.str('ownerName'),
      companyName: company.str('companyName'),
      street: street,
      houseNumber: number,
      zip: company.str('zip'),
      city: company.str('city'),
      country: _countryCode(company.str('country', 'CH')),
      email: company.str('email'),
      phone: company.str('phone'),
      website: company.str('website'),
      iban: Iban.pretty(inv.str('iban', company.str('iban'))),
      bankName: inv.str('bankName', company.str('bankName')),
      bic: inv.str('bic', company.str('bic')),
      vatNumber: company.str('vatNumber'),
      vatLiable: company.str('vatNumber').isNotEmpty,
      invoice: InvoiceSettings(
        invoicePrefix: inv.str('invoicePrefix', company.str('invoicePrefix', d.invoicePrefix)),
        paymentTermsDays: inv.integer('paymentTermsDays', company.integer('paymentTermsDays', d.paymentTermsDays)),
        font: inv.str('invoiceFont', d.font),
        accentColor: inv.str('accentColor', d.accentColor),
        title: inv.str('invoiceTitle', d.title),
        dueDateTitle: inv.str('dueDateTitle', d.dueDateTitle),
        totalTitle: inv.str('totalTitle', d.totalTitle),
        footerNote: placeholders(inv.str('footerNote', d.footerNote)),
        qrMessage: placeholders(inv.str('qrMessageTemplate', d.qrMessage)),
        qrCreditorName: switch (inv.str('qrCreditorNameSource')) {
          'company' => 'company',
          'custom' => 'custom',
          _ => 'owner',
        },
        qrCreditorCustomName: inv.str('qrCreditorCustomName'),
      ),
      deadlineRules: rules.isEmpty ? null : [for (final r in rules) DeadlineRule.fromJson(r)],
      updatedAt: now,
    );

    return LegacyData(
      entries: entries,
      newCategories: created,
      clients: clients,
      products: products,
      orders: orders,
      tasks: tasks,
      business: business,
      attachments: pending,
      invoicePaths: {
        for (final o in j.maps('orders'))
          if (o.str('invoiceFilePath').isNotEmpty) o.str('id'): o.str('invoiceFilePath'),
      },
      bankName: business.bankName,
      logo: _dataUrl(company.str('logoDataUrl')) ?? _dataUrl(inv.str('invoiceLogoDataUrl')),
      signature: _dataUrl(inv.str('signatureDataUrl')),
    );
  }

  /// In Conti übernehmen. [accountId]: Konto für alle Buchungen (die alte App
  /// kannte keine Konten). [receiptsFolder]: Ordner der alten App mit den
  /// Belegen (null = Belege nicht übernehmen).
  static Future<LegacyImportResult> apply(
    ContiState state,
    LegacyData data, {
    required String accountId,
    String? receiptsFolder,
    bool takeBusiness = true,
  }) async {
    final byId = {for (final e in data.entries) e.id: e};
    for (final e in data.entries) {
      e.accountId = accountId;
    }
    var found = 0;
    final missing = <String>[];
    if (receiptsFolder != null) {
      final index = await _indexFolder(receiptsFolder);
      for (final a in data.attachments) {
        final src = _find(receiptsFolder, a.storedFileName, index);
        final entry = byId[a.entryId];
        if (src == null || entry == null) {
          missing.add(a.originalName);
          continue;
        }
        final att = await state.addAttachmentBytes(
          bytes: await src.readAsBytes(),
          name: a.originalName,
          year: a.year,
          kind: a.kind,
          id: a.id,
        );
        entry.attachments.removeWhere((x) => x.id == att.id);
        entry.attachments.add(att);
        found++;
      }
    }

    Business? business;
    if (takeBusiness) {
      business = data.business.copy();
      if (data.logo != null) {
        final rel = 'bilder/logo${data.logo!.extension}';
        await state.store.putFile(rel, data.logo!.bytes);
        business.logoFile = rel;
      }
      if (data.signature != null) {
        final rel = 'bilder/unterschrift${data.signature!.extension}';
        await state.store.putFile(rel, data.signature!.bytes);
        business.signatureFile = rel;
      }
      // Kanton und MWST hat die alte App nicht: bestehende Angaben behalten.
      business.canton = state.business.canton;
      if (state.business.vatLiable) business.vatLiable = true;
      business.updatedAt = DateTime.now().toUtc();
    }

    await state.mergeIn(
      entries: data.entries,
      categories: data.newCategories,
      clients: data.clients,
      products: data.products,
      orders: data.orders,
      tasks: data.tasks,
      business: business,
    );
    // Rechnungs-PDFs der früheren App übernehmen, wenn sie auf diesem Gerät
    // liegen (am alten Ort oder im gewählten Ordner). Nur bei Aufträgen, die
    // in Conti noch keine Rechnungsdatei haben.
    final index = receiptsFolder == null ? <String, String>{} : await _indexFolder(p.dirname(receiptsFolder));
    for (final entry in data.invoicePaths.entries) {
      final o = state.order(entry.key);
      if (o == null || o.invoiceFile.isNotEmpty || o.invoiceNumber.isEmpty) continue;
      final name = entry.value.split(RegExp(r'[\\/]')).last;
      File? src = File(entry.value);
      if (!await src.exists()) {
        final hit = index[name.toLowerCase()];
        src = hit == null ? null : File(hit);
      }
      if (src == null) continue;
      final year = (o.invoicedAt ?? DateTime.now()).year;
      final rel = 'rechnungen/$year/${o.invoiceNumber.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')}.pdf';
      try {
        await state.store.putFile(rel, await src.readAsBytes());
        await state.saveOrder(o.copy()..invoiceFile = rel);
      } catch (_) {}
    }
    return LegacyImportResult(entries: data.entries.length, attachmentsFound: found, attachmentsMissing: missing);
  }

  /// Alle Dateien im Ordner (Dateiname klein → Pfad), für die Suche nach Namen.
  static Future<Map<String, String>> _indexFolder(String folder) async {
    final m = <String, String>{};
    try {
      await for (final f in Directory(folder).list(recursive: true, followLinks: false)) {
        if (f is File) m.putIfAbsent(p.basename(f.path).toLowerCase(), () => f.path);
      }
    } catch (_) {}
    return m;
  }

  static File? _find(String folder, String stored, Map<String, String> index) {
    final parts = stored.split(RegExp(r'[\\/]'));
    final direct = File(p.joinAll([folder, ...parts]));
    if (direct.existsSync()) return direct;
    final byName = index[parts.last.toLowerCase()];
    return byName == null ? null : File(byName);
  }

  static ImportedImage? _dataUrl(String s) {
    final m = RegExp(r'^data:([^;,]+)(;base64)?,(.*)$', dotAll: true).firstMatch(s);
    if (m == null) return null;
    final mime = m.group(1)!;
    final ext = switch (mime) {
      'image/svg+xml' => '.svg',
      'image/png' => '.png',
      'image/jpeg' => '.jpg',
      'image/webp' => '.webp',
      _ => '',
    };
    if (ext.isEmpty) return null;
    try {
      final bytes = m.group(2) != null ? base64Decode(m.group(3)!) : utf8.encode(Uri.decodeComponent(m.group(3)!));
      return ImportedImage(bytes, ext);
    } catch (_) {
      return null;
    }
  }

  static String _countryCode(String s) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty || t == 'ch' || t.startsWith('schweiz') || t == 'switzerland' || t == 'suisse' || t == 'svizzera') {
      return 'CH';
    }
    if (t == 'li' || t.startsWith('liechtenstein')) return 'LI';
    if (t == 'de' || t.startsWith('deutschland') || t == 'germany') return 'DE';
    if (t == 'at' || t.startsWith('österreich') || t == 'austria') return 'AT';
    if (t == 'fr' || t.startsWith('frankreich') || t == 'france') return 'FR';
    if (t == 'it' || t.startsWith('italien') || t == 'italy') return 'IT';
    return s.length == 2 ? s.toUpperCase() : s;
  }

  static OrderStatus _status(String s) => switch (s) {
    'paid' => OrderStatus.paid,
    'invoiced' => OrderStatus.invoiced,
    'done' || 'completed' => OrderStatus.done,
    'in-progress' || 'inProgress' || 'active' => OrderStatus.inProgress,
    'cancelled' || 'canceled' => OrderStatus.cancelled,
    _ => OrderStatus.open,
  };
}
