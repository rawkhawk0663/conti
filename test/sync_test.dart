import 'dart:io';

import 'package:conti/core/conti_state.dart';
import 'package:conti/core/model/account.dart';
import 'package:conti/core/model/business.dart';
import 'package:conti/core/model/category.dart';
import 'package:conti/core/model/entry.dart';
import 'package:conti/core/store/json_file.dart';
import 'package:conti/core/sync/dropbox_api.dart';
import 'package:conti/core/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Dropbox im Arbeitsspeicher.
class MemoryCloud implements CloudApi {
  final files = <String, (List<int>, int)>{};
  int _rev = 0;
  int downloads = 0;
  int uploads = 0;

  @override
  Future<List<RemoteEntry>> listAll() async => [for (final e in files.entries) RemoteEntry(path: e.key, rev: 'r${e.value.$2}')];

  @override
  Future<List<int>> download(RemoteEntry e) async {
    downloads++;
    return files[e.path]!.$1;
  }

  @override
  Future<RemoteEntry> upload(String path, List<int> bytes) async {
    uploads++;
    files[path] = (List.of(bytes), ++_rev);
    return RemoteEntry(path: path, rev: 'r$_rev');
  }
}

/// Ein Gerät: eigener Ordner, eigener Stand des Abgleichs.
class Device {
  Device(this.dir, this.cloud) : state = ContiState(dir);
  final String dir;
  final MemoryCloud cloud;
  final ContiState state;

  Future<SyncReport> sync() async {
    final r = await SyncEngine(
      api: cloud,
      store: state.store,
      stateFile: JsonFile(p.join(dir, 'abgleich_dropbox.json')),
    ).run();
    if (r.changedLocal) await state.reload();
    return r;
  }
}

void main() {
  late Directory tmp;
  late MemoryCloud cloud;
  late Device a, b;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('conti-sync-');
    cloud = MemoryCloud();
    a = Device(p.join(tmp.path, 'surface'), cloud);
    b = Device(p.join(tmp.path, 'handy'), cloud);
    await a.state.load();
    await b.state.load();
  });
  tearDown(() => tmp.delete(recursive: true));

  Entry e(String id, int amount, {DateTime? date, String text = ''}) => Entry(
    id: id,
    date: date ?? DateTime(2026, 5, 1),
    kind: EntryKind.expense,
    amount: amount,
    text: text,
    accountId: 'bank',
  );

  test('neues Gerät holt alles, auch Belege', () async {
    await a.state.mergeIn(categories: DefaultCategories.build(english: false));
    await a.state.saveAccount(Account(id: 'bank', name: 'Bank', openingDate: DateTime(2026, 1, 1)));
    await a.state.saveBusiness(Business(ownerName: 'Max Beispiel', iban: 'CH93 0076 2011 6238 5295 7'));
    final att = await a.state.addAttachmentBytes(bytes: [1, 2, 3], name: 'Quittung.jpg', year: 2026);
    await a.state.saveEntry(e('x', 3680, text: 'Saiten')..attachments.add(att));
    await a.state.finishSetup();

    final r1 = await a.sync();
    expect(r1.failed, isEmpty);
    expect(cloud.files.keys, containsAll(['conti.json', 'geschaeft.json', 'konten.json', 'kategorien.json', 'buchungen/2026.json', att.file]));

    final r2 = await b.sync();
    expect(r2.changedLocal, isTrue);
    expect(b.state.dataInitialized, isTrue);
    expect(b.state.entries.single.text, 'Saiten');
    expect(b.state.business.ownerName, 'Max Beispiel');
    expect(b.state.accounts.single.name, 'Bank');
    expect(File(b.state.dataPath(att.file)).readAsBytesSync(), [1, 2, 3]);

    // Nichts geändert: nichts mehr hoch- oder herunterladen.
    final before = (cloud.uploads, cloud.downloads);
    final r3 = await a.sync();
    final r4 = await b.sync();
    expect((cloud.uploads, cloud.downloads), before);
    expect(r3.changedLocal || r4.changedLocal, isFalse);
  });

  test('beide Geräte erfassen ohne Netz: nichts geht verloren', () async {
    await a.state.saveEntry(e('surface-1', 100));
    await a.sync();
    await b.sync();
    // Beide offline im selben Jahr
    await a.state.saveEntry(e('surface-2', 200));
    await b.state.saveEntry(e('handy-1', 300));
    await b.state.saveEntry(e('handy-2', 400, date: DateTime(2025, 12, 31)));
    await a.sync();
    await b.sync();
    await a.sync();
    final ids = {'surface-1', 'surface-2', 'handy-1', 'handy-2'};
    expect(a.state.entries.map((x) => x.id).toSet(), ids);
    expect(b.state.entries.map((x) => x.id).toSet(), ids);
  });

  test('gleiche Buchung auf zwei Geräten geändert: die jüngere gewinnt, Löschen kommt an', () async {
    await a.state.saveEntry(e('k', 100, text: 'alt'));
    await a.sync();
    await b.sync();
    final onA = a.state.entry('k')!.copy()..text = 'vom Surface';
    await a.state.saveEntry(onA);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final onB = b.state.entry('k')!.copy()..text = 'vom Handy';
    await b.state.saveEntry(onB);
    await a.sync();
    await b.sync();
    await a.sync();
    expect(a.state.entry('k')!.text, 'vom Handy');
    expect(b.state.entry('k')!.text, 'vom Handy');

    await b.state.deleteEntry(b.state.entry('k')!);
    await b.sync();
    await a.sync();
    expect(a.state.entries, isEmpty);
  });

  test('Mein Geschäft: die jüngere Fassung gewinnt als Ganzes', () async {
    await a.state.saveBusiness(Business(ownerName: 'Alt'));
    await a.sync();
    await b.sync();
    expect(b.state.business.ownerName, 'Alt');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final nb = b.state.business.copy()..city = 'Luzern';
    await b.state.saveBusiness(nb);
    await b.sync();
    await a.sync();
    expect(a.state.business.city, 'Luzern');
  });

  test('in ein anderes Jahr verschobene Buchung erscheint nur einmal', () async {
    await a.state.saveEntry(e('m', 500, date: DateTime(2026, 1, 3)));
    await a.sync();
    await b.sync();
    final moved = b.state.entry('m')!.copy()..date = DateTime(2025, 12, 30);
    await b.state.saveEntry(moved, previousYear: 2026);
    await b.sync();
    await a.sync();
    expect(a.state.entries.where((x) => x.id == 'm').single.year, 2025);
    expect(a.state.expensesOf(2026), 0);
    expect(a.state.expensesOf(2025), 500);
  });

  test('zusammenführen der Rohdaten', () {
    final merged = SyncEngine.mergeJson(
      'konten.json',
      {
        'format': 'conti-konten',
        'items': [
          {'id': '1', 'name': 'hier neuer', 'updatedAt': '2026-02-01T00:00:00Z'},
          {'id': '2', 'name': 'nur hier', 'updatedAt': '2026-01-01T00:00:00Z'},
        ],
      },
      {
        'format': 'conti-konten',
        'items': [
          {'id': '1', 'name': 'dort älter', 'updatedAt': '2026-01-01T00:00:00Z'},
          {'id': '3', 'name': 'nur dort', 'updatedAt': '2026-01-01T00:00:00Z'},
        ],
      },
    );
    final names = {for (final m in merged['items'] as List) m['id']: m['name']};
    expect(names, {'1': 'hier neuer', '2': 'nur hier', '3': 'nur dort'});
    expect(SyncEngine.isSyncedPath('buchungen/2026.json.tmp'), isFalse);
    expect(SyncEngine.isSyncedPath('belege/2026/a.jpg'), isTrue);
  });
}
